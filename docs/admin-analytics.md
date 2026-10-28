# Admin Analytics & Experiment Monitoring Panel

**Route:** `/admin/analytics` (linked prominently from `/admin`; requires the
same admin session as the existing panel — server-side `requireAdmin`).
**Stack:** Express 5 + TypeScript server, React 19 + Vite + Tailwind frontend,
existing MySQL `telemetry_events` — no new infrastructure, no new
dependencies, no chart library (charts are inline SVG).

**Stacked on PR #171.** This panel is a stacked PR on
`feat/activation-capture-monetization` (the activation/capture-ready/paywall/
purchase-v2/stage-timing work). Retarget to `main` once #171 merges. The
panel only *reads* experiment events; it never changes assignments, flags, or
rollout — see "Read-only" below.

## Architecture

```
iOS / web clients ──POST /api/telemetry──> telemetry_events (shared table)
                                                 │
server/adminAnalytics.ts                         │
  fetchAnalyticsDataset()   bounded, app='photo-recipes' ONLY, ORDER BY
                            created_at, hard cap 200,000 rows (+1 probe):
                            on overflow partial=true + warning, never silent
                            truncation. install_devices queried in the same
                            call for new-install + retention cohorts.
  compute*()              pure functions over normalized rows
                            {created_at, event, anon_id, session_id,
                             app_version, props}. Deterministic, DB-free,
                            unit-tested with fixtures (healthy + regressed).
server/admin.ts         GET /api/admin/analytics/* behind requireAdmin,
                        plus GET /api/admin/analytics/export (CSV).
src/pages/AdminAnalytics.tsx   presentation + interaction only.
```

Canonical funnel definitions in `server/telemetry.ts` are **not** modified
or forked: this panel's funnels are its own correlated definitions, and
anything it cannot correlate is kept in an explicit `legacy` block instead
of being merged into a funnel (the exact mistake the activation audit
warned about: `auto_optimize_success` 676 > `auto_optimize_start` 417
because iOS never emitted a paired start in the baseline period).

## API

All endpoints: `requireAdmin` (cookie `pr_admin` / Bearer `ADMIN_TOKEN`;
503 when admin is unconfigured, 401 when unauthenticated). Query params
(all validated, 400 on violation):

- `range` = `24h` | `7d` | `30d` (default `7d`), or `start` + `end` ISO-8601
  (both required; max span 92 days; start must precede end).
- `app_version` (validated pattern), `arm`, `lens`, `compare` (default on;
  `compare=false` hides previous-period deltas in the UI).
