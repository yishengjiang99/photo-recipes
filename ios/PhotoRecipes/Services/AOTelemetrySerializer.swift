import Foundation

// MARK: - Phase 3 telemetry serialization (privacy-preserving)
//
// Serializes the AO Ready telemetry payload: GPU stats, scene labels, planner
// output, verify residual — numeric only, never pixels. This is a SEPARATE
// serialization from `SceneFeatures.featureVector()`: the 45-dim Core ML
// vector contract is untouched; these props are additive keys on the existing
// `auto_optimize_success` analytics event (`telemetry_v2` marks the payload).
//
// No-pixel guarantee: every value is a formatted number, a short identifier,
// or a sanitized label string. The raw 64-bin histogram is quantized to 16
// bins; identifiers have `,`/`:` stripped so the format stays parseable.

enum AOTelemetrySerializer {
    /// Quantized histogram bins (64 → 16). Must stay small: Analytics drops
    /// values over 200 chars.
    static let quantizedHistogramBins = 16

    /// Device model identifier (e.g. "iPhone15,2"). Not identifying on its
    /// own — no serial, no user name (`UIDevice.name` is never used).
    static func deviceModelIdentifier() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let data = Data(bytes: &sysinfo.machine, count: Int(_SYS_NAMELEN))
        return String(data: data, encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            .nilIfEmpty ?? "unknown"
    }

    /// 64-bin luma histogram → 16-bin fractions, 3 decimals, comma-separated.
    /// Empty / wrong-sized input → "" (never crash on malformed stats).
    static func quantizedHistogram16(_ bins64: [Int]?) -> String {
        guard let bins64, bins64.count == GPUStatsCore.histogramBins else { return "" }
        let total = max(Double(bins64.reduce(0, +)), 1)
        let perBin = GPUStatsCore.histogramBins / quantizedHistogramBins
        return (0..<quantizedHistogramBins).map { i in
            let sum = bins64[(i * perBin)..<((i + 1) * perBin)].reduce(0, +)
            return String(format: "%.3f", Double(sum) / total)
        }.joined(separator: ",")
    }

    /// 13 gradient scores → 2 decimals, comma-separated.
    static func quantizedGradientScores(_ scores: [Float]?) -> String {
        guard let scores, scores.count == GPUStatsCore.gradientRatioCount else { return "" }
        return scores.map { String(format: "%.2f", $0) }.joined(separator: ",")
    }

    /// Top-5 Vision labels → "identifier:confidence" pairs, 2-decimal
    /// confidence. Identifiers are sanitized (`,`/`:` → `_`).
    static func sceneLabelString(_ labels: [SceneLabel]?) -> String {
        guard let labels, !labels.isEmpty else { return "" }
        return labels.prefix(5).map { label in
            let id = label.identifier
                .replacingOccurrences(of: ",", with: "_")
                .replacingOccurrences(of: ":", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(id):\(String(format: "%.2f", label.confidence))"
        }.joined(separator: ",")
    }

    /// Full Phase 3 prop set for `auto_optimize_success`. All keys are new
    /// (additive); the caller keeps every existing key intact.
    static func readyProps(
        features: SceneFeatures,
        planShutterSec: Double?,
        planISO: String?,
        planTargetEV: Double?,
        planResidualEV: Double?,
        residualEV: Double?,
        verifyIterations: Int,
        lensDeviceType: String
    ) -> [String: String] {
        // Same formula the solver uses: metered exposure product E_auto.
        let eAuto = (features.meteredExposureSeconds ?? 1 / 60)
            * Double(features.meteredISO ?? 100)
        return [
            "telemetry_v2": "1",
            // GPU stats (quantized; never pixels).
            "gpu_hist16": quantizedHistogram16(features.lumaHistogram64),
            "gpu_clip": String(format: "%.3f", features.highlightClipFraction),
            "gpu_crush": String(format: "%.3f", features.shadowCrushFraction),
            "gpu_grayworld": String(format: "%.3f,%.3f,%.3f",
                                    features.grayWorldMeanR ?? -1,
                                    features.grayWorldMeanG ?? -1,
                                    features.grayWorldMeanB ?? -1),
            "gpu_contrast": features.lumaContrast.map { String(format: "%.3f", $0) } ?? "",
            "gpu_grad": quantizedGradientScores(features.gradientScores),
            // Scene content (labels + subject; no pixels).
            "scene_labels": sceneLabelString(features.sceneLabels),
            "face_count": features.faceCount.map { "\($0)" } ?? "",
            "subject_kind": features.subjectKind?.rawValue ?? "",
            "subject_area": String(format: "%.3f", features.subjectAreaFraction),
            "handshake_rps": String(format: "%.3f", features.handShakeRadPerSec),
            // Device + planner output + verify residual.
            "e_auto": String(format: "%.4g", eAuto),
            "device_model": deviceModelIdentifier(),
            "lens": lensDeviceType,
            "plan_shutter": planShutterSec.map { String(format: "%.4g", $0) } ?? "",
            "plan_iso": planISO ?? "",
            "plan_target_ev": planTargetEV.map { String(format: "%.2f", $0) } ?? "",
            // Planner residual (+ = brighter than target — same convention
            // as the verify residual below), from Solution.residualEV.
            "plan_residual_ev": planResidualEV.map { String(format: "%.2f", $0) } ?? "",
            "verify_residual_ev": residualEV.map { String(format: "%.2f", $0) } ?? "",
            "verify_iterations": "\(verifyIterations)",
        ]
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
