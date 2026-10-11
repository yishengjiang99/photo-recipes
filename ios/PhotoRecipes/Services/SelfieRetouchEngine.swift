import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UIKit
import Vision

// MARK: - Geometry (pure, unit-tested)

/// One face's landmarks in **full-resolution pixel space, bottom-left origin**
/// (Core Image / Vision convention), on the upright (already-oriented) still.
struct SelfieFaceGeometry: Equatable {
    var boundingBox: CGRect
    /// Vision `faceContour`: jaw line ear-to-ear (an open curve — closed upward in the skin mask).
    var faceContour: [CGPoint] = []
    var leftEye: [CGPoint] = []
    var rightEye: [CGPoint] = []
    var leftEyebrow: [CGPoint] = []
    var rightEyebrow: [CGPoint] = []
    var outerLips: [CGPoint] = []

    var faceWidth: CGFloat { boundingBox.width }

    /// Eye bounding boxes (non-empty landmark regions only).
    var eyeBoxes: [CGRect] {
        [leftEye, rightEye].compactMap(SelfieRetouchMath.boundingRect)
    }

    /// Head roll (radians, counter-clockwise, bottom-left origin) from the two eye centres.
    var roll: CGFloat { SelfieRetouchMath.roll(eyes: [leftEye, rightEye]) }
}

/// Elliptical retouch region (center + full width/height in the face's own frame, rotated
/// by `angle` radians counter-clockwise), bottom-left origin pixels.
struct SelfieEllipse: Equatable {
    var center: CGPoint
    var width: CGFloat
    var height: CGFloat
    /// Rotation of the ellipse axes (head roll). 0 = axis-aligned.
    var angle: CGFloat = 0

    /// Axis-aligned bounding box (accounts for `angle`; equals the plain box at angle 0).
    var rect: CGRect {
        let a = width / 2, b = height / 2
        let c = abs(cos(angle)), s = abs(sin(angle))
        let hx = angle == 0 ? a : (a * a * c * c + b * b * s * s).squareRoot()
        let hy = angle == 0 ? b : (a * a * s * s + b * b * c * c).squareRoot()
        return CGRect(x: center.x - hx, y: center.y - hy, width: hx * 2, height: hy * 2)
    }
    /// Top edge in the face's own frame (image top when `angle` is 0).
    var top: CGFloat { center.y + height / 2 }

    /// Unit vector pointing "down the face" (toward the chin) for this ellipse's angle.
    var faceDown: CGVector { CGVector(dx: sin(angle), dy: -cos(angle)) }
}

/// Small pure helpers for the selfie retouch pass. Everything here is
/// deterministic and covered by `SelfieRetouchTests`.
enum SelfieRetouchMath {
    /// Fraction of high-frequency (texture) detail kept wherever skin is smoothed.
    /// ≥ 0.7 required for skin; ≥ 0.8 required under the eyes — one value satisfies both.
    static let highFrequencyKeep: Double = 0.80
    /// Local-contrast reduction in the under-eye region per unit of under-eye strength.
    static let underEyeContrastPerStrength: Double = 0.30
    /// Analysis copy long edge (Vision landmarks + person segmentation).
    static let analysisLongEdge: CGFloat = 1024

    /// Under-eye ellipse for an eye bounding box (bottom-left origin: "below" = smaller y).
    /// Centered 0.55 × eye height below the lower lid, 1.1 × eye width wide, 0.7 × eye
    /// height tall, and kept at least 0.1 × eye height clear of the lower lash line.
    static func underEyeRegion(eye: CGRect) -> SelfieEllipse {
        underEyeRegion(eyeCenter: CGPoint(x: eye.midX, y: eye.midY),
                       eyeWidth: eye.width, eyeHeight: eye.height, roll: 0)
    }

    /// Roll-aware under-eye region from an eye's landmark points. The eye is measured in the
    /// face's own frame (rotated by `roll`), and the region sits "below" along the face's down
    /// vector, so a tilted head keeps the region under the lid instead of drifting toward the
    /// nose / outer cheek. `roll == 0` gives exactly `underEyeRegion(eye:)` of the bounding box.
    static func underEyeRegion(eyePoints: [CGPoint], roll: CGFloat) -> SelfieEllipse? {
        guard let f = eyeFrame(points: eyePoints, roll: roll) else { return nil }
        return underEyeRegion(eyeCenter: f.center, eyeWidth: f.width, eyeHeight: f.height, roll: roll)
    }

