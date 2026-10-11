# Selfie preset pack — follow-ups

This is a review of the shipped selfie pack: #160 (presets and retouch engine) and #161 (Looks drawer Selfie section). Each item says whether it was implemented in the follow-up PR or is still open.

## Implemented in the follow-up PR

1. **The still bake runs off the main thread.** The photo delegate used to run `CreativeLookEngine.bakeJPEG` inside a `@MainActor` task. For a selfie look, that meant Vision landmarks, person segmentation, four `CIAreaAverage` readbacks, a full-resolution render and a JPEG re-encode all ran on the UI thread, which froze the camera for every selfie shot. The bake now runs in a detached `.userInitiated` task. `CreativeLookEngine` and `SelfieRetouchEngine` hold only immutable state (a thread-safe `CIContext`), so they are no longer main-actor bound.
2. **Under-eye placement follows head tilt.** The under-eye ellipse and cheek reference were placed straight down in image space, so on a tilted head they slid toward the nose or the outer cheek. Roll now comes from the two eye centres (clamped to ±45°). Each eye is measured in the face's own frame, and the region, the cheek patch and the mask all rotate with it. A level face gives exactly the old geometry.
3. **Under-eye safety guards.**
   - The lift is scaled uniformly so that no channel moves more than `underEyeMaxLift`. Uniform scaling keeps the result at or below the cheek and keeps the chroma direction.
   - The step is skipped when the cheek reference is more than 3× brighter than the region, or the region is near black. In practice that means glasses frames, sunglasses, hair, a hand or specular glare, where lifting would leave a visible patch.
4. **Small background faces are skipped.** Faces narrower than 40 % of the largest face are dropped before retouching. They were being smoothed with a blur sigma sized for the main face.
5. **On-device timing telemetry.** A `selfie_bake` event sends `look_id`, `bake_ms`, `long_edge_px`, `front` and `baked`. This gives the real per-device number for the < 400 ms target, which CI can't measure. No pixels and no face data are sent.

### Review fixes (same PR)

- **Tilted regions are sampled in the face frame.** The region and cheek means rotate the low-pass layer upright about the ellipse centre before `CIAreaAverage`. The axis-aligned box of a tilted ellipse reached past the lash line into the eye (about 5 % of the sample at 40°). Level faces are unchanged.
- **The occluder guard checks both ways.** It also skips when the region is more than 3× brighter than the cheek: glare on the under-eye, or hair, a hand or a frame over the cheek patch.
- **Faces are limited after the size filter.** The order is primary-face filter, then largest first, then the 4-face cap. Vision's result order isn't by size.
- **Backgrounding mid-shot.** A `UIApplication` background task covers shutter → bake → Photos save, for single shots and the bracket burst. iOS doesn't allow GPU work in the background, so a photo that arrives while the app is backgrounded, or a bake that runs into `didEnterBackground`, keeps the un-baked JPEG. That is the same fallback as a bake failure.
- **`selfie_bake` accuracy.** `front` is snapshotted before the bake, and a new `baked` (0/1) field marks fallbacks so they don't skew timing.
- **Concurrency.** `CreativeLookEngine` drops its leftover `ObservableObject` conformance. The static color kernels are `nonisolated(unsafe)` (immutable, initialised once), so a later move to Swift 6 doesn't flag them.

## Open, not in this PR

- **Live preview retouch.** The finder only shows a tint for selfie looks. A real-time path would be a Metal / `CIContext` render of a downscaled frame on the video queue, using the same masks at about 256 px.
- **Keep EXIF on baked stills.** `bakeJPEG` re-encodes through `UIImage.jpegData`, which drops capture metadata for every look. Writing through `CGImageDestination` with the source properties (orientation reset to 1) would keep it. This needs a decision on which fields to strip, to match the telemetry EXIF-strip policy.
- **Separate under-eye control.** Under-eye strength now rides the look intensity. A separate "Under-eye" slider in Controls would let people turn only that step up or down.
- **Before/after crops on device.** As noted in #160: capture each preset at 0.55 and 1.0 and compare the under-eye crops, especially on tilted heads and with glasses (the cases this PR changes).
- **Per-face smoothing sigma.** All faces share the largest face's sigma. That is fine now that small faces are dropped, but group selfies with similar-sized faces would benefit from per-face masks.
