# Activation, Capture-Ready, Paywall Value, Purchase Telemetry v2, and AO Latency

Spec: [`docs/prompts/activation-capture-monetization-performance-2026-10-27.md`](prompts/activation-capture-monetization-performance-2026-10-27.md)
(verbatim task prompt, included unchanged). Telemetry schema version: **v2**
(additive — all legacy event names and props are unchanged; new events/props
are additions only). Server: `server/telemetry.ts` accepts all event names
("All events accepted", line 3) and stores props generically, so **no server
change was required** for the new events; its sanitizer drops prop *keys*
matching `^(email|phone|password|token|image|photo|…)$`, which is why no new
prop key contains the substring `photo` (verified by
`FirstPhotoExperimentTests.testNoFilteredPropKeys`).

## Rebase reconciliation onto main `dfdaeaa` (2026-10-27)

This branch was originally based on `bf28e01`. The 105-commit gap to
`dfdaeaa` was **pre-existing history** (PRs #160–#166 and other work dated
2026-10-09→10-28) that the local clones' stale `origin/main` ref had hidden —
nobody pushed to main during this work. The single commit was rebased onto
`dfdaeaa` and conflicts in CameraView / PaywallView /
AutoOptimizeController / StoreKitManager were resolved keeping **both**
sides (SettingsSolver auto-merged). What main had landed in the meantime,
and how it interacts with this PR:

- **iOS `auto_optimize_start` now exists.** Main added exactly one paired
  start event per run (`AutoOptimizeController.startProps`, emitted after the
  running/quota guards). The §1 finding below ("iOS never emits
  `auto_optimize_start`") describes the **supplied baseline period** and the
  old base; it is no longer true at `dfdaeaa`, so a paired iOS success rate
  becomes computable for runs from this main onward.
- **Main added its own `PurchaseTelemetry`** (a props builder) and made
  `StoreKitManager.purchase()` itself emit `purchase_cancelled` /
  `purchase_pending` / `purchase_failed`. That overlaps the v2 emitter's
  event names, so the rebase **dropped the PR's PaywallView-side v2 calls**
  for cancelled/pending/failed (and made restore emit exactly one
  `purchase_restore` — v2's result-bearing form when the flag is on, the
  legacy form otherwise). PurchaseTelemetryV2's methods remain as the
  canonical contract API and are unit-tested directly; its live
  `purchase_success` path (verified + entitlement-activated, deduped) is
  unchanged and has no counterpart in main.
- Nothing from the PR was made redundant in full; no PR file was dropped.

## 1. Architecture / telemetry audit (pre-implementation findings)

### Why `auto_optimize_success` (676) > `auto_optimize_start` (417)

This is an instrumentation asymmetry, not a funnel paradox:

- **iOS never emits `auto_optimize_start`.** A repo-wide search finds zero
  `track("auto_optimize_start")` call sites in `ios/` (verified: 0 matches).
- iOS emits `auto_optimize_success` from **two** sites in
  `AutoOptimizeController.run(...)` — the coach-only path
  (`AutoOptimizeController.swift:773`) and the full apply+verify path
  (`AutoOptimizeController.swift:889`) — with no paired start event.
- The only `auto_optimize_start` emitter is the **web** app
  (`src/components/FieldCoach.tsx:354`), and the name appears in the server
  funnel definition (`server/telemetry.ts:119`, `FUNNEL_WEB_ACTIVATION`).

So the supplied baseline mixes web starts with iOS+web successes. **Do not
compute an optimize success rate from these two counters.** A trustworthy
rate needs a paired iOS start event (the new `optimize_latency_summary` /
stage events now provide per-run denominators for iOS: one summary per run
that reaches a terminal outcome, keyed by `run_id`).

### Baseline event emission points (verified in code)

| Event | Emission point |
|---|---|
| `auto_optimize_success` | `AutoOptimizeController.swift:773` (coach-only), `:889` (full) — quota consumed only on success via `FreeOptimizeQuota.recordSuccess` |
| `ae_converge_timeout` | `AutoOptimizeController.swift:635`, when `CameraSession.convergeAutoExposure` reports `timedOut` |
| `ao_metering_missing` | `SettingsSolver.swift:208`, metered exposure/ISO nil → `.systemAuto` fallback |
| `optimize_capture_abandoned` | `AutoOptimizeController.scheduleCaptureWindowCheck` — 30 s after Ready if `takeRecentRunIdForCapture` never consumed the run; cancelled by a newer run / `clear()` / undo |
| `optimize_photo_captured` | `CameraView.playCaptureFeedback`, when a run id is consumed within the same 30 s window |
| Control first-run flow | `CameraView.maybeAutoRunFirstOptimize` (`CameraView.swift:1556`), called **after** capture + save (`:1909`), gated by `FirstWinAutoRun.isEligible` + `markAttempted()` — i.e. control = post-capture only |
| `paywall_view` | `PaywallView.onAppear` with `EntitlementsStore.paywallViewProps` |
| `purchase_success` (legacy) | `PaywallView` plan button, on `StoreKitManager.purchase` returning `true` |

`optimize_capture_abandoned` eligibility (confirmed): exactly the runs that
reached Ready and armed the 30 s window; a capture still in flight at window
close is not distinguished today (the window is wall-clock from Ready), which
is a known limitation carried into §5.

### Purchase audit findings

`StoreKitManager.purchase()` (`StoreKitManager.swift:98`) **does** verify:
`checkVerified` (`:250`) throws on `.unverified`, then `syncEntitlement`
(`:219`) verifies with the server and only calls
`EntitlementsStore.applyVerifiedPro` when the server payload says `pro`, or —
on server error — when the StoreKit transaction is live (not revoked/expired).

Gaps found (all addressed or explicitly documented):

1. **Verified-but-not-entitled counted as success.** If the server verify
   round returns `pro == false`, `applyVerifiedPro` is never called, yet
   `purchase()` still returned `true` and the paywall emitted
   `purchase_success`. → `StoreKitManager` now records
   `lastPurchaseOutcome = .verified(transactionId, entitlementActivated:)`;
   with telemetry v2 on, `purchase_success` fires only when
   `entitlementActivated == true`.
2. **Cancel and pending were indistinguishable** (at the old base). At
   `dfdaeaa` main's own `PurchaseTelemetry` pass made `StoreKitManager`
   emit `purchase_cancelled` / `purchase_pending` itself; the PR's outcome
   enum still distinguishes `.cancelled` / `.pending` for callers, and the
   paywall no longer emits `purchase_fail` for a pending (Ask-to-Buy is not
   a failure). See the rebase reconciliation above for the de-duplication.
3. **Unverified was indistinguishable from a generic error** (at the old
   base). → `.unverified` outcome; `StoreKitManager` emits `purchase_failed`
   (`stage: verification`) and the paywall keeps the legacy `purchase_fail`.
4. **Renewals have no telemetry** (only a Meta event in
   `listenForTransactions`). Unchanged in this PR — see reconciliation (§4);
   renewals must be counted from App Store Connect / server verify records,
   not client telemetry.
5. Pre-existing: the paywall's plan cards hardcode "7-day free trial" copy
   and include hardcoded placeholder prices when products fail to load. The
   new value-proof section makes **no** trial or price claims; fixing the
   legacy cards' copy to be StoreKit-driven is follow-up work, flagged here
   rather than silently rewritten in this PR.

## 2. What was built

### New files

| File | Contents |
|---|---|
| `ios/PhotoRecipes/Services/FeatureFlags.swift` | `AnalyticsEventSink` protocol (+ `Analytics` conformance) and UserDefaults-backed `FeatureFlags` |
| `ios/PhotoRecipes/Services/ExperimentAssignment.swift` | FNV-1a bucketing, 50/50 arms, persisted independent assignments for `first_photo_v1` / `paywall_v1` |
| `ios/PhotoRecipes/Services/FirstPhotoExperiment.swift` | Eligibility/gate state machine, first-app-open tracking, at-most-once activation |
| `ios/PhotoRecipes/Services/CaptureReadiness.swift` | Derived `CaptureReadiness` + `OptimizeAttribution` classification (30 s window, reusing the legacy window constant) |
| `ios/PhotoRecipes/Services/OptimizeStageTimer.swift` | Monotonic stage timer, AE diagnostic props, metering-missing reason classifier |
| `ios/PhotoRecipes/Services/PurchaseTelemetryV2.swift` | Canonical purchase lifecycle emitter (transaction-id dedupe) + `PaywallValueProof` |
| `ios/PhotoRecipes/Features/Camera/CaptureReadyBanner.swift` | `CaptureReadyBanner` ("Settings applied — ready for your photo.") + `FirstPhotoGuidanceCard` |
| Tests | `ExperimentTestSupport`, `ExperimentAssignmentTests`, `FirstPhotoExperimentTests`, `CaptureReadinessTests`, `PurchaseTelemetryV2Tests`, `OptimizeStageTimerTests` |

### Minimal edits to existing files

- `AutoOptimizeController.swift`: stage-timer wiring at existing stage
  anchors (converge → features → apply → verify → both success sites +
  cancel); `ae_converge_timeout` gains diagnostic props (lens,
  phase_at_timeout, was_capture_in_flight, exposure_locked;
  **was_lens_switching is reported as `"unknown"`** — no reliable signal
  exists at that site and fabricating one would poison the diagnostic).
- `SettingsSolver.swift`: `ao_metering_missing` gains a `reason` prop
  (`missingInput` when both metered values are absent,
  `metadataUnavailable` when exactly one is).
- `StoreKitManager.swift`: additive `PurchaseOutcome` surface (Bool API and
  all verification/entitlement behavior unchanged).
- `PaywallView.swift`: experiment-aware `paywall_view`; value-proof section
  for the treatment arm; purchase flow routed through the outcome enum + v2
  emitter; restore emits the v2 result event. Restore/legal untouched.
- `CameraView.swift`: treatment guidance offered once from the launch task;
  capture-ready banner + `capture_ready_view` (once per run);
  `capture_ready_shutter_tap`; at-most-once activation + `PaywallValueProof`
  recording on a genuinely optimized save; `capture_after_optimize` next to
  the legacy `optimize_photo_captured`. Control path
  (`maybeAutoRunFirstOptimize`) is byte-for-byte unchanged.

Preserved untouched: `CameraReset` / `CameraLifecyclePolicy` /
`SelfieAutoPolicy` and the PR #165/#166 front-camera AO + reset behavior;
legacy event names; quota policy (success-only consumption).

## 3. Experiments

### Flags (UserDefaults keys `featureFlags.*`)

| Flag | Default | Notes |
|---|---|---|
| `first_photo_preoptimize_enabled` | true | arm decides behavior |
| `capture_ready_ui_enabled` | true | banner + capture-ready events |
| `paywall_value_experiment_enabled` | true | |
| `purchase_telemetry_v2_enabled` | **false** | changes legacy `purchase_success` gating — opt-in rollout |
| `optimize_stage_timing_enabled` | true | telemetry-only |
| `optimize_safe_timeout_enabled` | false | bounded-wait selection only; **the AE timeout is deliberately NOT shortened** — convergence correctness (metering from a converged auto state) is worth more than the tail latency, and no device data yet justifies changing it |
| `firstPhotoExperimentKilled` / `paywallExperimentKilled` | false | emergency kill; never resets assignment |

### First-photo experiment

- Assignment: `bucket = FNV-1a64("first_photo_v1:<anonId>") % 100`;
  buckets < 50 → treatment. Persisted on first computation; stable across
  launches, upgrades, and flag flips. Install id is the existing anonymous
  telemetry id — no PII.
- Control `post_capture_v1`: current behavior, untouched.
- Treatment `pre_capture_guided_v1`: after the camera session is running
  (launch task), if eligible and all gates are safe (session running, not
  backgrounded, not lens-transitioning, not capturing, optimizer idle), a
  dismissible guidance card is shown. "Optimize this shot" runs the existing
  pipeline with trigger `pre_capture_guided` — which never surfaces the hard
  paywall (`runOptimize` only gates manual/voice/deep_link triggers) and
  never blocks the shutter. Skip/decline is terminal. A guided run marks the
  legacy first-win as attempted so the post-capture auto-run cannot
  double-fire. Quota is untouched on skip/fail (success-only consumption is
  the controller's existing contract).
- Eligibility: never completed/declined/skipped, never activated, no prior
  activation (either first-capture or first-optimize key set), and no undo
  opt-out (`autoOptimize.userUndid`).
- Note: `first_photo_preoptimize_start` is emitted immediately after the
  guided run resolves so it can carry the real `run_id` (the controller
  generates it internally); the start/complete pair is adjacent in the
  stream. Server-side timestamps therefore reflect completion time for both.

### Paywall experiment

- Independent assignment (`paywall_v1` salt), same bucketing. Both
  assignments are logged (`first_photo_experiment_assigned`,
  `paywall_experiment_assigned`) so interaction effects can be controlled
  for.
- Treatment `paywall_value_v1`: when a genuine `PaywallValueProof` exists
  (recipe title + applied-settings summary recorded at the moment of a real
  optimized save), a proof section shows it above the plan cards. No
  before/after is fabricated — no baseline image was ever persisted. Prices
  remain the existing StoreKit `displayPrice` rendering; the proof section
  makes no trial claim. No proof → control UI, unchanged.

### Capture-ready

Readiness is derived (`CaptureReadinessDerivation.derive`) from session +
optimizer inputs; there are no new mutable booleans. The shutter stays
enabled in `.optimizing` and `.optimizedCaptureReady`. Attribution
(`OptimizeAttribution`, unit-tested; CameraView wires the subset of signals
available at its layer) classifies captures as `afterComplete` / `during` /
`afterUndo` / `afterFailure` / `afterManualOverride` /
`afterLensFlipOrReset` / `none`; only `afterComplete` counts as an optimized
capture.

## 4. Telemetry contract (new/changed events)

Common context: existing `Analytics` base props (`app_version`, `build`,
`hours_since_install`, `is_new_user`) ride on every event; `anon_id` /
`session_id` are envelope fields of `POST /api/telemetry`.

| Event | Key props | Semantics |
|---|---|---|
| `first_photo_experiment_assigned` | arm, bucket, exp_version | once per install, at first assignment |
| `first_photo_guidance_view` | arm | once, pending → shown edge |
| `first_photo_guidance_skip` | arm, reason (`skipped`/`declined`) | terminal |
| `first_photo_preoptimize_start` | arm, run_id | guided run (see ordering note §3) |
| `first_photo_preoptimize_complete` | arm, run_id, outcome | guided run result |
| `first_photo_activation_complete` | arm, elapsed_sec, within_window | **at most once per install**; first saved capture genuinely optimized at shutter time; `within_window` = within 5 min of first app open |
| `capture_ready_view` | run_id | once per run, when the banner state is reached |
| `capture_ready_shutter_tap` | run_id | shutter tapped while capture-ready |
| `capture_after_optimize` | run_id, classification, seconds_after_ready | next to legacy `optimize_photo_captured` |
| `paywall_experiment_assigned` | arm, bucket, exp_version | once per install |
| `paywall_view` (changed) | + experiment_arm, paywall_id when the experiment is active | legacy props unchanged |
| `paywall_value_proof_shown` | arm | once per paywall presentation with proof |
| `paywall_plan_select` (changed) | + product_id, paywall_id | legacy props kept |
| `purchase_start` (changed) | + product_id, paywall_id, purchase_attempt_id | legacy props kept |
| `purchase_cancelled` | purchase_attempt_id, cancellation_source | v2 only |
| `purchase_pending` | purchase_attempt_id, product_id | v2 only; NOT a failure |
| `purchase_failed` | purchase_attempt_id, error_category | v2 only |
| `purchase_verified` | purchase_attempt_id, transaction_id, product_id, environment | v2 only |
| `entitlement_activated` | entitlement_type, activation_source, transaction_id, product_id | v2 only |
| `purchase_success` (v2) | purchase_attempt_id, transaction_id, product_id, entitlement_type, telemetry_v=2 | v2 only; **only** after verified + activated; deduped per transaction id |
| `purchase_restore` (v2) | result, verified_entitlement_count, telemetry_v=2 | legacy restore event also still fires |
| `optimize_stage_complete` | run_id, trigger, lens, stage, duration_ms | per stage, monotonic clock |
| `optimize_latency_summary` | run_id, trigger, lens, outcome, total_ms, stage_*_ms | once per run reaching a terminal outcome |
| `optimize_fallback` | run_id, trigger, lens, reason | e.g. `ae_converge_timeout` |
| `ae_converge_timeout` (changed) | + lens, phase_at_timeout, was_lens_switching, was_capture_in_flight, exposure_locked | unknown values reported as `"unknown"` |
| `ao_metering_missing` (changed) | + reason | see classifier in §2 |

Stage-timing wiring populates requested / aeConvergence / inference / apply /
verify segments from the controller's existing section anchors;
cameraReadyWait and meteringPrep are not separately anchored in the
controller today (they are inside the convergence segment) — the timer type
supports them, and splitting them out needs a device-verified refactor of
`run(...)`, deliberately not done blind here.

### Reconciliation procedure (analytics vs StoreKit vs ASC)

1. **Starts**: count `purchase_start` (client) per day — expect drop-off vs
   `paywall_plan_select`; a start with no terminal event within the session
   is an instrumentation gap candidate, not a failed sale.
2. **Verified**: with v2 on, `purchase_verified` count should equal the
   number of distinct `transaction_id`s in `purchase_success` (telemetry_v=2)
   — dedupe guarantees 1:1; any mismatch is a bug, file it.
3. **Entitlement**: `entitlement_activated` (activation_source=purchase)
   should equal v2 `purchase_success`. Verified-but-not-activated cases now
   surface as `.verified(..., entitlementActivated: false)` in code and as a
   missing `entitlement_activated` in telemetry — count them; they are real
   revenue-at-risk, not noise.
4. **Ledger of record**: App Store Connect sales + the server's
   `/api/iap/verify` records are truth for money. Client telemetry
   undercounts by design (offline, killed app, v2 flag off). Compare weekly
   aggregates; investigate only divergences > a few percent.
5. **Renewals/restores**: never from client `purchase_success`. Restores
   appear as `purchase_restore`; renewals only in ASC/server records
   (client gap #4 in §1).

## 5. Performance notes

- Proposed targets (p50 < 1 s, p95 < 5 s, < 2 % of runs > 10 s) are rollout
  hypotheses to be measured with `optimize_latency_summary` — **no device
  measurements exist yet**, and none are claimed here.
- No AE timeout change: the 600 ms convergence wait anchors metering to a
  converged auto state; shortening it trades exposure correctness for tail
  latency. The diagnostics added here (lens / capture-in-flight /
  exposure-lock splits) are the evidence needed before any change.
- Known bottleneck candidates the new data can confirm or refute: front
  camera convergence in low light, convergence racing a capture, stale
  custom-exposure locks (the convergence step clears them by design).

## 6. Device validation matrix

**No physical device was available for this work (Linux VM, no Xcode).**
Every item below is **NOT RUN** unless marked automated.

| Check | Status |
|---|---|
| Front + rear camera guided flow | NOT RUN (device) |
| First install vs returning install | NOT RUN (device); eligibility logic unit-tested |
| Bright / low light AE convergence | NOT RUN (device) |
| Portrait / landscape | NOT RUN (device) |
| Rapid lens flipping during optimize | NOT RUN (device); invalidation logic unit-tested |
| Rapid background/foreground | NOT RUN (device); background gate unit-tested via gate inputs |
| Permission denied → later granted | NOT RUN (device) |
| Capture while optimization pending | NOT RUN (device); readiness derivation unit-tested (shutter stays enabled) |
| Reset during optimization | NOT RUN (device); generation-guard behavior preserved, untouched |
| Repeated captures | NOT RUN (device) |
| Offline operation | NOT RUN (device); analytics remains soft-fail by construction |
| StoreKit sandbox purchase / restore | NOT RUN (device) |
| Accessibility / VoiceOver / reduced motion | NOT RUN (device); banner + card carry accessibility labels/traits in code |
| Assignment stability, 50/50 split, kill-switch persistence | Automated (unit tests) |
| Capture classification (undo/flip/reset/window/override) | Automated (unit tests) |
| Purchase v2 ordering + dedupe + flag-off silence | Automated (unit tests) |
| Stage timer monotonicity / summary / fallback | Automated (unit tests, fake clock) |

Automated tests run in CI (`ios-unit-tests.yml`, macOS + XcodeGen). They
could not be executed locally — this VM has no Swift toolchain — so their
first real run is CI's; treat a red CI as the expected first feedback loop.

## 7. Rollout / rollback

1. Land with defaults as above (v2 telemetry OFF, timing ON).
2. Enable `purchase_telemetry_v2_enabled` for internal installs first;
   verify the §4 reconciliation checks for a few days before widening.
3. Watch guardrails: `optimize_capture_abandoned` rate, `ae_converge_timeout`
   rate by lens, capture_success rate, crash-free sessions. The experiments
   must not move capture_success or failed-capture rates adversely.
4. Rollback = flip the relevant kill switch / flag (no release needed for
   behavior gated on UserDefaults in internal builds; store builds need a
   config change or a new build — assignments persist either way, so
   re-enabling resumes cleanly). Full revert of this PR restores the exact
   pre-change behavior: every edit is additive or behind a flag, and the
   control paths were not modified.
