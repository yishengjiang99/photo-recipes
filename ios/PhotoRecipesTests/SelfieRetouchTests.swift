import CoreImage
import UIKit
import XCTest
@testable import PhotoRecipes

/// Selfie preset pack (docs/selfie/selfie-presets-prompt.md): catalog, pure geometry,
/// under-eye math, identity / no-face behavior, orientation and hard caps.
///
/// Vision face detection on a synthetic image is not reliable on CI simulators, so the
/// face-dependent steps are tested with injected `SelfieFaceGeometry` and orientation is
/// tested on the pixels Vision would see (`SelfieRetouchEngine.orientedInput`) plus the
/// pure landmark mapping (`SelfieRetouchMath.fullResPoint`).
@MainActor
final class SelfieRetouchTests: XCTestCase {

    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private lazy var engine = SelfieRetouchEngine(context: context)

    // MARK: - Catalog

    func testCatalog_selfieIdsAreKnownNamedAndDescribed() {
        XCTAssertEqual(CreativeLookCatalog.selfieIds,
                       ["selfieNatural", "selfieGlow", "selfieStudio", "selfieLowLight", "selfiePortrait"])
        XCTAssertEqual(CreativeLookCatalog.v1Ids.count, 14)
        XCTAssertEqual(CreativeLookCatalog.allIds, CreativeLookCatalog.v1Ids + CreativeLookCatalog.selfieIds)
        XCTAssertEqual(Set(CreativeLookCatalog.allIds).count, CreativeLookCatalog.allIds.count, "duplicate ids")
        for id in CreativeLookCatalog.selfieIds {
            XCTAssertTrue(CreativeLookCatalog.isKnown(id), id)
            XCTAssertTrue(CreativeLookCatalog.isSelfie(id), id)
            XCTAssertNotNil(CreativeLookCatalog.displayNames[id], "missing display name: \(id)")
            let sentence = try? XCTUnwrap(CreativeLookCatalog.craftSentences[id], "missing craft sentence: \(id)")
            let lower = (sentence ?? "").lowercased()
            for banned in ["fix", "flaw", "slim", "lighten", "whiten", "beauty", "perfect", "blemish"] {
                XCTAssertFalse(lower.contains(banned), "\(id) copy uses “\(banned)” — light/texture language only")
            }
        }
        for id in CreativeLookCatalog.v1Ids {
            XCTAssertFalse(CreativeLookCatalog.isSelfie(id), id)
        }
    }

    func testCatalog_everySelfieLookHasPresetAndBundledRecipe() {
        XCTAssertEqual(SelfiePresets.all.map(\.lookId), CreativeLookCatalog.selfieIds)
        for preset in SelfiePresets.all {
            let recipe = BundledPresets.recipe(id: preset.recipeId)
            XCTAssertNotNil(recipe, "missing BundledPresets recipe for \(preset.lookId)")
            XCTAssertTrue(BundledPresets.selfie.contains { $0.id == preset.recipeId })
            XCTAssertTrue(AutoOptimizeController.isSelfieRecipe(preset.recipeId))
            XCTAssertNil(preset.targets.creativeLook, "look is applied by applySelfiePreset, not targets")
            XCTAssertNil(preset.targets.shutter); XCTAssertNil(preset.targets.iso)
            XCTAssertNil(preset.targets.torch, "front camera has no torch")
            XCTAssertNotNil(preset.targets.ev)
            // Hard caps already hold at intensity 1.0.
            XCTAssertEqual(preset.retouch, preset.retouch.clamped(), preset.lookId)
        }
        XCTAssertEqual(BundledPresets.core.count, 10)
        XCTAssertEqual(BundledPresets.all.count, 15)
        XCTAssertEqual(Set(BundledPresets.all.map(\.id)).count, 15)
        // Selfie recipes stay out of the recommender scorer.
        for r in BundledPresets.selfie {
            XCTAssertFalse(SceneFeatures.recipeOrder.contains(r.id))
        }
    }

