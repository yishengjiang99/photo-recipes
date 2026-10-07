/**
 * telemetry_events schema ensure — runs at API boot (idempotent, safe to re-run).
 * Inlined because prod runs the esbuild bundle (server-dist/) without migrations/.
 * Mirrors migrations/001_telemetry_events.sql (table) and
 * migrations/003_telemetry_created_index.sql (created_at index on older tables).
 * Never drops or rewrites data: CREATE TABLE IF NOT EXISTS + conditional ADD INDEX.
 */
import type { Pool, RowDataPacket } from 'mysql2/promise'
import { getMysqlPool } from './mysql.ts'

export const TELEMETRY_TABLE_DDL = `CREATE TABLE IF NOT EXISTS telemetry_events (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`

export const TELEMETRY_CREATED_INDEX = 'idx_telemetry_created'
export const TELEMETRY_CREATED_INDEX_DDL =
  'ALTER TABLE telemetry_events ADD INDEX idx_telemetry_created (created_at), ALGORITHM=INPLACE, LOCK=NONE'

/** MySQL ER_DUP_KEYNAME — another process added the index first. */
const ER_DUP_KEYNAME = 1061

export async function ensureTelemetrySchemaWith(pool: Pick<Pool, 'query'>): Promise<{
  ok: boolean
  indexAdded: boolean
}> {
  try {
    await pool.query(TELEMETRY_TABLE_DDL)
    const [rows] = await pool.query<RowDataPacket[]>(
      `SELECT COUNT(*) AS n FROM information_schema.statistics
       WHERE table_schema = DATABASE()
         AND table_name = 'telemetry_events'
         AND index_name = ?`,
      [TELEMETRY_CREATED_INDEX],
    )
    if (Number(rows[0]?.n) > 0) return { ok: true, indexAdded: false }
    try {
      await pool.query(TELEMETRY_CREATED_INDEX_DDL)
      return { ok: true, indexAdded: true }
    } catch (err) {
      if ((err as { errno?: number }).errno === ER_DUP_KEYNAME) {
        return { ok: true, indexAdded: false }
      }
      throw err
    }
  } catch (err) {
    console.warn(
      '[telemetry] schema ensure failed:',
      err instanceof Error ? err.message : err,
    )
    return { ok: false, indexAdded: false }
  }
}

export async function ensureTelemetrySchema() {
  const pool = getMysqlPool()
  if (!pool) return { ok: false, indexAdded: false }
  return ensureTelemetrySchemaWith(pool)
}