    private static func underEyeRegion(eyeCenter: CGPoint, eyeWidth: CGFloat, eyeHeight: CGFloat,
                                       roll: CGFloat) -> SelfieEllipse {
        let w = eyeWidth * 1.1
        let h = eyeHeight * 0.7
        // Distance (along face-down) from the lower lid to the region centre; keep ≥ 0.1 × eye
        // height between the region's top and the lower lash line.
        var belowLid = 0.55 * eyeHeight
        let minBelowLid = 0.1 * eyeHeight + h / 2
        if belowLid < minBelowLid { belowLid = minBelowLid }
        let d = eyeHeight / 2 + belowLid
        let down = CGVector(dx: sin(roll), dy: -cos(roll))
        let center = CGPoint(x: eyeCenter.x + down.dx * d, y: eyeCenter.y + down.dy * d)
        return SelfieEllipse(center: center, width: w, height: h, angle: roll)
    }

    /// Reference cheek patch: same size, directly below the region along the face's down
    /// vector (offset by one region height).
    static func cheekPatch(for region: SelfieEllipse) -> SelfieEllipse {
        let down = region.faceDown
        return SelfieEllipse(center: CGPoint(x: region.center.x + down.dx * region.height,
                                             y: region.center.y + down.dy * region.height),
                             width: region.width, height: region.height, angle: region.angle)
    }

    /// Max head roll handled (±45°). Beyond that the face is lying sideways; clamp.
    static let maxRoll: CGFloat = .pi / 4

    /// Head roll from the two eye centres (radians, counter-clockwise, bottom-left origin).
    /// 0 when fewer than two non-empty eyes. Clamped to ±`maxRoll`.
    static func roll(eyes: [[CGPoint]]) -> CGFloat {
        let centers = eyes.compactMap(boundingRect).map { CGPoint(x: $0.midX, y: $0.midY) }
        guard centers.count >= 2 else { return 0 }
        let sorted = centers.sorted { $0.x < $1.x }
        let a = sorted[0], b = sorted[sorted.count - 1]
        let dx = b.x - a.x, dy = b.y - a.y
        guard dx.isFinite, dy.isFinite, dx != 0 || dy != 0 else { return 0 }
        let r = atan2(dy, dx)
        return min(max(r, -maxRoll), maxRoll)
    }

    /// Eye extent in the face's own frame: centre, width along the eye axis, height across it.
    static func eyeFrame(points: [CGPoint], roll: CGFloat) -> (center: CGPoint, width: CGFloat, height: CGFloat)? {
        guard !points.isEmpty else { return nil }
        let u = CGVector(dx: cos(roll), dy: sin(roll))     // along the eye axis
        let v = CGVector(dx: -sin(roll), dy: cos(roll))    // face up
        var minU = CGFloat.infinity, maxU = -CGFloat.infinity
        var minV = CGFloat.infinity, maxV = -CGFloat.infinity
        for p in points {
            let pu = p.x * u.dx + p.y * u.dy
            let pv = p.x * v.dx + p.y * v.dy
            minU = min(minU, pu); maxU = max(maxU, pu)
            minV = min(minV, pv); maxV = max(maxV, pv)
        }
        let w = maxU - minU, h = maxV - minV
        guard w > 0, h > 0, w.isFinite, h.isFinite else { return nil }
        let cu = (minU + maxU) / 2, cv = (minV + maxV) / 2
        let center = CGPoint(x: u.dx * cu + v.dx * cv, y: u.dy * cu + v.dy * cv)
        return (center, w, h)
    }

    /// Faces worth retouching: at least `primaryFaceFraction` of the largest face's width.
    /// Small background faces would otherwise be smoothed with the main face's blur sigma.
    static let primaryFaceFraction: CGFloat = 0.40

    static func primaryFaces(_ faces: [SelfieFaceGeometry]) -> [SelfieFaceGeometry] {
        guard let largest = faces.map(\.faceWidth).max(), largest > 0 else { return faces }
        return faces.filter { $0.faceWidth >= largest * primaryFaceFraction }
    }

    /// Max faces retouched per still.
    static let maxRetouchFaces = 4

    /// Faces to retouch: primary faces, largest first, at most `limit`. Vision doesn't return
    /// faces in size order, so the size filter and sort run before the limit. Otherwise a
    /// crowded frame could drop the main face.
    static func retouchFaces(_ faces: [SelfieFaceGeometry], limit: Int = maxRetouchFaces) -> [SelfieFaceGeometry] {
        Array(primaryFaces(faces).sorted { $0.faceWidth > $1.faceWidth }.prefix(max(limit, 0)))
    }

    /// Rec. 709 luminance of a linear RGB triple.
    static func luminance(_ rgb: SIMD3<Double>) -> Double {
        0.2126 * rgb.x + 0.7152 * rgb.y + 0.0722 * rgb.z
    }

