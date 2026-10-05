import Foundation
import UIKit
import Vision
import CoreImage

/// On-device scene signals for local Auto Optimize.
/// Classic CV only: AVFoundation metering + Vision (faces / saliency) + luminance histogram.
/// No VLM, no network, no Core ML multimodal.
struct LocalSceneSignals: Equatable {
    var exposureSeconds: Double
    var iso: Float
    var evBias: Float
    var brightness01: Double          // 0 dark … 1 bright (from histogram mean)
    var contrast01: Double            // luminance spread (HDR cue)
    var highlightClip01: Double       // fraction near white
    var shadowCrush01: Double         // fraction near black
    var warmBias: Double              // >0 warmer (R>B), <0 cooler
    var faceCount: Int
    var primaryFaceCenter: CGPoint?   // normalized 0…1, Vision coords flipped to UI top-left
    var saliencyPoint: CGPoint?       // attention peak, same coords
    var devicePitchDegrees: Double?   // CoreMotion attitude pitch (radians→°)
    var isLowAngle: Bool
    var sceneNoteHints: SceneNoteHints
    var senseSummary: String

    struct SceneNoteHints: Equatable {
        var wantsMotionBlur: Bool
        var wantsPanning: Bool
        var wantsHDR: Bool
        var wantsLowAngle: Bool
        var wantsLandscapeDoF: Bool
        var night: Bool
    }
}

enum LocalSceneAnalyzer {

    /// Sense from live metering + optional probe JPEG (Vision / histogram). Never leaves device.
    static func analyze(
        session: CameraSession,
        probeJPEG: Data?,
        sceneNote: String,
        pitchDegrees: Double? = nil
    ) async -> LocalSceneSignals {
        // CameraSession is @MainActor — snapshot meters on the main actor before Vision/histogram work.
        let (exposure, iso, ev) = await MainActor.run {
            session.refreshReadouts()
            return (session.exposureSeconds, session.iso, session.evBias)
        }
        let hints = parseSceneNote(sceneNote)

        var brightness = brightnessProxy(exposure: exposure, iso: iso)
        var contrast = 0.35
        var highlight = 0.0
        var shadow = 0.0
        var warm = 0.0
        var faces = 0
        var faceCenter: CGPoint?
        var saliency: CGPoint?

        if let data = probeJPEG, let image = UIImage(data: data), let cg = image.cgImage {
            let hist = histogramStats(cgImage: cg)
            brightness = hist.mean
            contrast = hist.contrast
            highlight = hist.highlightClip
            shadow = hist.shadowCrush
            warm = hist.warmBias

            let vision = await runVision(cgImage: cg)
            faces = vision.faceCount
            faceCenter = vision.faceCenter
            saliency = vision.saliency
        }

        let pitch = pitchDegrees ?? readPitchDegrees()
        let lowFromMotion: Bool = {
            guard let pitch else { return false }
            // Phone tilted back / held low looking slightly up → "low angle" composition
            return pitch < -25 || pitch > 55
        }()
        let isLow = hints.wantsLowAngle || lowFromMotion

        let summary = buildSenseSummary(
            brightness: brightness,
            contrast: contrast,
            faces: faces,
            isLow: isLow,
            hints: hints,
            exposure: exposure,
            iso: iso
        )

        return LocalSceneSignals(
            exposureSeconds: exposure,
            iso: iso,
            evBias: ev,
            brightness01: brightness,
            contrast01: contrast,
            highlightClip01: highlight,
            shadowCrush01: shadow,
            warmBias: warm,
            faceCount: faces,
            primaryFaceCenter: faceCenter,
            saliencyPoint: saliency,
            devicePitchDegrees: pitch,
            isLowAngle: isLow,
            sceneNoteHints: hints,
            senseSummary: summary
        )
    }

    // MARK: - Scene note keywords (no LLM)

    static func parseSceneNote(_ raw: String) -> LocalSceneSignals.SceneNoteHints {
        let s = raw.lowercased()
        let blur = matches(s, ["waterfall", "blur", "long exposure", "light trail", "light trails", "silk", "motion blur", "streak"])
        let pan = matches(s, ["pan", "panning", "running", "cyclist", "bike", "sports", "track", "car passing", "skate"])
        let hdr = matches(s, ["hdr", "sunset", "sunrise", "backlit", "high contrast", "bright and dark", "silhouette"])
        let low = matches(s, ["low", "knee", "kneel", "ground", "dog view", "worm", "get down"])
        let landscape = matches(s, ["landscape", "mountain", "horizon", "forest", "depth", "foreground", "hyperfocal", "sharp throughout"])
        let night = matches(s, ["night", "dark", "astro", "milky", "city lights", "neon"])
        return .init(
            wantsMotionBlur: blur,
            wantsPanning: pan,
            wantsHDR: hdr,
            wantsLowAngle: low,
            wantsLandscapeDoF: landscape,
            night: night
        )
    }

    private static func matches(_ s: String, _ keys: [String]) -> Bool {
        keys.contains { s.contains($0) }
    }

    // MARK: - Metering proxy when no probe

