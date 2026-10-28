# Codex Implementation Task: Photo-Recipes Activation, Capture, Monetization, and Performance Improvements

> Saved verbatim from the user's task prompt, 2026-10-27. This file is the
> specification for the `feat/activation-capture-monetization` branch / PR.
> Implementation notes, audit findings, and deviations belong in
> `docs/activation-experiments.md` and the PR description — not in this file.

Repository

https://github.com/yishengjiang99/photo-recipes

Role

You are a senior iOS engineer, camera systems engineer, product growth engineer, and analytics architect working directly in this repository.

Your assignment is to implement five coordinated product improvements, with production-quality Swift code, feature flags, reliable telemetry, automated tests, and release safeguards.

Do not stop after producing a plan. Inspect the repository, implement the work, run available tests, and create a pull request.

Do not assume paths or APIs beyond what you verify in the current codebase.

1. Product context and baseline

Photo-Recipes is an AI-assisted camera application with live camera controls, Auto Optimize, photographic recipes, creative looks, capture and saving, onboarding, and subscription monetization.

The application already has important camera lifecycle and safety behavior, including recent work on front-camera Auto Optimize and camera reset.

Preserve these behaviors.

Supplied analytics baseline

These are aggregate event counts, not distinct users or a verified sequential funnel.

Event	Count
session_start	1,237
app_open	1,236
camera_open	767
auto_optimize_success	676
shutter_tap	597
capture_success	568
auto_optimize_start	417
ao_tap	324
optimize_photo_captured	108
optimize_capture_abandoned	85
paywall_view	289
paywall_plan_select	37
purchase_start	34
purchase_success	6
purchase_cancelled	4
ae_converge_timeout	142
ao_metering_missing	110
auto_optimize_fail	50
cloud_refine_fail	28
post_save_card_view	69
post_save_card_action	62

Important: auto_optimize_success exceeds auto_optimize_start. Investigate whether event semantics, auto/manual paths, or telemetry inconsistencies explain this. Do not calculate success rates by naively dividing these counters.

The two optimize_capture_* events represent 108 captured and 85 abandoned outcomes, but their precise eligibility and time-window definitions must be confirmed in code.

Primary business goal

Increase the proportion of new users who save a genuinely optimized photo within five minutes of their first app open.

Secondary goals:

* Increase capture after optimization.
* Improve subscription purchase conversion.
* Establish trustworthy purchase telemetry.
* Reduce Auto Optimize latency and camera reliability issues.
* Preserve safe camera behavior and user control.

2. Required repository reconnaissance

Before changing code:

1. Read the current architecture, README, project instructions, test conventions, and recent camera-related pull requests.
2. Identify the current SwiftUI camera view, camera session, optimizer state machine, exposure and metering implementation, capture pipeline, onboarding, paywall, entitlements, purchase handling, analytics, and existing feature flags.
3. Inspect the actual event emission points for every baseline event listed above.
4. Examine the current first-capture behavior, including maybeAutoRunFirstOptimize, FirstWinAutoRun, and the ordering of optimization, capture, and photo saving if these components still exist.
5. Inspect recent front-camera Auto Optimize and reset work, including PRs #165 and #166 if accessible.
6. Identify all existing tests that protect camera lifecycle, orientation, lens changes, cancellation, and in-flight optimization.

Produce a concise architecture and telemetry audit in the PR description.

Reuse existing abstractions wherever possible. Avoid introducing a second analytics system, duplicate entitlement state, or parallel optimizer orchestration.

3. Workstream A — First-photo optimization experiment

Objective

Compare the current post-first-capture optimization behavior against a guided pre-capture optimization experience.

Experiment arms

Control: post_capture_v1

Preserve the current first-capture behavior as faithfully as possible.

Treatment: pre_capture_guided_v1

For an eligible first-time user:

1. Open the camera normally.
2. Wait until the camera session is ready and safe to optimize.
3. Present a concise, dismissible explanation of Auto Optimize.
4. Initiate optimization before the first photo, using the existing optimization pipeline.
5. Display progress without blocking the shutter.
6. Once optimization completes, show a subtle success indication.
7. Make the shutter the obvious next action.
8. Allow the user to capture immediately, skip optimization, or cancel.

