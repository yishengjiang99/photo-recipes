import XCTest
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PhotoRecipes

/// Phase 3: opt-in exposure-bracket capture + local-only store.
/// - Opt-in defaults OFF.
/// - Bracket settings: 5 frames at −2…+2 EV (construction only — no hardware).
/// - Store: downsampled JPEGs + meta.json, count/size caps evict oldest.
/// - Nothing uploads: only a manifest of metadata is ever built.
final class AOBracketCaptureTests: XCTestCase {

    // MARK: - Opt-in

    func testOptInDefaultsOff() {
        UserDefaults.standard.removeObject(forKey: AOBracketCapture.optInDefaultsKey)
        XCTAssertFalse(AOBracketCapture.optedIn, "improve opt-in must default OFF")
    }

    func testOptInRoundTrip() {
        UserDefaults.standard.removeObject(forKey: AOBracketCapture.optInDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: AOBracketCapture.optInDefaultsKey) }
        AOBracketCapture.optedIn = true
        XCTAssertTrue(AOBracketCapture.optedIn)
        AOBracketCapture.optedIn = false
        XCTAssertFalse(AOBracketCapture.optedIn)
    }

    // MARK: - Bracket construction

    func testEvOffsetsAreFiveFramesMinus2ToPlus2() {
        XCTAssertEqual(AOBracketCapture.evOffsets, [-2, -1, 0, 1, 2])
    }

    func testBracketedSettingsScaleExposureAtConstantISO() {
        let settings = AOBracketCapture.bracketedSettings(
            baseShutter: 1.0 / 60, baseISO: 100,
            offsets: AOBracketCapture.evOffsets,
            minShutter: 1.0 / 8000, maxShutter: 1.0 / 2)
        XCTAssertEqual(settings.count, 5)
        // Middle frame is the metered exposure; ends are ±2 EV (4x).
        XCTAssertEqual(settings[2].exposureDuration.seconds, 1.0 / 60, accuracy: 1e-4)
        XCTAssertEqual(settings[0].exposureDuration.seconds, 1.0 / 240, accuracy: 1e-4)
        XCTAssertEqual(settings[4].exposureDuration.seconds, 1.0 / 15, accuracy: 1e-4)
        for s in settings { XCTAssertEqual(s.iso, 100) }
    }

    func testBracketedSettingsClampToDeviceLimits() {
        // 1 s base at +2 EV would be 4 s — clamped to the 1/2 s device max.
        let settings = AOBracketCapture.bracketedSettings(
            baseShutter: 1.0, baseISO: 400,
            offsets: AOBracketCapture.evOffsets,
            minShutter: 1.0 / 8000, maxShutter: 1.0 / 2)
        XCTAssertEqual(settings.count, 5)
        XCTAssertEqual(settings[4].exposureDuration.seconds, 1.0 / 2, accuracy: 1e-4)
        XCTAssertEqual(settings[0].exposureDuration.seconds, 1.0 / 4, accuracy: 1e-4)
    }

    // MARK: - Downsample

    static func makeTestJPEG(width: Int = 1280, height: Int = 960) -> Data {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.2, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let img = ctx.makeImage()!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, [
            kCGImageDestinationLossyCompressionQuality: 1.0,
        ] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    func testDownsampleProducesSmallJPEG() {
        let big = Self.makeTestJPEG()
        let small = AOBracketDownsampler.downsampleJPEG(big)
        XCTAssertNotNil(small)
        XCTAssertLessThan(small!.count, big.count)
        let src = CGImageSourceCreateWithData(small! as CFData, nil)!
        let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        XCTAssertLessThanOrEqual(max(img.width, img.height), AOBracketDownsampler.maxPixelSize)
    }

    func testDownsampleRejectsGarbage() {
        XCTAssertNil(AOBracketDownsampler.downsampleJPEG(Data([0, 1, 2, 3])))
        XCTAssertNil(AOBracketDownsampler.downsampleJPEG(Data()))
    }

    // MARK: - Store

    private func makeRun(id: String, at: Date) -> AOBracketRun {
        var features = SceneFeatures()
        features.faceCount = 1
        features.sceneLabels = [SceneLabel(identifier: "waterfall", confidence: 0.9)]
        return AOBracketRun(
            runId: id, recipeId: "blur-moving-subjects", capturedAt: at,
            coachOnly: false, features: features, isCurrent: { true })
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func testStoreEnforcesCountCapEvictingOldest() throws {
        let dir = tempDir()
        let store = AOBracketStore(baseURL: dir, maxSets: 2, maxBytes: 100 * 1024 * 1024)
        let frames = (0..<5).map { _ in Self.makeTestJPEG(width: 64, height: 64) }
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 1...3 {
            try store.storeBracketSync(
                manifest: AOBracketManifest(run: makeRun(id: "run-\(i)", at: base.addingTimeInterval(Double(i)))),
                frames: frames)
        }
        let sets = store.pendingSets()
        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(Set(sets.map { $0.id }), ["run-2", "run-3"])
        // Newest first.
        XCTAssertEqual(sets[0].id, "run-3")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("run-1").path))
        // Sidecar + 5 downsampled frames per set.
        for set in sets {
            XCTAssertEqual(set.frameCount, 5)
            XCTAssertGreaterThan(set.bytes, 0)
        }
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("run-3/meta.json").path))
    }

    func testStoreEnforcesSizeCap() throws {
        let dir = tempDir()
        let frames = (0..<5).map { _ in Self.makeTestJPEG(width: 64, height: 64) }
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let generous = AOBracketStore(baseURL: dir, maxSets: 20, maxBytes: 100 * 1024 * 1024)
        try generous.storeBracketSync(
            manifest: AOBracketManifest(run: makeRun(id: "run-a", at: base)),
            frames: frames)
        let bytesA = generous.pendingSets().first?.bytes ?? 0
        XCTAssertGreaterThan(bytesA, 0)

        // Now a store over the same dir capped at exactly one set's bytes:
        // storing a second set must evict the first.
        let capped = AOBracketStore(baseURL: dir, maxSets: 20, maxBytes: bytesA)
        try capped.storeBracketSync(
            manifest: AOBracketManifest(run: makeRun(id: "run-b", at: base.addingTimeInterval(10))),
            frames: frames)
        let sets = capped.pendingSets()
        XCTAssertEqual(sets.count, 1)
        XCTAssertEqual(sets[0].id, "run-b")
    }

    func testPendingUploadManifestHasNoPixels() throws {
        let dir = tempDir()
        let store = AOBracketStore(baseURL: dir)
        let frames = (0..<5).map { _ in Self.makeTestJPEG(width: 64, height: 64) }
        try store.storeBracketSync(
            manifest: AOBracketManifest(run: makeRun(
                id: "run-m", at: Date(timeIntervalSince1970: 1_700_000_000))),
            frames: frames)
        let data = try XCTUnwrap(store.pendingUploadManifest())
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sets = try XCTUnwrap(json["sets"] as? [[String: Any]])
        XCTAssertEqual(sets.count, 1)
        XCTAssertEqual(sets[0]["id"] as? String, "run-m")
        XCTAssertEqual(sets[0]["frameCount"] as? Int, 5)
        // The manifest is metadata only — never image bytes.
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("/9j/"), "JPEG base64 must never appear in the manifest")
    }

    func testClearAll() throws {
        let dir = tempDir()
        let store = AOBracketStore(baseURL: dir)
        let frames = (0..<5).map { _ in Self.makeTestJPEG(width: 64, height: 64) }
        try store.storeBracketSync(
            manifest: AOBracketManifest(run: makeRun(
                id: "run-x", at: Date(timeIntervalSince1970: 1_700_000_000))),
            frames: frames)
        XCTAssertEqual(store.pendingSets().count, 1)
        store.clearAll()
        XCTAssertEqual(store.pendingSets().count, 0)
    }

    // MARK: - Section D helpers

    /// JPEG carrying EXIF exposure time + ISO (the store reads these from the
    /// ORIGINAL frame before downsampling).
    static func makeTestJPEGWithEXIF(exposureSeconds: Double, iso: Double, width: Int = 64, height: Int = 64) -> Data {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let img = ctx.makeImage()!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil)!
        let exif: [CFString: Any] = [
            kCGImagePropertyExifExposureTime: exposureSeconds,
            kCGImagePropertyExifISOSpeedRatings: [Int(iso)],
        ]
        CGImageDestinationAddImage(dest, img, [
            kCGImagePropertyExifDictionary: exif,
        ] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    /// JPEG carrying GPS + TIFF + EXIF metadata (must NOT survive the downsample).
    static func makeTestJPEGWithGPS(width: Int = 64, height: Int = 64) -> Data {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let img = ctx.makeImage()!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 37.33,
                kCGImagePropertyGPSLongitude: -122.01,
            ] as [CFString: Any],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "TestCam",
            ] as [CFString: Any],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifExposureTime: 1.0 / 60,
            ] as [CFString: Any],
        ] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    /// Reset the AOBracketCapture singleton's test seams + opt-in.
    @MainActor
    private func resetBracketShared() {
        AOBracketCapture.optedIn = false
        AOBracketCapture.shared.captureBracketOverride = nil
        AOBracketCapture.shared.bracketStore = .shared
        // Defensive: drop any armed run left by a failing test (no-op when none).
        AOBracketCapture.shared.userCaptureDidComplete(session: CameraSession())
    }

    /// Wait until the bracket fire task finishes (chip off) or time out.
    @MainActor
    private func waitForBracketQuiescence(timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while AOBracketCapture.shared.isSavingBracketData, Date() < deadline {
            await Task.yield()
        }
    }

    private func readMetaJSON(dir: URL, runId: String) throws -> [String: Any] {
        let url = dir.appendingPathComponent("\(runId)/meta.json")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Section D (b): post-capture trigger

    @MainActor
    func testBracketFiresAfterUserCapture() async throws {
        AOBracketCapture.optedIn = true
        defer { resetBracketShared() }
        let dir = tempDir()
        let store = AOBracketStore(baseURL: dir)
        AOBracketCapture.shared.bracketStore = store
        var fired: [(offsets: [Float], cap: Double?)] = []
        AOBracketCapture.shared.captureBracketOverride = { _, offsets, cap in
            fired.append((offsets, cap))
            return [Self.makeTestJPEG(width: 64, height: 64)]
        }
        var run = makeRun(id: "run-fire", at: Date())
        run.motionCapShutter = 1.0 / 60
        // Armed at Ready — nothing fires yet.
        AOBracketCapture.shared.armBracket(run: run)
        XCTAssertFalse(AOBracketCapture.shared.isSavingBracketData)
        XCTAssertEqual(store.pendingSets().count, 0)
        // The user's capture completes → the bracket fires (chip on).
        AOBracketCapture.shared.userCaptureDidComplete(session: CameraSession())
        XCTAssertTrue(AOBracketCapture.shared.isSavingBracketData)
        await waitForBracketQuiescence()
        XCTAssertEqual(fired.count, 1, "armed bracket must fire once the user's capture completes")
        XCTAssertEqual(fired[0].offsets, [-2, -1, 0, 1, 2])
        XCTAssertEqual(fired[0].cap, 1.0 / 60, "motion cap must thread through to the capture")
        XCTAssertFalse(AOBracketCapture.shared.isSavingBracketData)
        XCTAssertEqual(store.pendingSets().count, 1, "fired bracket must be stored")
    }

    @MainActor
    func testBracketSkipsWhenUserCaptureInFlight() async throws {
        AOBracketCapture.optedIn = true
        defer { resetBracketShared() }
        var fired = false
        AOBracketCapture.shared.captureBracketOverride = { _, _, _ in
            fired = true
            return []
        }
        var run = makeRun(id: "run-skip-flight", at: Date())
        run.userCaptureInFlight = { true } // racing second shutter tap
        AOBracketCapture.shared.armBracket(run: run)
        AOBracketCapture.shared.userCaptureDidComplete(session: CameraSession())
        await waitForBracketQuiescence()
        XCTAssertFalse(fired, "bracket must yield to an in-flight user capture")
        XCTAssertFalse(AOBracketCapture.shared.isSavingBracketData)
    }

    @MainActor
    func testBracketSkipsWhenRunChanged() async throws {
        AOBracketCapture.optedIn = true
        defer { resetBracketShared() }
        var fired = false
        AOBracketCapture.shared.captureBracketOverride = { _, _, _ in
            fired = true
            return []
        }
        var run = makeRun(id: "run-skip-stale", at: Date())
        run.isCurrent = { false } // a newer run started (generation bump)
        AOBracketCapture.shared.armBracket(run: run)
        AOBracketCapture.shared.userCaptureDidComplete(session: CameraSession())
        await waitForBracketQuiescence()
        XCTAssertFalse(fired, "bracket must not fire for a superseded run")
        XCTAssertFalse(AOBracketCapture.shared.isSavingBracketData)
    }

    // MARK: - Section D (c): ISO-raised positive offsets + blur_risk

    func testBracketedSettingsRaiseISOPastMotionCap() {
        // Dim scene: 1/30 s base, motion-safe cap 1/60 s.
        let settings = AOBracketCapture.bracketedSettings(
            baseShutter: 1.0 / 30, baseISO: 100,
            offsets: AOBracketCapture.evOffsets,
            minShutter: 1.0 / 8000, maxShutter: 1.0,
            motionCapShutter: 1.0 / 60, maxISO: 3200)
        XCTAssertEqual(settings.count, 5)
        // Negative offsets: shutter shortens, ISO untouched.
        XCTAssertEqual(settings[0].exposureDuration.seconds, 1.0 / 120, accuracy: 1e-6)
        XCTAssertEqual(settings[0].iso, 100)
        XCTAssertEqual(settings[1].exposureDuration.seconds, 1.0 / 60, accuracy: 1e-6)
        XCTAssertEqual(settings[1].iso, 100)
        XCTAssertEqual(settings[2].exposureDuration.seconds, 1.0 / 30, accuracy: 1e-6)
        XCTAssertEqual(settings[2].iso, 100)
        // +1 EV: shutter held AT the 1/60 cap, ISO raised 100 → 400.
        XCTAssertEqual(settings[3].exposureDuration.seconds, 1.0 / 60, accuracy: 1e-6)
        XCTAssertEqual(settings[3].iso, 400)
        // +2 EV: shutter held at the cap, ISO raised 100 → 800.
        XCTAssertEqual(settings[4].exposureDuration.seconds, 1.0 / 60, accuracy: 1e-6)
        XCTAssertEqual(settings[4].iso, 800)
    }

    func testBracketedSettingsClampRaisedISOToMax() {
        // +2 EV from 1/30 s at cap 1/60 would want ISO 800 — maxISO 500 wins.
        let settings = AOBracketCapture.bracketedSettings(
            baseShutter: 1.0 / 30, baseISO: 100,
            offsets: [2], minShutter: 1.0 / 8000, maxShutter: 1.0,
            motionCapShutter: 1.0 / 60, maxISO: 500)
        XCTAssertEqual(settings.count, 1)
        XCTAssertEqual(settings[0].exposureDuration.seconds, 1.0 / 60, accuracy: 1e-6)
        XCTAssertEqual(settings[0].iso, 500)
    }

    func testBracketedSettingsWithoutCapKeepShutterScaling() {
        // No motion cap → legacy behavior: shutter scales, ISO constant.
        let settings = AOBracketCapture.bracketedSettings(
            baseShutter: 1.0 / 60, baseISO: 100,
            offsets: AOBracketCapture.evOffsets,
            minShutter: 1.0 / 8000, maxShutter: 1.0 / 2)
        XCTAssertEqual(settings[4].exposureDuration.seconds, 1.0 / 15, accuracy: 1e-4)
        for s in settings { XCTAssertEqual(s.iso, 100) }
    }

    func testStoreFlagsBlurRiskPerFrame() throws {
        let dir = tempDir()
        let store = AOBracketStore(baseURL: dir)
        let frames = [
            Self.makeTestJPEGWithEXIF(exposureSeconds: 1.0 / 120, iso: 100),
            Self.makeTestJPEGWithEXIF(exposureSeconds: 1.0 / 60, iso: 100),
            Self.makeTestJPEGWithEXIF(exposureSeconds: 1.0 / 15, iso: 400),
        ]
        var run = makeRun(id: "run-blur", at: Date(timeIntervalSince1970: 1_700_000_000))
        run.motionCapShutter = 1.0 / 60
        try store.storeBracketSync(manifest: AOBracketManifest(run: run), frames: frames)
        let meta = try readMetaJSON(dir: dir, runId: "run-blur")
        let frameMetas = try XCTUnwrap(meta["frames"] as? [[String: Any]])
        XCTAssertEqual(frameMetas.count, 3)
        func blurRisk(shutter: Double) throws -> Bool {
            let entry = try XCTUnwrap(frameMetas.first {
                guard let t = $0["exposureSeconds"] as? Double else { return false }
                return abs(t - shutter) < 1e-9
            })
            return try XCTUnwrap(entry["blur_risk"] as? Bool)
        }
        XCTAssertFalse(try blurRisk(shutter: 1.0 / 120))
        XCTAssertFalse(try blurRisk(shutter: 1.0 / 60), "at the cap is not past the cap")
        XCTAssertTrue(try blurRisk(shutter: 1.0 / 15), "shutter past the motion cap must be flagged")
    }

    // MARK: - Section D (d): manifest anchors

    func testMetaJsonContainsLabelAnchors() throws {
        let dir = tempDir()
        let store = AOBracketStore(baseURL: dir)
        var features = SceneFeatures()
        features.meteredExposureSeconds = 1.0 / 60
        features.meteredISO = 200
        let run = AOBracketRun(
            runId: "run-anchors", recipeId: "portrait-pop",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            coachOnly: false, features: features, isCurrent: { true },
            motionCapShutter: 1.0 / 60, planTargetEV: 0.3,
            appliedShutterSec: 1.0 / 60, appliedISO: 200,
            verifyResidualEV: -0.1, lensDeviceType: "builtInWideAngleCamera")
        try store.storeBracketSync(
            manifest: AOBracketManifest(run: run),
            frames: [Self.makeTestJPEG(width: 64, height: 64)])
        let meta = try readMetaJSON(dir: dir, runId: "run-anchors")
        XCTAssertEqual(meta["schema_version"] as? Int, 1)
        XCTAssertEqual(try XCTUnwrap(meta["e_auto"] as? Double), (1.0 / 60) * 200, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(meta["plan_target_ev"] as? Double), 0.3, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(meta["appliedShutterSec"] as? Double), 1.0 / 60, accuracy: 1e-9)
        XCTAssertEqual(meta["appliedISO"] as? Double, 200)
        XCTAssertEqual(try XCTUnwrap(meta["verify_residual_ev"] as? Double), -0.1, accuracy: 1e-9)
        XCTAssertFalse((meta["device_model"] as? String ?? "").isEmpty)
        XCTAssertEqual(meta["lens"] as? String, "builtInWideAngleCamera")
    }

    // MARK: - Section D (e): EXIF strip

    func testDownsampledJPEGsStripGPSAndEXIF() throws {
        let tagged = Self.makeTestJPEGWithGPS()
        // Sanity: the input really carries GPS.
        let inSrc = try XCTUnwrap(CGImageSourceCreateWithData(tagged as CFData, nil))
        let inProps = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(inSrc, 0, nil) as? [CFString: Any])
        XCTAssertNotNil(inProps[kCGImagePropertyGPSDictionary], "test input must carry GPS EXIF")
        // The stored (downsampled) JPEG must carry none of it.
        let small = try XCTUnwrap(AOBracketDownsampler.downsampleJPEG(tagged))
        let outSrc = try XCTUnwrap(CGImageSourceCreateWithData(small as CFData, nil))
        let outProps = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(outSrc, 0, nil) as? [CFString: Any])
        XCTAssertNil(outProps[kCGImagePropertyGPSDictionary], "GPS must be stripped before anything reaches the upload manifest")
        XCTAssertNil(outProps[kCGImagePropertyExifDictionary], "non-exposure EXIF must not survive the downsample")
        XCTAssertNil(outProps[kCGImagePropertyTIFFDictionary], "TIFF metadata must not survive the downsample")
    }
}
