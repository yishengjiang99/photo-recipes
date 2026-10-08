import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import os.log

// MARK: - Phase 3 opt-in exposure bracket
//
// "Help improve Auto Optimize" (Settings, OFF by default): after an AO Ready,
// capture a 5-frame exposure bracket (−2…+2 EV) via
// AVCapturePhotoBracketSettings + AVCaptureManualExposureBracketedStillImageSettings
// and store the downsampled frames + EXIF + stats LOCALLY (app sandbox).
//
// Privacy contract:
// - Nothing is ever uploaded automatically or in the background.
// - Upload requires an explicit Settings tap + confirmation (the gate), and
//   the transport is a declared stub until the server endpoint exists.
// - Bracket capture never blocks the AO critical path: it is ARMED at Ready
//   and fires right after the user's own capture completes (Section D —
//   no timer that can collide with the shutter), skips when a newer run
//   started or a user capture is in flight, and soft-fails (logged) on any
//   error. The user's shutter always wins — photoOutput serializes requests,
//   so a tap during the bracket just queues behind it.

/// One AO run's bracket request. `isCurrent` is evaluated on the main actor
/// at fire time — a newer run (generation bump) or `clear()` drops the armed
/// bracket. `userCaptureInFlight` yields to a racing second shutter tap.
struct AOBracketRun {
    var runId: String
    var recipeId: String
    var capturedAt: Date
    var coachOnly: Bool
    var features: SceneFeatures
    var isCurrent: () -> Bool
    /// True while the user's own capture is in flight (their shutter wins).
    var userCaptureInFlight: () -> Bool = { false }
    /// Motion-safe shutter cap (s) from the run's exposure plan; nil when the
    /// run didn't write custom exposure.
    var motionCapShutter: Double? = nil
    /// Planner target EV at Ready (label anchor).
    var planTargetEV: Double? = nil
    /// Dials actually applied at Ready (label anchors).
    var appliedShutterSec: Double? = nil
    var appliedISO: Float? = nil
    /// Verify residual at Ready, in EV (label anchor).
    var verifyResidualEV: Double? = nil
    var lensDeviceType: String? = nil
}

/// Sendable manifest written next to the frames (meta.json) and used by the
/// future explicit-consent uploader. Numeric only — never pixels.
struct AOBracketManifest: Sendable, Codable, Equatable {
    /// meta.json schema — bump when the sidecar gains/loses keys.
    static let schemaVersion = 1

    var runId: String
    var recipeId: String
    var capturedAt: Date
    var coachOnly: Bool
    var gpuSource: String?
    var highlightClipFraction: Float
    var shadowCrushFraction: Float
    var lumaContrast: Float?
    var grayWorldR: Float?
    var grayWorldG: Float?
    var grayWorldB: Float?
    var sceneLabels: [SceneLabel]?
    var faceCount: Int?
    var handShakeRadPerSec: Float
    // Label anchors (Section D): everything needed to label the bracket set
    // without joining telemetry.
    /// Metered exposure product at Ready: (t·ISO) from the scene sensor —
    /// same formula as `AOTelemetrySerializer.readyProps`' e_auto.
    var eAuto: Double?
    var planTargetEV: Double?
    var appliedShutterSec: Double?
    var appliedISO: Float?
    var verifyResidualEV: Double?
    /// The motion-safe shutter cap the bracket was built against (s).
    var motionCapShutter: Double?
    var deviceModel: String
    var lensDeviceType: String?

    init(run: AOBracketRun) {
        let f = run.features
        runId = run.runId
        recipeId = run.recipeId
        capturedAt = run.capturedAt
        coachOnly = run.coachOnly
        gpuSource = f.gpuStatsFresh ? f.gpuStatsSource : nil
        highlightClipFraction = f.highlightClipFraction
        shadowCrushFraction = f.shadowCrushFraction
        lumaContrast = f.lumaContrast
        grayWorldR = f.grayWorldMeanR
        grayWorldG = f.grayWorldMeanG
        grayWorldB = f.grayWorldMeanB
        sceneLabels = f.sceneLabels
        faceCount = f.faceCount
        handShakeRadPerSec = f.handShakeRadPerSec
        eAuto = (f.meteredExposureSeconds ?? 1 / 60) * Double(f.meteredISO ?? 100)
        planTargetEV = run.planTargetEV
        appliedShutterSec = run.appliedShutterSec
        appliedISO = run.appliedISO
        verifyResidualEV = run.verifyResidualEV
        motionCapShutter = run.motionCapShutter
        deviceModel = AOTelemetrySerializer.deviceModelIdentifier()
        lensDeviceType = run.lensDeviceType
    }
}

