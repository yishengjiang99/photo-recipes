# ProTune Auto Optimize latency — measurement report (2026-10-18)

## TL;DR

- Optimize-run duration **is** in first-party telemetry for successes: `auto_optimize_success`
  carries **`latency_ms`** (tap → Ready, integer ms as a string), measured from the run's
  `startedAt` in `AutoOptimizeController.run`. `auto_optimize_cancel` carries it too.
- **Failures carried no duration at all** — in code (no prop on any `auto_optimize_fail` site)
  and in production (0 of 46 fail events in 30 days). Minimal instrumentation for the two
  in-run failure sites was landed on main: **commit `1ed9c7ca9062ae5fab476793c441f8eea6041293`**
  (details below). Failure latency starts measuring once a build containing it ships — the
  next build after the 1.6 TestFlight build of `184ab0a9`.
- Success latency today (iOS, production): **median ≈ 0.9–1.1 s**, but a slow tail
  (~8% of runs at 5–63 s) pushes **p95 to ≈ 11.6 s** in both windows.
- Proposed budget (rolling 7 days, iOS `auto_optimize_success.latency_ms`):
  **p95 ≤ 5,000 ms** (currently missed — tail-driven), **median ≤ 1,500 ms** (currently met),
  **share of runs > 10 s ≤ 2%** (currently 5.8–7.3% — missed).

## 1. What timing data exists in the code

Repo `yishengjiang99/photo-recipes`. Remote main was verified at
`184ab0a990c729698478cce35f22bfa79c44e72a` at the start of this work (local checkout was
stale/dirty, so a tree-verified copy of remote main was used; local tree ==
remote tree `963bb2d71a5ef753d270b3198434ac2cf7e6c6cc`).

### AOPerf (os_signpost — Instruments only, NOT telemetry)

`ios/PhotoRecipes/Services/AutoOptimizeController.swift` (lines 17–46 at `184ab0a9`):

- `AOPerf.begin(runId:)` / `AOPerf.end(_:outcome:)` — `os_signpost` interval named
  `auto_optimize`, subsystem `com.ragnus.mvp`, category `AutoOptimize`. Begin is called in
  `run()` after the already-running and quota guards; end outcomes: `cancelled`,
  `no-frame`, `no-recipe`, `unknown-recipe`, `ready-coach-only`, `ready`.
- `AOPerf.recordFrameStats(wallMs:gpuMs:source:)` (called from `GPUStatsEngine.swift`) —
  signpost event `gpu_frame_stats`. Device/Instruments only; never sent to the server.

### Analytics events (`Analytics.shared.track` → `POST /api/telemetry` → MySQL `telemetry_events.props_json`)

- `run()` sets `startedAt = Date()` and a fresh `runId` (UUID) immediately before
  `AOPerf.begin` and the `auto_optimize_start` emit — the single run choke point
  (start event restored in `2cbdc31e`).
- **`auto_optimize_success`** — two emit sites in `run()` (coach-only path and main
  Ready path). Props include:
  - **`latency_ms`** = `Int(Date().timeIntervalSince(startedAt) * 1000)`, as a string —
    present at both sites.
  - **`t_verify_ms`** — main Ready path only: wall time of the verify loop
    (`""` when no verify ran).
  - Plus `run_id`, `parent_run_id`, `trigger` (main site), `coach_only` (coach site),
    `recipe_id`, `path: "local"`, and the Phase 3 `telemetry_v2` prop set.
- **`auto_optimize_cancel`** (the `wasCancelled` helper) — `latency_ms` (same formula)
  + `stage`.
- **`auto_optimize_start`** — `run_id`, `trigger`, `parent_run_id`, `path`. No timing
  prop (it is the start marker; pairs with success by `run_id`).
- **`auto_optimize_fail`** — **no `latency_ms`, no `run_id` at any site** (before the fix
  landed in §4): quota in `AutoOptimizeController.run` (`path: "local"`), `no_frame`
  and `no_recipe` in the same function, and quota in `CameraView.swift`
  (`path: "camera_tap"`). The unknown-recipe failure emits no fail event at all
  (signpost only).
