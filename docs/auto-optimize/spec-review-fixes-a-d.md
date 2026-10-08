# Follow-up prompt: Auto Optimize Phases 1–3 review fixes

> Source: user prompt, sent 2026-10-08. Persisted verbatim at the user's request.

You are working in `yishengjiang99/photo-recipes`, iOS app at `ios/PhotoRecipes`. Phases 1–3 of the Auto Optimize upgrade are merged on `main` (as of `405d7ff`):
- **Phase 1:** `ExposurePlanner`, `SettingsSolver`, and `CameraSession.convergeAutoExposure` / `verifyExposure`.
- **Phase 2:** `GPUStatsEngine` + `GPUStats.metal`, plus Vision scene labels in `RecipeScorer`.
- **Phase 3:** `AOTelemetrySerializer`, `AOBracketCapture`, `AOBracketStore`, and the dial-override labels.

The architecture is right and most of the spec is met. This prompt fixes the defects a code review found, ordered by severity. Keep the existing analytics event names, add tests for every fix, and do one focused PR per section. Stop after section A for on-device validation.

---

## A. Phase 1 correctness (do first)

### A1. The verify loop reads stale meter values (high)
`CameraSession.settleLastExposureWrite()` waits on `lastExposureWriteDate`, which is only set inside the *completion handler* of the write. When `verifyExposure` starts, that property still holds the timestamp of an **earlier** write, often from a previous run, so `remaining <= 0`, there is no wait, and `exposureTargetOffset` is read before the new shutter/ISO has taken effect. The same thing happens after every `applyExposureCorrection`. The result is corrections computed from the old exposure, double corrections, and oscillation.

The fixed `0.07 s` "~2 frames" settle also assumes 30 fps. In dim scenes the frame duration is at least the shutter (1/8 s and longer), which is exactly where this feature matters most.

Fix:
- Replace the timestamp with an awaitable write. Make `setCustom`, `setISO` and `setShutter` return the completion's `syncTime` through a `CheckedContinuation`, and have `verifyExposure` await the write it just issued. Never read a timestamp left over from an earlier write.
- After the sync time arrives, wait `2 × max(activeVideoMaxFrameDuration, exposureDuration)`, bounded to ≤ 1.2 s, before reading `exposureTargetOffset`. Optionally require two consecutive readings within 0.1 EV of each other.
- Add a `ExposureWriteClock` test seam so the loop can be unit-tested with a fake device: it must issue one write per iteration, read only after the matching sync, and converge on a simulated 1/8 s scene without overshooting.

### A2. The 1/(2f) handheld limit is bypassed (high)
`ExposurePlanner.plan(.auto(shutterCapSeconds:))` uses `cap ?? derivedCap`. Every `.auto` recipe in `SettingsSolver` passes `min(tShake, tMotion)`, so the 1/(2f) rule never applies. When the gyro reading is near zero, or `handShake` is nil because `horizon.isAvailable` is false, `tShake = 1.5 / (1e-4 × focalPx)` is many seconds. In a dim room, handheld portrait and sharp-front-to-back can then plan shutters of 1/4 s to 1 s.

Fix:
- `safeCap = min(cap ?? .infinity, handheldLimit, motionLimit)`. The handheld limit is relaxed only when **tripod-steady** is detected: gyro < 0.005 rad/s sustained for ≥ 1.5 s (add `SceneFeatures.isTripodSteady`). In that case allow up to the device max and say "Tripod detected — long shutter".
- When `handShake` is unavailable, treat it as typical handheld (0.03 rad/s), not as zero.
- Replace `testAuto_recipeCap_overridesDerivedLimits` (it encodes the bug) with these tests: the cap can only shorten the shutter; nil gyro gives a shutter ≤ the 1/(2f) limit; tripod-steady allows a long shutter.

### A3. The metering point is stale and face EV can be double-counted (medium)
`convergeAutoExposure` resets the mode and bias but not `exposurePointOfInterest`, so `E_auto` is metered at whatever point the previous run or the user's last tap left. Then `applyPhoneTargets` moves the exposure point to the face **after** custom exposure is written. That means `E_auto` and the verify readback may be using different metering regions, and if the meter honors the face point, the +0.7 EV face bias is applied twice.

Fix:
- In `convergeAutoExposure`, set `exposurePointOfInterest` to frame center (or to a full-frame metering default) before converging. Keep the face only as the *focus* point, so `E_auto`, the planner and verify all use one metering region and `faceEVBias` stays the only face correction.
- Validate on device: a backlit face (lamp or window behind) should end with the face about +0.7 EV relative to stock auto, not +1.4. Log `exposureTargetOffset` before and after the POI change to confirm.

### A4. Missing metering silently falls back to a guess (medium)
`SettingsSolver.planExposure` uses `meteredExposureSeconds ?? 1/60` and `meteredISO ?? 100`, which brings back the original fixed-guess bug whenever metering is missing. Return `.systemAuto` instead, with the message "Couldn't read the light — left on auto", and emit `ao_metering_missing`.

### A5. Scene stats can predate convergence (medium)
`AutoOptimizeController.run` accepts a sensor snapshot up to 1 s old. That snapshot can come from frames exposed under the previous run's custom exposure, which skews the clipping, contrast and percentile spread that the solver uses for EV and HDR decisions. Require the snapshot's frame timestamp to be later than the convergence time. Otherwise call `refreshNow` (it is already budgeted).

