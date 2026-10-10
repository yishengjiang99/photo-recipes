# Task: Add selfie preset looks (with under-eye softening) to ProTune / PhotoRecipes

You are working in the `yishengjiang99/photo-recipes` repo (iOS app in `ios/PhotoRecipes`, server in `server/`). Add a small pack of **selfie presets** that combine real camera controls (exposure, focus, flash, low-light boost) with a face-aware still-image retouch pass that controls sharpness, lighting and blur, including a subtle **under-eye (eye-bag) softening** step. Everything runs on device with Apple frameworks (AVFoundation, Vision, Core Image). Do not add third-party SDKs or ML model weights.

## Read these first (do not skip)

- `ios/PhotoRecipes/Models/CreativeLook.swift`: `CreativeLook` (id plus 0…1 intensity, default 0.55) and `CreativeLookCatalog` (ids, display names, craft sentences).
- `ios/PhotoRecipes/Services/CreativeLookEngine.swift`: the global CIFilter chain. `apply(look:to:)` switches on id, `blend` dissolves graded output with the input by intensity, and `bakeJPEG` runs on every still.
- `ios/PhotoRecipes/Services/CameraSession.swift`: `apply(targets:)` (around L580–760) writes `PhoneTargets` to the device. It handles front camera (no torch), white balance, `lowLightBoost`, `creativeLook`, and `simulatedAperture` (coach-only). The photo delegate (near the end of the file) calls `CreativeLookEngine.shared.bakeJPEG` when `bakeLookOnNextCapture` is set. Front stills are mirrored via `mirrorFrontPhotos`.
- `ios/PhotoRecipes/Models/RecommendResponse.swift`: `PhoneTargets`, `TorchTarget`, `WhiteBalanceTarget`, `FocusPointNorm`.
- `ios/PhotoRecipes/Features/Camera/CameraPreviewView.swift`: the live finder shows looks only as a tinted `CALayer` overlay, not a real render.
- `ios/PhotoRecipes/Services/SceneFeatures.swift`: existing Vision usage (`VNDetectFaceRectanglesRequest`, downscaled buffers) and `CoordinateSpaces.swift` (Vision coordinates are normalized with a bottom-left origin).
- `ios/PhotoRecipes/Data/BundledPresets.swift` and `Services/RecipeCameraMapper.swift`: how recipes become camera settings. Look at `portrait-pop` as the closest existing recipe.
- `server/recommend.ts`: `CREATIVE_LOOK_IDS` must stay in sync with the iOS catalog (see `server/phoneTargets.test.ts`).

Match existing conventions: `@MainActor` engines, small pure functions with unit tests in `ios/PhotoRecipesTests`, clamped values, and craft-language copy. The catalog says looks are "capture grade, not a beauty filter". Keep that voice and describe these looks as light and texture choices, never as "fixing" a face.

## The presets

Add these five ids to `CreativeLookCatalog.allIds`, `displayNames`, `craftSentences`, and to `CREATIVE_LOOK_IDS` on the server.

| id | Name | Camera targets (`PhoneTargets`) | Retouch pass (still only) |
|---|---|---|---|
| `selfieNatural` | Natural Light | front camera, `ev: "+0.3"`, continuous AF/AE with `focusPoint` on the face | skin smoothing 0.20, under-eye 0.35, detail sharpen 0.25, warmth +150K |
| `selfieGlow` | Soft Glow | front camera, `ev: "+0.5"`, `flash: "auto"` | skin smoothing 0.30, under-eye 0.50, highlight bloom 0.15 (skin mask only), warmth +300K |
| `selfieStudio` | Studio Crisp | front camera, `ev: "+0.2"`, white balance locked after AE settles | skin smoothing 0.15, under-eye 0.30, detail sharpen 0.45, background blur 0.35 |
| `selfieLowLight` | Low Light | front camera, `lowLightBoost: true`, `flash: "on"` if Retina Flash is supported, `ev: "+0.3"` | noise reduction before smoothing, skin smoothing 0.25, under-eye 0.45, detail sharpen 0.20 |
| `selfiePortrait` | Portrait Blur | front camera, `ev: "+0.3"`, `simulatedAperture: 2.0` (existing coach path) | skin smoothing 0.20, under-eye 0.35, detail sharpen 0.30, background blur 0.70 |

All per-step strengths above apply at look intensity 1.0 and scale linearly with `CreativeLook.resolvedIntensity`. Hard caps apply at any intensity: skin smoothing ≤ 0.40, under-eye ≤ 0.60, detail sharpen ≤ 0.60, background blur radius ≤ 18 px at 12 MP (scale by image size). No reshaping, slimming, eye enlarging or skin-tone lightening in any preset.

Also add a matching `Recipe` per preset to `BundledPresets` (follow `portrait-pop`) so the presets appear in the library and route through the existing apply path.

## Camera controls (lighting and sharpness at capture)

Implement these in or next to `CameraSession.apply(targets:)`, reusing existing helpers:

- **Face-weighted exposure and focus:** when a selfie look is active and Vision has a face box, set `exposurePointOfInterest` and `focusPointOfInterest` to the face center using the existing Vision-to-device conversion (`CoordinateSpaces`). Guard with `isExposurePointOfInterestSupported` and `isFocusPointOfInterestSupported`, since some front cameras are fixed-focus.
- **EV bias:** use `ExposureApplyPolicy`. Do not program EV on top of a custom shutter/ISO write.
- **Front flash:** front cameras have no torch (already handled). For `flash: "on"` or `"auto"`, check `photoOutput.supportedFlashModes` and use Retina Flash via `AVCapturePhotoSettings.flashMode`. If unsupported, append a `clampMessages` entry and continue.
- **Capture quality:** keep `photoQualityPrioritization` at `maxPhotoQualityPrioritization` (already required; mismatches crash bracket capture).
- **Live preview:** the finder only supports tint overlays. Add a neutral warm tint for the selfie ids in `lookTint(for:)` and do not attempt real-time retouching in this task.

## Retouch pass (new `Services/SelfieRetouchEngine.swift`)

Dispatch to this engine from `CreativeLookEngine.apply(look:to:)` for ids prefixed with `selfie`. Then apply a light global grade (warmth via the existing `temperature` helper) and keep the existing intensity `blend`. Pipeline per still:

1. **Orientation first.** `bakeJPEG` builds `CIImage(cgImage:)` from a `UIImage`, which drops `imageOrientation`. Either pass the matching `CGImagePropertyOrientation` to `VNImageRequestHandler`, or orient the CIImage before analysis. Otherwise landmarks land on a sideways image. Write a test for this.
2. **Analysis on a downscaled copy** (long edge about 1024 px): run `VNDetectFaceLandmarksRequest` and `VNGeneratePersonSegmentationRequest` (`.balanced`) in one handler. Scale masks back to full resolution. With no face, skip steps 3–6 and apply only the global grade.
3. **Skin mask:** face-contour polygon from landmarks, minus eyes, brows and lips (dilated slightly), feathered by about 2% of face width. Intersect with the person mask.
4. **Skin smoothing (blur that keeps texture):** frequency separation. Low frequency is a Gaussian blur at about 1.2% of face width. High frequency is `image − low`. Smooth only the low layer (`CIBilateralFilter` if available, otherwise a second, stronger Gaussian), then recombine with at least 70% of the high-frequency layer so pores survive. Blend through the skin mask at the preset strength.
5. **Under-eye softening (eye bags):**
   - For each eye, take the landmark eye bounding box. The under-eye region is an ellipse centered 0.55 × eye height below the lower lid, 1.1 × eye width wide and 0.7 × eye height tall. Feather it heavily with a radial falloff and keep it clear of the lower lash line by 0.1 × eye height.
   - Sample a **reference cheek patch** directly below the region (same size, offset down by one region height). Compute mean luminance and chroma for both.
   - In the low-frequency layer only, raise the region's luminance toward the cheek mean (never above it), and pull its chroma toward the cheek chroma to neutralize purple/blue shadow. Strength equals the preset's under-eye value.
   - Reduce local contrast in the region by up to 30% of that strength. Keep at least 80% of high-frequency detail here so the result still looks like skin, not a patch.
   - All changes are relative to the person's own cheek, so this never lightens anyone's overall skin tone.
6. **Detail sharpen:** `CISharpenLuminance` (or `CIUnsharpMask` with a small radius) through a mask of eyes, brows, lashes, lips and hair (person mask minus skin mask). Never sharpen the skin mask.
7. **Background blur** (`selfieStudio`, `selfiePortrait`): `CIMaskedVariableBlur` using the inverted, feathered person mask. Erode the mask by about 1% of image width before inverting so hair edges do not halo.
8. **Low light:** for `selfieLowLight`, run `CINoiseReduction` on the low-frequency layer before step 4.

Performance target: under 400 ms per 12 MP still on an iPhone 12. Reuse the shared `CIContext` and do not render intermediate images to CGImage.

## Tests (`ios/PhotoRecipesTests`)

- Catalog: the new ids are in `allIds`, have names and craft sentences, and match the server's `CREATIVE_LOOK_IDS` (extend `server/phoneTargets.test.ts`).
- Pure geometry: the under-eye ellipse is computed from a sample eye box, stays below the lash line, and scales with face size.
- Under-eye math: the region's luminance after the lift is less than or equal to the cheek reference, and it equals the input at strength 0.
- Intensity 0 returns the input unchanged. A frame with no face applies only the global grade.
- Orientation: a `.right`-oriented test image yields landmarks in the correct place.
- Caps: requested strengths above the hard caps are clamped.

## Done when

- All five presets can be selected, apply their camera targets on the front camera, and bake the retouch into saved stills.
- The before/after chip shows the difference, and the result looks like the same person in better light.
- The existing iOS unit tests and server tests pass, along with the new ones.
- The PR description includes before/after crops of the under-eye region at intensity 0.55 and 1.0.