- Web `src/components/FieldCoach.tsx` also emits `auto_optimize_success`/`_fail`
  (`source: "field_coach"`, no latency prop) — 10 of the 494 success events in the
  30-day window are web; all figures below are **iOS only** unless stated.

### Why stored coverage is lossy (important caveat)

Server `sanitizeProps` (`server/telemetry.ts`) keeps at most **24 prop keys**
(`MAX_PROP_KEYS = 24`). A success payload carries ~34+ keys, so an arbitrary subset is
dropped per row: in production, `latency_ms` survived on 53.7% of iOS success rows
(30 d) / 76.2% (7 d), and **`t_verify_ms` survived on 0 of 494** — stage-level timing
cannot be recovered from telemetry today. Which keys survive is independent of the
latency value (Swift dictionary / JSON key order), so the surviving sample is treated
as representative — but every figure below quotes its n. Fail events carry only ~8
props total, well under the cap, so the new failure `latency_ms` (§4) will land
reliably. Raising the server cap is the real fix for success-side coverage; it was
**not** done here (separate server change/deploy) and is a recommended follow-up.

## 2. Observed distribution (production, read-only)

Method: `ssh grepawk` (egress-proxy CONNECT ProxyCommand, key `~/.ssh/grepawk`) →
MySQL `telemetry_events` on the production server (db `photo_recipes`), SELECT only,
no credentials printed or stored. Rows dumped for
`auto_optimize_success` / `_fail` / `_cancel` with `created_at` in window; percentiles
computed locally (linear interpolation on sorted values, numpy-default method).
Query anchored at server time **2026-10-18 21:29:21 UTC**; windows are rolling
24 h × days ending then. `latency_ms` first appears in production on
2026-10-06 23:01 UTC, so the 30-day latency sample effectively spans Oct 6–18.

### `auto_optimize_success` latency_ms — iOS

| Window (UTC) | Success events (iOS) | With `latency_ms` | Median | p90 | p95 | p99 | Mean | Min | Max | ≤2 s | ≤5 s | ≤10 s |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Last 7 d (2026-10-11 21:29 → 2026-10-18 21:29) | 126 | 96 (76.2%) | **1,056 ms** | 6,844 | **11,716** | 19,801 | 2,605 | 355 | 42,076 | 84.4% | 88.5% | 92.7% |
| Last 30 d (2026-09-18 21:29 → 2026-10-18 21:29) | 484 (+10 web) | 260 (53.7%) | **896 ms** | 2,032 | **11,630** | 31,323 | 2,499 | 343 | 62,563 | 89.2% | 92.3% | 94.2% |

Shape (30 d, n=260) — clearly bimodal:

- ≤5 s population: n=240 (92.3%) — median 860 ms, p95 1,967 ms.
- \>5 s tail: n=20 (7.7%) — median 16,920 ms, range 5,624–62,563 ms.
  Histogram: <0.5 s: 43 · 0.5–1 s: 100 · 1–2 s: 89 · 2–5 s: 8 · 5–10 s: 5 ·
  10–20 s: 9 · 20–60 s: 5 · ≥60 s: 1.
- The tail, not the typical run, sets p95. Telemetry cannot attribute the tail to a
  stage (the `t_verify_ms` prop never survives the server cap, §1).

By app version (30 d, latency-bearing rows only): 1.2 — n=98, median 856 ms,
p95 1,869 ms · 1.3 — n=39, median 760 ms, p95 14,828 ms · 1.4 — n=37,
median 1,100 ms, p95 18,866 ms · 1.5 — n=28, median 719 ms, p95 10,368 ms ·
null version — n=58, median 1,234 ms. Medians are stable ~0.7–1.2 s across versions;
the tail appears in every version slice.

### Failures and cancels

- `auto_optimize_fail`: 7 d — 5 events (all iOS), 30 d — 46 events (44 iOS, 2 web);
  **0 with `latency_ms` in either window → no failure distribution is possible**
  from existing data. 30-day error mix: `quota` 40, `no_frame` 3, `recommend` 1 (iOS);
  `504` 1, `exception` 1 (web).