    /// Additive RGB offset (low-frequency layer) moving the under-eye mean toward the cheek mean.
    /// - Luminance rises toward the cheek and never above it; when the region is already
    ///   brighter than the cheek, luminance is left alone (chroma only).
    /// - Chroma (purple / blue shadow) is pulled toward the cheek's chroma.
    /// - Strength 0 → zero offset. Relative to the person's own cheek: never a global lightening.
    static func underEyeDelta(region: SIMD3<Double>, cheek: SIMD3<Double>, strength: Double) -> SIMD3<Double> {
        let s = strength.isFinite ? min(max(strength, 0), 1) : 0
        guard s > 0 else { return .zero }
        var d = (cheek - region) * s
        let lumaGap = luminance(cheek) - luminance(region)
        if lumaGap < 0 {
            // Remove the (darkening) luma component; luminance weights sum to 1.
            let y = luminance(d)
            d -= SIMD3(repeating: y)
        }
        // Lift cap: scale uniformly so no channel moves more than `underEyeMaxLift`. Uniform
        // scaling keeps the chroma direction and keeps the result between region and cheek.
        let peak = max(abs(d.x), abs(d.y), abs(d.z))
        if peak > underEyeMaxLift, peak.isFinite {
            d *= underEyeMaxLift / peak
        }
        return d
    }

    /// Max per-channel under-eye lift (working-space linear units). Stops a wrong reference
    /// (glasses, hair, a hand) from turning into a visible patch.
    static let underEyeMaxLift: Double = 0.10
    /// Skip under-eye when one of region / cheek is more than this many times brighter than the
    /// other. That gap is an occluder (glasses frame, sunglasses, hair, a hand) or glare, not a
    /// shadow. Checked both ways: glare on the region, or something dark over the cheek patch,
    /// would otherwise turn into a chroma pull toward the occluder.
    static let underEyeMaxCheekRatio: Double = 3.0
    /// Skip under-eye when the region is essentially black (lens, deep occlusion).
    static let underEyeMinRegionLuma: Double = 0.005

    /// Whether the region / cheek pair looks like skin in shadow next to skin (safe to lift).
    static func underEyeIsReliable(region: SIMD3<Double>, cheek: SIMD3<Double>) -> Bool {
        let r = luminance(region), c = luminance(cheek)
        guard r.isFinite, c.isFinite, r >= underEyeMinRegionLuma else { return false }
        return c <= r * underEyeMaxCheekRatio && r <= c * underEyeMaxCheekRatio
    }

    /// Background blur radius in pixels: ≤ 18 px at 12 MP (4032 px long edge), scaled by image size.
    static func backgroundBlurRadius(strength: Double, imageSize: CGSize) -> Double {
        let s = strength.isFinite ? min(max(strength, 0), SelfieRetouchParams.maxBackgroundBlur) : 0
        let longEdge = Double(max(imageSize.width, imageSize.height))
        guard longEdge > 0 else { return 0 }
        return s * SelfieRetouchParams.maxBackgroundBlurPx12MP * (longEdge / 4032.0)
    }

    /// Low-frequency Gaussian sigma: ~1.2 % of face width.
    static func lowFrequencySigma(faceWidth: CGFloat) -> Double { max(1, Double(faceWidth) * 0.012) }
    /// Skin-mask feather: ~2 % of face width.
    static func featherRadius(faceWidth: CGFloat) -> Double { max(1, Double(faceWidth) * 0.02) }

    /// Downscale factor for the analysis copy (≤ 1).
    static func analysisScale(for size: CGSize, longEdge: CGFloat = analysisLongEdge) -> CGFloat {
        let le = max(size.width, size.height)
        guard le > 0 else { return 1 }
        return min(1, longEdge / le)
    }

    /// `UIImage.Orientation` → EXIF / `CGImagePropertyOrientation`.
    static func cgOrientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    /// Vision normalized landmark (bottom-left origin, relative to the upright analysis
    /// image) → full-resolution pixel (bottom-left origin). Analysis is uniformly downscaled,
    /// so normalized coordinates carry over directly.
    static func fullResPoint(visionNormalized p: CGPoint, fullSize: CGSize) -> CGPoint {
        CGPoint(x: p.x * fullSize.width, y: p.y * fullSize.height)
    }

    static func boundingRect(_ pts: [CGPoint]) -> CGRect? {
        guard let first = pts.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in pts.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let r = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return (r.width > 0 && r.height > 0) ? r : nil
    }
}

// MARK: - Analysis result

/// Vision analysis of one still: faces at full resolution + person mask at analysis resolution.
struct SelfieAnalysis {
    var faces: [SelfieFaceGeometry]
    /// Person segmentation (white = person) at analysis resolution, origin zero. Nil if unavailable.
    var personMask: CIImage?
    /// analysis px = full-res px × `analysisScale`.
    var analysisScale: CGFloat
}

