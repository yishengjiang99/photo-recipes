import Foundation
import CoreGraphics
import CoreImage
import CoreVideo
import CoreMedia
import UIKit
import os.log

/// What the sensor hands to Auto Optimize on tap.
struct SceneSnapshot {
    var features: SceneFeatures
    /// Seconds since the 1 Hz semantic snapshot was taken.
    var age: TimeInterval
    /// When the snapshot's frame was analyzed. The controller requires this
    /// to postdate AE convergence — frames exposed under a previous run's
    /// custom exposure would anchor `E_auto` to the wrong light level.
    /// Defaults to the distant past (conservative: forces a refresh).
    var frameAt: Date = .distantPast

    /// True when this snapshot's frame predates AE convergence — the caller
    /// should `refreshNow` instead of scoring from it.
    func predatesConvergence(_ convergedAt: Date) -> Bool {
        frameAt <= convergedAt
    }
}

/// Hysteresis for semantic groups so labels don't flicker frame to frame:
/// a group becomes active at confidence ≥ 0.5 and stays active until it
/// drops below 0.35.
struct SemanticHysteresis {
    private(set) var active = Set<SemanticGroup>()

    mutating func filter(_ groups: [SemanticGroup: Float]) -> [SemanticGroup: Float] {
        var out: [SemanticGroup: Float] = [:]
        for group in SemanticGroup.allCases {
            let conf = groups[group] ?? 0
            let wasActive = active.contains(group)
            let isActive = wasActive ? conf >= 0.35 : conf >= 0.5
            if isActive {
                active.insert(group)
                out[group] = conf
            } else {
                active.remove(group)
            }
        }
        return out
    }
}

