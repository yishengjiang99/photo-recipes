# Agentic Flow Review v1

## Scope
Review of the current Auto Optimize / Recommend agentic flow documented in:
- `/docs/design-handoff-agentic-v1.md`
- `/docs/agentic-prompt-v2.md`

## Current flow (observed)
1. **Sense** scene from image/text/viewfinder note.
2. **Reason** with tools (`list_presets`, optional `get_preset_details`) and pick one preset.
3. **Act / Finalize** with `select_preset` and structured `phoneTargets` + `coachOnly`.
4. **Verify** ranges and consistency, then return recommendation for client apply.
5. **Apply on client** with capability-gated keys, skipping unsupported keys.

This is strong and already aligned to the product story (`Sense → reason → apply → verify → capture`).

## Key gaps
1. **No explicit confidence model in output**
   - The flow can return a technically valid recommendation without signaling certainty.
2. **Weak fallback hierarchy for tool/runtime failures**
   - Loop failure is defined, but user-facing fallback behavior can be more deterministic.
3. **Verification is mostly static schema/range checks**
   - Missing explicit scene-technique consistency checks as first-class outputs.
4. **Single-shot reasoning loop for dynamic scenes**
   - Motion/light shifts after initial sense can make recommendations stale.
5. **Limited observability primitives in the contract**
   - Hard to diagnose whether misses come from sensing, reasoning, or capability gating.

## Suggested improvements (prioritized)

### P0 — Reliability and trust (highest impact)
1. **Add `confidence` + `confidenceReasons` to finalize output**
   - Helps UI decide when to show stronger caution copy before capture.
2. **Define deterministic fallback ladder**
   - If tools or finalize fail: fallback to safest known preset profile + short reason, instead of hard-stop behavior.
3. **Add `verificationSummary` structure**
   - Include explicit checks (exposure risk, motion risk, focus risk) and pass/warn flags.
4. **Strengthen capability reconciliation contract**
   - Require response to distinguish `requestedTargets` vs `appliedTargetsExpected` when device limits are known.

### P1 — Dynamic-scene handling
1. **Introduce lightweight re-verify trigger contract**
   - Add a short-lived validity window for recommendations (for fast-changing scenes).
2. **Add motion-scene mode hints**
   - Structured hints for panning/tracking stability to reduce stale recommendations.
3. **Codify user-intent lock semantics**
   - If user asks for a creative intent (e.g., blur), prevent loop from optimizing it away.

### P2 — Diagnostics and continuous improvement
1. **Add stage outcome telemetry schema**
   - Track per-stage outcome (sense/reason/finalize/apply-ready) and dominant failure reason.
2. **Track override-after-optimize signals**
   - Frequent manual overrides should feed prompt and preset tuning backlog.
3. **Add evaluation fixtures for recurring scenes**
   - Regression suite for common scenarios (night motion, high contrast backlight, indoor low light).

## Recommended implementation order
1. Ship P0 contract additions (`confidence`, `verificationSummary`, fallback ladder).
2. Wire UI messaging to new trust signals.
3. Add P1 dynamic-scene re-verify behavior.
4. Add P2 telemetry and fixture-driven regression loop.

## Expected outcome
- Higher trust in Auto Optimize decisions.
- Fewer hard failures and fewer confusing “valid but weak” recommendations.
- Better product feedback loop to improve agent quality over time.