### A6. Verify corrections must respect the recipe's priority (medium)
`applyExposureCorrection` falls back to changing the shutter when ISO clamps. For shutter-priority recipes (`blur-moving-subjects`, `panning-sharp-subject`), the shutter is the creative objective, so never change it. Clamp ISO and report the residual instead. For `.auto` recipes, never move the shutter past the motion-safe cap from A2. Pass the plan's priority and cap into `verifyExposure`.

### A7. Sign conventions (low)
`ExposurePlanner.Plan.residualEV` is positive when underexposed, while the verify residual (`offset − targetEV`) is positive when overexposed. The comment on `ExposureVerifyResult` also says "+ means under", which is wrong. Pick one convention (positive = brighter than target), use it in both places and in telemetry (`plan_residual_ev`, `verify_residual_ev`), and fix the comments. The UI copy currently matches the verify sign; keep its behavior.

**Section A acceptance (on device, before merging):**
- Dim room (~50 lux), handheld: the shutter is ≤ the 1/(2f) limit, the photo is within ±0.3 EV of stock Camera, and `verify_iterations` is ≤ 1 for a static scene.
- Overcast exterior: low ISO, within ±0.3 EV.
- Backlit face: face about +0.7 EV relative to stock auto.
- Run twice in a row after pointing somewhere new: the second run's `e_auto` changes.
- The "light trails" note: the shutter holds and the residual is reported, never a changed shutter.

Attach the readback logs for all five.

---

## B. Pass 2 cloud refine bypasses the planner (medium)

`schedulePass2CloudRefine` calls `session.applyPhoneTargets(targets)` with the server's absolute shutter/ISO. That skips the `ExposurePlanner` and verify, so when the user enables cloud refine it can undo a correct closed-loop exposure.

Also, `allowCloudRefine = isFirstSuccessPending || Self.cloudRefineEnabled` is inverted relative to its intent and to the "first_win_local" skip reason. It's only harmless because `schedulePass2CloudRefine` re-checks `cloudRefineEnabled`, which leaves the telemetry misleading.

Fix:
- Pass 2 may change the recipe's *intent* (EV offset ±1, WB, focus, look intensity) but never absolute shutter/ISO. Convert server exposure into a `targetEV` delta, re-run `ExposurePlanner` from the same `E_auto`, apply the result, then `verifyExposure` again.
- Make the gate `!isFirstSuccessPending && cloudRefineEnabled && trigger != "auto_first_capture"`, so the skip reasons match reality.

---

## C. Phase 2 tuning (low–medium)

1. **Thermal `.fair` skips motion entirely** (`SceneSensor.tick`). Subject and background speed drive the shutter choice in `blur-moving-subjects` and `panning-sharp-subject`, so at `.fair` those recipes fall back to "No subject motion measured" or the 1/30 default. Per the spec, keep motion at full rate at `.fair`, halve it at `.serious`, and stop it at `.critical`.
2. **GPU engine allocation and blocking:** `GPUStatsEngine.analyze` allocates new `MTLBuffer`s per call and blocks on a semaphore inside `visionQueue.sync`, called from the `SceneSensor` actor. That's acceptable at 1 Hz, but pre-allocate a ring of 3 buffer pairs and use `addCompletedHandler` with async continuation instead of `DispatchSemaphore.wait`, so the actor's executor is never blocked. Record GPU time with `MTLCommandBuffer.gpuStartTime`/`gpuEndTime` in `AOPerf` and confirm it's under 2 ms on an A15.
3. **Gradient scores are only logged.** That's fine for now (they're Phase 4 inputs). Add a debug overlay in the dev settings that shows the 13-ratio curve and its argmax, so their sanity can be checked on real scenes before training depends on them.

---

## D. Phase 3 label quality (medium)

1. **The dial-override label is recorded on first touch.** `markDirty` fires `optimize_dial_override` once per run, on the first change, so a slider drag logs a tiny partial delta. Record the label at the user's **capture** (or after 3 s of dial inactivity, whichever comes first), comparing the final state to `appliedDialsAtReady`. Add `exposure_delta_stops = log2((t·ISO)_final / (t·ISO)_ready) + evDelta(if auto)` as the single training target for `ExposureOffsetNet`. Keep the per-dial deltas.
2. **The bracket timer collides with the user's shot.** `AOBracketCapture` fires 2 s after Ready, which is about when people press the shutter. The user's capture can then be rejected by the overlapping-capture guard, and they get five unexpected shutter sounds. Instead, trigger the bracket **right after the user's own capture completes** (the user is already holding still on that scene), and skip it if a user capture is in flight or the run changed. Show a small "Saving improvement data…" chip while it runs.
3. **The bracket varies shutter only, at constant ISO.** In dim scenes the +1/+2 EV frames get 2–4× longer shutters and pick up motion blur, which biases "best frame" labels toward darker frames. For positive offsets beyond the motion-safe cap, raise ISO instead. Record the actual per-frame shutter and ISO (already read from EXIF) and flag `blur_risk` per frame.
4. **The bracket manifest is missing its training anchors.** Add `e_auto`, `plan_target_ev`, the applied shutter/ISO at Ready, `verify_residual_ev`, `device_model`, `lens`, and `schema_version` to `meta.json`, so a bracket set can be labeled without joining telemetry.
5. **Privacy:** confirm that the downsampled JPEGs strip GPS and other non-exposure EXIF before anything reaches the upload manifest, and add a test.

---

## Deliverables
- One PR each for A (split A1/A2 if large), B, C and D, with tests, a short design note, and on-device readback logs for section A.
- List any AVFoundation behavior you assumed but could not verify. In particular: whether `exposureTargetOffset` in `.custom` mode honors `exposurePointOfInterest`, and the latency between the completion handler's sync and the offset updating.
- Don't start Phase 4 until section A passes on device.