/// Continuous on-device scene sensing, fed by the camera's video data output
/// delegate. No network, no pixels leave the device.
///
/// Cadences:
/// - every frame: stash the latest pixel buffer + timestamp (cheap).
/// - ~5 Hz: optical flow on the newest frame pair; exponential moving average
///   of the motion features.
/// - ~1 Hz: classification, subject detection, saliency, histogram; EMAs with
///   hysteresis on semantic groups (enter at 0.5, exit at 0.35) so labels
///   don't flicker.
///
/// Behavior:
/// - Pauses when the camera tab isn't visible (`setVisible`) or
///   `ProcessInfo.thermalState` is `.serious` or worse.
/// - At `.fair` thermal state, drops to classification only (no flow).
/// - Vision runs on a dedicated serial queue at `.userInitiated`; the capture
///   queue is never blocked.
actor SceneSensor {
    static let shared = SceneSensor()

    private let log = Logger(subsystem: "com.ragnus.mvp", category: "SceneSensor")
    /// Dedicated serial Vision queue — never the capture queue.
    private let visionQueue = DispatchQueue(label: "photo-recipes.scene-sensor.vision", qos: .userInitiated)

    private var latest: (buffer: CVPixelBuffer, timestamp: CMTime)?
    private var previousForFlow: (buffer: CVPixelBuffer, timestamp: CMTime)?
    private var motionEMA = MotionFeatures(subjectSpeedPxPerSec: 0, backgroundSpeedPxPerSec: 0, subjectRelativeSpeedPxPerSec: 0)
    private var slowFeatures: SceneFeatures?
    private var slowFeaturesAt: Date?
    private var subjectBoxForFlow: NormalizedBox?

    private var metering: MeteringSample?
    private var pose: (elevationDegrees: Double, handShakeRadPerSec: Double) = (0, 0)

    private var hysteresis = SemanticHysteresis()
    private var running = false
    private var visible = false
    private var loopTask: Task<Void, Never>?
    private var lastMotionRun = Date.distantPast
    private var lastSlowRun = Date.distantPast
    /// Async probe-JPEG provider (wired by the camera view) for the
    /// no-video-frames fallback in `refreshNow`.
    private var probeProvider: (() async throws -> Data)?

    /// Wire the probe-frame source once (e.g. `session.captureProbeFrame`).
    func setProbeProvider(_ provider: @escaping () async throws -> Data) {
        probeProvider = provider
    }

    // MARK: - Ingest (called from the video delegate via CameraSession.frameConsumer)

    /// Stash the newest frame. Cheap — just retains the buffer.
    func ingestFrame(_ buffer: CVPixelBuffer, at timestamp: CMTime) {
        latest = (buffer, timestamp)
    }

    // MARK: - Context (pushed by the controller; used by the 1 Hz pass)

    func updateMetering(_ sample: MeteringSample) {
        metering = sample
    }

    func updatePose(elevationDegrees: Double, handShakeRadPerSec: Double) {
        pose = (elevationDegrees, handShakeRadPerSec)
    }

    // MARK: - Lifecycle

    func setVisible(_ visible: Bool) {
        self.visible = visible
        if visible { ensureLoop() } else { stopLoop() }
    }

    func start() {
        running = true
        ensureLoop()
    }

    func stop() {
        running = false
        stopLoop()
        latest = nil
        previousForFlow = nil
    }

    private func ensureLoop() {
        guard running, visible, loopTask == nil else { return }
        loopTask = Task { [weak self] in
            await self?.loop()
        }
    }

    private func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
    }

    // MARK: - Cadence loop

    private func loop() async {
        while running, visible, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 200_000_000) // 5 Hz tick
            tick()
        }
    }

    private func tick() {
        guard let latest else { return }
        let thermal = ProcessInfo.processInfo.thermalState
        if thermal == .critical {
            return // paused until the device cools; AO falls back to rules + system auto
        }
        let now = Date()

        // .serious: halve the analysis rate AND skip Vision classification
        // (don't just pause) — motion + GPU stats keep running at half rate.
        let motionInterval: TimeInterval = thermal == .serious ? 0.4 : 0.2
        let slowInterval: TimeInterval = thermal == .serious ? 2.0 : 1.0

        // ~5 Hz motion (skipped entirely at .fair — classification only).
        if thermal != .fair, now.timeIntervalSince(lastMotionRun) >= motionInterval {
            lastMotionRun = now
            runMotionTick(latest: latest)
        }
        // ~1 Hz semantics.
        if now.timeIntervalSince(lastSlowRun) >= slowInterval {
            lastSlowRun = now
            runSlowTick(latest: latest, includeClassification: thermal != .serious)
        }
    }

    private func runMotionTick(latest: (buffer: CVPixelBuffer, timestamp: CMTime)) {
        defer { previousForFlow = latest }
        guard let prev = previousForFlow else { return } // first tick seeds the pair
        let box = subjectBoxForFlow
        let metering = metering
        let motion = visionQueue.sync {
            SceneFeatureExtractor.extractMotion(
                previousPixelBuffer: prev.buffer,
                previousTimestamp: prev.timestamp,
                pixelBuffer: latest.buffer,
                timestamp: latest.timestamp,
                subjectBox: box,
                fullFrameWidthPx: metering?.fullFrameWidthPx
            )
        }
        guard let motion else { return }
        // EMA at 5 Hz (alpha 0.4).
        motionEMA = MotionFeatures(
            subjectSpeedPxPerSec: lerp(motionEMA.subjectSpeedPxPerSec, motion.subjectSpeedPxPerSec, 0.4),
            backgroundSpeedPxPerSec: lerp(motionEMA.backgroundSpeedPxPerSec, motion.backgroundSpeedPxPerSec, 0.4),
            subjectRelativeSpeedPxPerSec: lerp(motionEMA.subjectRelativeSpeedPxPerSec, motion.subjectRelativeSpeedPxPerSec, 0.4),
            directionX: motion.directionX,
            directionY: motion.directionY
        )
    }

    private func runSlowTick(latest: (buffer: CVPixelBuffer, timestamp: CMTime), includeClassification: Bool = true) {
        let metering = metering
        let pose = pose
        // Full pass without flow (the 5 Hz tick owns motion); then merge.
        // GPU stats run at this same ~1 Hz cadence — never per video frame.
        var features = visionQueue.sync {
            let stats = GPUStatsEngine.shared.analyze(latest.buffer)
            return SceneFeatureExtractor.extract(
                pixelBuffer: latest.buffer,
                previousPixelBuffer: nil,
                previousTimestamp: nil,
                timestamp: latest.timestamp,
                metering: metering ?? MeteringSample(
                    exposureSeconds: nil, iso: nil, aperture: nil,
                    exposureTargetOffset: nil, wasCustom: false,
                    fieldOfViewDegrees: nil, fullFrameWidthPx: nil
                ),
                pose: pose,
                note: "",
                gpuStats: stats,
                includeClassification: includeClassification
            )
        }
        if includeClassification {
            // Hysteresis on semantic groups so labels don't flicker frame to frame.
            features.semanticGroups = hysteresis.filter(features.semanticGroups)
        } else if let prev = slowFeatures {
            // Thermal .serious: classification skipped — reuse the last labels
            // and groups so the UI doesn't flicker to empty.
            features.semanticGroups = prev.semanticGroups
            features.sceneLabels = prev.sceneLabels
        }
        // Merge the motion EMA (the authoritative motion signal).
        features.subjectSpeedPxPerSec = motionEMA.subjectSpeedPxPerSec
        features.backgroundSpeedPxPerSec = motionEMA.backgroundSpeedPxPerSec
        features.subjectRelativeSpeedPxPerSec = motionEMA.subjectRelativeSpeedPxPerSec
        features.motionDirectionX = motionEMA.directionX
        features.motionDirectionY = motionEMA.directionY
        subjectBoxForFlow = features.subjectBox
        slowFeatures = features
        slowFeaturesAt = Date()
    }

    private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }

    // MARK: - Read

    /// Current snapshot for Auto Optimize. The controller stamps pose + intent
    /// and refreshes synchronously when `age` exceeds 1 s.
    func current() -> SceneSnapshot {
        let features = slowFeatures ?? SceneFeatures()
        let at = slowFeaturesAt
        let age = at.map { Date().timeIntervalSince($0) } ?? .infinity
        return SceneSnapshot(features: features, age: age, frameAt: at ?? .distantPast)
    }

    /// One full pass over the newest frame (classification, subjects, flow,
    /// GPU stats). Used on AO tap when the snapshot is older than 1 s — still
    /// within the tap-to-applied latency budget. Falls back to a probe JPEG
    /// (CPU feature path) when no video frames have arrived.
    func refreshNow(metering: MeteringSample, note: String) async -> SceneFeatures? {
        self.metering = metering
        let pose = pose
        if let latest {
            let prev = previousForFlow
            var features = visionQueue.sync {
                let stats = GPUStatsEngine.shared.analyze(latest.buffer)
                return SceneFeatureExtractor.extract(
                    pixelBuffer: latest.buffer,
                    previousPixelBuffer: prev?.buffer,
                    previousTimestamp: prev?.timestamp,
                    timestamp: latest.timestamp,
                    metering: metering,
                    pose: pose,
                    note: note,
                    gpuStats: stats,
                    includeClassification: true
                )
            }
            features.semanticGroups = hysteresis.filter(features.semanticGroups)
            // Seed the EMA from the fresh reading so the next ticks are stable.
            motionEMA = MotionFeatures(
                subjectSpeedPxPerSec: features.subjectSpeedPxPerSec,
                backgroundSpeedPxPerSec: features.backgroundSpeedPxPerSec,
                subjectRelativeSpeedPxPerSec: features.subjectRelativeSpeedPxPerSec,
                directionX: features.motionDirectionX,
                directionY: features.motionDirectionY
            )
            subjectBoxForFlow = features.subjectBox
            slowFeatures = features
            slowFeaturesAt = Date()
            return features
        }
        // Probe-JPEG fallback: no video frames (interrupted session, lens
        // switch). CPU histogram path — gpuStatsFresh stays false.
        guard let provider = probeProvider else {
            log.error("refreshNow with no frames — camera not streaming")
            return nil
        }
        guard let data = try? await provider(),
              let buffer = ProbeFrameDecoder.pixelBuffer(fromJPEG: data)
        else {
            log.error("refreshNow probe fallback failed")
            return nil
        }
        var features = visionQueue.sync {
            SceneFeatureExtractor.extract(
                pixelBuffer: buffer,
                previousPixelBuffer: nil,
                previousTimestamp: nil,
                timestamp: CMTime(value: 0, timescale: 1),
                metering: metering,
                pose: pose,
                note: note,
                gpuStats: nil,
                includeClassification: true
            )
        }
        features.semanticGroups = hysteresis.filter(features.semanticGroups)
        slowFeatures = features
        slowFeaturesAt = Date()
        return features
    }

    /// Latest frame as a small JPEG for the Pass 2 cloud refine (manual path
    /// only — Pass 1 never sends pixels anywhere).
    func latestJPEG(maxLongSide: CGFloat = 768, quality: CGFloat = 0.6) -> Data? {
        guard let latest else { return nil }
        return visionQueue.sync {
            let ciImage = CIImage(cvPixelBuffer: latest.buffer)
            let extent = ciImage.extent
            let longest = max(extent.width, extent.height)
            let scaled: CIImage
            if longest > maxLongSide {
                let s = maxLongSide / longest
                scaled = ciImage.transformed(by: CGAffineTransform(scaleX: s, y: s))
            } else {
                scaled = ciImage
            }
            let context = CIContext()
            guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
            return UIImage(cgImage: cgImage).jpegData(compressionQuality: quality)
        }
    }
}