// MARK: - Engine

/// Face-aware still retouch for the selfie preset pack. Runs on device with Vision +
/// Core Image only (no third-party SDKs / model weights). Light and texture only:
/// no warping, slimming, eye enlarging or skin-tone lightening.
///
/// Pipeline (`apply`): orientation is handled by the caller (`CreativeLookEngine.bake`
/// orients the CIImage before analysis) → Vision on a ~1024 px copy → skin / detail
/// masks → noise reduction (low light) → frequency-separation smoothing → highlight
/// bloom → under-eye softening → feature-only sharpen → masked background blur →
/// global warmth. No face → global grade only.
///
/// Not main-actor bound: the still bake runs off the main thread (see `CameraSession`'s
/// photo delegate). The only instance state is an immutable, thread-safe `CIContext`. Every
/// call builds its own Vision requests and CIFilters. The two static color kernels are
/// immutable and initialised once.
final class SelfieRetouchEngine: @unchecked Sendable {
    private let context: CIContext

    init(context: CIContext) {
        self.context = context
    }

    /// Full selfie pass for a look id at an intensity. `image` must be upright with an
    /// origin-zero extent. Intensity 0 (or unknown id) → input unchanged.
    func apply(lookId: String, intensity: Double, to image: CIImage) -> CIImage {
        guard let params = SelfiePresets.retouch(lookId: lookId, intensity: intensity),
              !params.isIdentity else { return image }
        let base = Self.normalized(image)
        if params.hasFaceSteps || params.noiseReduction > 0 {
            let analysis = analyze(base)
            if !analysis.faces.isEmpty {
                return globalGrade(retouch(base, analysis: analysis, params: params), params: params)
            }
        }
        return globalGrade(base, params: params)
    }

    /// Orient a UIImage-backed CIImage so analysis sees the upright frame (Vision landmarks
    /// otherwise land on a sideways image). Origin moved to zero.
    static func orientedInput(cgImage: CGImage, orientation: UIImage.Orientation) -> CIImage {
        normalized(CIImage(cgImage: cgImage).oriented(SelfieRetouchMath.cgOrientation(orientation)))
    }

    static func normalized(_ image: CIImage) -> CIImage {
        let e = image.extent
        guard e.minX != 0 || e.minY != 0, e.minX.isFinite, e.minY.isFinite else { return image }
        return image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
    }

    // MARK: Global grade

    /// Light global grade: warmth only (shared with the no-face path).
    func globalGrade(_ image: CIImage, params: SelfieRetouchParams) -> CIImage {
        guard params.warmthKelvin > 0 else { return image }
        let f = CIFilter.temperatureAndTint()
        f.inputImage = image
        f.neutral = CIVector(x: 6500, y: 0)
        // Same convention as CreativeLookEngine warm looks: lower target neutral = warmer.
        f.targetNeutral = CIVector(x: 6500 - CGFloat(params.warmthKelvin), y: 0)
        return f.outputImage?.cropped(to: image.extent) ?? image
    }

    // MARK: Analysis

    /// Vision landmarks + person segmentation on a downscaled copy (one handler).
    func analyze(_ image: CIImage) -> SelfieAnalysis {
        let extent = image.extent
        let scale = SelfieRetouchMath.analysisScale(for: extent.size)
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let handler = VNImageRequestHandler(ciImage: small, orientation: .up, options: [:])

        let faceReq = VNDetectFaceLandmarksRequest()
        var faces: [SelfieFaceGeometry] = []
        do {
            try handler.perform([faceReq])
            faces = SelfieRetouchMath.retouchFaces(
                (faceReq.results ?? []).compactMap { Self.geometry(from: $0, fullSize: extent.size) }
            )
        } catch {
            faces = []
        }
        guard !faces.isEmpty else { return SelfieAnalysis(faces: [], personMask: nil, analysisScale: scale) }

        var mask: CIImage?
        let segReq = VNGeneratePersonSegmentationRequest()
        segReq.qualityLevel = .balanced
        segReq.outputPixelFormat = kCVPixelFormatType_OneComponent8
        do {
            try handler.perform([segReq])
            if let buf = segReq.results?.first?.pixelBuffer {
                let m = CIImage(cvPixelBuffer: buf, options: [.colorSpace: NSNull()])
                let sx = small.extent.width / max(m.extent.width, 1)
                let sy = small.extent.height / max(m.extent.height, 1)
                mask = m.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
                    .cropped(to: CGRect(origin: .zero, size: small.extent.size))
            }
        } catch {
            mask = nil // simulator / unsupported: face masks only, no background blur
        }
        return SelfieAnalysis(faces: faces, personMask: mask, analysisScale: scale)
    }

