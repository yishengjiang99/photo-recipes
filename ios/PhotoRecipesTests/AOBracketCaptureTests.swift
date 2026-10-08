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
}
