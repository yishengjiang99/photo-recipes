import XCTest
@testable import PhotoRecipes

/// Phase 3: privacy-preserving AO Ready telemetry serialization.
/// - The 45-dim Core ML feature-vector contract is untouched.
/// - Every telemetry prop is numeric / short-identifier only (no-pixel guarantee).
/// - Override deltas (EV / shutter / ISO / Kelvin / recipe) are pure math.
final class AOTelemetryTests: XCTestCase {

    // MARK: - Contract: feature vector stays 45 dims

    func testVectorDimensionUnchanged() {
        XCTAssertEqual(SceneFeatures.vectorDimension, 45)
        XCTAssertEqual(SceneFeatures().featureVector().count, 45)
    }

    // MARK: - Quantization

    func testHistogramQuantizes64To16Bins() {
        // 64 bins × 100 px → each of the 16 output bins is 400/6400 = 0.0625.
        let bins = [Int](repeating: 100, count: 64)
        let q = AOTelemetrySerializer.quantizedHistogram16(bins)
        let parts = q.split(separator: ",")
        XCTAssertEqual(parts.count, 16)
        for p in parts { XCTAssertEqual(String(p), "0.062") }
        let sum = parts.compactMap { Double($0) }.reduce(0, +)
        XCTAssertEqual(sum, 1.0, accuracy: 0.02)
    }

    func testHistogramBadInputYieldsEmpty() {
        XCTAssertEqual(AOTelemetrySerializer.quantizedHistogram16(nil), "")
        XCTAssertEqual(AOTelemetrySerializer.quantizedHistogram16([1, 2, 3]), "")
    }

    func testGradientScoresQuantized() {
        let scores = (0..<13).map { Float($0) * 1234.567 }
        let q = AOTelemetrySerializer.quantizedGradientScores(scores)
        let parts = q.split(separator: ",")
        XCTAssertEqual(parts.count, 13)
        XCTAssertEqual(String(parts[0]), "0.00")
        XCTAssertEqual(String(parts[1]), "1234.57")
        XCTAssertEqual(AOTelemetrySerializer.quantizedGradientScores(nil), "")
    }

    func testSceneLabelStringSanitizes() {
        let labels = [
            SceneLabel(identifier: "waterfall", confidence: 0.9123),
            SceneLabel(identifier: "weird:label,with", confidence: 0.5),
        ]
        let s = AOTelemetrySerializer.sceneLabelString(labels)
        XCTAssertEqual(s, "waterfall:0.91,weird_label_with:0.50")
        XCTAssertEqual(AOTelemetrySerializer.sceneLabelString(nil), "")
        XCTAssertEqual(AOTelemetrySerializer.sceneLabelString([]), "")
    }

    // MARK: - No-pixel guarantee

    private func fullFeatures() -> SceneFeatures {
        var f = SceneFeatures()
        f.gpuStatsFresh = true
        f.gpuStatsSource = "cpu"
        f.lumaHistogram64 = (0..<64).map { _ in 768 }
        f.highlightClipFraction = 0.012
        f.shadowCrushFraction = 0.034
        f.grayWorldMeanR = 0.52
        f.grayWorldMeanG = 0.48
        f.grayWorldMeanB = 0.44
        f.lumaContrast = 0.21
        f.gradientScores = (0..<13).map { Float($0) * 1000 }
        f.sceneLabels = (0..<5).map { SceneLabel(identifier: "label\($0)", confidence: 0.9 - Float($0) * 0.1) }
        f.faceCount = 2
        f.subjectKind = .face
        f.subjectAreaFraction = 0.15
        f.handShakeRadPerSec = 0.042
        f.meteredExposureSeconds = 1.0 / 60
        f.meteredISO = 100
        return f
    }