@MainActor
final class AOBracketCapture: ObservableObject {
    static let shared = AOBracketCapture()

    private let log = Logger(subsystem: "com.ragnus.mvp", category: "AOBracket")

    /// UserDefaults key for the "Help improve Auto Optimize" opt-in.
    /// Default OFF: `bool(forKey:)` returns false when unset.
    static let optInDefaultsKey = "autoOptimize.improveOptIn"
    /// Nonisolated: plain UserDefaults access (thread-safe), reachable from
    /// Settings and unit tests without a MainActor hop.
    nonisolated static var optedIn: Bool {
        get { UserDefaults.standard.bool(forKey: optInDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: optInDefaultsKey) }
    }

    /// 5-frame bracket: −2, −1, 0, +1, +2 EV around the current exposure.
    static let evOffsets: [Float] = [-2, -1, 0, 1, 2]

    /// While the bracket capture + store runs — the view shows a small
    /// "Saving improvement data…" chip.
    @Published var isSavingBracketData = false

    /// Test seam: replaces the hardware bracket capture.
    var captureBracketOverride: ((CameraSession, [Float], Double?) async throws -> AOBracketFrames)?
    /// Test seam: bracket store (tests point it at a temp dir).
    var bracketStore: AOBracketStore = .shared

    private var inFlight = false
    /// Armed (not yet fired) bracket request — fires on the next user capture
    /// completion while the run is still current.
    private var armedRun: AOBracketRun?

    /// Arm the opt-in bracket at AO Ready. The bracket fires right after the
    /// user's own capture completes (they're holding still on that scene) —
    /// never on a timer that can collide with the shutter. No-ops when the
    /// toggle is off, a bracket is already in flight/armed, or on thermal
    /// .critical. Never throws — soft-fails with a log.
    func armBracket(run: AOBracketRun) {
        guard Self.optedIn else { return }
        guard !inFlight else {
            log.debug("bracket skipped — already in flight")
            return
        }
        guard armedRun == nil else {
            log.debug("bracket skipped — already armed")
            return
        }
        guard ProcessInfo.processInfo.thermalState != .critical else {
            log.info("bracket skipped — thermal critical")
            return
        }
        armedRun = run
    }

    /// Capture-completion hook — call after the user's photo returns. Fires
    /// the armed bracket when the run is still current and no user capture is
    /// in flight; otherwise the armed request is dropped. Shows the
    /// "Saving improvement data…" chip while running. Never throws.
    func userCaptureDidComplete(session: CameraSession) {
        guard let run = armedRun else { return }
        armedRun = nil
        guard Self.optedIn else { return }
        guard !inFlight else { return }
        inFlight = true
        isSavingBracketData = true
        let captureOverride = captureBracketOverride
        let store = bracketStore
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.inFlight = false; self.isSavingBracketData = false }
            // A racing second shutter tap wins — re-check on the main actor
            // before touching the photo output.
            await Task.yield()
            guard !Task.isCancelled else { return }
            guard run.isCurrent() else {
                self.log.debug("bracket skipped — run no longer current")
                return
            }
            guard !run.userCaptureInFlight() else {
                self.log.debug("bracket skipped — user capture in flight")
                return
            }
            guard ProcessInfo.processInfo.thermalState != .critical else {
                self.log.info("bracket skipped — thermal critical")
                return
            }
            let frames: [Data]
            do {
                if let captureOverride {
                    frames = try await captureOverride(session, Self.evOffsets, run.motionCapShutter)
                } else {
                    frames = try await session.captureExposureBracket(
                        evOffsets: Self.evOffsets, motionCapShutter: run.motionCapShutter)
                }
            } catch {
                self.log.error("bracket capture failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard !frames.isEmpty else { return }
            // CPU-heavy downsample + disk writes leave the main actor.
            let manifest = AOBracketManifest(run: run)
            await Task.detached {
                do {
                    try store.storeBracketSync(manifest: manifest, frames: frames)
                } catch {
                    Logger(subsystem: "com.ragnus.mvp", category: "AOBracket")
                        .error("bracket store failed: \(error.localizedDescription, privacy: .public)")
                }
            }.value
            Analytics.shared.track("ao_bracket_stored", props: [
                "run_id": run.runId,
                "recipe_id": run.recipeId,
                "frames": "\(frames.count)",
            ])
        }
    }

