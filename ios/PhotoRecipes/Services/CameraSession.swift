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

    private var configured = false

    func checkAuth() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: auth = .authorized
        case .notDetermined:
            auth = await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
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
        queue.async { [weak self] in
            self?.session.stopRunning()
            Task { @MainActor in self?.isRunning = false }
        }
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
        focusPoint = norm
        configure(device) {
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = norm }
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = norm }
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

    @discardableResult
    func apply(recipe: Recipe, dials: DialSettings? = nil, asPro: Bool) -> Bool {
        let dials = dials ?? recipe.dials
        appliedRecipeId = recipe.id
        appliedRecipeTitle = recipe.title
        clampMessages = []
        applyNotes = []
        let mapped = RecipeCameraMapper.map(dials: dials, capabilities: capabilities)
        apertureGuidance = mapped.apertureGuidance
        applyNotes = mapped.notes + mapped.unsupported

        guard asPro else {
            applyNotes.insert("Free Peek: recipe staged as guidance. Upgrade to write settable exposure/focus.", at: 0)
            return false
        }

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


    /// Shared with Auto Optimize button + Camera voice: write phone-settable targets when Pro.
    @discardableResult
    func applyPhoneTargets(_ targets: PhoneTargets, asPro: Bool) -> Bool {
        guard asPro else {
            clampMessages.append("Pro required to write phoneTargets (shutter/ISO/EV/focus).")
            return false
        }
        var wrote = false
        if let raw = targets.shutter, let sec = RecipeCameraMapper.parseShutter(raw) {
            setShutter(sec)
            wrote = true
        }
        if let raw = targets.iso, let val = RecipeCameraMapper.parseISO(raw) {
            setISO(val)
            wrote = true
        }
        if let raw = targets.ev, let bias = RecipeCameraMapper.parseEV(raw) {
            setEV(bias)
            wrote = true
        }
        if let focus = targets.focusMode?.lowercased() {
            switch focus {
            case "locked", "lock", "near":
                let pt = focusPoint ?? CGPoint(x: 0.5, y: 0.5)
                focus(at: pt, lock: true)
                wrote = true
            case "continuous", "auto", "infinity":
                unlockFocus()
                wrote = true
            default:
                clampMessages.append("Focus mode “\(focus)” left as guidance.")
            }
        }
        if let wb = targets.whiteBalance, !wb.isEmpty {
            if capabilities.supportsWhiteBalanceLock, let device = input?.device {
                configure(device) {
                    if device.isWhiteBalanceModeSupported(.locked) {
                        device.whiteBalanceMode = .locked
                    }
                }
                whiteBalanceLocked = true
                wrote = true
            } else {
                clampMessages.append("WB “\(wb)” — guidance only on this device.")
            }
        }
        return wrote
    }

    func clearRecipe() {
        appliedRecipeId = nil
        appliedRecipeTitle = nil
        apertureGuidance = nil
        clampMessages = []
        applyNotes = []
        optimizeReason = nil
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

    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            queue.async { [weak self] in
                guard let self else { cont.resume(throwing: CamError.noDevice); return }
                Task { @MainActor in self.photoCont = cont }
                let settings = AVCapturePhotoSettings()
                if self.photoOutput.supportedFlashModes.contains(self.flash.av) {
                    settings.flashMode = self.flash.av
                }
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func captureProbeFrame() async throws -> Data { try await capturePhoto() }

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
            lastThumb = UIImage(data: data)
            cont?.resume(returning: data)
        }
    }
}
