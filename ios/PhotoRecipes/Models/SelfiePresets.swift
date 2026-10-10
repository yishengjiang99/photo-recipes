import CoreGraphics
import Foundation

/// Per-step retouch strengths for one selfie preset (still only, see `SelfieRetouchEngine`).
/// Values in the catalog are the strengths at look intensity 1.0; `scaled(by:)` scales
/// them linearly with `CreativeLook.resolvedIntensity` and applies the hard caps.
/// Light and texture choices only — there is deliberately no geometry, slimming,
/// eye-size or skin-tone parameter here.
struct SelfieRetouchParams: Equatable {
    /// Skin smoothing blend through the skin mask (frequency separation), 0…`maxSkinSmoothing`.
    var skinSmoothing: Double = 0
    /// Under-eye softening toward the person's own cheek, 0…`maxUnderEye`.
    var underEye: Double = 0
    /// Luminance sharpen on eyes / brows / lips / hair (never skin), 0…`maxDetailSharpen`.
    var detailSharpen: Double = 0
    /// Background blur as a fraction of `maxBackgroundBlurPx12MP`, 0…1.
    var backgroundBlur: Double = 0
    /// Soft highlight bloom through the skin mask, 0…`maxHighlightBloom`.
    var highlightBloom: Double = 0
    /// Global warmth in Kelvin (positive = warmer), 0…`maxWarmthKelvin`.
    var warmthKelvin: Double = 0
    /// Low-light noise reduction strength 0…1 (runs before smoothing).
    var noiseReduction: Double = 0

    // Hard caps — hold at any intensity (docs/selfie/selfie-presets-prompt.md).
    static let maxSkinSmoothing = 0.40
    static let maxUnderEye = 0.60
    static let maxDetailSharpen = 0.60
    static let maxBackgroundBlur = 1.0
    /// Background blur radius cap at a 12 MP (4032 px long edge) still; scaled by image size.
    static let maxBackgroundBlurPx12MP = 18.0
    static let maxHighlightBloom = 0.30
    static let maxWarmthKelvin = 600.0
    static let maxNoiseReduction = 1.0

    /// Every strength clamped into its hard cap (non-finite → 0).
    func clamped() -> SelfieRetouchParams {
        func c(_ v: Double, _ hi: Double) -> Double {
            guard v.isFinite else { return 0 }
            return min(max(v, 0), hi)
        }
        return SelfieRetouchParams(
            skinSmoothing: c(skinSmoothing, Self.maxSkinSmoothing),
            underEye: c(underEye, Self.maxUnderEye),
            detailSharpen: c(detailSharpen, Self.maxDetailSharpen),
            backgroundBlur: c(backgroundBlur, Self.maxBackgroundBlur),
            highlightBloom: c(highlightBloom, Self.maxHighlightBloom),
            warmthKelvin: c(warmthKelvin, Self.maxWarmthKelvin),
            noiseReduction: c(noiseReduction, Self.maxNoiseReduction)
        )
    }

    /// Linear scale by look intensity (clamped 0…1), then hard caps. Intensity 0 → all zero.
    func scaled(by intensity: Double) -> SelfieRetouchParams {
        let k = intensity.isFinite ? min(max(intensity, 0), 1) : 0
        return SelfieRetouchParams(
            skinSmoothing: skinSmoothing * k,
            underEye: underEye * k,
            detailSharpen: detailSharpen * k,
            backgroundBlur: backgroundBlur * k,
            highlightBloom: highlightBloom * k,
            warmthKelvin: warmthKelvin * k,
            noiseReduction: noiseReduction * k
        ).clamped()
    }

    /// True when nothing would change (identity).
    var isIdentity: Bool {
        skinSmoothing <= 0 && underEye <= 0 && detailSharpen <= 0 && backgroundBlur <= 0
            && highlightBloom <= 0 && warmthKelvin <= 0 && noiseReduction <= 0
    }