    private static func brightnessProxy(exposure: Double, iso: Float) -> Double {
        // Higher ISO / longer shutter → darker scene (camera compensating).
        let evProxy = log2(max(exposure, 1.0 / 8000) * Double(max(iso, 25)) / 100.0)
        // Map rough EV to 0…1 (brighter scene → lower compensation → lower proxy)
        let inverted = 1.0 - min(max((evProxy + 2) / 8.0, 0), 1)
        return inverted
    }

    // MARK: - Histogram (luminance + warm bias)

    private struct HistStats {
        var mean: Double
        var contrast: Double
        var highlightClip: Double
        var shadowCrush: Double
        var warmBias: Double
    }

    private static func histogramStats(cgImage: CGImage) -> HistStats {
        let width = cgImage.width
        let height = cgImage.height
        let sampleW = min(width, 160)
        let sampleH = max(1, sampleW * height / max(width, 1))
        guard let ctx = CGContext(
            data: nil,
            width: sampleW,
            height: sampleH,
            bitsPerComponent: 8,
            bytesPerRow: sampleW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return HistStats(mean: 0.5, contrast: 0.35, highlightClip: 0, shadowCrush: 0, warmBias: 0)
        }
        ctx.interpolationQuality = .low
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleW, height: sampleH))
        guard let data = ctx.data else {
            return HistStats(mean: 0.5, contrast: 0.35, highlightClip: 0, shadowCrush: 0, warmBias: 0)
        }

        let ptr = data.bindMemory(to: UInt8.self, capacity: sampleW * sampleH * 4)
        var sum = 0.0
        var sumSq = 0.0
        var hi = 0
        var lo = 0
        var rSum = 0.0
        var bSum = 0.0
        let n = sampleW * sampleH
        for i in 0..<n {
            let o = i * 4
            let r = Double(ptr[o])
            let g = Double(ptr[o + 1])
            let b = Double(ptr[o + 2])
            let y = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
            sum += y
            sumSq += y * y
            if y > 0.92 { hi += 1 }
            if y < 0.08 { lo += 1 }
            rSum += r
            bSum += b
        }
        let mean = sum / Double(n)
        let variance = max(0, sumSq / Double(n) - mean * mean)
        let contrast = min(1, sqrt(variance) * 2.5)
        let warm = (rSum - bSum) / (rSum + bSum + 1)
        return HistStats(
            mean: mean,
            contrast: contrast,
            highlightClip: Double(hi) / Double(n),
            shadowCrush: Double(lo) / Double(n),
            warmBias: warm
        )
    }

    // MARK: - Vision

    private struct VisionOut {
        var faceCount: Int
        var faceCenter: CGPoint?
        var saliency: CGPoint?
    }

    private static func runVision(cgImage: CGImage) async -> VisionOut {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var faceCount = 0
                var faceCenter: CGPoint?
                var saliency: CGPoint?

                let faceReq = VNDetectFaceRectanglesRequest()
                let salReq = VNGenerateAttentionBasedSaliencyImageRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
                do {
                    try handler.perform([faceReq, salReq])
                } catch {
                    cont.resume(returning: VisionOut(faceCount: 0, faceCenter: nil, saliency: nil))
                    return
                }

                if let results = faceReq.results, !results.isEmpty {
                    faceCount = results.count
                    let best = results.max(by: { $0.boundingBox.area < $1.boundingBox.area })
                    if let box = best?.boundingBox {
                        // Vision: origin bottom-left → UI top-left normalized
                        faceCenter = CGPoint(x: box.midX, y: 1 - box.midY)
                    }
                }

                if let obs = salReq.results?.first as? VNSaliencyImageObservation,
                   let objects = obs.salientObjects,
                   let top = objects.max(by: { $0.confidence < $1.confidence }) {
                    let box = top.boundingBox
                    saliency = CGPoint(x: box.midX, y: 1 - box.midY)
                }

                cont.resume(returning: VisionOut(faceCount: faceCount, faceCenter: faceCenter, saliency: saliency))
            }
        }
    }

    private static func readPitchDegrees() -> Double? {
        // Prefer caller-supplied pitch from HorizonMonitor (injected via analyze pitchDegrees:).
        // One-shot CoreMotion samples are unreliable here.
        return nil
    }

    private static func buildSenseSummary(
        brightness: Double,
        contrast: Double,
        faces: Int,
        isLow: Bool,
        hints: LocalSceneSignals.SceneNoteHints,
        exposure: Double,
        iso: Float
    ) -> String {
        var parts: [String] = []
        if brightness < 0.28 { parts.append("low light") }
        else if brightness > 0.72 { parts.append("bright light") }
        else { parts.append("mid light") }
        if contrast > 0.55 { parts.append("high contrast") }
        if faces > 0 { parts.append(faces == 1 ? "1 face" : "\(faces) faces") }
        if isLow { parts.append("low angle") }
        if hints.wantsPanning { parts.append("panning cue") }
        if hints.wantsMotionBlur { parts.append("motion-blur cue") }
        if hints.wantsHDR { parts.append("HDR cue") }
        parts.append(String(format: "meter %@ · ISO %.0f", RecipeCameraMapper.formatShutter(exposure), iso))
        return parts.joined(separator: " · ")
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
