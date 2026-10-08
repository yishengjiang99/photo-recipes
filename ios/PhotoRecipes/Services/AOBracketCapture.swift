import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
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
// - Bracket capture never blocks the AO critical path: it fires ~2 s after
//   Ready in its own task, skips when a newer run started, and soft-fails
//   (logged) on any error. The user's shutter always wins — photoOutput
//   serializes requests, so a tap during the bracket just queues behind it.

/// One AO run's bracket request. `isCurrent` is evaluated on the main actor
/// after the post-Ready delay — a newer run or a capture in between cancels
/// the bracket.
struct AOBracketRun {
    var runId: String
    var recipeId: String
    var capturedAt: Date
    var coachOnly: Bool
    var features: SceneFeatures
    var isCurrent: () -> Bool
}

/// Sendable manifest written next to the frames (meta.json) and used by the
/// future explicit-consent uploader. Numeric only — never pixels.
struct AOBracketManifest: Sendable, Codable, Equatable {
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
    }
}

@MainActor
final class AOBracketCapture {
    static let shared = AOBracketCapture()

    private let log = Logger(subsystem: "com.ragnus.mvp", category: "AOBracket")

    /// UserDefaults key for the "Help improve Auto Optimize" opt-in.
    /// Default OFF: `bool(forKey:)` returns false when unset.
    static let optInDefaultsKey = "autoOptimize.improveOptIn"
    static var optedIn: Bool {
        get { UserDefaults.standard.bool(forKey: optInDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: optInDefaultsKey) }
    }

    /// 5-frame bracket: −2, −1, 0, +1, +2 EV around the current exposure.
    static let evOffsets: [Float] = [-2, -1, 0, 1, 2]
    /// Post-Ready delay so the user's immediate shutter tap wins the queue.
    static let bracketDelayNanoseconds: UInt64 = 2_000_000_000

    private var inFlight = false

    /// Fire-and-forget after AO Ready. No-ops when the toggle is off, when a
    /// bracket is already in flight, on thermal .critical, or when the run is
    /// no longer current after the delay. Never throws — soft-fails with a log.
    func maybeCaptureBracket(session: CameraSession, run: AOBracketRun) {
        guard Self.optedIn else { return }
        guard !inFlight else {
            log.debug("bracket skipped — already in flight")
            return
        }
        inFlight = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.inFlight = false }
            try? await Task.sleep(nanoseconds: Self.bracketDelayNanoseconds)
            guard !Task.isCancelled else { return }
            guard run.isCurrent() else {
                self.log.debug("bracket skipped — run no longer current")
                return
            }
            guard ProcessInfo.processInfo.thermalState != .critical else {
                self.log.info("bracket skipped — thermal critical")
                return
            }
            let frames: [Data]
            do {
                frames = try await session.captureExposureBracket(evOffsets: Self.evOffsets)
            } catch {
                self.log.error("bracket capture failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard !frames.isEmpty else { return }
            // CPU-heavy downsample + disk writes leave the main actor.
            let manifest = AOBracketManifest(run: run)
            let store = AOBracketStore.shared
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

    /// Pure construction of the 5 manual-exposure bracket settings, scaling
    /// the shutter by 2^offset at constant ISO, clamped to device limits.
    /// Unit-testable: no hardware touched.
    static func bracketedSettings(
        baseShutter: Double,
        baseISO: Float,
        offsets: [Float],
        minShutter: Double,
        maxShutter: Double
    ) -> [AVCaptureManualExposureBracketedStillImageSettings] {
        offsets.map { offset in
            let shutter = min(max(baseShutter * pow(2, Double(offset)), minShutter), maxShutter)
            return AVCaptureManualExposureBracketedStillImageSettings.manualExposureSettings(
                exposureDuration: CMTimeMakeWithSeconds(shutter, preferredTimescale: 1_000_000),
                iso: baseISO
            )
        }
    }
}

// MARK: - Bracket photo delegate (separate from the normal capture path)

/// Accumulates one `didFinishProcessingPhoto` per bracketed frame, then
/// resolves when the bracket completes. Never touches `CameraSession.photoCont`.
final class AOBracketPhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let lock = NSLock()
    private let continuation: CheckedContinuation<[Data], Error>
    private var frames: [Data] = []
    private var errors: [Error] = []
    private var done = false
    /// Called (once) on completion so the session can drop its strong ref.
    var onDone: (() -> Void)?

    init(continuation: CheckedContinuation<[Data], Error]) {
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
            out, kUTTypeJPEG as String, 1, nil) else { return nil }
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