- `auto_optimize_cancel`: exactly 1 event in 30 days (2026-10-09, stage `sense`,
  `latency_ms` 46,103 ms) — it does carry the prop, but n=1 is not a distribution.

## 3. Proposed latency budget

Rolling 7-day window, iOS `auto_optimize_success.latency_ms`, judged only when the
window holds ≥50 latency-bearing success events (coverage is lossy, §1):

| Budget | Target | Current (7 d / 30 d) | Status |
|---|---|---|---|
| Typical run — median | ≤ 1,500 ms | 1,056 / 896 ms | ✅ met |
| User-facing tail — p95 | ≤ 5,000 ms | 11,716 / 11,630 ms | ❌ missed |
| Stuck-run share — % of runs > 10,000 ms | ≤ 2% | 7.3% / 5.8% | ❌ missed |

Grounding: 92.3% of runs already finish within 5 s and the ≤5 s population's own p95
is ~2 s, so a 5 s p95 does not ask the typical path to get faster — it requires
roughly halving the >5 s tail (7.7% → ≤5%), e.g. by time-boxing whatever stage
produces 10–60 s runs. The >10 s share cap names that tail directly so the p95
can't be gamed by reshaping the middle of the distribution.

## 4. Instrumentation landed (failure side only)

Success/cancel already carried `latency_ms`; failure carried none, in code or in
production — so only the missing piece was added, following the existing pattern
(the `auto_optimize_cancel` emit in the same function):

- **Commit `1ed9c7ca9062ae5fab476793c441f8eea6041293`** on `main`
  (parent `db294afb0673dc9049fa70977f336f1d4995df33` — main advanced two
  funnel-definition commits past `184ab0a9` during this work; the touched file was
  byte-identical between the two heads, and the change was re-based and
  tree-verified onto the new head before pushing).
- File: `ios/PhotoRecipes/Services/AutoOptimizeController.swift` (+10 lines, one file).
- Change: the two `auto_optimize_fail` sites that fire **after a run has started**
  (`no_frame`, `no_recipe`) now also send `run_id` and
  `latency_ms = Int(Date().timeIntervalSince(startedAt) * 1000)` — the same run
  identity and the same `startedAt` the success/cancel events measure from.
- Deliberately unchanged: quota fail sites (`AutoOptimizeController` + `CameraView`)
  fire **before a run exists** (no `startedAt`/`run_id`; per the funnel contract they
  are not starts), so there is no run duration to report. The unknown-recipe path
  still emits no fail event at all — noted as a separate gap, not fixed here.
- No user-visible behavior change. Pushed via `gh-push.py` (Git Data API): API tree
  == local tree, recursive-tree check 608 blobs, byte comparison OK on the changed
  file, fast-forward only, no force, no squash. CI was **not** polled (standing
  rule); the workflow that exercises this code on push is `ios-unit-tests.yml`
  (`ios-testflight.yml` runs on dispatch only).
- **The failure-latency budget starts measuring once a build containing `1ed9c7c`
  ships** — i.e. the next build after the 1.6 TestFlight build of `184ab0a9`.
  Until then, failure latency remains unmeasurable (only quota failures, which
  have no run, dominate the fail mix anyway: 40 of 44 iOS fails in 30 days).

## 5. Recommended follow-ups (not done here)

1. Raise/ rework the server's 24-prop-key cap (`MAX_PROP_KEYS` in
   `server/telemetry.ts`) — it silently drops ~half of success `latency_ms` values
   and 100% of `t_verify_ms`, which is what blocks stage-level attribution of the
   >5 s tail.
2. Once a build with `1ed9c7c` is live, add a failure-latency line (median/p95 of
   in-run fails) next to the success budget above; expect small n.
3. Investigate the >5 s tail (20 runs in 30 d, up to 62.6 s) once `t_verify_ms`
   or an equivalent stage prop actually lands in telemetry.