- Response envelope (adapted to the repo's `{ok, ...}` convention):

```json
{
  "ok": true,
  "period": { "start": "ISO-8601", "end": "ISO-8601" },
  "previousPeriod": { "start": "ISO-8601", "end": "ISO-8601" },
  "timezone": "UTC",
  "displayTimezone": "America/Los_Angeles",
  "data_freshness": "ISO-8601 (latest event in window) | null",
  "generatedAt": "ISO-8601",
  "partial": false,
  "app": "photo-recipes",
  "warnings": ["..."],
  "metrics": {},
  "sample_sizes": { "rows": 0, "distinctUsers": 0 }
}
```

| Endpoint | View |
| --- | --- |
| `GET /api/admin/analytics/overview` | Executive KPIs + experiments & alerts |
| `GET /api/admin/analytics/activation` | First-photo experiment |
| `GET /api/admin/analytics/capture` | Capture-ready, run_id-correlated |
| `GET /api/admin/analytics/paywall` | Paywall funnel + segments + revenue snapshots |
| `GET /api/admin/analytics/purchases` | Purchase reconciliation (alias view) |
| `GET /api/admin/analytics/reconciliation` | Purchase reconciliation |
| `GET /api/admin/analytics/optimize-performance` | AO latency / reliability |
| `GET /api/admin/analytics/experiments` | Experiments + alerts only |
| `GET /api/admin/analytics/export?view=…&format=csv` | Aggregate-only CSV (audit-logged) |

## Metric definitions & calculation methods

Common rules: counts are **distinct users** unless the unit says otherwise;
retried events are deduplicated on (event, anon, session, timestamp,
correlation ids + key props); breakdown cells with < 5 distinct users are
suppressed (`null` + note), never shown; missing instrumentation yields
`instrumented: false` + `value: null`, never 0; windows are `[start, end)`
in UTC, daily buckets are UTC days, and the UI labels display timezone
explicitly.

### Executive overview

- **DAU** = distinct `anon_id` on the last UTC day of the period;
  **WAU** = distinct `anon_id` in the trailing 7 days of the period.
- **New installations** = `install_devices` rows first seen in the period
  (null + warning when that table is unavailable — not zero).
- **Camera activation rate** = users with `camera_open` / users with
  `session_start` (fallback denominator: any-event users, labeled).
- **First optimized photo within 5 min** = users with
  `first_photo_activation_complete` where `within_window=true` /
  eligible unique new users. Eligible = users with
  `first_photo_experiment_assigned` in the period; if no assignments exist,
  new installs in the period are used as the denominator and the source is
  labeled. `within_window` is a client-computed prop; its 5-minute
  boundary semantics live client-side — the panel trusts the prop and
  labels it as such (see data gaps).
- **Optimize → capture** = correlated runs: `optimize_latency_summary`
  with `outcome=success` that have a `capture_after_optimize` with
  `classification=afterComplete` on the same `run_id`, with the capture at
  or after the summary timestamp, / successful runs.
- **D1/D7 retention** = install cohorts from `install_devices.first_seen_at`
  (cohort = installs on one UTC day; retained = any event on cohort day
  +1 / +7). Null when the retention day has not fully elapsed or the
  cohort has < 30 installs.
- **Paywall → purchase** = users with `purchase_verified` (or
  `purchase_success` with `telemetry_v=2`) / `paywall_view` users.
- **Verified purchases** = distinct `transaction_id` across
  `purchase_verified` + `purchase_success` — a transaction count, **not
  revenue**.
- **AO latency** = nearest-rank p50/p95/p99 over
  `optimize_latency_summary.total_ms`. The pooled figure is labeled as
  pooled across versions; per-version breakdowns are in
  optimize-performance (timing definitions may differ across versions).
- **Capture failure rate** = `capture_failed` / (`capture_failed` +
  `capture_success`) events — **currently not instrumented** (see gaps).
  The client emits `capture_success` but no failure event, so the KPI
  reports not-instrumented rather than a fabricated 0%.

Legacy aggregates (start/success/captured/abandoned/shutter/capture-success
event counts) are shown separately and are never divided into a funnel.

### First-photo activation experiment

Per arm (`post_capture_v1` control, `pre_capture_guided_v1` treatment):

```
assigned (eligible) → guidance_view → guidance_skip → preoptimize_start
→ preoptimize_complete → activation_complete → activation_within_5min
```

A stage counts only for users whose event is at/after their assignment
time (sequence enforced). Guidance and pre-optimize stages are
treatment-only (shown as n/a for control). Primary metric:

```
unique users with first optimized photo within 5 min / eligible unique new users
```

Comparison: absolute percentage-point difference and relative lift.
Significance: **only** a two-proportion z-test (normal approximation,
two-sided, α=0.05) and only when both arms have ≥ 30 eligible users —
otherwise the panel says "insufficient data for significance" and claims
no winner. The z-test assumes independent assignments and no
peeking correction; treat it as directional. Retention by arm uses
assignment-anchored windows (event on assignment day +1 / +7; < 30
eligible assignments → null).

**Arm-name mapping (real data quirk):** the iOS assignment code emits the
generic raw values `control` / `treatment` on assignment events
(`ExperimentAssignment.swift`), while the experiment contract names the
logical arms. The panel normalizes by experiment context:
`control` → `post_capture_v1` (first-photo) / `paywall_control_v1`
(paywall); `treatment` → `pre_capture_guided_v1` / `paywall_value_v1`;
the long names are accepted verbatim. If the client ever changes the
emitted values, the normalization table in `server/adminAnalytics.ts`
(`normalizeFirstPhotoArm` / `normalizePaywallArm`) is the one place to
update.

### Capture-ready

Funnel strictly by `run_id`, in order: terminal `optimize_latency_summary`
→ `capture_ready_view` → `capture_ready_shutter_tap` →
`capture_after_optimize` with `classification=afterComplete`. Only
`afterComplete` counts; `during` / `afterUndo` / `afterFailure` /
`afterLensFlipOrReset` captures do not. Median seconds from ready to
shutter comes from `capture_after_optimize.seconds_after_ready`.
Abandoned: legacy `optimize_capture_abandoned` events (counted
separately) plus ready runs with no capture recorded in the period.
Breakdowns: lens, trigger, app version, experiment arm (suppressed under
5 users). If `run_id` coverage is zero the view returns
`instrumented: false` — it does not display a zero funnel.

### Paywall & revenue

Ordered funnel per (anon_id, session_id): `paywall_view` →
`paywall_plan_select` → `purchase_start` → `purchase_verified` →
`entitlement_activated`. A stage counts only after the previous stage
within the **same** session; cross-session progression is rejected.
Segments: experiment arm (`experiment_arm`), trigger/`paywall_id`,
product (from the session's `purchase_start.product_id`), app version,
new vs returning (`is_new_user` base prop). Cancellations / pending /
failed are counted as distinct `purchase_attempt_id`s (anon+session
fallback when no attempt id). Verified trial starts are null unless a
trial signal appears in verified-event props (`is_trial` / `trial` /
`entitlement_type=trial`). Restores are `purchase_restore` event counts.

**Revenue is never derived from telemetry.** The paywall view attaches
the existing local snapshots only: entitlement snapshot (local
StoreKit-verified Pro entitlements; IAP estimated MRR gross, before
Apple's cut) and Stripe snapshot (approx MRR from active/trialing
subscriptions, first page ≤ 100). App Store Connect is the sales ledger
of record and Stripe is the web ledger; both are labeled as estimates
here. `purchase_success` without `telemetry_v=2` is a legacy client
event (fired when StoreKit returned `true`, pre-verification gating) and
is never used as a verified-purchase count or revenue.

### Purchase reconciliation

Sets keyed by `transaction_id` (client telemetry only):

- starts without terminal outcome — `purchase_start` by
  `purchase_attempt_id` with no `purchase_verified` / `purchase_success` /
  `purchase_cancelled` / `purchase_pending` / `purchase_failed` for the
  same attempt in the period (a missing terminal event is an
  instrumentation-gap candidate, not proof of a failed sale).
- duplicate `purchase_success` — the same `transaction_id` with > 1
  success row (v2 dedupe should make this 1:1; any mismatch is a bug).
- verified without entitlement — `purchase_verified` with no
  `entitlement_activated` for the same transaction (revenue at risk).
- entitlement without verified or restore — `entitlement_activated`
  with no `purchase_verified`/`purchase_success` for the transaction
  and no `purchase_restore` for the same user.

Discrepancy rate = (all three discrepancy counts) / verified
transactions; tolerance **2%** (documented proposal — investigate only
divergences above a few percent per activation-experiments.md §4).
Diagnostic rows expose `transaction_id` + `product_id` + timestamps
only, max 200, read-only. CSV exports contain aggregate counts only —
transaction ids are never exported.

### Optimize performance

Runs = `optimize_latency_summary` rows (one per run reaching a terminal
outcome). Outcomes from the `outcome` prop (success / failure /
cancelled / fallback). Stage latencies come from `stage_*_ms` props
(`requested`, `aeConvergence`, `inference`, `apply`, `verify` in the
current client; `cameraReadyWait` / `meteringPrep` are not separately
anchored — they sit inside the convergence segment). Slowest stage is
ranked by p95. Rates: AE timeouts (`ae_converge_timeout` events / runs),
metering missing (`ao_metering_missing` / runs), > 10 s share
(`total_ms > 10,000` / runs). Reliability counts come from real events
only: `ao_exposure_reverted` (exposure reverts), `ao_reset_on_flip`
(lens-flip invalidations), `camera_reset` / `camera_exposure_reset`,
and capture-failure events (null when none are emitted). Regression
flags vs the previous period: p95 up > 20% (needs n ≥ 30 runs in both
periods) and failure rate up > 50% relative (same n gate) — otherwise
the flag reports "insufficient n", never a regression.

### Experiments & alerts

Six flags (read-only): `first_photo_preoptimize_enabled`,
`capture_ready_ui_enabled`, `paywall_value_experiment_enabled`,
`purchase_telemetry_v2_enabled`, `optimize_stage_timing_enabled`,
`optimize_safe_timeout_enabled`. For each: experiment id, version, arms,
assignment (50/50 FNV-1a persisted bucketing for the two bucketed
experiments), eligibility, start date (first observed assignment /
relevant event, else null), current sample size, exposure count,
primary metric, guardrails. **Configuration status is always
`unknown_client_side`** — flags are client UserDefaults and the server
cannot read them; "no events" is never presented as proof a flag is off.

Alert definitions are read-only proposals (thresholds from the spec,
**not established production baselines**):

| Metric | Condition |
| --- | --- |
| First-photo activation | > 10% relative decline |
| Optimize → capture | > 10% relative decline |
| Capture failure rate | > 2× previous baseline |
| AO p95 latency | > 5,000 ms |
| Runs over 10 s | > 2% of runs |
| AE timeout rate | > 2× previous baseline |
| Purchase verification failures | ≥ 5 events and > 50% relative increase |
| Reconciliation gap | discrepancy rate > 2% of verified |

An alert can only fire with n ≥ 100 (reconciliation: ≥ 20 verified
transactions) and — for periods ending within the last 24 h — data
fresher than 24 h. Delayed ingestion or missing instrumentation yields
`unknown`, never a false alarm.

## Security & authorization review

- Every route, including the CSV export, sits behind `requireAdmin`
  (existing cookie/Bearer auth; 503 if admin is unconfigured). There is
  no public analytics endpoint and no frontend-only gating.
- Query parameters are allow-listed and validated; `app_version` /
  `arm` / `lens` patterns are restricted; repeated parameters are
  rejected; ranges are capped at 92 days; DB reads are bounded by the
  200k row cap with `ORDER BY created_at` and parameterized queries
  (`app` bound as a parameter, never interpolated).
- Least privilege: the panel issues read-only `SELECT`s against
  `telemetry_events` / `install_devices`; no mutation endpoints, no
  flag/rollout writes, no experiment reassignment (none exists in the
  repo's control plane, and none was invented).
- Privacy: responses are aggregates by default; breakdown cells under 5
  distinct users are suppressed; reconciliation rows carry only
  transaction ids, products and timestamps — never receipts, payment
  credentials, anon ids, or personal details. CSV exports are
  aggregate-only and are audit-logged server-side
  (`[admin-analytics] export` with view + period + row count).
- No analytics service secrets are exposed to the client: the frontend
  fetches only the admin endpoints with the admin session cookie.
- Known limitation: export audit logs record view + period, not admin
  identity (the session cookie carries only an issue timestamp), so
  exports are attributable to "an authenticated admin" only.

## Data gaps & instrumentation dependencies

1. **Purchase telemetry v2 defaults OFF** (`purchase_telemetry_v2_enabled`
   = false in the client). Until it is enabled, `purchase_verified` /
   `entitlement_activated` do not exist and the paywall-verified,
   reconciliation, and purchase-alert views report not-instrumented.
   Legacy `purchase_success` cannot substitute (see above).
2. **Capture failures are not emitted.** There is no `capture_failed`
   event in the client; the failure-rate KPI and its alert stay
   not-instrumented/unknown until one is added.
3. **Renewals, refunds, revocations** never appear in client telemetry.
   They are counted from App Store Connect / server verify records
   only. The panel has no ASC API integration, so the authoritative
   comparison remains the weekly aggregate check in
   activation-experiments.md §4 (a few-percent tolerance).
4. **Stage timing is partial**: `cameraReadyWait` / `meteringPrep` are
   inside the convergence segment, not separately anchored.
5. **First-photo `within_window`** is client-computed; the panel trusts
   the prop (5-minute boundary semantics live in the client, not in
   this repo's server).
6. **Assignment emission lag**: `first_photo_experiment_assigned` fires
   at first computation, so users deemed ineligible by the client never
   appear in denominators — the correct exclusion, but it means the
   panel cannot independently verify the client's eligibility gating.
7. **Retention** depends on `install_devices` (populated by telemetry
   ingest); if that table is unavailable, installs and retention are
   null.
8. **Historical data without correlation ids** is handled by the
   `legacy` blocks: pre-v2 runs have no `run_id` on legacy events, so
   they cannot produce correlated funnels and are not retrofitted into
   one.

## Tests

`server/adminAnalytics.test.ts` (in `npm run test:server`): deterministic
fixtures (healthy + regressed), covering: auth 401/503, invalid and
> 92-day ranges, empty dataset → not-instrumented states, missing v2
instrumentation distinguished from zero, duplicate-event dedupe,
out-of-order and cross-session funnel rejection, experiment eligibility
denominators, 5-minute window boundary semantics, all four
reconciliation discrepancy classes, refund/renewal exclusion from
client counts, nearest-rank percentile correctness, > 10 s share,
small-cohort suppression, run_id-coverage gating, alert gating on empty
data, and CSV export auth + aggregate-only contents. Frontend: no
frontend test harness exists in this repo, so none was invented;
`npm run build` (tsc + Vite + server bundle) is the frontend gate.

## Deployment

No new infrastructure, environment variables, or migrations. The panel
rides the existing push-to-main deploy: server code is bundled by
`npm run build:server`, the frontend is a lazy route in the same Vite
app. Admin access requires the existing `ADMIN_PASSWORD` /
`ADMIN_TOKEN` environment on the server. Verify after deploy with an
authenticated `GET /api/admin/analytics/overview?range=7d` (expect 200
with the envelope above) and a visit to
https://photo.grepawk.com/admin/analytics (admin sign-in first).

## Screenshots

Captured from a local fixture harness (deterministic healthy dataset,
same fixtures as the tests — not production numbers) — see
`docs/admin-analytics-screenshots/`:
overview, activation, capture, paywall, reconciliation, optimize.