    func testReadyPropsAreNumericOnly() throws {
        let props = AOTelemetrySerializer.readyProps(
            features: fullFeatures(),
            planShutterSec: 1.0 / 125,
            planISO: "200",
            planTargetEV: 0.3,
            planResidualEV: 0.05,
            residualEV: -0.12,
            verifyIterations: 1,
            lensDeviceType: "builtInWideAngleCamera",
            readbackShutterSec: 1.0 / 125,
            readbackISO: 200
        )
        XCTAssertEqual(props["telemetry_v2"], "1")
        // Raw 64-bin histogram never appears — only the 16-bin quantized form.
        XCTAssertEqual(props["gpu_hist16"]?.split(separator: ",").count, 16)
        XCTAssertNil(props["lumaHistogram64"])
        XCTAssertEqual(props["gpu_grad"]?.split(separator: ",").count, 13)
        XCTAssertEqual(props["face_count"], "2")
        XCTAssertEqual(props["subject_kind"], "face")
        XCTAssertEqual(props["plan_shutter"], "0.008")
        XCTAssertEqual(props["plan_iso"], "200")
        XCTAssertEqual(props["plan_target_ev"], "0.30")
        XCTAssertEqual(props["plan_residual_ev"], "0.05")
        XCTAssertEqual(props["verify_residual_ev"], "-0.12")
        XCTAssertEqual(props["verify_iterations"], "1")
        XCTAssertEqual(props["rb_shutter"], "0.008")
        XCTAssertEqual(props["rb_iso"], "200")

        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789:.,+-_ ")
        for (k, v) in props {
            XCTAssertFalse(v.isEmpty || k.isEmpty, "empty key/value for \(k)")
            // No pixel data: strict charset (no '/', no '=', no base64 padding),
            // no data URIs, and Analytics' 200-char cap respected.
            XCTAssertTrue(v.unicodeScalars.allSatisfy { allowed.contains($0) },
                          "non-numeric chars in \(k)=\(v)")
            XCTAssertFalse(v.contains("data:image"), "pixel payload in \(k)")
            XCTAssertFalse(v.lowercased().contains("base64"), "pixel payload in \(k)")
            XCTAssertLessThanOrEqual(v.count, 200, "value too long: \(k)")
        }
        // The whole payload JSON-encodes (what Analytics POSTs).
        let json = try JSONSerialization.data(withJSONObject: props)
        let text = String(data: json, encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("data:image"))
    }

    func testReadyPropsTolerateMissingStats() {
        let props = AOTelemetrySerializer.readyProps(
            features: SceneFeatures(),
            planShutterSec: nil,
            planISO: nil,
            planTargetEV: nil,
            planResidualEV: nil,
            residualEV: nil,
            verifyIterations: 0,
            lensDeviceType: "unknown"
        )
        XCTAssertEqual(props["telemetry_v2"], "1")
        XCTAssertEqual(props["gpu_hist16"], "")
        XCTAssertEqual(props["gpu_grad"], "")
        XCTAssertEqual(props["face_count"], "")
        XCTAssertEqual(props["plan_shutter"], "")
        XCTAssertEqual(props["plan_residual_ev"], "")
        XCTAssertEqual(props["verify_residual_ev"], "")
        XCTAssertEqual(props["rb_shutter"], "")
        XCTAssertEqual(props["rb_iso"], "")
        // E_auto falls back to the 1/60 @ ISO 100 anchor.
        XCTAssertEqual(props["e_auto"], String(format: "%.4g", (1.0 / 60) * 100))
    }

    // MARK: - faceCount Codable

    func testFaceCountRoundTrip() throws {
        var f = SceneFeatures()
        f.faceCount = 3
        let data = try JSONEncoder().encode(f)
        let back = try JSONDecoder().decode(SceneFeatures.self, from: data)
        XCTAssertEqual(back.faceCount, 3)
        // Still schema v3; still out of the Core ML vector.
        XCTAssertEqual(back.schemaVersion, 3)
        XCTAssertEqual(back.featureVector().count, 45)
    }