    private static func geometry(from obs: VNFaceObservation, fullSize: CGSize) -> SelfieFaceGeometry? {
        let bb = obs.boundingBox
        let box = CGRect(x: bb.minX * fullSize.width, y: bb.minY * fullSize.height,
                         width: bb.width * fullSize.width, height: bb.height * fullSize.height)
        guard box.width > 4, box.height > 4 else { return nil }
        func pts(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            guard let region else { return [] }
            // normalizedPoints are relative to the face bounding box.
            return region.normalizedPoints.map { p in
                let v = CGPoint(x: bb.minX + CGFloat(p.x) * bb.width, y: bb.minY + CGFloat(p.y) * bb.height)
                return SelfieRetouchMath.fullResPoint(visionNormalized: v, fullSize: fullSize)
            }
        }
        let lm = obs.landmarks
        return SelfieFaceGeometry(
            boundingBox: box,
            faceContour: pts(lm?.faceContour),
            leftEye: pts(lm?.leftEye),
            rightEye: pts(lm?.rightEye),
            leftEyebrow: pts(lm?.leftEyebrow),
            rightEyebrow: pts(lm?.rightEyebrow),
            outerLips: pts(lm?.outerLips)
        )
    }

    // MARK: Retouch (injectable geometry — no Vision needed in tests)

    func retouch(_ image: CIImage, analysis: SelfieAnalysis, params p: SelfieRetouchParams) -> CIImage {
        let extent = image.extent
        guard !analysis.faces.isEmpty, extent.width > 0, extent.height > 0 else { return image }
        let p = p.clamped()
        let scale = analysis.analysisScale > 0 ? analysis.analysisScale : 1
        let faceW = analysis.faces.map(\.faceWidth).max() ?? extent.width * 0.3
        let toFull = CGAffineTransform(scaleX: 1 / scale, y: 1 / scale)
        let analysisSize = CGSize(width: ceil(extent.width * scale), height: ceil(extent.height * scale))

        // Person mask (analysis res) — absent → treat face region as the person.
        let person = analysis.personMask

        // Skin mask: face polygon minus eyes / brows / lips (dilated), feathered ~2 % face width,
        // intersected with the person mask.
        let featherA = SelfieRetouchMath.featherRadius(faceWidth: faceW) * Double(scale)
        var skinSmall = Self.rasterMask(size: analysisSize, scale: scale) { ctx in
            for f in analysis.faces { Self.drawSkin(f, in: ctx) }
        }.map { Self.feather($0, radius: featherA) }
        if let s = skinSmall, let person { skinSmall = Self.multiply(s, person) }
        let skin = skinSmall.map { $0.transformed(by: toFull).cropped(to: extent) }

        var out = image

        // 8. Low light: noise reduction before smoothing (see PR notes — on the full image,
        // since the low-frequency layer is already noise-free by construction).
        if p.noiseReduction > 0 {
            let nr = CIFilter.noiseReduction()
            nr.inputImage = out
            nr.noiseLevel = Float(0.01 + 0.03 * p.noiseReduction)
            nr.sharpness = 0.4
            out = nr.outputImage?.cropped(to: extent) ?? out
        }

        // 4. Frequency-separation smoothing. low = Gaussian(1.2 % face width); smooth the low
        // layer with a second, stronger Gaussian (CIBilateralFilter is not a built-in Core
        // Image filter), recombine with 80 % of the high-frequency layer, blend through skin.
        let sigma = SelfieRetouchMath.lowFrequencySigma(faceWidth: faceW)
        let low = Self.gaussian(out, sigma: sigma)
        if p.skinSmoothing > 0, let skin {
            let smoothLow = Self.gaussian(low, sigma: sigma * 2.5)
            if let recombined = Self.recombine(base: out, low: low, smoothLow: smoothLow,
                                               keep: SelfieRetouchMath.highFrequencyKeep) {
                out = Self.blend(recombined, over: out, mask: Self.scaleMask(skin, p.skinSmoothing))
            }
        }

        // Highlight bloom (Soft Glow) — skin mask only.
        if p.highlightBloom > 0, let skin {
            let bloom = CIFilter.bloom()
            bloom.inputImage = out
            bloom.radius = Float(max(2, faceW * 0.03))
            bloom.intensity = 1.0
            if let b = bloom.outputImage?.cropped(to: extent) {
                out = Self.blend(b, over: out, mask: Self.scaleMask(skin, p.highlightBloom))
            }
        }

        // 5. Under-eye softening, relative to the person's own cheek.
        if p.underEye > 0 {
            out = applyUnderEye(out, low: low, faces: analysis.faces, strength: p.underEye)
        }

        // 6. Detail sharpen on eyes / brows / lips + hair (person minus skin, above the eyes).
        if p.detailSharpen > 0 {
            let featureSmall = Self.rasterMask(size: analysisSize, scale: scale) { ctx in
                for f in analysis.faces { Self.drawFeatures(f, in: ctx) }
            }
            var detail = featureSmall
            if let person, let skinSmall,
               let band = Self.rasterMask(size: analysisSize, scale: scale, draw: { ctx in
                   for f in analysis.faces { Self.drawHairBand(f, in: ctx) }
               }) {
                let hair = Self.multiply(Self.multiply(band, person), Self.invert(skinSmall))
                detail = detail.map { Self.maximum($0, hair) } ?? hair
            }
            if let detail {
                let mask = Self.feather(detail, radius: max(1, featherA * 0.5)).transformed(by: toFull).cropped(to: extent)
                let sharp = CIFilter.sharpenLuminance()
                sharp.inputImage = out
                sharp.sharpness = Float(p.detailSharpen)
                sharp.radius = Float(max(1.0, 2.0 * Double(max(extent.width, extent.height)) / 4032.0))
                if let s = sharp.outputImage?.cropped(to: extent) {
                    out = Self.blend(s, over: out, mask: mask)
                }
            }
        }

        // 7. Background blur: inverted, eroded (~1 % width), feathered person mask.
        if p.backgroundBlur > 0, let person {
            let radius = SelfieRetouchMath.backgroundBlurRadius(strength: p.backgroundBlur, imageSize: extent.size)
            if radius >= 0.5 {
                let erode = CIFilter.morphologyMinimum()
                erode.inputImage = person.clampedToExtent()
                erode.radius = Float(max(1, analysisSize.width * 0.01))
                let eroded = (erode.outputImage ?? person).cropped(to: person.extent)
                let bgMask = Self.invert(Self.feather(eroded, radius: max(1, featherA)))
                    .transformed(by: toFull).cropped(to: extent)
                let mvb = CIFilter.maskedVariableBlur()
                mvb.inputImage = out.clampedToExtent()
                mvb.mask = bgMask.clampedToExtent()
                mvb.radius = Float(radius)
                if let b = mvb.outputImage?.cropped(to: extent) { out = b }
            }
        }
        return out.cropped(to: extent)
    }

