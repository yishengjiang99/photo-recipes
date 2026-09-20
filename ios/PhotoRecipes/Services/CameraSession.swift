import AVFoundation
import UIKit
import Combine

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
        var av: AVCaptureDevice.FlashMode {
            switch self { case .off: return .off; case .on: return .on; case .auto: return .auto }
        }
    }

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "photo-recipes.camera")
    private let photoOutput = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    private var photoCont: CheckedContinuation<Data, Error>?

    @Published var auth: AuthState = .notDetermined
    @Published var isRunning = false
    @Published var errorMessage: String?
    @Published var capabilities = DeviceCapabilities.unknown
    @Published var captureMode: CaptureMode = .auto
    @Published var flash: FlashCycle = .off
    @Published var showGrid = true
    @Published var isFront = false
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
                    session.commitConfiguration()
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
        capabilities = DeviceCapabilities(
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
        )
    }

    func setShutter(_ seconds: Double) {
        guard let device = input?.device, device.isExposureModeSupported(.custom) else {
            clampMessages.append("Shutter lock unavailable on this lens/format.")
            return
        }
        let clamped = min(max(seconds, capabilities.minExposureSeconds), capabilities.maxExposureSeconds)
        if clamped != seconds {
            clampMessages.append("Shutter clamped to \(RecipeCameraMapper.formatShutter(clamped)).")
        }
        configure(device) {
            let t = CMTime(seconds: clamped, preferredTimescale: 1_000_000)
            device.setExposureModeCustom(duration: t, iso: device.iso, completionHandler: nil)
        }
        exposureLocked = true
        exposureSeconds = clamped
        if captureMode == .auto || captureMode == .program { captureMode = .shutter }
    }

    func setISO(_ value: Float) {
        guard let device = input?.device, device.isExposureModeSupported(.custom) else {
            clampMessages.append("ISO lock unavailable on this lens/format.")
            return
        }
        let clamped = min(max(value, capabilities.minISO), capabilities.maxISO)
        configure(device) {
            device.setExposureModeCustom(duration: device.exposureDuration, iso: clamped, completionHandler: nil)
        }
        exposureLocked = true
        iso = clamped
        if captureMode == .auto { captureMode = .manual }
    }

    func setEV(_ bias: Float) {
        guard let device = input?.device else { return }
        let clamped = min(max(bias, capabilities.minEV), capabilities.maxEV)
        configure(device) {
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.setExposureTargetBias(clamped, completionHandler: nil)
        }
        exposureLocked = false
        evBias = clamped
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

    func focus(at norm: CGPoint, lock: Bool) {
        guard let device = input?.device else { return }
        let clamped = CGPoint(x: min(max(norm.x, 0), 1), y: min(max(norm.y, 0), 1))
        focusPoint = clamped
        configure(device) {
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = clamped }
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = clamped }
            if lock, device.isFocusModeSupported(.locked) {
                device.focusMode = .locked
            } else if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            } else if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
        }
        focusLocked = lock
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
    func apply(recipe: Recipe, dials: DialSettings? = nil) -> Bool {
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
            setCustom(duration: s, iso: i)
        } else if let s = mapped.shutterSeconds, capabilities.supportsCustomExposure {
            setShutter(s)
        } else if let i = mapped.iso, capabilities.supportsCustomExposure {
            setISO(i)
        }
        if let ev = mapped.evCompensation { setEV(ev) }
        return true
    }


    /// Shared with Auto Optimize button + Camera voice. Wire keys locked to server #21.
    /// Always writes phone-settable levers (Free Peek + Pro). Capability-gate every lever;
    /// skip unsupported; never pretend aperture was set. Quota lives in AutoOptimizeController.
    @discardableResult
    func applyPhoneTargets(_ targets: PhoneTargets) -> Bool {
        var wrote = false

        // Prefer optical cameraDevice over zoom-only.
        if let cam = targets.cameraDevice, switchCameraDevice(cam) {
            wrote = true
        }

        let durationSec = targets.exposureDurationSec
            ?? targets.shutter.flatMap { RecipeCameraMapper.parseShutter($0) }
        let isoVal: Float? = targets.iso.flatMap { RecipeCameraMapper.parseISO($0) }

        if let d = durationSec, let i = isoVal, capabilities.supportsCustomExposure {
            setCustom(duration: d, iso: i)
            wrote = true
        } else if let d = durationSec, capabilities.supportsCustomExposure {
            setShutter(d)
            wrote = true
        } else if let i = isoVal, capabilities.supportsCustomExposure {
            setISO(i)
            wrote = true
        } else if durationSec != nil || isoVal != nil {
            clampMessages.append("Custom exposure unavailable on this lens/format — guidance only.")
        }

        if let raw = targets.ev, let bias = RecipeCameraMapper.parseEV(raw) {
            setEV(bias)
            wrote = true
        }

        if let lp = targets.lensPosition, setLensPosition(lp) {
            wrote = true
        }

        if let fp = targets.focusPoint {
            let lock = (targets.focusMode?.lowercased()).map { ["locked", "lock", "near"].contains($0) } ?? true
            focus(at: fp.cgPoint, lock: lock)
            wrote = true
        } else if targets.lensPosition == nil, let focusMode = targets.focusMode?.lowercased() {
            switch focusMode {
            case "locked", "lock", "near":
                focus(at: focusPoint ?? CGPoint(x: 0.5, y: 0.5), lock: true)
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

        if let torch = targets.torch, applyTorch(torch) {
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

        // P1 — creativeLook is suggested to UI (never silent apply). Capture settings stay primary.
        // AutoOptimizeController promotes targets.creativeLook → suggestedLook chip (Apply/Dismiss).
        if let look = targets.creativeLook, !look.id.isEmpty {
            let intensity = look.intensity ?? CreativeLookCatalog.defaultIntensity
            applyNotes.append(
                String(format: "Suggested look “\(look.id)” @ %.0f%% — Apply from chip to bake preview & still.", intensity * 100)
            )
            wrote = true
        }

        // P1 — simulatedAperture only if OS API exists; else coach.
        if let sa = targets.simulatedAperture {
            if applySimulatedAperture(sa) {
                wrote = true
            } else {
                let msg = String(format: "f/%.1f guidance only — phone lens is fixed.", sa)
                simulatedApertureCoach = msg
                clampMessages.append(msg)
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

    private func setCustom(duration: Double, iso isoVal: Float) {
        guard let device = input?.device, device.isExposureModeSupported(.custom) else { return }
        let d = min(max(duration, capabilities.minExposureSeconds), capabilities.maxExposureSeconds)
        let i = min(max(isoVal, capabilities.minISO), capabilities.maxISO)
        configure(device) {
            let t = CMTime(seconds: d, preferredTimescale: 1_000_000)
            device.setExposureModeCustom(duration: t, iso: i, completionHandler: nil)
        }
        exposureLocked = true
        exposureSeconds = d
        iso = i
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

    @discardableResult
    func applyFlash(_ raw: String) -> Bool {
        switch raw.lowercased() {
        case "on": flash = .on
        case "auto": flash = .auto
        default: flash = .off
        }
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
        guard let fps, fps > 0 else { return choseFormat }
        let duration = CMTime(value: 1, timescale: CMTimeScale(max(1, Int(fps.rounded()))))
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


    // MARK: - Creative Look (user apply) + lens pick

    func setActiveLook(_ look: CreativeLook) {
        guard CreativeLookCatalog.isKnown(look.id) else {
            clampMessages.append("Look couldn’t apply")
            return
        }
        var copy = look
        if copy.intensity == nil { copy.intensity = CreativeLookCatalog.defaultIntensity }
        activeCreativeLook = copy
        applyNotes.append(
            String(format: "Look “\(copy.displayName)” @ %.0f%% — baking preview & still.", copy.resolvedIntensity * 100)
        )
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
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }


    func captureProbeFrame() async throws -> Data { try await capturePhoto(bakeLook: false) }

    func refreshReadouts() {
        guard let device = input?.device else { return }
        exposureSeconds = CMTimeGetSeconds(device.exposureDuration)
        iso = device.iso
        evBias = device.exposureTargetBias
    }

    var readoutLine: String {
        let f = apertureGuidance.map { " · \($0)" } ?? ""
        return "\(captureMode.shortLabel)\(f) · \(RecipeCameraMapper.formatShutter(exposureSeconds)) · ISO \(Int(iso.rounded()))"
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
        case noDevice, badInput, badOutput, captureFailed
        var errorDescription: String? {
            switch self {
            case .noDevice: return "No camera available."
            case .badInput: return "Could not open camera input."
            case .badOutput: return "Could not configure photo output."
            case .captureFailed: return "Capture failed — try again"
            }
        }
    }
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