    func testFaceCountTolerantDecode() throws {
        let v2: [String: Any] = ["schemaVersion": 2, "highlightClipFraction": 0.1]
        let data = try JSONSerialization.data(withJSONObject: v2)
        let f = try JSONDecoder().decode(SceneFeatures.self, from: data)
        XCTAssertNil(f.faceCount)
    }

    // MARK: - Override deltas

    func testDialDeltaProps() {
        let applied = AutoOptimizeController.AppliedDials(
            shutterSec: 1.0 / 60, iso: 100, ev: 0.3, wbKelvin: 5600, recipeId: "portrait-pop")
        let current = AutoOptimizeController.AppliedDials(
            shutterSec: 1.0 / 120, iso: 200, ev: -0.3, wbKelvin: 5200, recipeId: "portrait-pop")
        let p = AutoOptimizeController.dialDeltaProps(applied: applied, current: current)
        XCTAssertEqual(p["ev_delta"], "-0.6")
        XCTAssertEqual(p["shutter_delta_stops"], "-1.00") // 1/60 → 1/120: exactly one stop
        XCTAssertEqual(p["iso_delta_stops"], "+1.00")
        XCTAssertEqual(p["wb_kelvin_delta"], "-400")
        XCTAssertEqual(p["recipe_unchanged"], "1")
    }

    func testDialDeltaPropsMissingKelvin() {
        let applied = AutoOptimizeController.AppliedDials(
            shutterSec: 1.0 / 60, iso: 100, ev: 0, wbKelvin: nil, recipeId: "a")
        let current = AutoOptimizeController.AppliedDials(
            shutterSec: 1.0 / 60, iso: 100, ev: 0.3, wbKelvin: nil, recipeId: "b")
        let p = AutoOptimizeController.dialDeltaProps(applied: applied, current: current)
        XCTAssertNil(p["wb_kelvin_delta"])
        XCTAssertEqual(p["ev_delta"], "+0.3")
        XCTAssertEqual(p["shutter_delta_stops"], "+0.00")
        XCTAssertEqual(p["recipe_unchanged"], "0")
    }

    // MARK: - Section D: deferred override label

    func testExposureDeltaStopsMath() {
        let applied = AutoOptimizeController.AppliedDials(
            shutterSec: 1.0 / 60, iso: 100, ev: 0, wbKelvin: nil, recipeId: "a")
        let current = AutoOptimizeController.AppliedDials(
            shutterSec: 1.0 / 30, iso: 200, ev: 0.5, wbKelvin: nil, recipeId: "a")
        // (1/30·200)/(1/60·100) = 4 → +2 stops, + 0.5 EV bias in auto exposure.
        XCTAssertEqual(
            AutoOptimizeController.exposureDeltaStops(
                applied: applied, current: current, inAutoExposure: true)!,
            2.5, accuracy: 1e-9)
        // Custom exposure: the EV dial is a no-op — excluded from the target.
        XCTAssertEqual(
            AutoOptimizeController.exposureDeltaStops(
                applied: applied, current: current, inAutoExposure: false)!,
            2.0, accuracy: 1e-9)
        // Degenerate dials → nil (no target recorded).
        let bad = AutoOptimizeController.AppliedDials(
            shutterSec: 0, iso: 100, ev: 0, wbKelvin: nil, recipeId: "a")
        XCTAssertNil(AutoOptimizeController.exposureDeltaStops(
            applied: bad, current: current, inAutoExposure: true))
        XCTAssertNil(AutoOptimizeController.exposureDeltaStops(
            applied: applied, current: bad, inAutoExposure: true))
    }

