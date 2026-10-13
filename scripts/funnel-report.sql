-- Funnel snapshot (7 days). Run: mysql … < scripts/funnel-report.sql

SELECT 'web_activation' AS funnel, event, COUNT(*) AS c, COUNT(DISTINCT anon_id) AS users
FROM telemetry_events
WHERE created_at >= (NOW(3) - INTERVAL 7 DAY)
  AND event IN ('landing_view','landing_cta_camera','camera_open','auto_optimize_start','auto_optimize_success')
GROUP BY event;

SELECT 'ios_capture' AS funnel, event, COUNT(*) AS c, COUNT(DISTINCT anon_id) AS users
FROM telemetry_events
WHERE created_at >= (NOW(3) - INTERVAL 7 DAY) AND platform='ios'
  AND event IN ('camera_open','auto_optimize_success','capture_success')
GROUP BY event;

SELECT 'monetization' AS funnel,
  COALESCE(JSON_UNQUOTE(JSON_EXTRACT(props_json,'$.plan')),'unknown') AS plan,
  SUM(event='paywall_view') AS paywall_view,
  SUM(event='paywall_dismiss') AS paywall_dismiss,
  SUM(event='purchase_start') AS purchase_start,
  SUM(event='purchase_cancelled') AS purchase_cancelled,
  SUM(event='purchase_pending') AS purchase_pending,
  SUM(event IN ('purchase_failed','purchase_fail')) AS purchase_failed,
  SUM(event='purchase_success') AS purchase_success
FROM telemetry_events
WHERE created_at >= (NOW(3) - INTERVAL 7 DAY)
  AND event IN ('paywall_view','paywall_dismiss','paywall_plan_select','purchase_start',
    'purchase_cancelled','purchase_pending','purchase_failed','purchase_fail',
    'checkout_redirect','purchase_success')
GROUP BY plan;

SELECT 'paywall_dismiss' AS funnel,
  JSON_UNQUOTE(JSON_EXTRACT(props_json,'$.paywall_type')) AS paywall_type,
  COUNT(*) AS c, COUNT(DISTINCT anon_id) AS users
FROM telemetry_events
WHERE created_at >= (NOW(3) - INTERVAL 7 DAY) AND event = 'paywall_dismiss'
GROUP BY paywall_type;

SELECT COUNT(DISTINCT anon_id) AS dau FROM telemetry_events WHERE created_at >= (NOW(3) - INTERVAL 1 DAY);
SELECT COUNT(DISTINCT anon_id) AS wau FROM telemetry_events WHERE created_at >= (NOW(3) - INTERVAL 7 DAY);
