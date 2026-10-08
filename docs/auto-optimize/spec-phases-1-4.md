# Prompt: Fix and upgrade "Auto Optimize" in PhotoRecipes (iOS)

> Source: user prompt, sent 2026-10-07. Persisted verbatim at the user's request.

You are a senior iOS camera engineer working in the `photo-recipes` repo, in the iOS app at `ios/PhotoRecipes` (SwiftUI, AVFoundation, Vision; the Xcode project is generated from `ios/project.yml`; tests are in `ios/PhotoRecipesTests`). Your job is to make the **Auto Optimize** button produce correctly exposed photos and then turn it into an on-device, data-driven system using the iPhone GPU (Metal) and Neural Engine (Core ML). Work in the phases below, in order. Every phase must ship independently, behind no flags unless stated, with tests passing.

## Context: how Auto Optimize works today

- `Services/AutoOptimizeController.swift` drives Sense → Reason → Apply → Verify → Ready. It snapshots metering (`session.refreshReadouts()`), captures a probe JPEG (`session.captureProbeFrame()`), calls `LocalSceneAnalyzer.analyze`, then `LocalAutoOptimizeEngine.recommend`, then `session.applyPhoneTargets`.
- `Services/LocalSceneAnalyzer.swift` produces `LocalSceneSignals`: `brightness01` (the **histogram mean of the probe JPEG**), contrast, clipping, warmBias, faces and saliency via Vision, plus keyword hints parsed from the user's scene note.
- `Services/LocalAutoOptimizeEngine.swift` picks a recipe (`chooseRecipeId`, using hand thresholds and keywords). It then builds `PhoneTargets`, where `handshakeSafeShutter(brightness:)` and `pickISO(forBrightness:)` each pick **shutter and ISO independently from `brightness01`**, and `faceEV` sets an EV bias.
- `Services/CameraSession.swift#applyPhoneTargets` calls `setCustom(duration:iso:)`, which wraps `setExposureModeCustom`, and then `setEV`.

## The basic problems to fix (Phase 1)

1. **Open-loop exposure.** The system auto-exposure has already normalized the probe JPEG toward mid-gray, so `brightness01` reflects scene tonality, not light level. A dim room and a sunny street can both read ~0.45 and receive the same 1/125 s at ISO 100, which leaves the indoor shot several stops underexposed. Shutter and ISO are never tied to the metered exposure.
2. **EV bias is a no-op in custom mode.** `exposureTargetBias` affects only the auto exposure modes. After `setExposureModeCustom`, the backlit-face `+0.7` from `faceEV` does nothing.
3. **Stale metering.** If a previous run left exposure locked in custom mode, the next run meters the locked values, not the scene.
4. **No real verification.** The Verify phase only warns about slow shutters and never checks the resulting exposure.

---

## Phase 1: Closed-loop exposure planner (highest priority)

Create `Services/ExposurePlanner.swift`, a pure, unit-testable module with no AVFoundation types in its core API.

**1a. Meter from a converged auto state.** At the start of `run`, before sensing:
- Switch the device to `.continuousAutoExposure` with `exposureTargetBias = 0`. Wait until `!device.isAdjustingExposure` and `abs(device.exposureTargetOffset) < 0.15` EV, with a timeout of about 600 ms. On timeout, proceed and record it in analytics as `ae_converge_timeout`.
- Snapshot `exposureSeconds` and `iso`. The **metered exposure product** is `E_auto = exposureSeconds × iso`. In the same snapshot, keep the existing `brightness01` and the other signals.

**1b. Plan within recipe intent.** Replace the independent brightness → shutter and brightness → ISO tables with:

```
targetEV   = recipeEVOffset + faceEVOffset (+ learned offset in Phase 4)   // in stops
E_target   = E_auto × 2^targetEV
priority   = recipe decides: .shutter(seconds) | .iso(value) | .auto
.shutter(t): shutter = clamp(t);   iso = clamp(E_target / shutter)
.iso(i):     iso = clamp(i);       shutter = clamp(E_target / iso)
.auto:       shutter = min(handheldLimit, motionLimit, max(E_target / minISO, minShutter))
             iso = clamp(E_target / shutter)   // longest safe shutter first, then gain
```