    func testOverrideLabelPropsIncludeTrainingTarget() {
        let applied = AutoOptimizeController.AppliedDials(
            shutterSec: 1.0 / 60, iso: 100, ev: 0, wbKelvin: nil, recipeId: "a")
        let current = AutoOptimizeController.AppliedDials(
            shutterSec: 1.0 / 30, iso: 200, ev: 0.5, wbKelvin: nil, recipeId: "a")
        let p = AutoOptimizeController.overrideLabelProps(
            applied: applied, current: current, inAutoExposure: true)
        // The single ExposureOffsetNet training target…
        XCTAssertEqual(p["exposure_delta_stops"], "+2.50")
        // …alongside the per-dial deltas.
        XCTAssertEqual(p["shutter_delta_stops"], "+1.00")
        XCTAssertEqual(p["iso_delta_stops"], "+1.00")
        XCTAssertEqual(p["ev_delta"], "+0.5")
        XCTAssertEqual(p["recipe_unchanged"], "1")
    }

    @MainActor
    func testOverrideLabelDeferredUntilCapture() async {
        let controller = AutoOptimizeController()
        let session = CameraSession()
        controller.seedCurrentRunForTests(
            runId: "run-1",
            appliedDials: AutoOptimizeController.AppliedDials(
                shutterSec: 1.0 / 60, iso: 100, ev: 0, wbKelvin: nil, recipeId: "a"))
        // The user drags dials after Ready…
        session.exposureSeconds = 1.0 / 30
        session.iso = 200
        session.evBias = 0.5
        var captured: [[String: String]] = []
        controller.overrideLabelSink = { captured.append($0) }
        controller.markDirty(session: session)
        // …but the label does NOT fire on the first touch.
        XCTAssertTrue(captured.isEmpty, "override label must be deferred past the first dial touch")
        // The user's capture completes → the FINAL dial state is labeled.
        controller.recordPendingOverrideLabel()
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured[0]["run_id"], "run-1")
        XCTAssertEqual(captured[0]["exposure_delta_stops"], "+2.50")
        XCTAssertEqual(captured[0]["shutter_delta_stops"], "+1.00")
        // Once per run — a second record is a no-op.
        controller.recordPendingOverrideLabel()
        XCTAssertEqual(captured.count, 1)
    }

    @MainActor
    func testOverrideLabelFiresAfterDialInactivity() async {
        let controller = AutoOptimizeController()
        let session = CameraSession()
        controller.seedCurrentRunForTests(
            runId: "run-2",
            appliedDials: AutoOptimizeController.AppliedDials(
                shutterSec: 1.0 / 60, iso: 100, ev: 0, wbKelvin: nil, recipeId: "a"))
        session.exposureSeconds = 1.0 / 30
        session.iso = 200
        session.evBias = 0.5
        var captured: [[String: String]] = []
        controller.overrideLabelSink = { captured.append($0) }
        let previousDelay = AutoOptimizeController.overrideLabelInactivityDelayNanoseconds
        AutoOptimizeController.overrideLabelInactivityDelayNanoseconds = 50_000_000
        defer { AutoOptimizeController.overrideLabelInactivityDelayNanoseconds = previousDelay }
        controller.markDirty(session: session)
        XCTAssertTrue(captured.isEmpty)
        // No capture — 3 s (here 50 ms) of dial inactivity fires the label.
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured[0]["run_id"], "run-2")
        XCTAssertEqual(captured[0]["exposure_delta_stops"], "+2.50")
    }

    @MainActor
    func testOverrideLabelSkippedWhenRunMovedOn() async {
        let controller = AutoOptimizeController()
        let session = CameraSession()
        controller.seedCurrentRunForTests(
            runId: "run-3",
            appliedDials: AutoOptimizeController.AppliedDials(
                shutterSec: 1.0 / 60, iso: 100, ev: 0, wbKelvin: nil, recipeId: "a"))
        var captured: [[String: String]] = []
        controller.overrideLabelSink = { captured.append($0) }
        controller.markDirty(session: session)
        // The run id was consumed/closed (capture window) before the label
        // fired → the armed label belongs to a stale run and must not fire.
        _ = controller.takeRecentRunIdForCapture()
        controller.recordPendingOverrideLabel()
        XCTAssertTrue(captured.isEmpty)
    }
}