    /// Pure construction of the 5 manual-exposure bracket settings.
    /// Negative offsets (and positive ones within the motion-safe cap) scale
    /// the shutter by 2^offset at constant ISO, clamped to device limits.
    /// Positive offsets past `motionCapShutter` hold the shutter AT the cap
    /// and raise ISO instead — in dim scenes a 2–4× longer shutter picks up
    /// motion blur that would bias "best frame" labels toward darker frames.
    /// Unit-testable: no hardware touched. Nonisolated: pure function.
    nonisolated static func bracketedSettings(
        baseShutter: Double,
        baseISO: Float,
        offsets: [Float],
        minShutter: Double,
        maxShutter: Double,
        motionCapShutter: Double? = nil,
        maxISO: Float? = nil
    ) -> [AVCaptureManualExposureBracketedStillImageSettings] {
        offsets.map { offset in
            let desiredShutter = baseShutter * pow(2, Double(offset))
            var shutter = min(max(desiredShutter, minShutter), maxShutter)
            var iso = baseISO
            if offset > 0, let cap = motionCapShutter, cap > 0, desiredShutter > cap {
                shutter = min(max(cap, minShutter), maxShutter)
                if shutter > 0 {
                    iso = Float(Double(baseISO) * desiredShutter / shutter)
                }
                if let maxISO, maxISO > 0 { iso = min(iso, maxISO) }
            }
            return AVCaptureManualExposureBracketedStillImageSettings.manualExposureSettings(
                exposureDuration: CMTimeMakeWithSeconds(shutter, preferredTimescale: 1_000_000),
                iso: iso
            )
        }
    }
}

// MARK: - Bracket photo delegate (separate from the normal capture path)

/// One captured JPEG per bracketed frame.
typealias AOBracketFrames = [Data]

/// Accumulates one `didFinishProcessingPhoto` per bracketed frame, then
/// resolves when the bracket completes. Never touches `CameraSession.photoCont`.
final class AOBracketPhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let lock = NSLock()
    private let continuation: CheckedContinuation<AOBracketFrames, Error>
    private var frames: AOBracketFrames = []
    private var errors: [Error] = []
    private var done = false
    /// Called (once) on completion so the session can drop its strong ref.
    var onDone: (() -> Void)?

    init(continuation: CheckedContinuation<AOBracketFrames, Error>) {
        self.continuation = continuation
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        if let error { errors.append(error); return }
        if let data = photo.fileDataRepresentation() { frames.append(data) }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        if let error { errors.append(error) }
        let frames = self.frames
        let errors = self.errors
        let onDone = self.onDone
        // Resume off the lock — the continuation may hop threads.
        DispatchQueue.global().async {
            if frames.isEmpty, let first = errors.first {
                self.continuation.resume(throwing: first)
            } else {
                self.continuation.resume(returning: frames)
            }
            onDone?()
        }
    }
}

// MARK: - Downsample + EXIF helpers (pure ImageIO; unit-testable)

enum AOBracketDownsampler {
    /// Long-side cap for stored bracket frames.
    static let maxPixelSize = 640
    /// JPEG quality for stored frames.
    static let jpegQuality = 0.7

    /// Downsample a captured JPEG to ≤640px, re-encode at 0.7 quality.
    /// Returns nil when the input isn't a decodable image.
    ///
    /// Privacy: the output is a FRESH JPEG written from bare pixel data with
    /// only the compression-quality property — no EXIF, GPS, TIFF, or other
    /// metadata dictionary is ever copied, so GPS and other non-exposure EXIF
    /// are stripped by construction before anything reaches the store or the
    /// upload manifest. (Per-frame shutter/ISO are read from the ORIGINAL
    /// frame's EXIF before downsampling and recorded numerically in
    /// meta.json; the originals are discarded.)
    static func downsampleJPEG(_ data: Data) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOptions as CFDictionary) else {
            return nil
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, thumb, [
            kCGImageDestinationLossyCompressionQuality: jpegQuality,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// Exposure time + ISO from a captured JPEG's EXIF. Used to label each
    /// bracket frame with its true EV offset (order-independent).
    static func exifExposure(_ data: Data) -> (exposureSeconds: Double, iso: Double)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let t = exif[kCGImagePropertyExifExposureTime] as? Double, t > 0
        else { return nil }
        // ISOSpeedRatings may be a single number or an array.
        let iso: Double? = {
            if let v = exif[kCGImagePropertyExifISOSpeedRatings] as? Double { return v }
            if let arr = exif[kCGImagePropertyExifISOSpeedRatings] as? [Double] { return arr.first }
            if let arr = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int] { return arr.first.map(Double.init) }
            return nil
        }()
        return (t, iso ?? 0)
    }
}
