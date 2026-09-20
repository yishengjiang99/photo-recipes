-- Devices + APNs push tokens (guest-scoped; no users table).
-- Apply when MYSQL_* is configured. CREATE IF NOT EXISTS is a no-op if tables exist.

CREATE TABLE IF NOT EXISTS devices (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  guest_id VARCHAR(64) NOT NULL,
  platform VARCHAR(16) NOT NULL DEFAULT 'ios',
  bundle_id VARCHAR(128) NULL,
  app_version VARCHAR(32) NULL,
  created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  UNIQUE KEY uq_devices_guest_platform (guest_id, platform),
  KEY idx_devices_guest (guest_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS push_tokens (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  device_id BIGINT UNSIGNED NOT NULL,
  token VARCHAR(255) NOT NULL,
  environment ENUM('sandbox', 'production') NOT NULL,
  app_version VARCHAR(32) NULL,
  last_seen_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  UNIQUE KEY uq_push_tokens_token (token),
  KEY idx_push_tokens_device (device_id),
  KEY idx_push_tokens_env (environment),
  CONSTRAINT fk_push_tokens_device
    FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