Do not force optimization before every photograph.

Do not automatically rerun optimization on every camera appearance.

Do not charge quota for a skipped or failed optimization. Preserve the existing successful-run quota policy unless the code establishes a different contract.

Safety requirements

* Never initiate optimization when the camera session is stopped, backgrounded, or transitioning lenses.
* Prevent stale results from applying to a different lens, camera generation, or capture session.
* Respect cancellation and existing reset behavior.
* Do not race with shutter capture.
* Avoid automatic hard paywalls during guided optimization.
* Preserve explicit user exposure overrides.
* Prevent repeated first-run experiments after the user has completed or declined the experience.
* Handle permission denial, interruption, low-memory conditions, and session-start failure.
* Respect the current first-win opt-out/undo semantics.

Experiment assignment

Implement deterministic, persistent, installation-scoped assignment using a stable random installation identifier and a versioned experiment salt.

Do not use personally identifying information.

Default allocation:

* 50% control
* 50% treatment

Provide a remote configuration integration if the existing architecture supports one; otherwise use local configuration with an emergency kill switch.

An assignment must remain stable across app launches and upgrades unless intentionally versioned.

4. Workstream B — Capture-ready flow

Objective

Make capture the primary action after successful optimization.

UI behavior

When optimization completes:

* Show a compact confirmation such as “Ready for your photo.”
* Keep the shutter prominent and enabled when the camera is ready.
* Visually de-emphasize secondary recipe actions.
* Avoid modal interruptions.
* Retain the user’s ability to adjust settings.
* Preserve accessibility and VoiceOver support.
* Support front and rear cameras.
* Do not block capturing while secondary AI work is pending.

Do not claim an optimization improved image quality unless that claim is supported. “Settings applied” is preferable to “Photo improved” when the result is not independently verified.

State model

Model capture readiness explicitly, preferably as a derived state from the existing camera and optimizer state machines.

Avoid adding independently mutable booleans that can become inconsistent.

Suggested conceptual states:

* camera unavailable
* camera starting
* camera ready
* optimization running
* optimized and capture ready
* capture in progress
* capture saved
* recoverable error

Preserve existing user-facing error handling.

Outcome attribution

Associate optimization and capture through a stable optimize_run_id.

Track capture after optimization using an explicitly defined attribution window.

Distinguish:

* capture after a completed optimization
* capture during an optimization
* capture after an optimization was undone
* capture after an optimization failed
* capture after manual overrides
* capture after a lens flip or camera reset

An optimization must not be counted as producing an optimized capture when its settings were reverted, invalidated, or replaced before shutter time.

5. Workstream C — Paywall experiment

Objective

Improve subscription conversion by communicating demonstrated product value.

Experiment arms

Control: paywall_current_v1

Preserve the existing paywall experience.

Treatment: paywall_value_v1

Present a clearer value proposition based on actual product usage.

When available, display:

* The user’s real saved optimized photo.
* The recipe or look used.
* A concise summary of settings that were actually applied.
* The benefit of additional or unlimited optimization, subject to actual entitlement rules.

Do not fabricate before/after comparisons.

If a genuine original and transformed image pair exists, a comparison can be shown. Otherwise display the real saved result without pretending to have a baseline image.

Pricing and subscription integrity

Use actual StoreKit product metadata for price, currency, period, and introductory offers.

Do not hardcode prices.

Clearly disclose trial length, renewal terms, and subscription conditions.

Do not imply a free trial is available when StoreKit reports that the user is ineligible.

Retain Restore Purchases, legal links, and cancellation information.

Paywall triggers

Segment paywalls by source, including:

* free quota exhausted
* upgrade button
* onboarding
* post-capture
* feature gate

Do not introduce an intrusive paywall during shutter capture, an active optimization, or an unresolved camera error.

Maintain the existing entitlement and quota enforcement system.

Experiment independence

Assign the paywall experiment independently from the first-photo experiment.