    /// Under-eye step only (exposed for tests with synthetic geometry).
    func applyUnderEye(_ image: CIImage, low: CIImage, faces: [SelfieFaceGeometry], strength: Double) -> CIImage {
        let s = min(max(strength, 0), SelfieRetouchParams.maxUnderEye)
        guard s > 0 else { return image }
        var out = image
        for face in faces {
            let roll = face.roll
            for eye in [face.leftEye, face.rightEye] where !eye.isEmpty {
                guard let region = SelfieRetouchMath.underEyeRegion(eyePoints: eye, roll: roll) else { continue }
                let cheek = SelfieRetouchMath.cheekPatch(for: region)
                guard let rMean = mean(low, in: region),
                      let cMean = mean(low, in: cheek),
                      SelfieRetouchMath.underEyeIsReliable(region: rMean, cheek: cMean)
                else { continue }
                let delta = SelfieRetouchMath.underEyeDelta(region: rMean, cheek: cMean, strength: s)
                let mask = Self.ellipseMask(region).cropped(to: image.extent)
                if let lifted = Self.underEyeKernelApply(
                    base: out, low: low, mask: mask, delta: delta, regionMean: rMean,
                    contrastCut: SelfieRetouchMath.underEyeContrastPerStrength * s
                ) {
                    out = lifted
                }
            }
        }
        return out
    }

    /// Mean working-space RGB over an ellipse's box, inset by `inset` on each side, measured in
    /// the face's own frame. A rotated ellipse is sampled upright: the image is rotated by
    /// −angle about the centre. The axis-aligned bounding box of a tilted ellipse would reach
    /// past the lash line into the eye (about 5 % of the sample at 40°) and onto the side of
    /// the nose. `angle == 0` is the plain inset-rect mean.
    func mean(_ image: CIImage, in e: SelfieEllipse, inset: CGFloat = 0.15) -> SIMD3<Double>? {
        if e.angle == 0 {
            let r = e.rect
            return mean(image, in: r.insetBy(dx: r.width * inset, dy: r.height * inset))
        }
        guard e.angle.isFinite, e.width >= 1, e.height >= 1,
              !e.rect.intersection(image.extent).isNull else { return nil }
        let c = e.center
        let upright = CGAffineTransform(translationX: c.x, y: c.y)
            .rotated(by: -e.angle)
            .translatedBy(x: -c.x, y: -c.y)
        // Clamp first so a region near the frame edge repeats edge pixels instead of averaging
        // in transparent black.
        let rotated = image.clampedToExtent().transformed(by: upright)
        let box = CGRect(x: c.x - e.width / 2, y: c.y - e.height / 2, width: e.width, height: e.height)
            .insetBy(dx: e.width * inset, dy: e.height * inset)
        return mean(rotated, in: box)
    }

