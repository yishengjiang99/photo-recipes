# Funnel queries

Assumes table `telemetry_events` from `server/migrations/001_telemetry_events.sql`.

## Canonical ProTune funnel — THE funnel (single source of truth)

This is the only definition that may be called "the ProTune funnel" (and the
only one from which a "camera share" / stage-conversion number may be quoted).
It is the definition validated by the weekly funnel watch (session-based
re-check, 2026-10-18) and implemented by the server as
`fetchCanonicalFunnel` in `server/telemetry.ts` (surfaced in
`GET /api/telemetry/funnels` → `funnels.canonical` and in the admin summary →
`telemetry.canonicalFunnel`, displayed on the admin page as the Canonical
funnel).

- **Unit:** distinct `session_id`. One session counts at most once per stage.
  Rows with a NULL/empty `session_id` cannot be counted under this unit and
  are excluded.
- **Stages, in order:**
  1. `sessions` — sessions with any telemetry event
  2. `camera_open`
  3. `auto_optimize_start`
  4. `auto_optimize_success`
- **Window:** trailing complete days in `America/Los_Angeles` — PT calendar
  days, midnight–midnight, today (a partial day) excluded. The default window
  is the trailing 7 complete days. Bounds are computed as PT midnights in Node
  (production MySQL has no timezone tables) and applied as
  `created_at >= FROM_UNIXTIME(start)` AND `created_at < FROM_UNIXTIME(end)`.
- **Platform / app scope:** all platforms; **app fixed to `photo-recipes`**.
  `telemetry_events` is shared with other apps (`omr-sheet-cam`,
  `grepawk-photos`, …), and their rows must never enter the ProTune funnel —
  every canonical query filters `app = 'photo-recipes'` (the server's
  `REAL_APP` constant; `fetchCanonicalFunnel` and `GET /api/telemetry/funnels`
  both default to it). The server's `?app=` parameter / admin app selector can
  still scope a read to another app or to all apps for cross-app questions,
  but numbers produced that way are not the canonical ProTune funnel and must
  not be quoted as it. (An unscoped read once inflated all-time
  `purchase_success` from 4 to 5 with another app's purchase, and a weekly
  sessions count by 72 foreign sessions.)
- **Like-for-like rule:** only compare canonical numbers with canonical
  numbers produced under the identical unit, stages, window, timezone, and
  scope. Never compare a canonical (session) number against a raw event count
  or a distinct-`anon_id` (user-level) number — those are different cuts and
  produce different "camera share" figures. If the unit, a stage event, the
  window, or the timezone changes, the baseline resets and the change must be
  stated with the numbers. The same applies when an app version stops (or
  resumes) emitting a stage event: that is an instrumentation break, not a
  conversion change, and comparisons across the break are not like-for-like.

Canonical query (bounds are epoch seconds of the PT midnights bounding the
trailing complete days; this is the query `fetchCanonicalFunnel` runs):

```sql
SELECT
  COUNT(DISTINCT session_id) AS sessions,
  COUNT(DISTINCT IF(event = 'camera_open', session_id, NULL)) AS camera_open,
  COUNT(DISTINCT IF(event = 'auto_optimize_start', session_id, NULL)) AS auto_optimize_start,
  COUNT(DISTINCT IF(event = 'auto_optimize_success', session_id, NULL)) AS auto_optimize_success
FROM telemetry_events
WHERE session_id IS NOT NULL AND session_id <> ''
  AND app = 'photo-recipes'
  AND created_at >= FROM_UNIXTIME(?)   -- PT midnight of the first day in the window
  AND created_at <  FROM_UNIXTIME(?);  -- PT midnight today (exclusive)
```

Conversions are stage-to-stage ratios of these counts
(`camera_open / sessions`, `auto_optimize_start / camera_open`,
`auto_optimize_success / auto_optimize_start`).

## Alternate cuts — NOT the canonical funnel

Everything below is an alternate cut, kept for the questions it answers
(landing behaviour, iOS-only capture, monetization, user-level activity).
Each uses a different unit (raw event counts and/or distinct `anon_id`),
and/or a rolling `NOW() - INTERVAL` window in server time instead of
complete PT calendar days. Numbers from these cuts must be labelled with
their cut when reported and must never be compared against, or substituted
for, the canonical funnel above. All cuts in this doc are scoped to
`app = 'photo-recipes'`, same as the canonical funnel.

### A1. Web activation (alternate cut: raw counts + distinct anon_id, rolling 7 days)

Landing → Camera CTA → camera_open → auto_optimize_success

```sql
SELECT event, COUNT(*) AS c, COUNT(DISTINCT anon_id) AS users
FROM telemetry_events
WHERE created_at >= (NOW(3) - INTERVAL 7 DAY)
  AND app = 'photo-recipes'
  AND event IN (
    'landing_view','landing_cta_camera','camera_open',
    'auto_optimize_start','auto_optimize_success'
  )
GROUP BY event
ORDER BY FIELD(event,
  'landing_view','landing_cta_camera','camera_open',
  'auto_optimize_start','auto_optimize_success');
```