    func testPresetTargets_matchPlan() {
        let glow = SelfiePresets.preset(lookId: "selfieGlow")!
        XCTAssertEqual(glow.targets.ev, "+0.5"); XCTAssertEqual(glow.targets.flash, "auto")
        let low = SelfiePresets.preset(lookId: "selfieLowLight")!
        XCTAssertEqual(low.targets.lowLightBoost, true); XCTAssertEqual(low.targets.flash, "on")
        XCTAssertGreaterThan(low.retouch.noiseReduction, 0)
        XCTAssertTrue(SelfiePresets.preset(lookId: "selfieStudio")!.lockWhiteBalanceAfterAE)
        XCTAssertEqual(SelfiePresets.preset(lookId: "selfiePortrait")!.targets.simulatedAperture, 2.0)
        XCTAssertEqual(SelfiePresets.preset(lookId: "selfiePortrait")!.retouch.backgroundBlur, 0.70)
        // EV is programmed (no custom shutter/ISO written by a selfie preset).
        XCTAssertEqual(ExposureApplyPolicy.evBiasToProgram(evRaw: glow.targets.ev, wroteCustomExposure: false), 0.5)
    }

    func testPinnedRecipe_selfieRecipesNeverPinAutoOptimize() {
        XCTAssertNil(AutoOptimizeController.pinnedRecipeId(staged: "selfie-soft-glow", applied: nil, aoChosen: nil))
        XCTAssertNil(AutoOptimizeController.pinnedRecipeId(staged: nil, applied: "selfie-low-light", aoChosen: nil))
        XCTAssertEqual(AutoOptimizeController.pinnedRecipeId(staged: "portrait-pop", applied: nil, aoChosen: nil), "portrait-pop")
    }