Log both experiment assignments so downstream analysis can control for interactions.

Prevent a first-session treatment from accidentally causing a different number of paywall opportunities without recording those exposures.

6. Workstream D — Purchase telemetry audit

Objective

Make monetization analytics reconcile with verified StoreKit and, where applicable, web checkout transactions.

Audit

Trace the complete purchase lifecycle:

1. Paywall presented.
2. Product metadata loaded.
3. Plan selected.
4. Purchase initiated.
5. StoreKit result received.
6. Transaction verification completed.
7. Entitlement activated.
8. Purchase or subscription outcome recorded.

Inspect restore flows, interrupted purchases, pending Ask to Buy transactions, app relaunches, refunds, revocations, and subscription renewals.

If the repository contains Stripe checkout, audit that path separately. Do not assume Stripe is present.

Event contracts

Keep existing event names for compatibility unless there is a documented reason to migrate them.

Define and implement a canonical event contract:

Event	Required properties
paywall_view	paywall_id, trigger, experiment_arm
paywall_plan_select	paywall_id, product_id
purchase_start	purchase_attempt_id, product_id, paywall_id
purchase_cancelled	purchase_attempt_id, cancellation_source
purchase_pending	purchase_attempt_id, product_id
purchase_failed	purchase_attempt_id, error_category
purchase_verified	transaction_id, product_id, environment
purchase_success	transaction_id, product_id, entitlement_type
purchase_restore	result, verified_entitlement_count
entitlement_activated	entitlement_type, activation_source

Only emit purchase_success after verified purchase and successful entitlement activation.

Separate initial purchases from renewals and restores.

Deduplicate verified transactions using a durable transaction identifier, while protecting user privacy.

Never log receipts, authentication credentials, payment details, or raw StoreKit verification payloads.

Reconciliation

Provide a documented process to compare:

* analytics purchase starts
* StoreKit outcomes
* verified transactions
* entitlement activations
* App Store Connect sales data

Where possible, add an automated reconciliation report or test fixture.

Explicitly distinguish instrumentation gaps from actual purchase failures.

7. Workstream E — Auto Optimize latency and reliability

Objective

Reduce long-tail optimization latency while preserving photographic correctness.

Instrumentation

Add structured timing for:

* optimization requested
* camera readiness wait
* exposure/metering preparation
* AE convergence
* inference or recommendation
* settings application
* verification
* completion or fallback

Use a monotonic clock for durations.

Record:

* optimize_run_id
* trigger
* lens position
* device model/category
* OS version
* application version
* total duration
* stage durations
* outcome
* fallback reason
* cancellation reason

Avoid collecting unnecessary image or scene data.

AE convergence

Investigate the causes of ae_converge_timeout.

Determine whether the timeout is associated with:

* front camera
* rear camera
* low-light conditions
* camera startup
* lens switching
* stale callbacks
* exposure lock state
* capture concurrency

Do not blindly shorten the AE timeout without evaluating exposure correctness.

Missing metering

Investigate ao_metering_missing.

Distinguish missing input, unsupported device capabilities, unavailable metadata, transient camera state, and internal errors.

Provide a safe fallback where appropriate.

Latency safeguards

Implement bounded waits and explicit cancellation.

Avoid blocking the main thread.

Prevent stale asynchronous completions from changing camera settings after cancellation, reset, lens flip, backgrounding, or capture.

Preserve successful optimization behavior for normal runs.

Do not make unsafe exposure changes merely to satisfy latency targets.

Performance goals

Proposed experiment targets, subject to device measurements:

* p50 optimization latency under 1 second.
* p95 under 5 seconds.
* Fewer than 2% of eligible runs exceeding 10 seconds.
* No increase in failed captures.
* No increase in incorrect exposure or stale-state application.

8. Unified analytics architecture

Extend the existing analytics layer instead of creating a parallel one.

Every relevant event should support a consistent schema:

event_name
event_timestamp
anonymous_install_id
session_id
app_version
build_number
platform
experiment_id
experiment_arm
camera_session_id
optimize_run_id
capture_id

Only attach fields that are applicable to the event.