### A2. iOS capture (alternate cut: raw counts + distinct anon_id, iOS only, rolling 7 days)

camera_open → auto_optimize_success → capture_success

```sql
SELECT event, COUNT(*) AS c, COUNT(DISTINCT anon_id) AS users
FROM telemetry_events
WHERE created_at >= (NOW(3) - INTERVAL 7 DAY)
  AND platform = 'ios'
  AND app = 'photo-recipes'
  AND event IN ('camera_open','auto_optimize_success','capture_success')
GROUP BY event
ORDER BY FIELD(event,'camera_open','auto_optimize_success','capture_success');
```

### A3. Monetization by plan (alternate cut — a different funnel, not the product funnel)

Steps (same order as `GET /api/telemetry/funnels` → `funnels.monetization`):
`paywall_view` → `paywall_dismiss` | `paywall_plan_select` → `purchase_start` →
`purchase_cancelled` | `purchase_pending` | `purchase_failed` | `purchase_success`
(`checkout_redirect` = web Stripe; `purchase_fail` = legacy iOS ≤ 1.4, replaced by `purchase_failed`).

**Purchases are telemetry events, not sales.** `purchase_success` counts here
are first-party telemetry events (iOS rows carry props `source=storekit`; the
funnels API also splits them by source in
`funnels.purchase_success_by_source`). Web Stripe sales do not emit
`purchase_success` into telemetry, so they are never counted in this cut.
App Store Connect is the sales ledger for StoreKit purchases and Stripe is
the ledger for web sales — never quote a telemetry purchase count as total
sales.

iOS event props (all strings):

| event | props |
|---|---|
| `paywall_dismiss` | `paywall_type` (soft/hard/settings/upgrade), `mode`, `paywall_trigger` (trigger source), `action` (keep_free/close/swipe), `time_on_screen_ms`, `plan` (selected plan or `none`), `free_tries_left` (`unlimited` for Pro), `source=ios_sheet` |
| `purchase_cancelled` | StoreKit 2 `.userCancelled` — `plan`, `product_id`, `source=storekit` |
| `purchase_pending` | StoreKit 2 `.pending` (Ask to Buy / SCA) — `plan`, `product_id`, `source=storekit` |
| `purchase_failed` | thrown error or verification failure — `plan`, `product_id`, `error_domain`, `error_code`, `stage` (purchase/verification), `source=storekit` |

```sql
SELECT
  COALESCE(JSON_UNQUOTE(JSON_EXTRACT(props_json,'$.plan')),'unknown') AS plan,
  SUM(event='paywall_view') AS paywall_view,
  SUM(event='paywall_dismiss') AS paywall_dismiss,
  SUM(event='purchase_start') AS purchase_start,
  SUM(event='purchase_cancelled') AS purchase_cancelled,
  SUM(event='purchase_pending') AS purchase_pending,
  SUM(event IN ('purchase_failed','purchase_fail')) AS purchase_failed,
  SUM(event='checkout_redirect') AS checkout_redirect,
  SUM(event='purchase_success') AS purchase_success
FROM telemetry_events
WHERE created_at >= (NOW(3) - INTERVAL 7 DAY)
  AND app = 'photo-recipes'
  AND event IN ('paywall_view','paywall_dismiss','paywall_plan_select','purchase_start',
    'purchase_cancelled','purchase_pending','purchase_failed','purchase_fail',
    'checkout_redirect','purchase_success')
GROUP BY plan;
```

Paywall dismiss breakdown:

```sql
SELECT JSON_UNQUOTE(JSON_EXTRACT(props_json,'$.paywall_type')) AS paywall_type,
  COUNT(*) AS dismisses, COUNT(DISTINCT anon_id) AS users,
  ROUND(AVG(CAST(JSON_UNQUOTE(JSON_EXTRACT(props_json,'$.time_on_screen_ms')) AS UNSIGNED))) AS avg_ms
FROM telemetry_events
WHERE created_at >= (NOW(3) - INTERVAL 7 DAY) AND event = 'paywall_dismiss'
  AND app = 'photo-recipes'
GROUP BY paywall_type;
```

### A4. DAU / WAU (alternate cut: user-level, distinct anon_id)

```sql
SELECT COUNT(DISTINCT anon_id) AS dau
FROM telemetry_events
WHERE created_at >= (NOW(3) - INTERVAL 1 DAY) AND app = 'photo-recipes';

SELECT COUNT(DISTINCT anon_id) AS wau
FROM telemetry_events
WHERE created_at >= (NOW(3) - INTERVAL 7 DAY) AND app = 'photo-recipes';
```

### A5. Step drop-off counts (alternate cuts only)

Use the step counts from alternate cut A1 for A1's own drop-off
(≈ `1 - users_B/users_A`). Do not compute canonical-funnel drop-off from A1 —
use the canonical counts above.

Also: `scripts/funnel-report.sql` and `scripts/funnel-report.mjs` (both put
the canonical funnel first, then the alternate cuts, labelled as such; the
`.sql` canonical query takes its PT-midnight bounds from caller-set
`@canonical_start` / `@canonical_end`, as its header explains).