    func testFaceMeteringPoint_isUISpaceBoxCenter() {
        let p = SelfiePresets.faceMeteringPoint(uiFaceBox: CGRect(x: 0.4, y: 0.2, width: 0.2, height: 0.3))
        XCTAssertEqual(p?.x ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(p?.y ?? -1, 0.35, accuracy: 1e-9)
        XCTAssertNil(SelfiePresets.faceMeteringPoint(uiFaceBox: .zero))
    }

    // MARK: - Caps + intensity scaling

    func testCaps_requestedStrengthsAboveCapsAreClamped() {
        let wild = SelfieRetouchParams(skinSmoothing: 0.9, underEye: 2, detailSharpen: 5, backgroundBlur: 3,
                                       highlightBloom: 4, warmthKelvin: 9000, noiseReduction: 7)
        let c = wild.clamped()
        XCTAssertEqual(c.skinSmoothing, 0.40)
        XCTAssertEqual(c.underEye, 0.60)
        XCTAssertEqual(c.detailSharpen, 0.60)
        XCTAssertEqual(c.backgroundBlur, 1.0)
        XCTAssertEqual(c.highlightBloom, SelfieRetouchParams.maxHighlightBloom)
        XCTAssertEqual(c.warmthKelvin, SelfieRetouchParams.maxWarmthKelvin)
        // Caps hold at any intensity (including out-of-range intensity).
        XCTAssertEqual(wild.scaled(by: 1.7), c)
        XCTAssertEqual(SelfieRetouchParams(skinSmoothing: .nan).clamped().skinSmoothing, 0)
        // Background blur radius: ≤ 18 px at 12 MP, scaled by image size.
        XCTAssertEqual(SelfieRetouchMath.backgroundBlurRadius(strength: 5, imageSize: CGSize(width: 4032, height: 3024)), 18, accuracy: 1e-9)
        XCTAssertEqual(SelfieRetouchMath.backgroundBlurRadius(strength: 1, imageSize: CGSize(width: 2016, height: 1512)), 9, accuracy: 1e-9)
        XCTAssertEqual(SelfieRetouchMath.backgroundBlurRadius(strength: 0.7, imageSize: CGSize(width: 3024, height: 4032)), 12.6, accuracy: 1e-9)
    }

    func testIntensity_scalesLinearlyAndZeroIsIdentityParams() {
        let natural = SelfiePresets.preset(lookId: "selfieNatural")!.retouch
        let half = natural.scaled(by: 0.5)
        XCTAssertEqual(half.skinSmoothing, 0.10, accuracy: 1e-12)
        XCTAssertEqual(half.underEye, 0.175, accuracy: 1e-12)
        XCTAssertEqual(half.detailSharpen, 0.125, accuracy: 1e-12)
        XCTAssertEqual(half.warmthKelvin, 75, accuracy: 1e-9)
        XCTAssertTrue(natural.scaled(by: 0).isIdentity)
        XCTAssertEqual(SelfiePresets.retouch(lookId: "selfieNatural", intensity: 1), natural)
        XCTAssertNil(SelfiePresets.retouch(lookId: "warmGlow", intensity: 1))
    }

    // MARK: - Under-eye geometry

    func testUnderEyeRegion_fromEyeBox_staysBelowLashLine() {
        let eye = CGRect(x: 100, y: 200, width: 40, height: 20)
        let r = SelfieRetouchMath.underEyeRegion(eye: eye)
        XCTAssertEqual(r.center.x, 120, accuracy: 1e-9)
        XCTAssertEqual(r.center.y, 200 - 0.55 * 20, accuracy: 1e-9) // bottom-left origin: below = smaller y
        XCTAssertEqual(r.width, 44, accuracy: 1e-9)
        XCTAssertEqual(r.height, 14, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(r.top, eye.minY - 0.1 * eye.height, "region must clear the lower lash line")
        let cheek = SelfieRetouchMath.cheekPatch(for: r)
        XCTAssertEqual(cheek.width, r.width); XCTAssertEqual(cheek.height, r.height)
        XCTAssertEqual(cheek.center.y, r.center.y - r.height, accuracy: 1e-9)
        XCTAssertLessThan(cheek.top, r.center.y)
    }

    func testUnderEyeRegion_scalesWithFaceSize() {
        let small = SelfieRetouchMath.underEyeRegion(eye: CGRect(x: 10, y: 50, width: 20, height: 10))
        let large = SelfieRetouchMath.underEyeRegion(eye: CGRect(x: 20, y: 100, width: 40, height: 20))
        XCTAssertEqual(large.width, small.width * 2, accuracy: 1e-9)
        XCTAssertEqual(large.height, small.height * 2, accuracy: 1e-9)
        XCTAssertEqual(large.center.x, small.center.x * 2, accuracy: 1e-9)
        XCTAssertEqual(large.center.y, small.center.y * 2, accuracy: 1e-9)
        // Lash clearance also scales.
        let eye = CGRect(x: 20, y: 100, width: 40, height: 20)
        XCTAssertLessThanOrEqual(large.top, eye.minY - 0.1 * eye.height)
    }

    // MARK: - Under-eye math

    func testUnderEyeDelta_neverAboveCheek_identityAtZero() {
        let region = SIMD3<Double>(0.30, 0.22, 0.30) // darker, purple-ish shadow
        let cheek = SIMD3<Double>(0.55, 0.40, 0.33)
        XCTAssertEqual(SelfieRetouchMath.underEyeDelta(region: region, cheek: cheek, strength: 0), .zero)
        for s in stride(from: 0.05, through: 1.0, by: 0.05) {
            let after = region + SelfieRetouchMath.underEyeDelta(region: region, cheek: cheek, strength: s)
            XCTAssertLessThanOrEqual(SelfieRetouchMath.luminance(after), SelfieRetouchMath.luminance(cheek) + 1e-12, "s=\(s)")
            XCTAssertGreaterThan(SelfieRetouchMath.luminance(after), SelfieRetouchMath.luminance(region), "s=\(s)")
        }
        // Region already brighter than the cheek: luminance untouched (chroma only) — never darkens / lightens skin overall.
        let bright = SIMD3<Double>(0.7, 0.6, 0.6)
        let d = SelfieRetouchMath.underEyeDelta(region: bright, cheek: cheek, strength: 0.6)
        XCTAssertEqual(SelfieRetouchMath.luminance(d), 0, accuracy: 1e-12)
        // Cap: strength > 1 behaves as 1 (never overshoots the cheek).
        let over = region + SelfieRetouchMath.underEyeDelta(region: region, cheek: cheek, strength: 4)
        XCTAssertLessThanOrEqual(SelfieRetouchMath.luminance(over), SelfieRetouchMath.luminance(cheek) + 1e-12)
    }

    func testUnderEyeImage_liftsRegionTowardCheek_andIsIdentityAtZero() {
        let size = CGSize(width: 200, height: 200)
        let eye = CGRect(x: 80, y: 120, width: 40, height: 20)
        let region = SelfieRetouchMath.underEyeRegion(eye: eye)
        let cheek = SelfieRetouchMath.cheekPatch(for: region)
        let skin = CIImage(color: CIColor(red: 0.78, green: 0.60, blue: 0.50)).cropped(to: CGRect(origin: .zero, size: size))
        let shadow = CIImage(color: CIColor(red: 0.52, green: 0.40, blue: 0.48))
            .cropped(to: CGRect(x: region.rect.minX - 6, y: region.rect.minY, width: region.width + 12, height: region.height + 2))
        let input = shadow.composited(over: skin)
        let face = SelfieFaceGeometry(boundingBox: CGRect(x: 40, y: 40, width: 120, height: 140), leftEye: corners(eye))
        let low = SelfieRetouchEngine.gaussian(input, sigma: 1.5)

        let zero = engine.applyUnderEye(input, low: low, faces: [face], strength: 0)
        XCTAssertEqual(bytes(zero, size), bytes(input, size), "strength 0 must return the input")

        let inner = region.rect.insetBy(dx: region.width * 0.3, dy: region.height * 0.3)
        let cheekInner = cheek.rect.insetBy(dx: cheek.width * 0.3, dy: cheek.height * 0.3)
        let before = try! XCTUnwrap(engine.mean(input, in: inner))
        let cheekMean = try! XCTUnwrap(engine.mean(input, in: cheekInner))
        let out = engine.applyUnderEye(input, low: low, faces: [face], strength: SelfieRetouchParams.maxUnderEye)
        let after = try! XCTUnwrap(engine.mean(out, in: inner))
        XCTAssertGreaterThan(SelfieRetouchMath.luminance(after), SelfieRetouchMath.luminance(before) + 1e-3,
                             "under-eye region should lift (kernel ran)")
        XCTAssertLessThanOrEqual(SelfieRetouchMath.luminance(after), SelfieRetouchMath.luminance(cheekMean) + 1e-3,
                                 "never brighter than the person's own cheek")
        // Cheek reference itself is untouched.
        let cheekAfter = try! XCTUnwrap(engine.mean(out, in: cheekInner))
        XCTAssertEqual(SelfieRetouchMath.luminance(cheekAfter), SelfieRetouchMath.luminance(cheekMean), accuracy: 2e-3)
    }

    // MARK: - Identity / no face

    func testIntensityZero_returnsInputUnchanged() {
        let input = gradient(CGSize(width: 64, height: 48))
        for id in CreativeLookCatalog.selfieIds {
            let out = engine.apply(lookId: id, intensity: 0, to: input)
            XCTAssertEqual(bytes(out, CGSize(width: 64, height: 48)), bytes(input, CGSize(width: 64, height: 48)), id)
        }
        // Through the shared engine: bake is a no-op (nil) at intensity 0.
        let ui = UIImage(cgImage: context.createCGImage(input, from: input.extent)!)
        XCTAssertNil(CreativeLookEngine.shared.bake(image: ui, look: CreativeLook(id: "selfieGlow", intensity: 0)))
    }

    func testNoFace_appliesGlobalGradeOnly() {
        let size = CGSize(width: 96, height: 64)
        let input = gradient(size)
        let params = SelfiePresets.retouch(lookId: "selfieGlow", intensity: 1)!
        let out = engine.apply(lookId: "selfieGlow", intensity: 1, to: input)
        let expected = engine.globalGrade(input, params: params)
        XCTAssertEqual(bytes(out, size), bytes(expected, size), "no face → warmth grade only, no retouch")
        XCTAssertNotEqual(bytes(out, size), bytes(input, size), "Soft Glow still warms a no-face frame")
        // Studio Crisp has no warmth → no face means unchanged.
        let studio = engine.apply(lookId: "selfieStudio", intensity: 1, to: input)
        XCTAssertEqual(bytes(studio, size), bytes(input, size))
    }

    func testRetouch_syntheticFace_keepsSizeAndFiniteOutput() {
        let size = CGSize(width: 240, height: 320)
        let input = gradient(size)
        let face = SelfieFaceGeometry(
            boundingBox: CGRect(x: 60, y: 90, width: 120, height: 150),
            faceContour: (0...10).map { i in
                let t = Double(i) / 10 * Double.pi
                return CGPoint(x: 120 - 60 * cos(t), y: 160 - 70 * sin(t))
            },
            leftEye: corners(CGRect(x: 80, y: 190, width: 30, height: 12)),
            rightEye: corners(CGRect(x: 130, y: 190, width: 30, height: 12)),
            leftEyebrow: [CGPoint(x: 78, y: 210), CGPoint(x: 95, y: 215), CGPoint(x: 112, y: 212)],
            rightEyebrow: [CGPoint(x: 128, y: 212), CGPoint(x: 145, y: 215), CGPoint(x: 162, y: 210)],
            outerLips: corners(CGRect(x: 100, y: 120, width: 40, height: 14))
        )
        let analysis = SelfieAnalysis(faces: [face], personMask: nil, analysisScale: 1)
        let params = SelfiePresets.retouch(lookId: "selfieLowLight", intensity: 1)!
        let out = engine.retouch(input, analysis: analysis, params: params)
        XCTAssertEqual(out.extent, input.extent)
        XCTAssertEqual(bytes(out, size).count, Int(size.width * size.height * 4))
    }

    func testBackgroundBlur_onlyOutsidePersonMask() {
        // 1000 px long edge → blur radius ≈ 4.5 px at strength 1 (18 px @ 4032 px, scaled).
        let size = CGSize(width: 1000, height: 1000)
        let input = checkerboard(size)
        let personCG = maskImage(size: size) { ctx in ctx.fillEllipse(in: CGRect(x: 250, y: 200, width: 500, height: 650)) }
        let face = SelfieFaceGeometry(boundingBox: CGRect(x: 350, y: 450, width: 300, height: 350))
        let analysis = SelfieAnalysis(faces: [face], personMask: personCG, analysisScale: 1)
        let out = engine.retouch(input, analysis: analysis, params: SelfieRetouchParams(backgroundBlur: 1.0))
        let a = bytes(input, size), b = bytes(out, size)
        func diff(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> Double {
            var total = 0.0, n = 0.0
            for yy in y..<(y + h) { for xx in x..<(x + w) {
                // bytes are top-down rows; convert from bottom-left y.
                let row = Int(size.height) - 1 - yy
                let i = (row * Int(size.width) + xx) * 4
                total += abs(Double(a[i]) - Double(b[i])); n += 1
            } }
            return total / n
        }
        XCTAssertGreaterThan(diff(10, 10, 100, 100), 10, "background corner should blur")
        XCTAssertLessThan(diff(475, 500, 50, 50), 3, "person center should stay sharp")
    }

    // MARK: - Orientation

    func testOrientation_rightOrientedStillIsUprightBeforeAnalysis() {
        // Raw (sensor) bitmap 40×20 with a red block in its top-left corner, tagged `.right`
        // (display = rotate 90° clockwise). Upright frame is 20×40 and the block lands top-right.
        let raw = rawWithTopLeftBlock(width: 40, height: 20, block: 6)
        XCTAssertEqual(SelfieRetouchMath.cgOrientation(.right), .right)
        let upright = SelfieRetouchEngine.orientedInput(cgImage: raw, orientation: .right)
        XCTAssertEqual(upright.extent, CGRect(x: 0, y: 0, width: 20, height: 40))
        XCTAssertTrue(isRed(pixel(upright, x: 17, y: 37)), "block should be top-right on the upright frame")
        XCTAssertFalse(isRed(pixel(upright, x: 2, y: 37)), "not top-left (sideways frame)")
        XCTAssertFalse(isRed(pixel(upright, x: 17, y: 2)))
        // A landmark Vision reports at that spot (normalized, bottom-left) maps back onto the block.
        let p = SelfieRetouchMath.fullResPoint(visionNormalized: CGPoint(x: 17.5 / 20, y: 37.5 / 40),
                                               fullSize: upright.extent.size)
        XCTAssertTrue(isRed(pixel(upright, x: Int(p.x), y: Int(p.y))))
        // Baking through CreativeLookEngine returns an upright `.up` image of the oriented size.
        let ui = UIImage(cgImage: raw, scale: 1, orientation: .right)
        let baked = CreativeLookEngine.shared.bake(image: ui, look: CreativeLook(id: "selfieNatural", intensity: 1))
        XCTAssertEqual(baked?.imageOrientation, .up)
        XCTAssertEqual(baked?.cgImage?.width, 20)
        XCTAssertEqual(baked?.cgImage?.height, 40)
    }

    // MARK: - Helpers

    private func corners(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.midY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.midX, y: r.minY)]
    }

    private func gradient(_ size: CGSize) -> CIImage {
        let g = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0),
            "inputPoint1": CIVector(x: size.width, y: size.height),
            "inputColor0": CIColor(red: 0.2, green: 0.3, blue: 0.5),
            "inputColor1": CIColor(red: 0.8, green: 0.7, blue: 0.4),
        ])!.outputImage!
        return g.cropped(to: CGRect(origin: .zero, size: size))
    }

    private func checkerboard(_ size: CGSize) -> CIImage {
        CIFilter(name: "CICheckerboardGenerator", parameters: [
            "inputCenter": CIVector(x: 0, y: 0),
            "inputColor0": CIColor(red: 1, green: 1, blue: 1),
            "inputColor1": CIColor(red: 0, green: 0, blue: 0),
            "inputWidth": 4,
            "inputSharpness": 1,
        ])!.outputImage!.cropped(to: CGRect(origin: .zero, size: size))
    }

    private func maskImage(size: CGSize, draw: (CGContext) -> Void) -> CIImage {
        SelfieRetouchEngine.rasterMask(size: size, scale: 1) { ctx in
            ctx.setFillColor(gray: 1, alpha: 1)
            draw(ctx)
        }!
    }

    private func rawWithTopLeftBlock(width: Int, height: Int, block: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        // CGContext origin is bottom-left: top rows are y = height - block … height.
        ctx.fill(CGRect(x: 0, y: height - block, width: block, height: block))
        return ctx.makeImage()!
    }

    private func bytes(_ image: CIImage, _ size: CGSize) -> [UInt8] {
        let w = Int(size.width), h = Int(size.height)
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        context.render(image, toBitmap: &buf, rowBytes: w * 4,
                       bounds: CGRect(x: 0, y: 0, width: w, height: h),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        return buf
    }

    private func pixel(_ image: CIImage, x: Int, y: Int) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: 4)
        context.render(image, toBitmap: &buf, rowBytes: 4,
                       bounds: CGRect(x: x, y: y, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        return buf
    }

    private func isRed(_ px: [UInt8]) -> Bool { px[0] > 200 && px[1] < 60 && px[2] < 60 }
}