Use typed event/property definitions where practical.

New recommended events

first_photo_experiment_assigned
first_photo_guidance_view
first_photo_guidance_skip
first_photo_preoptimize_start
first_photo_preoptimize_complete
first_photo_activation_complete
capture_ready_view
capture_ready_shutter_tap
capture_after_optimize
paywall_experiment_assigned
paywall_value_proof_shown
optimize_stage_complete
optimize_fallback
optimize_latency_summary

Avoid redundant emissions if equivalent events already exist.

Critical event semantics

first_photo_activation_complete should fire at most once per installation, after the first successfully saved photo that was genuinely optimized at capture time.

Record elapsed time from the first app open.

For the five-minute activation metric, distinguish users who were eligible for the experiment from users who had already activated before the experiment was introduced.

optimize_capture_abandoned must have a precise eligibility window and terminal outcome definition. Do not count an optimization as abandoned while a valid capture is still in progress.

Event quality

* Enforce at-most-once semantics where required.
* Avoid double counting SwiftUI onAppear calls.
* Preserve event ordering within an optimization/capture attempt.
* Handle offline buffering through the existing analytics provider.
* Document analytics schema version changes.
* Keep analytics failure nonblocking for camera and purchases.

9. Feature flags

Provide these logical flags, mapped to the repository’s existing configuration mechanism:

first_photo_preoptimize_enabled
capture_ready_ui_enabled
paywall_value_experiment_enabled
purchase_telemetry_v2_enabled
optimize_stage_timing_enabled
optimize_safe_timeout_enabled

Requirements:

* Independent flags.
* Deterministic experiment assignment.
* Safe defaults.
* Persistent assignment.
* Emergency disable capability.
* No remote configuration dependency on the critical camera path.
* Tests for all enabled/disabled combinations that materially affect camera state.

Telemetry-only improvements may be enabled independently of UI experiments.

Do not reset an experiment assignment merely because a feature flag is temporarily disabled.

10. Architecture constraints

Prefer the following separation of concerns:

Camera session layer: Owns AVFoundation lifecycle, camera state, metering, exposure, focus, and lens transitions.

Optimization layer: Owns optimization execution, cancellation, results, and verification.

Capture coordination: Associates an optimization result with a valid camera generation and capture attempt.

SwiftUI presentation: Renders guidance, progress, capture readiness, and errors based on authoritative state.

Experiment configuration: Owns assignments, eligibility, and kill switches.

Analytics: Emits typed, documented events without owning product behavior.

Monetization: Owns StoreKit verification and entitlements independently from paywall presentation.

Do not introduce a large architectural rewrite unless the current structure makes the required behavior unsafe.

11. Automated testing

Add tests at the appropriate existing levels.

First-photo experiment

* Stable assignment across launches.
* Correct control/treatment behavior.
* No repeated guidance after completion or opt-out.
* Permission denied.
* Camera startup failure.
* Background during optimization.
* Lens flip during optimization.
* Shutter during optimization.
* Quota exhaustion.
* Cancellation and undo.
* Feature flag disabled.

Capture-ready flow

* Successful optimization produces capture-ready UI.
* Failure does not claim success.
* Capture remains available when safe.
* Optimization is invalidated by reset or lens change.
* No stale result is attributed to a photo.
* VoiceOver labels and accessible actions exist.
* Capture success telemetry is not duplicated.

Paywall

* Correct experiment assignment.
* Real image shown when available.
* Graceful fallback without an image.
* No fabricated comparison.
* Correct StoreKit prices and trial eligibility.
* Restore Purchases remains functional.
* Paywall dismissal does not change entitlements.
* No interruption of active capture.

Purchases

* Verified purchase.
* User cancellation.
* Pending purchase.
* Unverified transaction.
* Failed purchase.
* Restore.
* Renewal.
* Revocation.
* Duplicate transaction callback.
* App termination and relaunch.
* Analytics delivery failure.
* Entitlement activation failure.

Optimization performance

