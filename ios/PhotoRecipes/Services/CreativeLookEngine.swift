import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Capture-grade Creative Looks (V1 pack). CIFilter chain + intensity blend.
/// Bakes into live preview AND still JPEG when intensity > 0 (not a beauty filter).
@MainActor
final class CreativeLookEngine: ObservableObject {
    static let shared = CreativeLookEngine()

    private let context = CIContext(options: [.useSoftwareRenderer: false])
    /// Face-aware still retouch for the selfie pack (shares this engine's CIContext).
    private lazy var selfie = SelfieRetouchEngine(context: context)

    /// Apply look to a UIImage (preview strip / Teach / still bake). Returns nil if unknown or intensity ≤ 0.
    func bake(image: UIImage, look: CreativeLook) -> UIImage? {
        let intensity = look.resolvedIntensity
        guard intensity > 0, CreativeLookCatalog.isKnown(look.id),
              let cg = image.cgImage else { return nil }
        if CreativeLookCatalog.isSelfie(look.id) {
            // Orientation first: CIImage(cgImage:) drops imageOrientation, and Vision landmarks
            // must run on the upright frame. Bake upright and return `.up`.
            let upright = SelfieRetouchEngine.orientedInput(cgImage: cg, orientation: image.imageOrientation)
            guard let blended = blend(look: look, input: upright, intensity: intensity),
                  let out = context.createCGImage(blended, from: blended.extent) else { return nil }
            return UIImage(cgImage: out, scale: image.scale, orientation: .up)
        }
        let input = CIImage(cgImage: cg)
        guard let blended = blend(look: look, input: input, intensity: intensity) else { return nil }
        guard let out = context.createCGImage(blended, from: blended.extent) else { return nil }
        return UIImage(cgImage: out, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Bake JPEG Data in place when look intensity > 0. Returns original data on failure / no-op.
    func bakeJPEG(_ data: Data, look: CreativeLook?) -> Data {
        guard let look, look.resolvedIntensity > 0,
              let img = UIImage(data: data),
              let baked = bake(image: img, look: look),
              let out = baked.jpegData(compressionQuality: 0.92) else { return data }
        return out
    }

    /// Alias for strip / Teach preview.
    func preview(image: UIImage, look: CreativeLook) -> UIImage? {
        bake(image: image, look: look)
    }

    func apply(look: CreativeLook, to image: CIImage) -> CIImage {
        if CreativeLookCatalog.isSelfie(look.id) {
            // Selfie pack: face-aware retouch + light warmth. Strengths already scale linearly
            // with intensity inside the engine (see `blend`).
            return selfie.apply(lookId: look.id, intensity: look.resolvedIntensity, to: image)
        }
        switch look.id {
        case "crispCool":
            return temperature(contrast(image, 1.12), neutral: 6500, target: 7200)
        case "warmGlow":
            return vibrance(temperature(image, neutral: 6500, target: 4800), 0.18)
        case "warmPop":
            return contrast(vibrance(temperature(image, neutral: 6500, target: 4500), 0.35), 1.08)
        case "editorialRed":
            return hue(colorControls(image, saturation: 1.15, brightness: 0.02, contrast: 1.05), angle: -0.04)
        case "softVintage":
            return temperature(
                colorControls(image, saturation: 0.78, brightness: 0.04, contrast: 0.92),
                neutral: 6500, target: 5200
            )
        case "monoInk":
            return contrast(mono(image), 1.25)
        case "goldenHour":
            return colorControls(
                temperature(image, neutral: 6500, target: 4200),
                saturation: 1.05, brightness: 0.03, contrast: 1.02
            )
        case "loFiPunch":
            return vignette(vibrance(contrast(image, 1.18), 0.22), intensity: 0.6, radius: 1.4)
        case "tealOrange":
            return contrast(vibrance(temperature(image, neutral: 6500, target: 7800), 0.28), 1.1)
        case "blockbuster":
            return vibrance(temperature(contrast(image, 1.22), neutral: 6500, target: 7000), 0.12)
        case "moodyFilm":
            return temperature(
                colorControls(image, saturation: 0.85, brightness: -0.04, contrast: 1.08),
                neutral: 6500, target: 5600
            )
        case "coolBlue":
            return contrast(temperature(image, neutral: 6500, target: 8200), 1.1)
        case "softDream":
            return bloom(
                colorControls(image, saturation: 0.9, brightness: 0.06, contrast: 0.88),
                radius: 4, intensity: 0.35
            )
        case "filmGrain":
            return noise(colorControls(image, saturation: 0.92, brightness: 0, contrast: 1.05), amount: 0.04)
        default:
            return image
        }
    }

    private func blend(look: CreativeLook, input: CIImage, intensity: Double) -> CIImage? {
        if CreativeLookCatalog.isSelfie(look.id) {
            // Selfie strengths are scaled by intensity per step (capped); dissolving on top would
            // square the effect and ghost the background blur. Intensity 0 stays identity.
            if intensity <= 0.01 { return input }
            return apply(look: look, to: input)
        }
        let graded = apply(look: look, to: input)
        if intensity >= 0.99 { return graded }
        if intensity <= 0.01 { return input }
        guard let mix = CIFilter(name: "CIDissolveTransition") else { return graded }
        mix.setValue(input, forKey: kCIInputImageKey)
        mix.setValue(graded, forKey: kCIInputTargetImageKey)
        mix.setValue(intensity, forKey: kCIInputTimeKey)
        return mix.outputImage ?? graded
    }

    // MARK: - CIFilter helpers

    private func contrast(_ image: CIImage, _ c: Double) -> CIImage {
        colorControls(image, saturation: 1, brightness: 0, contrast: c)
    }

    private func colorControls(_ image: CIImage, saturation: Double, brightness: Double, contrast: Double) -> CIImage {
        let f = CIFilter.colorControls()
        f.inputImage = image
        f.saturation = Float(saturation)
        f.brightness = Float(brightness)
        f.contrast = Float(contrast)
        return f.outputImage ?? image
    }

    private func temperature(_ image: CIImage, neutral: CGFloat, target: CGFloat) -> CIImage {
        let f = CIFilter.temperatureAndTint()
        f.inputImage = image
        f.neutral = CIVector(x: neutral, y: 0)
        f.targetNeutral = CIVector(x: target, y: 0)
        return f.outputImage ?? image
    }

    private func vibrance(_ image: CIImage, _ amount: Double) -> CIImage {
        let f = CIFilter.vibrance()
        f.inputImage = image
        f.amount = Float(amount)
        return f.outputImage ?? image
    }

    private func hue(_ image: CIImage, angle: Double) -> CIImage {
        let f = CIFilter.hueAdjust()
        f.inputImage = image
        f.angle = Float(angle)
        return f.outputImage ?? image
    }

    private func mono(_ image: CIImage) -> CIImage {
        let f = CIFilter.photoEffectNoir()
        f.inputImage = image
        return f.outputImage ?? image
    }

    private func vignette(_ image: CIImage, intensity: Double, radius: Double) -> CIImage {
        let f = CIFilter.vignette()
        f.inputImage = image
        f.intensity = Float(intensity)
        f.radius = Float(radius)
        return f.outputImage ?? image
    }

    private func bloom(_ image: CIImage, radius: Double, intensity: Double) -> CIImage {
        let f = CIFilter.bloom()
        f.inputImage = image
        f.radius = Float(radius)
        f.intensity = Float(intensity)
        return f.outputImage ?? image
    }

    private func noise(_ image: CIImage, amount: Double) -> CIImage {
        guard let noiseImg = CIFilter(name: "CIRandomGenerator")?.outputImage?
            .cropped(to: image.extent),
              let mono = CIFilter(name: "CIColorMatrix") else { return image }
        mono.setValue(noiseImg, forKey: kCIInputImageKey)
        mono.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputAVector")
        mono.setValue(CIVector(x: amount, y: amount, z: amount, w: 0), forKey: "inputRVector")
        mono.setValue(CIVector(x: amount, y: amount, z: amount, w: 0), forKey: "inputGVector")
        mono.setValue(CIVector(x: amount, y: amount, z: amount, w: 0), forKey: "inputBVector")
        guard let grain = mono.outputImage,
              let comp = CIFilter(name: "CISourceOverCompositing") else { return image }
        comp.setValue(grain.cropped(to: image.extent), forKey: kCIInputImageKey)
        comp.setValue(image, forKey: kCIInputBackgroundImageKey)
        return comp.outputImage?.cropped(to: image.extent) ?? image
    }
}
