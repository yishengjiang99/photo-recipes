/**
 * MySQL-backed devices + push_tokens (dual-write with push-prefs.json).
 * Soft no-op when MYSQL_* unset or pool unavailable — never throw to callers.
 */
import type { Pool, ResultSetHeader, RowDataPacket } from 'mysql2/promise'
import { getMysqlPool } from './mysql.ts'
import type { ApnsDeviceToken, ApnsEnvironment } from './pushPrefs.ts'

/**
 * DDL inlined (mirrors server/migrations/002_devices_push_tokens.sql).
 * Prod runs the esbuild bundle from server-dist/, which never shipped the
 * migrations/ folder → ENOENT at boot and the MySQL dual-write never ran.
 * Keep in sync with the .sql file (pushDevices.test.ts asserts parity).
 */
export const PUSH_DEVICES_DDL: readonly string[] = [
  `CREATE TABLE IF NOT EXISTS devices (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  guest_id VARCHAR(64) NOT NULL,
  platform VARCHAR(16) NOT NULL DEFAULT 'ios',
  bundle_id VARCHAR(128) NULL,
  app_version VARCHAR(32) NULL,
  created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  UNIQUE KEY uq_devices_guest_platform (guest_id, platform),
  KEY idx_devices_guest (guest_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
  `CREATE TABLE IF NOT EXISTS push_tokens (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
]

/**
 * Split a .sql migration into statements: drop `--` comment lines first
 * (the old filter dropped any chunk that *started* with a comment, which
 * silently skipped CREATE TABLE devices).
 */
export function splitSqlStatements(sql: string): string[] {
  return sql
    .split('\n')
    .filter((line) => !line.trim().startsWith('--'))
    .join('\n')
    .split(/;\s*(?:\n|$)/)
    .map((s) => s.trim())
    .filter((s) => s.length > 0)
}

let schemaReady: Promise<boolean> | null = null

async function ensureSchema(pool: Pool): Promise<boolean> {
  if (!schemaReady) {
    schemaReady = (async () => {
      try {
        for (const stmt of PUSH_DEVICES_DDL) {
          await pool.query(stmt)
        }
        return true
      } catch (err) {
        console.warn(
          '[pushDevices] schema ensure failed:',
          err instanceof Error ? err.message : err,
        )
        schemaReady = null
        return false
      }
    })()
  }
  return schemaReady
}

export type UpsertPushDeviceInput = {
  guestId: string
  platform: 'ios'
  bundleId: string
  environment: ApnsEnvironment
  token: string
  appVersion?: string
}

/**
 * Upsert device by (guest_id, platform) and push_token by unique token.
 * Returns false if MySQL unavailable or write failed (caller should ignore).
 */
export async function upsertDeviceAndPushToken(
  input: UpsertPushDeviceInput,
): Promise<boolean> {
  const pool = getMysqlPool()
  if (!pool) return false
  if (!(await ensureSchema(pool))) return false

  const token = input.token.trim().toLowerCase()
  const appVersion = input.appVersion?.trim() || null

  try {
    const [devResult] = await pool.query<ResultSetHeader>(
      `INSERT INTO devices (guest_id, platform, bundle_id, app_version)
       VALUES (?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         bundle_id = VALUES(bundle_id),
         app_version = COALESCE(VALUES(app_version), app_version),
         updated_at = CURRENT_TIMESTAMP(3)`,
      [input.guestId, input.platform, input.bundleId, appVersion],
    )

    let deviceId = Number(devResult.insertId)
    if (!deviceId) {
      const [rows] = await pool.query<RowDataPacket[]>(
        `SELECT id FROM devices WHERE guest_id = ? AND platform = ? LIMIT 1`,
        [input.guestId, input.platform],
      )
      deviceId = Number(rows[0]?.id ?? 0)
    }
    if (!deviceId) {
      console.warn('[pushDevices] device id missing after upsert')
      return false
    }

    // If this token was on another device, move it (UNIQUE token).
    await pool.query<ResultSetHeader>(
      `INSERT INTO push_tokens (device_id, token, environment, app_version, last_seen_at)
       VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP(3))
       ON DUPLICATE KEY UPDATE
         device_id = VALUES(device_id),
         environment = VALUES(environment),
         app_version = COALESCE(VALUES(app_version), app_version),
         last_seen_at = CURRENT_TIMESTAMP(3),
         updated_at = CURRENT_TIMESTAMP(3)`,
      [deviceId, token, input.environment, appVersion],
    )
    return true
  } catch (err) {
    console.warn(
      '[pushDevices] upsert failed:',
      err instanceof Error ? err.message : err,
    )
    return false
  }
}

/** Tokens for a guest from MySQL (empty if unset/error). */
export async function listPushTokensForGuest(
  guestId: string,
): Promise<ApnsDeviceToken[]> {
  const pool = getMysqlPool()
  if (!pool) return []
  if (!(await ensureSchema(pool))) return []

  try {
    const [rows] = await pool.query<RowDataPacket[]>(
      `SELECT d.bundle_id AS bundleId, d.platform AS platform,
              t.token AS token, t.environment AS environment,
              t.app_version AS appVersion, t.updated_at AS updatedAt
       FROM push_tokens t
       INNER JOIN devices d ON d.id = t.device_id
       WHERE d.guest_id = ?`,
      [guestId],
    )
    return rows.map((r) => ({
      token: String(r.token),
      platform: 'ios' as const,
      bundleId: String(r.bundleId || 'com.ragnus.mvp'),
      environment: (r.environment === 'production'
        ? 'production'
        : 'sandbox') as ApnsEnvironment,
      ...(r.appVersion ? { appVersion: String(r.appVersion) } : {}),
      updatedAt: new Date(r.updatedAt as Date).toISOString(),
    }))
  } catch (err) {
    console.warn(
      '[pushDevices] list failed:',
      err instanceof Error ? err.message : err,
    )
    return []
  }
}

/** Remove one token (only if it belongs to this guest). Soft-fail → false. */
export async function deletePushTokenForGuest(
  guestId: string,
  token: string,
): Promise<boolean> {
  const pool = getMysqlPool()
  if (!pool) return false
  if (!(await ensureSchema(pool))) return false
  try {
    await pool.query<ResultSetHeader>(
      `DELETE t FROM push_tokens t
       INNER JOIN devices d ON d.id = t.device_id
       WHERE d.guest_id = ? AND t.token = ?`,
      [guestId, token.trim().toLowerCase()],
    )
    return true
  } catch (err) {
    console.warn(
      '[pushDevices] delete failed:',
      err instanceof Error ? err.message : err,
    )
    return false
  }
}

/** Remove a token everywhere (APNs said BadDeviceToken / Unregistered). */
export async function deletePushTokenEverywhere(token: string): Promise<boolean> {
  const pool = getMysqlPool()
  if (!pool) return false
  if (!(await ensureSchema(pool))) return false
  try {
    await pool.query<ResultSetHeader>(`DELETE FROM push_tokens WHERE token = ?`, [
      token.trim().toLowerCase(),
    ])
    return true
  } catch (err) {
    console.warn(
      '[pushDevices] delete-all failed:',
      err instanceof Error ? err.message : err,
    )
    return false
  }
}

/**
 * Merge JSON tokens with MySQL tokens (MySQL wins on same token hex).
 */
export function mergeApnsTokens(
  fromJson: ApnsDeviceToken[],
  fromMysql: ApnsDeviceToken[],
): ApnsDeviceToken[] {
  const map = new Map<string, ApnsDeviceToken>()
  for (const t of fromJson) map.set(t.token.toLowerCase(), t)
  for (const t of fromMysql) map.set(t.token.toLowerCase(), t)
  return [...map.values()]
}

/** Boot helper — create devices/push_tokens if MySQL is configured. */
export async function ensurePushDevicesSchema(): Promise<boolean> {
  const pool = getMysqlPool()
  if (!pool) return false
  return ensureSchema(pool)
}