    /// Mean working-space RGB over a rect (CIAreaAverage → one RGBAf pixel).
    func mean(_ image: CIImage, in rect: CGRect) -> SIMD3<Double>? {
        let r = rect.intersection(image.extent)
        guard !r.isNull, r.width >= 1, r.height >= 1 else { return nil }
        let f = CIFilter.areaAverage()
        f.inputImage = image
        f.extent = r
        guard let px = f.outputImage else { return nil }
        var buf = [Float](repeating: 0, count: 4)
        context.render(px, toBitmap: &buf, rowBytes: 16,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBAf, colorSpace: nil)
        let v = SIMD3(Double(buf[0]), Double(buf[1]), Double(buf[2]))
        guard v.x.isFinite, v.y.isFinite, v.z.isFinite else { return nil }
        return v
    }

    // MARK: - Kernels (Core Image built-ins have no signed add; small color kernels instead)

    // `nonisolated(unsafe)`: CIColorKernel isn't marked Sendable, but these are initialised
    // once (swift_once) and never mutated, and Core Image kernels are safe to apply from
    // several threads. The engine runs off the main thread (see the class doc).
    nonisolated(unsafe) private static let recombineKernel: CIColorKernel? = CIColorKernel(source: """
    kernel vec4 selfieRecombine(__sample src, __sample lowf, __sample smoothed, float keep) {
        return vec4(smoothed.rgb + keep * (src.rgb - lowf.rgb), src.a);
    }
    """)

    nonisolated(unsafe) private static let underEyeKernel: CIColorKernel? = CIColorKernel(source: """
    kernel vec4 selfieUnderEye(__sample src, __sample lowf, __sample m, vec4 offset, vec4 regionMean, float cut) {
        vec3 lift = offset.rgb - cut * (lowf.rgb - regionMean.rgb);
        return vec4(src.rgb + m.r * lift, src.a);
    }
    """)

    static func recombine(base: CIImage, low: CIImage, smoothLow: CIImage, keep: Double) -> CIImage? {
        recombineKernel?.apply(extent: base.extent, arguments: [base, low, smoothLow, Float(keep)])
    }

    static func underEyeKernelApply(base: CIImage, low: CIImage, mask: CIImage,
                                    delta: SIMD3<Double>, regionMean: SIMD3<Double>, contrastCut: Double) -> CIImage? {
        underEyeKernel?.apply(extent: base.extent, arguments: [
            base, low, mask,
            CIVector(x: delta.x, y: delta.y, z: delta.z, w: 0),
            CIVector(x: regionMean.x, y: regionMean.y, z: regionMean.z, w: 0),
            Float(contrastCut),
        ])
    }

    // MARK: - Mask helpers

