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

```sql
SELECT
  COALESCE(JSON_UNQUOTE(JSON_EXTRACT(props_json,'$.plan')),'unknown') AS plan,
  SUM(event='paywall_view') AS paywall_view,
  SUM(event='purchase_start') AS purchase_start,
  SUM(event='checkout_redirect') AS checkout_redirect,
  SUM(event='purchase_success') AS purchase_success
FROM telemetry_events
WHERE created_at >= (NOW(3) - INTERVAL 7 DAY)
  AND event IN ('paywall_view','purchase_start','checkout_redirect','purchase_success','paywall_plan_select')
GROUP BY plan;
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
