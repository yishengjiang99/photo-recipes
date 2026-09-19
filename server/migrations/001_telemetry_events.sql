-- In-house product / funnel telemetry (privacy-first).
-- Apply when MYSQL_* is configured:
--   mysql "$MYSQL_DATABASE" < server/migrations/001_telemetry_events.sql

CREATE TABLE IF NOT EXISTS telemetry_events (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  ts TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  app VARCHAR(64) NOT NULL DEFAULT 'photo-recipes',
  platform VARCHAR(32) NOT NULL,
  event VARCHAR(64) NOT NULL,
  anon_id VARCHAR(64) NOT NULL,
  session_id VARCHAR(64) NULL,
  props JSON NULL,
  ip_hash CHAR(64) NULL,
  KEY idx_telemetry_ts (ts),
  KEY idx_telemetry_event (event),
  KEY idx_telemetry_anon (anon_id),
  KEY idx_telemetry_session (session_id),
  KEY idx_telemetry_platform_event (platform, event)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
