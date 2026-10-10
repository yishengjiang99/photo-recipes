import AVFoundation
import UIKit
import Combine
import CoreImage
import CoreVideo

@MainActor
final class CameraSession: NSObject, ObservableObject {
    enum AuthState { case notDetermined, authorized, denied, restricted }

    enum CaptureMode: String, CaseIterable, Identifiable {
        case auto, program, aperture, shutter, manual
        var id: String { rawValue }
        var shortLabel: String {
            switch self {
            case .auto: return "Auto"
            case .program: return "P"
            case .aperture: return "A"
            case .shutter: return "S"
            case .manual: return "M"
            }
        }
    }

    enum FlashCycle: String, CaseIterable {
        case off, on, auto
        var next: FlashCycle {
            switch self { case .off: return .on; case .on: return .auto; case .auto: return .off }
        }
        var icon: String {
            switch self {
            case .off: return "bolt.slash.fill"
            case .on: return "bolt.fill"
            case .auto: return "bolt.badge.automatic.fill"
            }
        }
        /// Short caption for on-finder toast (Off / On / Auto).
        var modeCaption: String {
            switch self {
            case .off: return "Off"
            case .on: return "On"
            case .auto: return "Auto"
            }
        }
        var av: AVCaptureDevice.FlashMode {
            switch self { case .off: return .off; case .on: return .on; case .auto: return .auto }
        }
    }

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "photo-recipes.camera")
    /// Dedicated serial queue for live video-frame delivery — never the capture queue.
    private let videoQueue = DispatchQueue(label: "photo-recipes.video-frames", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    /// Latest viewfinder frame for silent probes. `nonisolated(unsafe)` is sound:
    /// every access is serialized on `videoQueue` (delegate runs on `videoQueue`,
    /// readers go through `videoQueue.sync`).
    private nonisolated(unsafe) var latestProbeFrame: (buffer: CVPixelBuffer, timestamp: CMTime)?
    private var input: AVCaptureDeviceInput?
    private var photoCont: CheckedContinuation<Data, Error>?

    /// Live-frame consumer (SceneSensor). Invoked from a Task hop off the video
    /// delegate — never blocks the capture queue.
    var frameConsumer: ((CVPixelBuffer, CMTime) -> Void)?
    /// UI → device point-of-interest converter. Production sets a
    /// `PreviewLayerDevicePointConverter` once the preview layer exists; tests
    /// inject a mock. Nil → identity fallback.
    var devicePointConverter: DevicePointConverter?

    @Published var auth: AuthState = .notDetermined
    @Published var isRunning = false
    @Published var errorMessage: String?
    @Published var capabilities = DeviceCapabilities.unknown
    @Published var captureMode: CaptureMode = .auto
    @Published var flash: FlashCycle = .off
    @Published var showGrid = true
    @Published var isFront = false
    /// Save front-camera stills mirrored, matching the (always mirrored) preview.
    @Published var mirrorFrontPhotos: Bool =
        UserDefaults.standard.object(forKey: CameraSession.mirrorFrontPhotosKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(mirrorFrontPhotos, forKey: Self.mirrorFrontPhotosKey) }
    }
    private static let mirrorFrontPhotosKey = "camera.mirrorFrontPhotos"
    @Published var exposureSeconds: Double = 1.0 / 60
    @Published var iso: Float = 100
    @Published var evBias: Float = 0
    @Published var exposureLocked = false
    @Published var focusLocked = false
    @Published var focusPoint: CGPoint?
    @Published var whiteBalanceLocked = false
    @Published var appliedRecipeId: String?
    @Published var appliedRecipeTitle: String?
    @Published var apertureGuidance: String?
    @Published var clampMessages: [String] = []
    @Published var applyNotes: [String] = []
    @Published var lensLabel = "1×"
    @Published var lastThumb: UIImage?
    @Published var optimizeReason: String?
    /// Debounced subject-area changes (monitorSubjectAreaChange) — CameraView re-runs Auto Optimize.
    @Published var subjectAreaChangeToken: Int = 0
    /// Preview-only LUT id from previewLUT — never baked into JPEG.
    @Published var previewLUTId: String?
    /// Active Creative Look (user-applied). Baked into preview + still when intensity > 0.
    @Published var activeCreativeLook: CreativeLook?
    @Published var pendingBracket: BracketTarget?
    @Published var simulatedApertureCoach: String?

    // Controls sheet state (Light / Lens / Capture)
    @Published var torchOn = false
    @Published var lowLightBoostOn = false
    @Published var videoHDROn = false
    @Published var preferredFrameRate: Double?
    @Published var selectedLens: LensChoice = .wide
    @Published var lensPosition: Double = 0.5

    enum LensChoice: String, CaseIterable, Identifiable {
        case ultraWide, wide, tele
        var id: String { rawValue }
        var label: String {
            switch self {
            case .ultraWide: return "UW"
            case .wide: return "Wide"
            case .tele: return "Tele"
            }
        }
    }

    var supportsTorch: Bool { input?.device.hasTorch == true }
    var supportsLowLightBoost: Bool { input?.device.isLowLightBoostSupported == true }
    var supportsVideoHDR: Bool { input?.device.activeFormat.isVideoHDRSupported == true }
    var supportsLensPosition: Bool {
        input?.device.isLockingFocusWithCustomLensPositionSupported == true
    }
    var pendingBracketStops: [Double]? { pendingBracket?.stops }

    /// Back-compat alias used by older notes paths.
    var creativeLook: CreativeLook? {
        get { activeCreativeLook }
        set { activeCreativeLook = newValue }
    }

    private var configured = false
    private var interruptionObserver: NSObjectProtocol?
    private var interruptionEndedObserver: NSObjectProtocol?
    private var subjectAreaObserver: NSObjectProtocol?
    private var subjectAreaDebounceTask: Task<Void, Never>?
    private var monitorSubjectArea = false

    func checkAuth() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: auth = .authorized
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            Analytics.shared.track(granted ? "camera_permission_granted" : "camera_permission_denied", props: ["source": "camera_session"])
            auth = granted ? .authorized : .denied
        case .denied: auth = .denied
        case .restricted: auth = .restricted
        @unknown default: auth = .denied
        }
    }

    func start() async {
        await checkAuth()
        guard auth == .authorized else { return }
        do {
            try await configureIfNeeded()
            // Re-start safe: drop any prior observers before attaching new ones.
            unregisterInterruptionObservers()
            registerInterruptionObservers()
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                queue.async { [weak self] in
                    self?.session.startRunning()
                    c.resume()
                }
            }
            isRunning = session.isRunning
            refreshReadouts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        unregisterInterruptionObservers()
        queue.async { [weak self] in
            self?.session.stopRunning()
            Task { @MainActor in self?.isRunning = false }
        }
    }

    private func registerInterruptionObservers() {
        let center = NotificationCenter.default
        interruptionObserver = center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            let reason = (notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int)
                .flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
            let message: String = {
                switch reason {
                case .audioDeviceInUseByAnotherClient, .videoDeviceInUseByAnotherClient:
                    return "Camera is being used by another app."
                case .videoDeviceNotAvailableDueToSystemPressure:
                    return "Camera paused due to system pressure."
                case .videoDeviceNotAvailableWithMultipleForegroundApps:
                    return "Camera unavailable while multitasking."
                default:
                    return "Camera interrupted — tap to resume."
                }
            }()
            Task { @MainActor in self.errorMessage = message }
        }
        interruptionEndedObserver = center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.errorMessage = nil }
        }
    }

    private func unregisterInterruptionObservers() {
        let center = NotificationCenter.default
        if let observer = interruptionObserver {
            center.removeObserver(observer)
            interruptionObserver = nil
        }
        if let observer = interruptionEndedObserver {
            center.removeObserver(observer)
            interruptionEndedObserver = nil
        }
        unregisterSubjectAreaObserver()
    }

    private func unregisterSubjectAreaObserver() {
        if let observer = subjectAreaObserver {
            NotificationCenter.default.removeObserver(observer)
            subjectAreaObserver = nil
        }
        subjectAreaDebounceTask?.cancel()
        subjectAreaDebounceTask = nil
    }

    private func configureIfNeeded() async throws {
        guard !configured else { return }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    session.beginConfiguration()
                    session.sessionPreset = .photo
                    guard let device = bestDevice(front: false) else { throw CamError.noDevice }
                    let inp = try AVCaptureDeviceInput(device: device)
                    guard session.canAddInput(inp) else { throw CamError.badInput }
                    session.addInput(inp)
                    guard session.canAddOutput(photoOutput) else { throw CamError.badOutput }
                    session.addOutput(photoOutput)
                    photoOutput.maxPhotoQualityPrioritization = .quality
                    // Silent viewfinder frames for the scene probe — no shutter, no flash.
                    // Delivered on `videoQueue`; latest frame retained for probe grabs.
                    videoOutput.alwaysDiscardsLateVideoFrames = true
                    videoOutput.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                    ]
                    videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
                    guard session.canAddOutput(videoOutput) else { throw CamError.badOutput }
                    session.addOutput(videoOutput)
                    session.commitConfiguration()
                    // Orientation/mirror must be set after the output joins the session
                    // (the connection only exists then). Runs on the main actor.
                    let output = videoOutput
                    Task { @MainActor in
                        self.applyVideoOutputOrientation(output: output, isFront: self.isFront)
                    }
                    Task { @MainActor in
                        self.input = inp
                        self.configured = true
                        self.updateCapabilities(device)
                        self.lensLabel = Self.label(for: device.deviceType)
                    }
                    cont.resume()
                } catch {
                    session.commitConfiguration()
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func bestDevice(front: Bool) -> AVCaptureDevice? {
        let pos: AVCaptureDevice.Position = front ? .front : .back
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera]
        let disc = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: pos)
        return disc.devices.first { $0.deviceType == .builtInWideAngleCamera } ?? disc.devices.first
    }

    /// Sets the video data output connection rotation so every frame handed to
    /// Vision is upright, and mirrors the front camera. Sensor-native frames are
    /// landscape; without this, Vision runs on sideways frames and every box it
    /// returns is in the wrong space.
    private func applyVideoOutputOrientation(output: AVCaptureVideoDataOutput, isFront: Bool) {
        guard let connection = output.connection(with: .video) else { return }
        if #available(iOS 17, *) {
            let angle = Self.videoRotationAngle(for: Self.currentInterfaceOrientation())
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        } else if connection.isVideoOrientationSupported {
            connection.videoOrientation = Self.videoOrientation(for: Self.currentInterfaceOrientation())
        }
        Self.setMirroring(isFront, on: output)
    }

    /// Explicit mirroring for an output's video connection. Session-queue safe.
    nonisolated private static func setMirroring(_ mirrored: Bool, on output: AVCaptureOutput) {
        guard let connection = output.connection(with: .video),
              connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = mirrored
    }

    /// Re-apply rotation/mirror, e.g. on interface rotation or camera flip.
    /// Safe to call any time after `start()`.
    func updateVideoOutputOrientation() {
        applyVideoOutputOrientation(output: videoOutput, isFront: isFront)
    }

    /// Clockwise rotation (degrees) that makes sensor-native landscape frames upright.
    static func videoRotationAngle(for orientation: UIInterfaceOrientation) -> CGFloat {
        switch orientation {
        case .portrait: return 90
        case .portraitUpsideDown: return 270
        case .landscapeLeft: return 180
        case .landscapeRight: return 0
        @unknown default: return 90
        }
    }

    private static func videoOrientation(for orientation: UIInterfaceOrientation) -> AVCaptureVideoOrientation {
        switch orientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        @unknown default: return .portrait
        }
    }

    private static func currentInterfaceOrientation() -> UIInterfaceOrientation {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })?.interfaceOrientation
            ?? scenes.first?.interfaceOrientation
            ?? .portrait
    }

    func flipCamera() {
        let wantFront = !isFront
        queue.async { [weak self] in
            guard let self, let device = self.bestDevice(front: wantFront) else { return }
            do {
                let newIn = try AVCaptureDeviceInput(device: device)
                self.session.beginConfiguration()
                if let cur = self.input { self.session.removeInput(cur) }
                if self.session.canAddInput(newIn) { self.session.addInput(newIn) }
                self.session.commitConfiguration()
                Task { @MainActor in
                    self.input = newIn
                    self.isFront = wantFront
                    self.updateCapabilities(device)
                    self.lensLabel = Self.label(for: device.deviceType)
                    self.exposureLocked = false
                    self.focusLocked = false
                    // The input swap recreated the video connection: re-apply
                    // rotation + mirroring so Vision keeps getting upright frames.
                    self.updateVideoOutputOrientation()
                    // Per-device state belongs to the old camera.
                    self.selectedLens = .wide
                    self.focusPoint = nil
                    self.torchOn = false
                    self.lowLightBoostOn = false
                    self.videoHDROn = false
                }
            } catch {
                Task { @MainActor in self.errorMessage = error.localizedDescription }
            }
        }
    }

    private static func label(for t: AVCaptureDevice.DeviceType) -> String {
        switch t {
        case .builtInUltraWideCamera: return "0.5×"
        case .builtInTelephotoCamera: return "Tele"
        default: return "1×"
        }
    }

    func updateCapabilities(_ device: AVCaptureDevice) {
        let custom = device.isExposureModeSupported(.custom)
        capabilities = CameraValues.sanitized(DeviceCapabilities(
            supportsCustomExposure: custom,
            supportsExposureTargetBias: true,
            supportsWhiteBalanceLock: device.isWhiteBalanceModeSupported(.locked),
            supportsFocusLock: device.isFocusModeSupported(.locked),
            minExposureSeconds: CMTimeGetSeconds(device.activeFormat.minExposureDuration),
            maxExposureSeconds: CMTimeGetSeconds(device.activeFormat.maxExposureDuration),
            minISO: device.activeFormat.minISO,
            maxISO: device.activeFormat.maxISO,
            minEV: device.minExposureTargetBias,
            maxEV: device.maxExposureTargetBias,
            deviceTypeName: device.deviceType.rawValue
        ))
    }

    /// Writes the shutter and returns the completion handler's syncTime
    /// (`.invalid` when the write couldn't be issued). Await the write before
    /// metering — see `issueExposureWrite`.
    @discardableResult
    func setShutter(_ seconds: Double) async -> CMTime {
        guard let device = input?.device, device.isExposureModeSupported(.custom) else {
            clampMessages.append("Shutter lock unavailable on this lens/format.")
            return .invalid
        }
        guard CameraValues.finitePositive(seconds) != nil else { return .invalid }
        let clamped = min(max(seconds, capabilities.minExposureSeconds), capabilities.maxExposureSeconds)
        if clamped != seconds {
            clampMessages.append("Shutter clamped to \(RecipeCameraMapper.formatShutter(clamped)).")
        }
        let sync = await issueExposureWrite(
            duration: CMTime(seconds: clamped, preferredTimescale: 1_000_000),
            iso: device.iso)
        exposureLocked = true
        exposureSeconds = CameraValues.exposure(clamped, fallback: exposureSeconds)
        if captureMode == .auto || captureMode == .program { captureMode = .shutter }
        return sync
    }

    /// Writes the ISO and returns the completion handler's syncTime
    /// (`.invalid` when the write couldn't be issued).
    @discardableResult
    func setISO(_ value: Float) async -> CMTime {
        guard let device = input?.device, device.isExposureModeSupported(.custom) else {
            clampMessages.append("ISO lock unavailable on this lens/format.")
            return .invalid
        }
        guard CameraValues.finitePositive(value) != nil else { return .invalid }
        let clamped = min(max(value, capabilities.minISO), capabilities.maxISO)
        let sync = await issueExposureWrite(
            duration: device.exposureDuration,
            iso: clamped)
        exposureLocked = true
        iso = CameraValues.iso(clamped, fallback: iso)
        if captureMode == .auto { captureMode = .manual }
        return sync
    }

    /// Programs the exposure-target bias WITHOUT touching `exposureMode`.
    /// Previously this switched the device back to continuous auto-exposure,
    /// silently discarding custom shutter/ISO written just before it.
    func setEV(_ bias: Float) {
        guard let device = input?.device, bias.isFinite else { return }
        let clamped = min(max(bias, capabilities.minEV), capabilities.maxEV)
        configure(device) {
            device.setExposureTargetBias(clamped, completionHandler: nil)
        }
        evBias = CameraValues.evBias(clamped, fallback: evBias)
        exposureLocked = device.exposureMode == .custom
    }

    func unlockExposure() {
        guard let device = input?.device else { return }
        configure(device) {
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
        }
        exposureLocked = false
    }

    /// Applies focus + exposure point of interest. Takes a **device** point
    /// (sensor space, 0…1) — callers must convert from UI space first via
    /// `focusOnUIPoint(_:lock:)` or `devicePointConverter`. Never stores the
    /// reticle: `focusPoint` is UI-space and is only written by `focusOnUIPoint`.
    func focus(at devicePoint: CGPoint, lock: Bool) {
        guard let device = input?.device else { return }
        let clamped = CoordinateSpaces.clamp01(devicePoint)
        configure(device) {
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = clamped }
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = clamped }
            // `.autoFocus` scans once at the point of interest and then holds the
            // lens, so it serves both lock and non-lock. Writing `.locked` here
            // would freeze the lens where it is without ever focusing on the point.
            if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            } else if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            } else if lock, device.isFocusModeSupported(.locked) {
                device.focusMode = .locked
            }
            // The exposure point only takes effect when the mode is (re)written.
            // Leave locked / custom exposure alone so applied dials survive a tap.
            if device.isExposurePointOfInterestSupported,
               device.exposureMode == .continuousAutoExposure {
                device.exposureMode = .continuousAutoExposure
            }
        }
        focusLocked = lock
    }

    /// UI-space entry point for tap-to-focus and Auto Optimize. Converts the
    /// UI-normalized point (top-left origin) to a device point of interest,
    /// applies it, and stores the **UI** point in `focusPoint` for the reticle.
    func focusOnUIPoint(_ uiPoint: CGPoint, lock: Bool) {
        let ui = CoordinateSpaces.clamp01(uiPoint)
        focusPoint = ui
        let device = devicePointConverter?.devicePoint(uiNormalized: ui) ?? ui
        focus(at: device, lock: lock)
    }

    /// Converts a UI-normalized point (top-left origin) to a device point of
    /// interest (sensor space). Used by Auto Optimize's Vision → device path.
    func devicePointOfInterest(fromUINormalized uiPoint: CGPoint) -> CGPoint {
        devicePointConverter?.devicePoint(uiNormalized: uiPoint) ?? CoordinateSpaces.clamp01(uiPoint)
    }

    func unlockFocus() {
        guard let device = input?.device else { return }
        configure(device) {
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
        }
        focusLocked = false
        focusPoint = nil
    }

    /// Writes phone-settable dials for Free Peek and Pro alike.
    /// Soft paywall is Optimize quota (`AutoOptimizeController.canRun`), not dial writes.
    /// Coach-only levers (aperture / ND / tripod) stay guidance via mapper notes — never forced as phone settings.
    @discardableResult
    func apply(recipe: Recipe, dials: DialSettings? = nil) async -> Bool {
        let dials = dials ?? recipe.dials
        appliedRecipeId = recipe.id
        appliedRecipeTitle = recipe.title
        clampMessages = []
        applyNotes = []
        let mapped = RecipeCameraMapper.map(dials: dials, capabilities: capabilities)
        apertureGuidance = mapped.apertureGuidance
        applyNotes = mapped.notes + mapped.unsupported

        switch dials.mode {
        case .auto, .phoneHdr: captureMode = .auto
        case .aperturePriority: captureMode = .aperture
        case .shutterPriority: captureMode = .shutter
        case .manual: captureMode = .manual
        }

        if let s = mapped.shutterSeconds, let i = mapped.iso, capabilities.supportsCustomExposure {
            await setCustom(duration: s, iso: i)
        } else if let s = mapped.shutterSeconds, capabilities.supportsCustomExposure {
            await setShutter(s)
        } else if let i = mapped.iso, capabilities.supportsCustomExposure {
            await setISO(i)
        }
        // EV is folded into the exposure solve when custom exposure was written;
        // programming a bias on top would fight the just-written shutter/ISO.
        if !ExposureApplyPolicy.wroteCustomExposure(shutter: mapped.shutterSeconds, iso: mapped.iso, supported: capabilities.supportsCustomExposure),
           let ev = mapped.evCompensation {
            setEV(ev)
        }
        // Selfie preset recipes carry front-camera targets + their look.
        if let preset = SelfiePresets.preset(recipeId: recipe.id) {
            await applySelfiePreset(preset, switchToFront: true, setLook: true)
        }
        return true
    }

    // MARK: - Selfie presets (front camera)

    /// Applies a selfie preset's capture targets on the front camera: EV via
    /// `ExposureApplyPolicy` (no custom shutter/ISO is written), Retina Flash via
    /// `flashMode` when supported, low-light boost when the device has it, face-weighted
    /// AF/AE, and (Studio Crisp) a white-balance hold once auto exposure settles.
    /// - switchToFront: Library apply flips to the front camera; a look-picker tap does not.
    /// - setLook: also activate the preset's look (Library apply). Intensity keeps the user's.
    func applySelfiePreset(_ preset: SelfiePresets.Preset, switchToFront: Bool, setLook: Bool) async {
        if switchToFront, !isFront {
            await ensureFrontCamera()
        }
        if setLook {
            let current = activeCreativeLook?.id == preset.lookId ? activeCreativeLook?.intensity : nil
            let look = CreativeLook(id: preset.lookId, intensity: current ?? CreativeLookCatalog.defaultIntensity)
            activeCreativeLook = look
            applyNotes.append(
                String(format: "Look “\(look.displayName)” @ %.0f%% — baking still.", look.resolvedIntensity * 100)
            )
        }
        guard isFront else {
            applyNotes.append("Selfie light settings apply on the front camera.")
            return
        }
        var targets = preset.targets
        targets.creativeLook = nil // look handled above; never recurse through setActiveLook
        _ = await applyPhoneTargets(targets, autoApplyLook: true)
        if preset.meterOnFace {
            _ = await meterOnDetectedFace()
        }
        if preset.lockWhiteBalanceAfterAE {
            await lockWhiteBalanceAfterExposureSettles()
        }
    }

    /// Flips to the front camera and waits (≤ 2 s) for the input swap to land.
    private func ensureFrontCamera() async {
        guard !isFront else { return }
        flipCamera()
        for _ in 0..<40 where !isFront {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Face-weighted continuous AF/AE at the face the scene sensor last saw.
    /// Guards point-of-interest support (many front cameras are fixed-focus).
    @discardableResult
    func meterOnDetectedFace() async -> Bool {
        let snapshot = await SceneSensor.shared.current()
        guard snapshot.age < 3, snapshot.features.subjectKind == .face,
              let box = snapshot.features.subjectBox,
              let ui = SelfiePresets.faceMeteringPoint(uiFaceBox: box.cgRect),
              let device = input?.device else { return false }
        let dp = CoordinateSpaces.clamp01(devicePointOfInterest(fromUINormalized: ui))
        var wrote = false
        configure(device) {
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = dp
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                wrote = true
            }
            // Leave custom exposure alone; re-writing the mode applies the new point.
            if device.isExposurePointOfInterestSupported, device.exposureMode != .custom {
                device.exposurePointOfInterest = dp
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                wrote = true
            }
        }
        if wrote {
            focusPoint = ui
            focusLocked = false
        }
        return wrote
    }

    /// Hold white balance at the current gains once auto exposure stops adjusting (≤ 1.5 s).
    func lockWhiteBalanceAfterExposureSettles(timeout: TimeInterval = 1.5) async {
        guard let device = input?.device else { return }
        guard device.isWhiteBalanceModeSupported(.locked) else {
            clampMessages.append("WB lock unavailable — guidance only.")
            return
        }
        let start = Date()
        while (device.isAdjustingExposure || device.isAdjustingWhiteBalance),
              Date().timeIntervalSince(start) < timeout {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        configure(device) { device.whiteBalanceMode = .locked }
        whiteBalanceLocked = true
        applyNotes.append("White balance held once exposure settled.")
    }


    /// Shared with Auto Optimize button + Camera voice. Wire keys locked to server #21.
    /// Always writes phone-settable levers (Free Peek + Pro). Capability-gate every lever;
    /// skip unsupported; never pretend aperture was set. Quota lives in AutoOptimizeController.
    @discardableResult
    func applyPhoneTargets(_ targets: PhoneTargets, autoApplyLook: Bool = false) async -> Bool {
        var wrote = false

        // Prefer optical cameraDevice over zoom-only.
        // Front camera has one lens and no torch — skip both silently.
        if let cam = targets.cameraDevice, !isFront, switchCameraDevice(cam) {
            wrote = true
        }

        let durationSec = targets.exposureDurationSec
            ?? targets.shutter.flatMap { RecipeCameraMapper.parseShutter($0) }
        let isoVal: Float? = targets.iso.flatMap { RecipeCameraMapper.parseISO($0) }

        var wroteCustomExposure = false
        if let d = durationSec, let i = isoVal, capabilities.supportsCustomExposure {
            await setCustom(duration: d, iso: i)
            wrote = true
            wroteCustomExposure = true
        } else if let d = durationSec, capabilities.supportsCustomExposure {
            await setShutter(d)
            wrote = true
            wroteCustomExposure = true
        } else if let i = isoVal, capabilities.supportsCustomExposure {
            await setISO(i)
            wrote = true
            wroteCustomExposure = true
        } else if durationSec != nil || isoVal != nil {
            clampMessages.append("Custom exposure unavailable on this lens/format — guidance only.")
        }

        // EV is folded into the ISO solve when custom shutter/ISO was written
        // this apply — programming a bias on top would fight the solve.
        // (setEV itself also never leaves .custom anymore; this skips the call entirely.)
        if let bias = ExposureApplyPolicy.evBiasToProgram(
            evRaw: targets.ev,
            wroteCustomExposure: wroteCustomExposure
        ) {
            setEV(bias)
            wrote = true
        }

        if let lp = targets.lensPosition, setLensPosition(lp) {
            wrote = true
        }

        if let fp = targets.focusPoint {
            let lock = (targets.focusMode?.lowercased()).map { ["locked", "lock", "near"].contains($0) } ?? true
            // focusPoint is UI-space (top-left normalized); convert to device space.
            focusOnUIPoint(fp.cgPoint, lock: lock)
            wrote = true
        } else if targets.lensPosition == nil, let focusMode = targets.focusMode?.lowercased() {
            switch focusMode {
            case "locked", "lock", "near":
                focusOnUIPoint(focusPoint ?? CGPoint(x: 0.5, y: 0.5), lock: true)
                wrote = true
            case "continuous", "auto", "infinity":
                unlockFocus()
                wrote = true
            default:
                clampMessages.append("Focus mode “\(focusMode)” left as guidance.")
            }
        }

        if let factor = targets.zoom {
            setZoomFactor(factor)
            wrote = true
        }

        if let wb = targets.whiteBalance, applyWhiteBalance(wb) {
            wrote = true
        }

        if let torch = targets.torch, !isFront, applyTorch(torch) {
            wrote = true
        }
        if let flashMode = targets.flash, applyFlash(flashMode) {
            wrote = true
        }

        if let boost = targets.lowLightBoost, setLowLightBoost(boost) {
            wrote = true
        }
        if let hdr = targets.videoHDR, setVideoHDR(hdr) {
            wrote = true
        }

        if targets.frameRate != nil || targets.preferFormatHint != nil {
            if setFrameRate(targets.frameRate, preferFormatHint: targets.preferFormatHint) {
                wrote = true
            }
        }

        if let monitor = targets.monitorSubjectAreaChange {
            setSubjectAreaMonitoring(monitor)
            wrote = true
        }

        if let dims = targets.maxPhotoDimensions, applyMaxPhotoDimensions(dims) {
            wrote = true
        }

        if let stops = targets.bracket?.stops, !stops.isEmpty {
            pendingBracket = targets.bracket
            applyNotes.append(
                "Bracket \(stops.map { String(format: "%+.1f", $0) }.joined(separator: ", ")) EV — use bracket capture to save burst."
            )
            wrote = true
        } else {
            pendingBracket = nil
        }

        // P1 — previewLUT is preview-only (never bake into JPEG).
        if let lut = targets.previewLUT, !lut.isEmpty {
            previewLUTId = lut
            applyNotes.append("Preview LUT “\(lut)” — preview only, not baked into capture.")
            wrote = true
        } else {
            previewLUTId = nil
        }

        // creativeLook: AO keeps suggest-via-chip; Recommend auto-applies so the viewfinder changes immediately.
        if let look = targets.creativeLook, !look.id.isEmpty {
            if autoApplyLook {
                setActiveLook(look)
                wrote = true
            } else {
                let intensity = look.intensity ?? CreativeLookCatalog.defaultIntensity
                applyNotes.append(
                    String(format: "Suggested look “\(look.id)” @ %.0f%% — Apply from chip to bake preview & still.", intensity * 100)
                )
                wrote = true
            }
        }

        // P1 — simulatedAperture only if OS API exists; else coach.
        // Dead-end "guidance only" / "not available" copy is not pushed to clampMessages when auto-applying
        // (Recommend) — those banners feel like a failed apply. Coach string still set for dials sheet.
        if let sa = targets.simulatedAperture {
            if applySimulatedAperture(sa) {
                wrote = true
            } else {
                let msg = String(format: "f/%.1f guidance only — phone lens is fixed.", sa)
                simulatedApertureCoach = msg
                if !autoApplyLook {
                    clampMessages.append(msg)
                }
            }
        }

        return wrote
    }

    func setZoomFactor(_ factor: Double) {
        guard let device = input?.device else { return }
        let minZ = Double(device.minAvailableVideoZoomFactor)
        let maxZ = Double(device.maxAvailableVideoZoomFactor)
        let clamped = min(max(factor, minZ), maxZ)
        if abs(clamped - factor) > 0.01 {
            clampMessages.append(String(format: "Zoom %.2f× clamped to %.2f×", factor, clamped))
        }
        configure(device) {
            device.videoZoomFactor = CGFloat(clamped)
        }
        lensLabel = String(format: "%.1f×", clamped)
    }

    func clearRecipe() {
        appliedRecipeId = nil
        appliedRecipeTitle = nil
        apertureGuidance = nil
        clampMessages = []
        applyNotes = []
        optimizeReason = nil
        previewLUTId = nil
        activeCreativeLook = nil
        pendingBracket = nil
        preferredFrameRate = nil
        simulatedApertureCoach = nil
        setSubjectAreaMonitoring(false)
        captureMode = .auto
        unlockExposure()
        unlockFocus()
    }

    /// Writes shutter + ISO together and returns the completion handler's
    /// syncTime (`.invalid` when the write couldn't be issued).
    @discardableResult
    private func setCustom(duration: Double, iso isoVal: Float) async -> CMTime {
        guard let device = input?.device, device.isExposureModeSupported(.custom),
              CameraValues.finitePositive(duration) != nil, CameraValues.finitePositive(isoVal) != nil else { return .invalid }
        let d = min(max(duration, capabilities.minExposureSeconds), capabilities.maxExposureSeconds)
        let i = min(max(isoVal, capabilities.minISO), capabilities.maxISO)
        let sync = await issueExposureWrite(
            duration: CMTime(seconds: d, preferredTimescale: 1_000_000),
            iso: i)
        exposureLocked = true
        exposureSeconds = CameraValues.exposure(d, fallback: exposureSeconds)
        iso = CameraValues.iso(i, fallback: iso)
        return sync
    }

    // MARK: - Awaitable exposure writes (A1)

    /// Epoch of the most recently *issued* custom-exposure write, plus the
    /// task that resolves with its completion-handler syncTime. Assigned
    /// synchronously when the write is issued — `verifyExposure` awaits this
    /// instead of a timestamp left over from an earlier write.
    private var exposureWriteEpoch: UInt64 = 0
    private var inFlightExposureWrite: (epoch: UInt64, task: Task<CMTime, Never>)?

    /// Issues one custom-exposure write and returns the completion handler's
    /// syncTime. The write is tracked by epoch so a later `verifyExposure`
    /// awaits exactly the write its iteration issued.
    ///
    /// The write itself is issued by a task created synchronously with the
    /// epoch bump (no suspension between the two, so ordering is exact);
    /// the task resolves with the `setExposureModeCustom` completion
    /// handler's syncTime.
    private func issueExposureWrite(duration: CMTime, iso: Float) async -> CMTime {
        exposureWriteEpoch &+= 1
        let epoch = exposureWriteEpoch
        let task = Task<CMTime, Never> { @MainActor [weak self] in
            await withCheckedContinuation { (c: CheckedContinuation<CMTime, Never>) in
                guard let self, let device = self.input?.device else {
                    c.resume(returning: .invalid)
                    return
                }
                self.configure(device) {
                    device.setExposureModeCustom(duration: duration, iso: iso) { syncTime in
                        c.resume(returning: syncTime)
                    }
                }
            }
        }
        inFlightExposureWrite = (epoch: epoch, task: task)
        let syncTime = await task.value
        if inFlightExposureWrite?.epoch == epoch { inFlightExposureWrite = nil }
        return syncTime
    }

    /// Awaits the most recently issued exposure write when it is still in
    /// flight (covers fire-and-forget issuers such as dial taps). Normally a
    /// no-op: awaited issuers have already completed.
    private func awaitInFlightExposureWrite() async {
        if let inFlight = inFlightExposureWrite {
            _ = await inFlight.task.value
        }
    }


    // MARK: - phoneTargets helpers (#21 wire keys, capability-gated)

    @discardableResult
    func setLensPosition(_ position: Double) -> Bool {
        guard let device = input?.device else { return false }
        guard device.isLockingFocusWithCustomLensPositionSupported else {
            clampMessages.append("Lens position lock unsupported — focus guidance only.")
            return false
        }
        let clamped = Float(min(max(position, 0), 1))
        configure(device) {
            device.setFocusModeLocked(lensPosition: clamped, completionHandler: nil)
        }
        focusLocked = true
        lensPosition = Double(clamped)
        return true
    }

    @discardableResult
    func applyWhiteBalance(_ target: WhiteBalanceTarget) -> Bool {
        guard let device = input?.device else { return false }
        guard device.isWhiteBalanceModeSupported(.locked) else {
            clampMessages.append("WB lock unavailable — guidance only.")
            return false
        }
        switch target {
        case .mode(let raw):
            let key = raw.lowercased()
            if key == "auto" || key == "continuous" {
                configure(device) {
                    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                        device.whiteBalanceMode = .continuousAutoWhiteBalance
                    }
                }
                whiteBalanceLocked = false
                return true
            }
            let kelvin: Float? = {
                switch key {
                case "daylight", "sunny": return 5600
                case "cloudy": return 6000
                case "shade": return 7000
                case "tungsten", "incandescent": return 3200
                case "fluorescent": return 4000
                case "flash": return 5500
                default:
                    let digits = key.filter { $0.isNumber || $0 == "." }
                    return digits.isEmpty ? nil : Float(digits)
                }
            }()
            if let k = kelvin, k > 0 {
                return lockWhiteBalance(device: device, temperature: k, tint: 0)
            }
            configure(device) { device.whiteBalanceMode = .locked }
            whiteBalanceLocked = true
            applyNotes.append("WB “\(raw)” locked (mode only).")
            return true
        case .temperatureTint(let temperature, let tint):
            return lockWhiteBalance(
                device: device,
                temperature: Float(temperature ?? 5600),
                tint: Float(tint ?? 0)
            )
        case .gains(let redGain, let greenGain, let blueGain):
            var gains = device.deviceWhiteBalanceGains
            if let r = redGain { gains.redGain = clampGain(Float(r), device: device) }
            if let g = greenGain { gains.greenGain = clampGain(Float(g), device: device) }
            if let b = blueGain { gains.blueGain = clampGain(Float(b), device: device) }
            let locked = clampedGains(gains, device: device)
            configure(device) {
                device.setWhiteBalanceModeLocked(with: locked, completionHandler: nil)
            }
            whiteBalanceLocked = true
            return true
        }
    }

    private func lockWhiteBalance(device: AVCaptureDevice, temperature: Float, tint: Float) -> Bool {
        let tempTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: temperature, tint: tint)
        let gains = clampedGains(device.deviceWhiteBalanceGains(for: tempTint), device: device)
        configure(device) {
            device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
        }
        whiteBalanceLocked = true
        return true
    }

    private func clampGain(_ v: Float, device: AVCaptureDevice) -> Float {
        min(max(v, 1.0), device.maxWhiteBalanceGain)
    }

    private func clampedGains(_ gains: AVCaptureDevice.WhiteBalanceGains, device: AVCaptureDevice) -> AVCaptureDevice.WhiteBalanceGains {
        var g = gains
        g.redGain = clampGain(g.redGain, device: device)
        g.greenGain = clampGain(g.greenGain, device: device)
        g.blueGain = clampGain(g.blueGain, device: device)
        return g
    }

    @discardableResult
    func applyTorch(_ torch: TorchTarget) -> Bool {
        guard let device = input?.device, device.hasTorch else {
            clampMessages.append("Torch unavailable on this camera.")
            return false
        }
        let mode = torch.mode.lowercased()
        configure(device) {
            do {
                switch mode {
                case "on":
                    let level = Float(min(max(torch.level ?? 1.0, 0.01), 1.0))
                    if device.isTorchModeSupported(.on) {
                        try device.setTorchModeOn(level: level)
                    }
                case "auto":
                    if device.isTorchModeSupported(.auto) {
                        device.torchMode = .auto
                    } else if device.isTorchModeSupported(.off) {
                        device.torchMode = .off
                    }
                default:
                    if device.isTorchModeSupported(.off) { device.torchMode = .off }
                }
            } catch {
                Task { @MainActor in self.clampMessages.append("Torch: \(error.localizedDescription)") }
            }
        }
        torchOn = (torch.mode.lowercased() == "on")
        return true
    }

    func setTorch(_ on: Bool) {
        _ = applyTorch(TorchTarget(mode: on ? "on" : "off", level: on ? 1.0 : nil))
    }

    /// Brief torch blink on the back camera when the user selects Flash On, so the
    /// mode change is visible in the preview (still flash only fires on the next still).
    /// Leaves `flash` as `.on` for AVCapturePhotoSettings; torch returns to off.
    func pulseTorchForFlashPreview() {
        guard !isFront, supportsTorch else { return }
        guard let device = input?.device, device.hasTorch, device.isTorchModeSupported(.on) else { return }
        configure(device) {
            do { try device.setTorchModeOn(level: 0.35) } catch { /* ignore */ }
        }
        torchOn = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard let device = self.input?.device, device.hasTorch else { return }
            self.configure(device) {
                if device.isTorchModeSupported(.off) { device.torchMode = .off }
            }
            self.torchOn = false
        }
    }

    @discardableResult
    func applyFlash(_ raw: String) -> Bool {
        let wanted: FlashCycle
        switch raw.lowercased() {
        case "on": wanted = .on
        case "auto": wanted = .auto
        default: wanted = .off
        }
        // Front camera: no torch; Retina Flash (screen flash) rides AVCapturePhotoSettings.flashMode
        // only when the photo output lists it. Otherwise say so and keep going.
        if isFront, wanted != .off, !photoOutput.supportedFlashModes.contains(wanted.av) {
            clampMessages.append("Front flash isn’t available on this camera — shooting with available light.")
            flash = .off
            return false
        }
        flash = wanted
        return true
    }

    @discardableResult
    func setLowLightBoost(_ enabled: Bool) -> Bool {
        guard let device = input?.device else { return false }
        guard device.isLowLightBoostSupported else {
            clampMessages.append("Low-light boost unsupported on this device.")
            return false
        }
        configure(device) {
            device.automaticallyEnablesLowLightBoostWhenAvailable = enabled
        }
        lowLightBoostOn = enabled
        return true
    }

    @discardableResult
    func setVideoHDR(_ enabled: Bool) -> Bool {
        guard let device = input?.device else { return false }
        guard device.activeFormat.isVideoHDRSupported else {
            clampMessages.append("Video HDR unsupported on active format — still capture unaffected.")
            return false
        }
        configure(device) {
            if enabled {
                device.automaticallyAdjustsVideoHDREnabled = true
            } else {
                device.automaticallyAdjustsVideoHDREnabled = false
                device.isVideoHDREnabled = false
            }
        }
        videoHDROn = enabled
        return true
    }

    @discardableResult
    func switchCameraDevice(_ name: String) -> Bool {
        let key = name.lowercased()
            .replacingOccurrences(of: "builtin", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        let wantType: AVCaptureDevice.DeviceType? = {
            switch key {
            case "ultrawide", "ultrawidecamera", "0.5": return .builtInUltraWideCamera
            case "tele", "telephoto", "telephotocamera", "2", "3": return .builtInTelephotoCamera
            case "wide", "wideangle", "wideanglecamera", "1": return .builtInWideAngleCamera
            default: return nil
            }
        }()
        guard let wantType else {
            clampMessages.append("Unknown cameraDevice “\(name)” — left unchanged.")
            return false
        }
        let pos: AVCaptureDevice.Position = isFront ? .front : .back
        let disc = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: pos
        )
        guard let device = disc.devices.first(where: { $0.deviceType == wantType }) else {
            clampMessages.append("cameraDevice \(name) not available — try zoom instead.")
            return false
        }
        if input?.device.uniqueID == device.uniqueID {
            lensLabel = Self.label(for: device.deviceType)
            return true
        }
        do {
            let newIn = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            if let cur = input { session.removeInput(cur) }
            if session.canAddInput(newIn) {
                session.addInput(newIn)
            } else {
                session.commitConfiguration()
                clampMessages.append("Could not switch to \(name).")
                return false
            }
            session.commitConfiguration()
            input = newIn
            updateCapabilities(device)
            lensLabel = Self.label(for: device.deviceType)
            exposureLocked = false
            focusLocked = false
            updateVideoOutputOrientation()
            return true
        } catch {
            clampMessages.append("cameraDevice switch failed: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func setFrameRate(_ fps: Double?, preferFormatHint: String?) -> Bool {
        guard let device = input?.device else { return false }
        var choseFormat = false
        if let hint = preferFormatHint?.lowercased(), !hint.isEmpty {
            if let fmt = pickFormat(device: device, hint: hint) {
                configure(device) { device.activeFormat = fmt }
                updateCapabilities(device)
                choseFormat = true
            } else {
                clampMessages.append("Format hint “\(preferFormatHint!)” unavailable — skipped.")
            }
        }
        guard let fps, let fpsInt = CameraValues.safeRoundedInt(fps), fps > 0, fpsInt <= 1000 else { return choseFormat }
        let duration = CMTime(value: 1, timescale: CMTimeScale(max(1, fpsInt)))
        let ranges = device.activeFormat.videoSupportedFrameRateRanges
        guard !ranges.isEmpty else {
            clampMessages.append("No frame-rate ranges for active format — skipped.")
            return choseFormat
        }
        // minFrameDuration = fastest allowed; maxFrameDuration = slowest allowed
        let minD = ranges.map(\.minFrameDuration).min(by: { CMTimeCompare($0, $1) < 0 })!
        let maxD = ranges.map(\.maxFrameDuration).max(by: { CMTimeCompare($0, $1) < 0 })!
        var use = duration
        if CMTimeCompare(duration, minD) < 0 { use = minD }
        if CMTimeCompare(duration, maxD) > 0 { use = maxD }
        if CMTimeCompare(use, duration) != 0 {
            clampMessages.append(String(format: "frameRate %.0f fps clamped to device range.", fps))
        }
        configure(device) {
            device.activeVideoMinFrameDuration = use
            device.activeVideoMaxFrameDuration = use
        }
        preferredFrameRate = fps
        return true
    }

    func setPreferredFrameRate(_ fps: Double) {
        _ = setFrameRate(fps, preferFormatHint: nil)
    }

    private func pickFormat(device: AVCaptureDevice, hint: String) -> AVCaptureDevice.Format? {
        let want4k = hint.contains("4k") || hint.contains("2160")
        let want1080 = hint.contains("1080")
        let want60 = hint.contains("60")
        let want30 = hint.contains("30")
        let targetFps: Double = want60 ? 60 : (want30 ? 30 : 0)
        return device.formats.reversed().first { fmt in
            let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
            let h = Int(dims.height)
            if want4k && h < 2160 { return false }
            if want1080 && !(h == 1080 || h == 1920) { return false }
            if targetFps > 0 {
                let maxFps = fmt.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
                if maxFps + 0.1 < targetFps { return false }
            }
            return true
        }
    }

    func setSubjectAreaMonitoring(_ enabled: Bool) {
        monitorSubjectArea = enabled
        guard let device = input?.device else { return }
        configure(device) {
            device.isSubjectAreaChangeMonitoringEnabled = enabled
        }
        unregisterSubjectAreaObserver()
        guard enabled else { return }
        subjectAreaObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.subjectAreaDidChangeNotification,
            object: device,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.subjectAreaDebounceTask?.cancel()
                self.subjectAreaDebounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard !Task.isCancelled else { return }
                    self.subjectAreaChangeToken &+= 1
                }
            }
        }
    }

    @discardableResult
    func applyMaxPhotoDimensions(_ dims: MaxPhotoDimensions) -> Bool {
        let w = Int(dims.width.rounded())
        let h = Int(dims.height.rounded())
        guard w > 0, h > 0 else { return false }
        if #available(iOS 16.0, *) {
            let want = CMVideoDimensions(width: Int32(w), height: Int32(h))
            let supported = photoOutput.maxPhotoDimensions
            photoOutput.maxPhotoDimensions = want
            applyNotes.append(
                "maxPhotoDimensions \(w)×\(h) requested (device may clamp; active \(supported.width)×\(supported.height))."
            )
            return true
        }
        clampMessages.append("maxPhotoDimensions requires iOS 16+ — skipped.")
        return false
    }

    @discardableResult
    func applySimulatedAperture(_ value: Double) -> Bool {
        // Fixed phone lenses: no public AVFoundation aperture write on current deployment.
        // Gate future OS APIs here; until then → coach only (never pretend hardware f-stop).
        _ = value
        return false
    }

    /// Bracketed stills when `bracket.stops` present. Sequential EV-bias best-effort
    /// (AVCapturePhotoBracketSettings when hardware allows — limits documented in README).
    func captureBracketBurst(stops: [Double]? = nil, saveToLibrary: Bool = true) async throws -> [Data] {
        let evStops = stops ?? pendingBracket?.stops ?? []
        guard !evStops.isEmpty else { throw CamError.captureFailed }
        let limited = Array(evStops.prefix(9))
        var results: [Data] = []
        let previousEV = evBias
        defer { setEV(previousEV) }
        for stop in limited {
            setEV(Float(stop))
            try? await Task.sleep(nanoseconds: 120_000_000)
            let data = try await capturePhoto()
            results.append(data)
            if saveToLibrary {
                try? await PhotoLibrarySaver.saveJPEG(data)
            }
        }
        applyNotes.append(
            "Bracket burst: \(results.count)/\(limited.count) frames saved (sequential EV bias best-effort)."
        )
        return results
    }

    /// Strong refs to in-flight bracket delegates (AVFoundation does not
    /// retain the delegate passed to `capturePhoto`).
    private var activeBracketDelegates: [AOBracketPhotoDelegate] = []

    /// True while the device holds system auto exposure, so the EV-bias dial
    /// actually moves exposure. In `.custom` the EV dial is a no-op (the
    /// controller never calls setEV after custom writes). No device (unit
    /// tests) → nothing custom was ever written → true.
    var isAutoExposure: Bool {
        guard let device = input?.device else { return true }
        return device.exposureMode != .custom
    }

    /// Phase 3 opt-in bracket: frames at the given EV offsets via
    /// AVCapturePhotoBracketSettings + AVCaptureManualExposureBracketedStillImageSettings.
    /// Uses its own delegate — never touches the normal capture path's
    /// `photoCont`. Throws when the session isn't running or the bracket fails.
    ///
    /// `motionCapShutter`: positive offsets past this motion-safe cap hold
    /// the shutter at the cap and raise ISO instead (Section D).
    ///
    /// Assumed-but-unverified on device: bracketed frames each deliver one
    /// `didFinishProcessingPhoto` before `didFinishCaptureFor`; the
    /// per-frame EV offset is read back from EXIF (order-independent).
    func captureExposureBracket(evOffsets: [Float], motionCapShutter: Double? = nil) async throws -> AOBracketFrames {
        let baseShutter = exposureSeconds
        let baseISO = iso
        let caps = capabilities
        let maxQuality = photoOutput.maxPhotoQualityPrioritization
        let mirror = isFront && mirrorFrontPhotos
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<AOBracketFrames, Error>) in
            queue.async { [weak self] in
                guard let self else { cont.resume(throwing: CamError.noDevice); return }
                guard self.session.isRunning else {
                    cont.resume(throwing: CamError.captureFailed); return
                }
                guard !self.photoOutput.connections.isEmpty else {
                    cont.resume(throwing: CamError.badOutput); return
                }
                let manual = AOBracketCapture.bracketedSettings(
                    baseShutter: baseShutter,
                    baseISO: baseISO,
                    offsets: evOffsets,
                    minShutter: caps.minExposureSeconds,
                    maxShutter: caps.maxExposureSeconds,
                    motionCapShutter: motionCapShutter,
                    maxISO: caps.maxISO)
                guard !manual.isEmpty else { cont.resume(throwing: CamError.captureFailed); return }
                // Processed (non-RAW) bracket: rawPixelFormatType 0 + explicit
                // JPEG processed format + the 5 manual-exposure bracket settings.
                let settings = AVCapturePhotoBracketSettings(
                    rawPixelFormatType: 0,
                    processedFormat: [AVVideoCodecKey: AVVideoCodecType.jpeg],
                    bracketedSettings: manual)
                // Must match photoOutput.maxPhotoQualityPrioritization or AVFoundation aborts (SIGABRT).
                settings.photoQualityPrioritization = maxQuality
                let delegate = AOBracketPhotoDelegate(continuation: cont)
                delegate.onDone = { [weak self, weak delegate] in
                    Task { @MainActor in
                        self?.activeBracketDelegates.removeAll { $0 === delegate }
                    }
                }
                self.activeBracketDelegates.append(delegate)
                Self.setMirroring(mirror, on: self.photoOutput)
                self.photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }


    // MARK: - Creative Look (user apply) + lens pick


    /// Drop non-actionable "not available" / "guidance only" / unsupported banners after Recommend.
    /// Keeps dial clamps the user can act on (zoom clamped, EV limited, etc.).
    func suppressDeadEndClampMessages() {
        let dead = ["not available", "unavailable", "unsupported", "guidance only", "couldn’t apply", "couldn't apply", "left as guidance", "left unchanged"]
        clampMessages.removeAll { msg in
            let lower = msg.lowercased()
            return dead.contains { lower.contains($0) }
        }
    }

    func setActiveLook(_ look: CreativeLook) {
        guard CreativeLookCatalog.isKnown(look.id) else {
            clampMessages.append("Look couldn’t apply")
            return
        }
        var copy = look
        if copy.intensity == nil { copy.intensity = CreativeLookCatalog.defaultIntensity }
        let changed = activeCreativeLook?.id != copy.id
        activeCreativeLook = copy
        applyNotes.append(
            String(format: "Look “\(copy.displayName)” @ %.0f%% — baking preview & still.", copy.resolvedIntensity * 100)
        )
        // Selfie look picked on the front camera → also set its capture light (not on intensity drags).
        if changed, isFront, let preset = SelfiePresets.preset(lookId: copy.id) {
            Task { @MainActor [weak self] in
                await self?.applySelfiePreset(preset, switchToFront: false, setLook: false)
            }
        }
    }

    func clearActiveLook() {
        activeCreativeLook = nil
    }

    func supportsLens(_ lens: LensChoice) -> Bool {
        let pos: AVCaptureDevice.Position = isFront ? .front : .back
        let type: AVCaptureDevice.DeviceType = {
            switch lens {
            case .ultraWide: return .builtInUltraWideCamera
            case .wide: return .builtInWideAngleCamera
            case .tele: return .builtInTelephotoCamera
            }
        }()
        let disc = AVCaptureDevice.DiscoverySession(
            deviceTypes: [type],
            mediaType: .video,
            position: pos
        )
        return !disc.devices.isEmpty
    }

    func selectLens(_ lens: LensChoice) {
        let name: String = {
            switch lens {
            case .ultraWide: return "ultrawide"
            case .wide: return "wide"
            case .tele: return "tele"
            }
        }()
        if switchCameraDevice(name) {
            selectedLens = lens
        }
    }

    /// When false, photo delegate skips Creative Look bake (probe / vision frames).
    private var bakeLookOnNextCapture = true
    /// Session-queue flag to reject overlapping capturePhoto calls.

    func capturePhoto(bakeLook: Bool = true) async throws -> Data {
        bakeLookOnNextCapture = bakeLook
        let mirror = isFront && mirrorFrontPhotos
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            queue.async { [weak self] in
                guard let self else { cont.resume(throwing: CamError.noDevice); return }
                guard self.session.isRunning else {
                    cont.resume(throwing: CamError.captureFailed)
                    return
                }
                guard !self.photoOutput.connections.isEmpty else {
                    cont.resume(throwing: CamError.badOutput)
                    return
                }
                Task { @MainActor in self.photoCont = cont }
                let settings = AVCapturePhotoSettings()
                // Must match photoOutput.maxPhotoQualityPrioritization or AVFoundation aborts (SIGABRT).
                settings.photoQualityPrioritization = self.photoOutput.maxPhotoQualityPrioritization
                if #available(iOS 16.0, *) {
                    let dims = self.photoOutput.maxPhotoDimensions
                    if dims.width > 0, dims.height > 0 {
                        settings.maxPhotoDimensions = dims
                    }
                }
                if self.photoOutput.supportedFlashModes.contains(self.flash.av) {
                    settings.flashMode = self.flash.av
                }
                Self.setMirroring(mirror, on: self.photoOutput)
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }


    func captureProbeFrame() async throws -> Data {
        // Prefer a silent viewfinder frame — no shutter sound, no flash.
        // Waits briefly for the first live frame, then gives up quietly.
        if let jpeg = viewfinderJPEG() { return jpeg }
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 150_000_000)
            try Task.checkCancellation()
            if let jpeg = viewfinderJPEG() { return jpeg }
        }
        throw CamError.noFrame
    }

    /// Latest viewfinder frame + presentation timestamp, or nil if the camera
    /// isn't streaming yet. Serialized on `videoQueue`.
    func latestFrame() -> (buffer: CVPixelBuffer, timestamp: CMTime)? {
        videoQueue.sync { latestProbeFrame }
    }

    /// Latest viewfinder frame as a small JPEG, or nil if the camera isn't streaming yet.
    /// Called from Tasks; pixel buffer is retained/released on `videoQueue`.
    private func viewfinderJPEG(maxDimension: CGFloat = 768, quality: CGFloat = 0.6) -> Data? {
        guard let pixelBuffer = latestFrame()?.buffer else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ciImage.extent
        let longest = max(extent.width, extent.height)
        let scaled: CIImage
        if longest > maxDimension {
            let s = maxDimension / longest
            scaled = ciImage.transformed(by: CGAffineTransform(scaleX: s, y: s))
        } else {
            scaled = ciImage
        }
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: quality)
    }

    func refreshReadouts() {
        guard let device = input?.device else { return }
        // Before the session is running exposureDuration can be an invalid CMTime (NaN seconds);
        // keep the last good readout instead of publishing NaN to the dial views.
        exposureSeconds = CameraValues.exposure(CMTimeGetSeconds(device.exposureDuration), fallback: exposureSeconds)
        iso = CameraValues.iso(device.iso, fallback: iso)
        evBias = CameraValues.evBias(device.exposureTargetBias, fallback: evBias)
    }

    var readoutLine: String {
        let f = apertureGuidance.map { " · \($0)" } ?? ""
        return "\(captureMode.shortLabel)\(f) · \(RecipeCameraMapper.formatShutter(exposureSeconds)) · ISO \(RecipeCameraMapper.formatISO(iso))"
    }

    /// Reads the live device state back after an apply — the verify step
    /// compares this against what the solver asked for.
    func readbackState() -> DeviceReadback {
        guard let device = input?.device else { return .unknown }
        let exposureMode: String = {
            switch device.exposureMode {
            case .custom: return "custom"
            case .locked: return "locked"
            case .autoExpose: return "autoExpose"
            case .continuousAutoExposure: return "continuousAutoExposure"
            @unknown default: return "unknown"
            }
        }()
        let focusMode: String = {
            switch device.focusMode {
            case .locked: return "locked"
            case .autoFocus: return "autoFocus"
            case .continuousAutoFocus: return "continuousAutoFocus"
            @unknown default: return "unknown"
            }
        }()
        return DeviceReadback(
            exposureMode: exposureMode,
            exposureDuration: CMTimeGetSeconds(device.exposureDuration),
            iso: device.iso,
            focusMode: focusMode,
            lensDeviceType: device.deviceType.rawValue,
            exposureTargetOffset: device.exposureTargetOffset
        )
    }

    /// Current white-balance gains (for HDR bracket consistency). Nil without a device.
    func currentWhiteBalanceGains() -> (red: Double, green: Double, blue: Double)? {
        guard let device = input?.device else { return nil }
        let g = device.deviceWhiteBalanceGains
        return (Double(g.redGain), Double(g.greenGain), Double(g.blueGain))
    }

    /// Current white-balance color temperature estimate (Kelvin), for Phase 3
    /// override-delta telemetry. Nil without a device.
    func currentWhiteBalanceKelvin() -> Float? {
        guard let device = input?.device else { return nil }
        return device.temperatureAndTintValues(for: device.deviceWhiteBalanceGains).temperature
    }

    /// Field of view of the active format, in degrees (for px/rad conversions).
    func activeFieldOfViewDegrees() -> Double? {
        guard let device = input?.device else { return nil }
        let fov = Double(device.activeFormat.videoFieldOfView)
        return fov > 0 ? fov : nil
    }

    /// Width (px) of the active video frame — the reference width the solver's
    /// motion speeds are expressed in.
    var videoFrameWidth: Double? {
        guard let device = input?.device else { return nil }
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        return dims.width > 0 ? Double(dims.width) : nil
    }

    /// Metering snapshot for the scene sensor: current exposure state before
    /// the solver writes custom exposure. Uses the top-level `MeteringSample`
    /// (SceneFeatures.swift) so the sensor and controller share one type.
    func meteringSample() -> MeteringSample {
        refreshReadouts()
        let device = input?.device
        let rb = readbackState()
        return MeteringSample(
            exposureSeconds: exposureSeconds > 0 ? exposureSeconds : nil,
            iso: iso > 0 ? iso : nil,
            aperture: device.map { Float($0.lensAperture) },
            exposureTargetOffset: rb.exposureTargetOffset,
            wasCustom: rb.exposureMode == "custom",
            fieldOfViewDegrees: activeFieldOfViewDegrees(),
            fullFrameWidthPx: videoFrameWidth,
            isFrontCamera: isFront
        )
    }

    // MARK: - Phase 1: closed-loop exposure (converge → plan → verify)

    /// Metered exposure product from a converged AE state.
    struct AEConvergeResult {
        var exposureSeconds: Double
        var iso: Float
        var timedOut: Bool
        /// When convergence finished — the controller requires the sensor
        /// snapshot's frame timestamp to be later than this (frames exposed
        /// under a previous run's custom exposure must not anchor `E_auto`).
        var convergedAt: Date = Date()
        /// `exposureSeconds × iso` — the anchor for the exposure planner.
        var eAuto: Double { exposureSeconds * Double(iso) }
    }

    /// Meters from a converged auto state, before sensing.
    ///
    /// Switches the device to `.continuousAutoExposure` at zero bias — this
    /// also clears any stale custom-exposure lock a previous run left behind
    /// — then waits until `!isAdjustingExposure &&
    /// abs(exposureTargetOffset) < 0.15 EV`, with a ~600 ms timeout. On
    /// timeout it proceeds anyway; the caller tracks `ae_converge_timeout`.
    ///
    /// Never blocks the capture queue: the waits yield the actor between polls.
    func convergeAutoExposure(timeoutNanoseconds: UInt64 = 600_000_000) async throws -> AEConvergeResult {
        guard let device = input?.device else {
            return AEConvergeResult(exposureSeconds: exposureSeconds, iso: iso, timedOut: true)
        }
        configure(device) {
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            // Reset the metering point to frame center so E_auto is metered
            // from a known point: a stale face/spot POI from a previous run
            // would bias the convergence and double-count the face EV that
            // is applied after custom exposure. Face stays the *focus* point
            // only.
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            let zeroBias = min(max(Float(0), capabilities.minEV), capabilities.maxEV)
            device.setExposureTargetBias(zeroBias, completionHandler: nil)
        }
        exposureLocked = false

        let deadline = Date().addingTimeInterval(Double(timeoutNanoseconds) / 1_000_000_000)
        var converged = false
        while Date() < deadline {
            try Task.checkCancellation()
            guard let device = input?.device else { break }
            if !device.isAdjustingExposure && abs(device.exposureTargetOffset) < 0.15 {
                converged = true
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        refreshReadouts()
        return AEConvergeResult(
            exposureSeconds: exposureSeconds, iso: iso, timedOut: !converged)
    }

    /// Closed-loop verify + correct after a custom-exposure apply.
    struct ExposureVerifyResult {
        /// Final `offset − targetEV`, in stops (+ means over — brighter than
        /// target; − means under). Same sign convention as
        /// `ExposurePlanner.Plan.residualEV`.
        var residualEV: Double
        var iterations: Int
        var clamped: Bool
        /// Error measured before any correction, in stops.
        var initialError: Double
        /// False when the device wasn't in custom mode — nothing to verify.
        var verified: Bool
    }

    /// Closed-loop verify + correct after a custom-exposure apply.
    ///
    /// Awaits the exact write each iteration issues (tracked by epoch in
    /// `issueExposureWrite` — never a timestamp left over from an earlier
    /// write), settles `2 × max(activeVideoMaxFrameDuration, exposureDuration)`
    /// (≤ 1.2 s) for the meter to catch up, then reads `exposureTargetOffset`.
    /// While |offset − targetEV| > 0.3 EV it corrects per the recipe's
    /// `priority` (A6), with at most `maxIterations` correction writes.
    /// The loop itself lives in `ExposureVerifyLoop` (unit-testable via the
    /// `ExposureWriteClock` seam); this is the thin device-backed entry point.
    func verifyExposure(
        targetEV: Double,
        priority: ExposurePlanner.Priority?,
        shutterCapSeconds: Double?,
        maxIterations: Int = 2
    ) async -> ExposureVerifyResult {
        // Normally a no-op: applyPhoneTargets awaited its writes before verify
        // started. Covers fire-and-forget issuers (dial taps) otherwise.
        await awaitInFlightExposureWrite()
        let r = await ExposureVerifyLoop.run(
            targetEV: targetEV, priority: priority,
            shutterCapSeconds: shutterCapSeconds,
            maxIterations: maxIterations, clock: self)
        refreshReadouts()
        return ExposureVerifyResult(
            residualEV: r.residualEV, iterations: r.iterations,
            clamped: r.clamped, initialError: r.initialError,
            verified: r.verified)
    }

    // MARK: - ExposureWriteClock (A1 test seam)

    /// Device-backed `ExposureWriteClock`: issue-write → await sync → settle →
    /// read offset. The verify loop (`ExposureVerifyLoop.run`) drives these;
    /// tests substitute a fake device.
    func issueWrite(durationSeconds: Double, iso: Float) async -> CMTime {
        guard CameraValues.finitePositive(durationSeconds) != nil, CameraValues.finitePositive(iso) != nil else { return .invalid }
        let d = min(max(durationSeconds, capabilities.minExposureSeconds), capabilities.maxExposureSeconds)
        let i = min(max(iso, capabilities.minISO), capabilities.maxISO)
        // No clamp banners here: corrections are internal; the loop reports
        // `clamped` and the controller turns it into a single verify note.
        let sync = await issueExposureWrite(
            duration: CMTime(seconds: d, preferredTimescale: 1_000_000), iso: i)
        exposureLocked = true
        exposureSeconds = CameraValues.exposure(d, fallback: exposureSeconds)
        self.iso = CameraValues.iso(i, fallback: self.iso)
        return sync
    }

    func settleAfterWrite(exposureDurationSeconds: Double) async {
        // ~2 frames at the active frame duration; in dim scenes the frame
        // duration is the shutter itself (1/8 s+), not 1/30 s. Bounded ≤ 1.2 s.
        let frame = activeVideoMaxFrameDurationSeconds()
        let wait = min(2 * max(frame, exposureDurationSeconds), 1.2)
        guard wait > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
    }

    func readExposureOffset() -> Float? {
        guard let device = input?.device, device.exposureMode == .custom else { return nil }
        return device.exposureTargetOffset
    }

    func currentExposure() -> (shutterSeconds: Double, iso: Float) {
        if let device = input?.device {
            let s = CMTimeGetSeconds(device.exposureDuration)
            if s.isFinite, s > 0, device.iso.isFinite, device.iso > 0 { return (s, device.iso) }
        }
        return (exposureSeconds, iso)
    }

    var isoRange: ClosedRange<Float> { capabilities.minISO...capabilities.maxISO }
    var shutterRange: ClosedRange<Double> { capabilities.minExposureSeconds...capabilities.maxExposureSeconds }

    /// Active video max frame duration in seconds; 1/30 s when unavailable.
    private func activeVideoMaxFrameDurationSeconds() -> Double {
        guard let device = input?.device else { return 1 / 30 }
        let s = CMTimeGetSeconds(device.activeVideoMaxFrameDuration)
        return s > 0 ? s : 1 / 30
    }

    private func configure(_ device: AVCaptureDevice, _ block: () throws -> Void) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            try block()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    enum CamError: LocalizedError {
        case noDevice, badInput, badOutput, captureFailed, noFrame
        var errorDescription: String? {
            switch self {
            case .noDevice: return "No camera available."
            case .badInput: return "Could not open camera input."
            case .badOutput: return "Could not configure photo output."
            case .captureFailed: return "Capture failed — try again"
            case .noFrame: return "Camera preview not ready yet."
            }
        }
    }
}

/// CameraSession is the production `ExposureWriteClock` (A1 seam).
extension CameraSession: ExposureWriteClock {}

/// Pure policy for the exposure seam: EV bias is folded into the ISO solve when
/// custom shutter/ISO was written in the same apply; programming a bias on top
/// would fight the solve (and the old `setEV` even reset the exposure mode).
/// Unit-tested — this is the seam that proves `setEV` is never called after
/// `setCustom` in one apply.
enum ExposureApplyPolicy {
    /// Returns the bias to program via `setEV`, or nil to skip the call.
    static func evBiasToProgram(evRaw: String?, wroteCustomExposure: Bool) -> Float? {
        guard !wroteCustomExposure else { return nil }
        guard let raw = evRaw else { return nil }
        return RecipeCameraMapper.parseEV(raw)
    }

    /// `apply(recipe:)` variant — same rule from mapped dial values.
    static func wroteCustomExposure(shutter: Double?, iso: Float?, supported: Bool) -> Bool {
        guard supported else { return false }
        return shutter != nil || iso != nil
    }
}

/// Live device state read back after an apply (verify step).
struct DeviceReadback: Equatable {
    var exposureMode: String
    var exposureDuration: Double
    var iso: Float
    var focusMode: String
    var lensDeviceType: String
    var exposureTargetOffset: Float

    static let unknown = DeviceReadback(
        exposureMode: "unknown",
        exposureDuration: 0,
        iso: 0,
        focusMode: "unknown",
        lensDeviceType: "unknown",
        exposureTargetOffset: 0
    )
}

extension CameraSession: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        Task { @MainActor in
            let cont = photoCont
            photoCont = nil
            if let error { cont?.resume(throwing: error); return }
            guard let data = photo.fileDataRepresentation() else {
                cont?.resume(throwing: CamError.captureFailed); return
            }
            let out: Data
            if self.bakeLookOnNextCapture {
                out = CreativeLookEngine.shared.bakeJPEG(data, look: self.activeCreativeLook)
            } else {
                out = data
            }
            self.bakeLookOnNextCapture = true
            lastThumb = UIImage(data: out)
            cont?.resume(returning: out)
        }
    }
}

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Runs on `videoQueue`. Storing into the strong var retains the frame
        // (Swift retains the unretained Get-rule return); the previous frame
        // is released by ARC, keeping memory flat.
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        latestProbeFrame = (buffer: pixelBuffer, timestamp: timestamp)
        // Hop to the consumer off the capture path — Vision never blocks frames.
        Task { @MainActor [weak self] in
            self?.frameConsumer?(pixelBuffer, timestamp)
        }
    }
}