    /// Face-aware steps (everything except the global warmth grade).
    var hasFaceSteps: Bool {
        skinSmoothing > 0 || underEye > 0 || detailSharpen > 0 || backgroundBlur > 0 || highlightBloom > 0
    }
}

/// Front-camera selfie preset pack: camera targets (capture light) + still retouch strengths.
/// Ids are `CreativeLookCatalog.selfieIds` (server `SELFIE_CREATIVE_LOOK_IDS`).
enum SelfiePresets {

    struct Preset: Equatable {
        var lookId: String
        var recipeId: String
        /// Strengths at look intensity 1.0.
        var retouch: SelfieRetouchParams
        /// Capture targets written through `CameraSession.applyPhoneTargets` on the front camera.
        var targets: PhoneTargets
        /// Lock white balance once auto exposure has settled (Studio Crisp).
        var lockWhiteBalanceAfterAE: Bool = false
        /// Meter + focus on the detected face (continuous AF/AE at the face point).
        var meterOnFace: Bool = true
    }

    static let all: [Preset] = [
        Preset(
            lookId: "selfieNatural",
            recipeId: "selfie-natural-light",
            retouch: SelfieRetouchParams(skinSmoothing: 0.20, underEye: 0.35, detailSharpen: 0.25, warmthKelvin: 150),
            targets: PhoneTargets(ev: "+0.3", focusMode: "continuous")
        ),
        Preset(
            lookId: "selfieGlow",
            recipeId: "selfie-soft-glow",
            retouch: SelfieRetouchParams(skinSmoothing: 0.30, underEye: 0.50, highlightBloom: 0.15, warmthKelvin: 300),
            targets: PhoneTargets(ev: "+0.5", flash: "auto")
        ),
        Preset(
            lookId: "selfieStudio",
            recipeId: "selfie-studio-crisp",
            retouch: SelfieRetouchParams(skinSmoothing: 0.15, underEye: 0.30, detailSharpen: 0.45, backgroundBlur: 0.35),
            targets: PhoneTargets(ev: "+0.2"),
            lockWhiteBalanceAfterAE: true
        ),
        Preset(
            lookId: "selfieLowLight",
            recipeId: "selfie-low-light",
            retouch: SelfieRetouchParams(skinSmoothing: 0.25, underEye: 0.45, detailSharpen: 0.20, noiseReduction: 1.0),
            // flash "on" is gated on Retina Flash support in CameraSession.applyFlash (clamp message if absent).
            targets: PhoneTargets(ev: "+0.3", flash: "on", lowLightBoost: true)
        ),
        Preset(
            lookId: "selfiePortrait",
            recipeId: "selfie-portrait-blur",
            retouch: SelfieRetouchParams(skinSmoothing: 0.20, underEye: 0.35, detailSharpen: 0.30, backgroundBlur: 0.70),
            // simulatedAperture is coach-only on phones (existing path) — the blur itself is the still retouch.
            targets: PhoneTargets(ev: "+0.3", simulatedAperture: 2.0)
        ),
    ]

    static func preset(lookId: String) -> Preset? {
        all.first { $0.lookId == lookId }
    }

    static func preset(recipeId: String) -> Preset? {
        all.first { $0.recipeId == recipeId }
    }

    /// Retouch strengths for a look at a given intensity (linear, capped). Nil for non-selfie ids.
    static func retouch(lookId: String, intensity: Double) -> SelfieRetouchParams? {
        preset(lookId: lookId)?.retouch.scaled(by: intensity)
    }

    /// Face-weighted metering point in **UI space** (top-left origin, 0…1).
    /// `SceneFeatures.subjectBox` is already UI-space (converted from Vision via
    /// `CoordinateSpaces.visionRectToUI` in SceneFeatures), so no further flip here.
    /// Nil when the box is empty / non-finite.
    static func faceMeteringPoint(uiFaceBox box: CGRect) -> CGPoint? {
        guard box.width > 0, box.height > 0,
              box.midX.isFinite, box.midY.isFinite else { return nil }
        return CoordinateSpaces.clamp01(CGPoint(x: box.midX, y: box.midY))
    }
}
