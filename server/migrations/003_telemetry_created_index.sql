-- Index on telemetry_events.created_at for time-window queries (admin
-- hourly/daily active-user histograms, KPIs). Prod's table predates 001 and
-- only had (event, created_at) / (anon_id, created_at).
-- Idempotent + safe to re-run: MySQL 8 has no ADD INDEX IF NOT EXISTS, so check
-- information_schema and run a no-op when the index already exists.
-- Online DDL: ALGORITHM=INPLACE, LOCK=NONE (no write lock on InnoDB).
-- Also applied at API boot by server/telemetrySchema.ts (server-dist does not
-- ship migrations/); keep the two in sync (telemetrySchema.test.ts).

SET @idx_exists := (
  SELECT COUNT(*) FROM information_schema.statistics
  WHERE table_schema = DATABASE()
    AND table_name = 'telemetry_events'
    AND index_name = 'idx_telemetry_created'
);
SET @ddl := IF(
  @idx_exists = 0,
  'ALTER TABLE telemetry_events ADD INDEX idx_telemetry_created (created_at), ALGORITHM=INPLACE, LOCK=NONE',
  'DO 0'
);
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
