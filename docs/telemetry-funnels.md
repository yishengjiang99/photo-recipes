# Funnel queries (7-day window)

Assumes table `telemetry_events` from `server/migrations/001_telemetry_events.sql`.

## 1. Web activation: Landing → Camera CTA → camera_open → auto_optimize_success

```sql
SELECT event, COUNT(*) AS c, COUNT(DISTINCT anon_id) AS users
FROM telemetry_events
WHERE created_at >= (NOW(3) - INTERVAL 7 DAY)
  AND event IN (
    'landing_view','landing_cta_camera','camera_open',
    'auto_optimize_start','auto_optimize_success'
  )
GROUP BY event
ORDER BY FIELD(event,
  'landing_view','landing_cta_camera','camera_open',
  'auto_optimize_start','auto_optimize_success');
```

## 2. iOS capture: camera_open → auto_optimize_success → capture_success

```sql
SELECT event, COUNT(*) AS c, COUNT(DISTINCT anon_id) AS users
FROM telemetry_events
WHERE created_at >= (NOW(3) - INTERVAL 7 DAY)
  AND platform = 'ios'
  AND event IN ('camera_open','auto_optimize_success','capture_success')
GROUP BY event
ORDER BY FIELD(event,'camera_open','auto_optimize_success','capture_success');
```

## 3. Monetization by plan

Steps (same order as `GET /api/telemetry/funnels` → `funnels.monetization`):
`paywall_view` → `paywall_dismiss` | `paywall_plan_select` → `purchase_start` →
`purchase_cancelled` | `purchase_pending` | `purchase_failed` | `purchase_success`
(`checkout_redirect` = web Stripe; `purchase_fail` = legacy iOS ≤ 1.4, replaced by `purchase_failed`).

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
GROUP BY paywall_type;
```

## 4. DAU / WAU (distinct anon_id)

```sql
SELECT COUNT(DISTINCT anon_id) AS dau
FROM telemetry_events WHERE created_at >= (NOW(3) - INTERVAL 1 DAY);

SELECT COUNT(DISTINCT anon_id) AS wau
FROM telemetry_events WHERE created_at >= (NOW(3) - INTERVAL 7 DAY);
```

## 5. Step drop-off counts (web activation)

Use the step counts from query (1). Drop-off from A→B ≈ `1 - users_B/users_A`.

Also: `scripts/funnel-report.sql` and `scripts/funnel-report.mjs`.