* AE convergence success.
* AE timeout.
* Missing metering.
* Camera reset while awaiting AE.
* Lens flip while verification is running.
* Background cancellation.
* Stale asynchronous completion.
* Partial fallback.
* Monotonic duration measurements.
* No main-thread blocking.

Use deterministic clocks, mockable dependencies, and controlled asynchronous tests where appropriate.

Avoid fragile sleep-based timing tests.

12. Device validation matrix

Document and execute what can be tested on available hardware.

At minimum, provide a manual validation plan for:

* Front and rear camera.
* First install and returning install.
* Bright light and low light.
* Portrait and landscape.
* Rapid lens flipping.
* Rapid background/foreground transitions.
* Camera permission denied and later granted.
* Capture while optimization is pending.
* Reset during optimization.
* Repeated captures.
* Offline operation.
* StoreKit sandbox purchase and restore.
* Accessibility and reduced motion.

Clearly distinguish automated coverage from checks that still require physical devices.

Do not claim device validation if no device was available.

13. Implementation phases

Implement in reviewable phases or separate pull requests if the work is too large for one safe change.

Phase 1 — Baseline and instrumentation

Audit event definitions, add correlation IDs, establish reliable outcome attribution, and introduce feature flags.

Phase 2 — First-photo and capture-ready experiments

Implement the guided pre-capture arm and post-optimization shutter experience.

Phase 3 — Paywall and purchase correctness

Implement the value-based paywall experiment and verified transaction lifecycle telemetry.

Phase 4 — Latency and reliability

Instrument stages, fix proven bottlenecks, and add safe timeouts/fallbacks.

Phase 5 — Validation and rollout

Run tests, document remaining device checks, and prepare a staged release.

Do not merge incomplete work into main.

14. Acceptance criteria

The work is complete when:

* [ ]	Both first-photo experiment arms work and assignments are stable.
* [ ]	Pre-capture optimization is cancellable and never prevents safe immediate capture.
* [ ]	Optimized capture attribution is accurate across reset, undo, lens changes, and backgrounding.
* [ ]	The capture-ready experience is implemented and accessible.
* [ ]	The paywall experiment uses genuine results and accurate StoreKit product information.
* [ ]	Purchases are counted only after verified transactions and entitlement activation.
* [ ]	Purchase cancellation, pending, failure, restore, and renewal paths are distinguishable.
* [ ]	AE convergence and missing metering are instrumented with actionable diagnostic categories.
* [ ]	Latency is measured by stage and long-tail regressions are testable.
* [ ]	Existing camera safety behavior is preserved.
* [ ]	Existing analytics dashboards can continue consuming legacy events.
* [ ]	New event contracts and experiment metrics are documented.
* [ ]	Relevant automated tests pass.
* [ ]	Remaining device validation is explicitly documented.
* [ ]	All changes are committed and a pull request is created.

The numerical activation, conversion, and latency targets are rollout hypotheses, not guaranteed completion criteria. Do not fabricate improvements without actual experiment results.

15. Required final deliverables

At completion, report:

1. Architecture: Existing components reused and any new components introduced.
2. Implementation: Files changed and behavior delivered.
3. Experiments: Assignment logic, eligibility, control/treatment behavior, and kill switches.
4. Telemetry: Event schema, correlation IDs, compatibility, and known limitations.
5. Purchase audit: Identified gaps, fixes, and reconciliation procedure.
6. Performance: Instrumented stages, bottlenecks found, and measured results where available.
7. Tests: Tests added, commands executed, pass/fail results, and physical-device checks remaining.
8. Release plan: Safe rollout sequence, guardrail metrics, and rollback procedure.
9. Pull request: Link to the completed PR or PRs.

Final operating instructions

Start by inspecting the current repository and producing a short implementation map. Then proceed with code changes.

Favor small, testable modifications over broad rewrites.

Protect the existing camera lifecycle, front-camera Auto Optimize, reset behavior, and StoreKit entitlement logic.

Never sacrifice camera correctness, purchase verification, or user control to improve a funnel metric.

The final product goal is simple: help more first-time users take a genuinely optimized photograph, make that success immediately understandable, and convert demonstrated value into repeat usage and sustainable revenue.
