-- In-house funnel telemetry (matches production photo_recipes.telemetry_events).
-- Apply when MYSQL_* is configured. CREATE IF NOT EXISTS is a no-op if table exists.

CREATE TABLE IF NOT EXISTS telemetry_events (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  received_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  app VARCHAR(64) NOT NULL DEFAULT 'grepawk-photos',
  platform VARCHAR(32) NOT NULL,
  event VARCHAR(64) NOT NULL,
  anon_id VARCHAR(64) NOT NULL,
  session_id VARCHAR(64) NULL,
  app_version VARCHAR(32) NULL,
  props_json JSON NULL,
  ip_hash CHAR(64) NULL,
  KEY idx_telemetry_created (created_at),
  KEY idx_telemetry_event (event),
  KEY idx_telemetry_anon (anon_id),
  KEY idx_telemetry_session (session_id),
  KEY idx_telemetry_platform_event (platform, event)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