- `handheldLimit` is 1/(2 × 35mm-equivalent focal length), derived from `activeFormat.videoFieldOfView`. `motionLimit` comes from the gyro: `blurBudgetPx / (|ω| × focalLengthPx)`, where `focalLengthPx = (width/2) / tan(fov/2)` and `blurBudgetPx = 1.0`.
- When clamping makes `E_target` unreachable (for example the 20 s "trails" target versus the device's `maxExposureDuration`), report the residual EV in `clampMessages` (e.g. "Max shutter 1/3 s on this lens — 3 stops short; tripod + Night mode recommended").
- Map each recipe in `buildPhoneTargets` onto a priority. Shutter priority: blur-moving-subjects (keeping the night/day split), panning-sharp-subject (1/30 s). ISO priority with the lowest ISO: sharp-front-to-back, leading-lines, minimalist. Auto: portrait-pop, sharp-and-in-focus, get-down-low. HDR keeps system auto exposure plus brackets, but those brackets are now relative to `E_auto`.
- Convert today's string EVs (`faceEV`, minimalist −0.3) into `targetEV` stops inside the planner. Never rely on `exposureTargetBias` when writing custom exposure.

**1c. Verify and correct.** After `setExposureModeCustom(duration:iso:completionHandler:)`, wait for the completion handler's `syncTime` plus about 2 frames. Then read `device.exposureTargetOffset` (it remains valid in custom mode) and compute the error as `offset − targetEV`. If |error| > 0.3 EV, correct ISO by `2^(−error)` (falling back to shutter when ISO is clamped), with at most 2 iterations. Show the final residual in the existing verify UI and emit `auto_optimize_verify` with `{residual_ev, iterations, clamped}`.

**1d. Tests** (`PhotoRecipesTests/ExposurePlannerTests.swift`): the dim-indoor versus bright-outdoor case, where the same `brightness01` but different `E_auto` must give different ISOs; shutter-priority conservation (shutter×ISO = E_target within 1%); clamping residual reporting; face +0.7 EV producing a 2^0.7 exposure increase; and the motion limit shortening the shutter.

**Acceptance:** under the same scene, an AO capture's mean luma is within ±0.3 EV of system auto plus the recipe's intended offset, in a dim room (~50 lux), on an overcast exterior and on a backlit face. Record before/after captures and attach them to the PR.

---

## Phase 2: Fast on-device sensing (Metal + Vision)

Goal: replace the probe-JPEG round trip with live frames from the existing `AVCaptureVideoDataOutput` in `CameraSession` and cut sensing latency.

- Build `Services/GPUStatsEngine.swift`. Wrap each sampled `CVPixelBuffer` (BGRA or 420f) as a zero-copy `MTLTexture` via `CVMetalTextureCache`, downsample it to about 256×192 (`MPSImageBilinearScale`), and run a single compute kernel. The kernel produces a 64-bin luma histogram (threadgroup atomics with a merge, or `MPSImageHistogram`), clipped and crushed fractions, gray-world RGB means over unclipped pixels, a contrast value, and a **synthetic re-exposure gradient score** for 13 ratios in [¼, 4]. For each ratio it inverse-sRGBs, scales, clips, re-gammas, computes the Sobel magnitude and accumulates `log1p(100·g)` for g > 0.01, so the AE can see which direction recovers detail. Optionally weight pixels by the face or saliency mask. Triple-buffer the outputs. The target is under 2 ms GPU time per analysis on an A15.
- Document the caveat that preview frames are tone-mapped, so treat the stats as relative signals and keep the absolute exposure from `E_auto`.
- **Vision, with no training required:** add `VNClassifyImageRequest` for on-device scene labels (sunset, food, waterfall, night, etc.) to `LocalSceneSignals.sceneLabels` (top 5 with confidence). Keep the existing `VNDetectFaceRectanglesRequest` and saliency, but run them on a video frame. Run Vision at ≤5 Hz on a background queue and reuse the results between runs.
- Use the scene labels in `chooseRecipeId` alongside the note keywords (for example, `waterfall` or `fireworks` → blur-moving-subjects, `sunset` plus clipping → HDR, `food` → the warmPop look). The user's explicit note still wins.
- Keep the probe-JPEG path as a fallback when no recent video-frame stats exist.
- Parity test: the Metal stats against a CPU/vImage reference within 1e-3 on fixture images.

---

## Phase 3: Data collection for learning

The existing telemetry (`Analytics.track` → `POST /api/telemetry`, server in `server/`) becomes the training data. All of it must be privacy-preserving, with **no images uploaded** by default.

- At AO Ready, log a feature vector: the GPU stats (histogram bins quantized, clipping, contrast, gray-world, the gradient-score curve), the top 5 scene labels, face count, gyro magnitude, `E_auto`, device model and lens, plus the chosen recipe, the planner output and the verify residual.
- Log the outcomes: the user's dial changes after AO (`ManualDialsSheet`, with the deltas in EV, Kelvin and recipe), a recipe switch, capture versus abandon, the look being kept versus dismissed, and the before/after chip toggles. These are the labels.
- Add an opt-in "Help improve Auto Optimize" setting, off by default with clear copy. With it on, AO captures a 5-frame exposure bracket (`AVCapturePhotoBracketSettings` with `AVCaptureManualExposureBracketedStillImageSettings`, −2…+2 EV) and saves the downsampled frames, EXIF and stats locally. Upload happens only with explicit consent.
- Update `PrivacyInfo.xcprivacy` and the onboarding copy accordingly.

---

## Phase 4: Core ML models (Neural Engine)

Train offline in Python and convert with `coremltools` (`convert_to="mlprogram"`, `compute_precision=FLOAT16`, minimum target iOS 17, small inputs so the ops stay on the ANE). Load with `MLModelConfiguration().computeUnits = .all`, keep at most one inference in flight, and verify ANE residency in Xcode's Core ML performance report. Put the training scripts in `scripts/ml/`.

1. **`RecipeNet` (the main model):** input is the Phase 3 feature vector (scene-label confidences, histogram, stats, `log E_auto`, faces, motion); output is a recipe distribution. A gradient-boosted tree or a 2-layer MLP is enough. Labels are the recipe the user ultimately kept and captured with. Ship it behind a remote flag. Fall back to the rules when the max probability is below 0.5, and keep the explicit note intent as an override.
2. **`ExposureOffsetNet`:** predicts the residual `targetEV` offset the user would choose, learned from the post-AO EV and dial corrections, conditioned on the recipe. It feeds `targetEV` in the Phase 1 planner, clamped to ±1 EV.
3. **Optional, later:** `IlluminantNet`, a log-chroma (u = log G/R, v = log G/B) white-balance estimator applied through `setWhiteBalanceModeLocked(with:)` with gains clamped to `maxWhiteBalanceGain`. It replaces the coarse daylight/cloudy mapping from `warmBias`. Pretrain it on Gehler-Shi / Cube+ / NUS, then fine-tune with gray-card captures per device.

Training guidance:
- Self-supervised exposure labels from the opt-in brackets: pick the bracket that maximizes the gradient-information score without clipping more than 1% (the Shim / Tomasi approach), optionally task-weighted by face-detection confidence (the Onzon approach). Use these labels to pretrain `ExposureOffsetNet` before fine-tuning on the user corrections.
- **Don't** train exposure on DSLR RAW simulators alone, because the preview pipeline (tone-mapped, fixed aperture) won't match.
- Evaluate on a held-out device mix. Report recipe top-1 accuracy, mean |EV error| against user corrections, and the A/B lift in capture rate after AO and in the share of runs without manual dial changes.
- Parity test: Core ML output against PyTorch or sklearn within 1e-2 on fixtures.

---

## Constraints for every phase

- iPhone apertures are fixed, so the controllable parameters are shutter, ISO, white balance, focus and zoom. Keep the existing coach-only aperture copy.
- Don't block the capture queue. Use the existing `@MainActor` boundaries in `CameraSession`, and run the analysis on its own queue.
- Respect `ProcessInfo.thermalState`: at `.serious`, halve the analysis rate and skip Vision classification; at `.critical`, fall back to the rules plus system auto.
- Handle lens switches by re-reading the `DeviceCapabilities` limits. Handle session interruptions and an AO run cancelled mid-flight (the existing `runGeneration` pattern).
- AO end-to-end latency must not regress. The target is p50 under 600 ms, including AE convergence. Keep the existing analytics event contract and add only new properties.
- Keep the user-facing copy (`reason`, `teachWhy`, the diffs) truthful. If an EV or a shutter couldn't be reached, say so.
- Prefer Apple frameworks. Ask before adding third-party dependencies.

## Deliverables

For each phase: a focused PR with a short design note, the tests, before/after captures or benchmarks (Instruments: Metal System Trace, Core ML, Energy Log), and a list of any API behavior you assumed but couldn't verify on device. Start with Phase 1 and stop for review before Phase 2.
