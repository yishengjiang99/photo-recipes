/**
 * MySQL-backed devices + push_tokens (dual-write with push-prefs.json).
 * Soft no-op when MYSQL_* unset or pool unavailable — never throw to callers.
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import type { Pool, ResultSetHeader, RowDataPacket } from 'mysql2/promise'
import { getMysqlPool } from './mysql.ts'
import type { ApnsDeviceToken, ApnsEnvironment } from './pushPrefs.ts'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const MIGRATION_PATH = path.join(
  __dirname,
  'migrations',
  '002_devices_push_tokens.sql',
)

let schemaReady: Promise<boolean> | null = null

async function ensureSchema(pool: Pool): Promise<boolean> {
  if (!schemaReady) {
    schemaReady = (async () => {
      try {
        const sql = fs.readFileSync(MIGRATION_PATH, 'utf8')
        // mysql2 does not run multi-statements by default — split on ;\n
        const stmts = sql
          .split(/;\s*\n/)
          .map((s) => s.trim())
          .filter((s) => s.length > 0 && !s.startsWith('--'))
        for (const stmt of stmts) {
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