    static func gaussian(_ image: CIImage, sigma: Double) -> CIImage {
        image.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: image.extent)
    }

    static func feather(_ mask: CIImage, radius: Double) -> CIImage {
        mask.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: mask.extent)
    }

    static func multiply(_ a: CIImage, _ b: CIImage) -> CIImage {
        let f = CIFilter.multiplyCompositing()
        f.inputImage = a
        f.backgroundImage = b
        return (f.outputImage ?? a).cropped(to: a.extent)
    }

    static func maximum(_ a: CIImage, _ b: CIImage) -> CIImage {
        let f = CIFilter.maximumCompositing()
        f.inputImage = a
        f.backgroundImage = b
        return (f.outputImage ?? a).cropped(to: a.extent)
    }

    static func invert(_ mask: CIImage) -> CIImage {
        let f = CIFilter.colorInvert()
        f.inputImage = mask
        return (f.outputImage ?? mask).cropped(to: mask.extent)
    }

    /// Gray mask × strength (0…1).
    static func scaleMask(_ mask: CIImage, _ s: Double) -> CIImage {
        let k = CGFloat(min(max(s, 0), 1))
        let f = CIFilter.colorMatrix()
        f.inputImage = mask
        f.rVector = CIVector(x: k, y: 0, z: 0, w: 0)
        f.gVector = CIVector(x: 0, y: k, z: 0, w: 0)
        f.bVector = CIVector(x: 0, y: 0, z: k, w: 0)
        f.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return (f.outputImage ?? mask).cropped(to: mask.extent)
    }

    static func blend(_ top: CIImage, over base: CIImage, mask: CIImage) -> CIImage {
        let f = CIFilter.blendWithMask()
        f.inputImage = top
        f.backgroundImage = base
        f.maskImage = mask
        return (f.outputImage ?? base).cropped(to: base.extent)
    }

    /// Heavily feathered elliptical mask (radial falloff: solid core 30 %, fades to 0 at the edge).
    static func ellipseMask(_ e: SelfieEllipse) -> CIImage {
        let g = CIFilter.radialGradient()
        g.center = .zero
        g.radius0 = 0.3
        g.radius1 = 1.0
        g.color0 = CIColor(red: 1, green: 1, blue: 1)
        g.color1 = CIColor(red: 0, green: 0, blue: 0)
        let unit = g.outputImage ?? CIImage(color: .black)
        return unit
            .transformed(by: CGAffineTransform(scaleX: max(e.width / 2, 0.5), y: max(e.height / 2, 0.5)))
            .transformed(by: CGAffineTransform(rotationAngle: e.angle))
            .transformed(by: CGAffineTransform(translationX: e.center.x, y: e.center.y))
    }

    /// Rasterize a gray mask at analysis resolution. Drawing callbacks use **full-res**
    /// coordinates (the context is pre-scaled), bottom-left origin like Core Image.
    static func rasterMask(size: CGSize, scale: CGFloat, draw: (CGContext) -> Void) -> CIImage? {
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        draw(ctx)
        guard let cg = ctx.makeImage() else { return nil }
        return CIImage(cgImage: cg, options: [.colorSpace: NSNull()])
    }

    private static func polygon(_ pts: [CGPoint], in ctx: CGContext) {
        guard pts.count >= 3 else { return }
        ctx.beginPath()
        ctx.addLines(between: pts)
        ctx.closePath()
    }

    /// Face polygon (jaw contour closed up over the forehead) minus dilated eyes / brows / lips.
    static func drawSkin(_ f: SelfieFaceGeometry, in ctx: CGContext) {
        let box = f.boundingBox
        let dilate = max(2, f.faceWidth * 0.04)
        ctx.setFillColor(gray: 1, alpha: 1)
        if f.faceContour.count >= 3, let first = f.faceContour.first, let last = f.faceContour.last {
            var pts = f.faceContour
            let foreheadTop = box.maxY + box.height * 0.12
            pts.append(CGPoint(x: last.x, y: box.maxY))
            pts.append(CGPoint(x: box.midX, y: foreheadTop))
            pts.append(CGPoint(x: first.x, y: box.maxY))
            polygon(pts, in: ctx)
            ctx.fillPath()
        } else {
            ctx.fillEllipse(in: box.insetBy(dx: box.width * 0.08, dy: 0))
        }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.setStrokeColor(gray: 0, alpha: 1)
        ctx.setLineWidth(dilate)
        ctx.setLineJoin(.round)
        for region in [f.leftEye, f.rightEye, f.leftEyebrow, f.rightEyebrow, f.outerLips] where region.count >= 3 {
            polygon(region, in: ctx)
            ctx.drawPath(using: .fillStroke)
        }
        // Brows are open curves — stroke them as lines too.
        for brow in [f.leftEyebrow, f.rightEyebrow] where brow.count >= 2 {
            ctx.beginPath()
            ctx.addLines(between: brow)
            ctx.strokePath()
        }
    }

    /// Eyes (incl. lashes via dilation), brows, lips — the only facial areas that get sharpened.
    static func drawFeatures(_ f: SelfieFaceGeometry, in ctx: CGContext) {
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.setStrokeColor(gray: 1, alpha: 1)
        ctx.setLineWidth(max(2, f.faceWidth * 0.03))
        ctx.setLineJoin(.round)
        for region in [f.leftEye, f.rightEye, f.outerLips] where region.count >= 3 {
            polygon(region, in: ctx)
            ctx.drawPath(using: .fillStroke)
        }
        for brow in [f.leftEyebrow, f.rightEyebrow] where brow.count >= 2 {
            ctx.beginPath()
            ctx.addLines(between: brow)
            ctx.strokePath()
        }
    }

    /// Region around / above the head where hair lives (multiplied by person − skin).
    static func drawHairBand(_ f: SelfieFaceGeometry, in ctx: CGContext) {
        let box = f.boundingBox
        let eyeY = f.eyeBoxes.map(\.midY).max() ?? box.midY
        let band = CGRect(x: box.minX - box.width * 0.4, y: eyeY,
                          width: box.width * 1.8, height: (box.maxY - eyeY) + box.height * 0.7)
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(band)
    }
}
