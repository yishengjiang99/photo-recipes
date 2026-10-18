-- Funnel snapshot. Run: mysql … < scripts/funnel-report.sql
-- Canonical ProTune funnel (THE funnel; see docs/telemetry-funnels.md):
-- unit = distinct session_id; stages = sessions (any event) -> camera_open ->
-- auto_optimize_start -> auto_optimize_success; window = trailing complete
-- days, America/Los_Angeles. @canonical_start / @canonical_end MUST be set by
-- the caller to the epoch seconds of the PT midnights bounding the trailing
-- complete days (e.g. via `mysql --init-command="SET @canonical_start=…, @canonical_end=…"`,
-- using the windowStart/windowEndExclusive values from GET /api/telemetry/funnels,
-- which computes PT midnights in Node — production MySQL has no tz tables).
-- Left unset, the canonical query below returns no rows rather than a
-- wrong-timezone number.

SELECT 'canonical' AS funnel,
  COUNT(DISTINCT session_id) AS sessions,
  COUNT(DISTINCT IF(event='camera_open', session_id, NULL)) AS camera_open,
  COUNT(DISTINCT IF(event='auto_optimize_start', session_id, NULL)) AS auto_optimize_start,
  COUNT(DISTINCT IF(event='auto_optimize_success', session_id, NULL)) AS auto_optimize_success
FROM telemetry_events
WHERE session_id IS NOT NULL AND session_id <> ''
  AND created_at >= FROM_UNIXTIME(@canonical_start)
  AND created_at < FROM_UNIXTIME(@canonical_end);

-- Alternate cuts below — NOT the canonical funnel (raw counts / distinct
-- anon_id, rolling 7-day window). Do not compare them against canonical.

SELECT 'web_activation (alternate)' AS funnel, event, COUNT(*) AS c, COUNT(DISTINCT anon_id) AS users
FROM telemetry_events
WHERE created_at >= (NOW(3) - INTERVAL 7 DAY)
  AND event IN ('landing_view','landing_cta_camera','camera_open','auto_optimize_start','auto_optimize_success')
GROUP BY event;

SELECT 'ios_capture (alternate)' AS funnel, event, COUNT(*) AS c, COUNT(DISTINCT anon_id) AS users
FROM telemetry_events
WHERE created_at >= (NOW(3) - INTERVAL 7 DAY) AND platform='ios'
  AND event IN ('camera_open','auto_optimize_success','capture_success')
GROUP BY event;

SELECT 'monetization (alternate)' AS funnel,
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

SELECT 'paywall_dismiss (alternate)' AS funnel,
  JSON_UNQUOTE(JSON_EXTRACT(props_json,'$.paywall_type')) AS paywall_type,
  COUNT(*) AS c, COUNT(DISTINCT anon_id) AS users
FROM telemetry_events
WHERE created_at >= (NOW(3) - INTERVAL 7 DAY) AND event = 'paywall_dismiss'
GROUP BY paywall_type;

-- Alternate cut: user-level DAU/WAU (distinct anon_id) — not the canonical funnel.
SELECT COUNT(DISTINCT anon_id) AS dau FROM telemetry_events WHERE created_at >= (NOW(3) - INTERVAL 1 DAY);
SELECT COUNT(DISTINCT anon_id) AS wau FROM telemetry_events WHERE created_at >= (NOW(3) - INTERVAL 7 DAY);
