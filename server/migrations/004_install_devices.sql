-- One row per telemetry install (anon_id × app × platform). Named install_devices
-- because `devices` already exists for APNs push registration (002).
-- Backfilled (idempotently) from telemetry_events at every API boot; upserted on every
-- POST /api/telemetry. Also applied at boot by server/installDevices.ts (keep in sync).
CREATE TABLE IF NOT EXISTS install_devices (
  anon_id VARCHAR(64) NOT NULL,
  app VARCHAR(64) NOT NULL,
  platform VARCHAR(32) NOT NULL,
  first_seen_at TIMESTAMP(3) NOT NULL,
  last_seen_at TIMESTAMP(3) NOT NULL,
  first_app_version VARCHAR(32) NULL,
  latest_app_version VARCHAR(32) NULL,
  first_build VARCHAR(32) NULL,
  latest_build VARCHAR(32) NULL,
  device_model VARCHAR(64) NULL,
  os_version VARCHAR(32) NULL,
  source VARCHAR(64) NULL,
  is_test TINYINT(1) NOT NULL DEFAULT 0,
  event_count INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (anon_id, app, platform),
  KEY idx_install_devices_first (first_seen_at),
  KEY idx_install_devices_last (last_seen_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
