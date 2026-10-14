/**
 * install_devices — one row per telemetry install (anon_id × app × platform).
 * DDL mirrors migrations/004_install_devices.sql (server-dist ships no migrations/).
 * Source of truth for DAU identity, new-vs-returning and test-device exclusion.
 */
import type { Pool } from 'mysql2/promise'
import { getMysqlPool } from './mysql.ts'

export const INSTALL_DEVICES_DDL = `CREATE TABLE IF NOT EXISTS install_devices (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`

/** The primary product audience counted as "real users" on the admin. */
export const REAL_APP = 'photo-recipes'

/**
 * Test/dev heuristics:
 *  - server-side pseudo ids (server-api-error) or platform=server
 *  - iOS 1.2 build 50: the repo's default MARKETING_VERSION/CURRENT_PROJECT_VERSION
 *    (ios/project.yml) — only local/simulator builds report it; store builds are
 *    stamped by CI. It first appeared Oct 10, after 1.4(72) shipped.
 *  - ids listed in TELEMETRY_TEST_ANON_IDS (comma-separated)
 */
export function isTestInstall(r: {
  anonId: string
  platform: string
  appVersion?: string | null
  build?: string | null
}): boolean {
  if (r.platform === 'server' || r.anonId.startsWith('server-')) return true
  if (r.platform === 'ios' && r.appVersion === '1.2' && r.build === '50') return true
  const extra = (process.env.TELEMETRY_TEST_ANON_IDS || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)
  return extra.includes(r.anonId)
}

export const IS_TEST_SQL = `(platform = 'server' OR anon_id LIKE 'server-%'
  OR (platform = 'ios' AND first_app_version = '1.2' AND first_build = '50'))`

const s = (v: unknown, n: number) =>
  typeof v === 'string' && v.trim() ? v.trim().slice(0, n) : typeof v === 'number' ? String(v).slice(0, n) : null

export async function upsertInstallDevice(
  pool: Pick<Pool, 'execute'>,
  row: {
    anon_id: string
    app: string
    platform: string
    props: Record<string, string | number | boolean> | null
  },
): Promise<void> {
  const p = row.props ?? {}
  const ver = s(p.app_version, 32)
  const build = s(p.build, 32)
  const model = s(p.device_model, 64)
  const os = s(p.os_version ?? p.ios_version, 32)
  const source = s(p.attribution_source ?? p.utm_source ?? p['ad-network-id'], 64)
  const test = isTestInstall({ anonId: row.anon_id, platform: row.platform, appVersion: ver, build }) ? 1 : 0
  await pool.execute(
    `INSERT INTO install_devices
       (anon_id, app, platform, first_seen_at, last_seen_at, first_app_version, latest_app_version,
        first_build, latest_build, device_model, os_version, source, is_test, event_count)
     VALUES (?, ?, ?, NOW(3), NOW(3), ?, ?, ?, ?, ?, ?, ?, ?, 1)
     ON DUPLICATE KEY UPDATE
       last_seen_at = NOW(3),
       first_app_version = COALESCE(first_app_version, VALUES(first_app_version)),
       first_build = COALESCE(first_build, VALUES(first_build)),
       latest_app_version = COALESCE(VALUES(latest_app_version), latest_app_version),
       latest_build = COALESCE(VALUES(latest_build), latest_build),
       device_model = COALESCE(VALUES(device_model), device_model),
       os_version = COALESCE(VALUES(os_version), os_version),
       source = COALESCE(source, VALUES(source)),
       is_test = GREATEST(is_test, VALUES(is_test)),
       event_count = event_count + 1`,
    [row.anon_id, row.app, row.platform, ver, ver, build, build, model, os, source, test],
  )
}

const BACKFILL_SQL = `INSERT INTO install_devices
  (anon_id, app, platform, first_seen_at, last_seen_at, first_app_version, latest_app_version,
   first_build, latest_build, device_model, os_version, source, is_test, event_count)
SELECT anon_id, app, platform, MIN(created_at), MAX(created_at),
  SUBSTRING_INDEX(MIN(CONCAT(DATE_FORMAT(created_at, '%Y%m%d%H%i%s%f'), '|', app_version)), '|', -1),
  SUBSTRING_INDEX(MAX(CONCAT(DATE_FORMAT(created_at, '%Y%m%d%H%i%s%f'), '|', app_version)), '|', -1),
  SUBSTRING_INDEX(MIN(CONCAT(DATE_FORMAT(created_at, '%Y%m%d%H%i%s%f'), '|', JSON_UNQUOTE(JSON_EXTRACT(props_json, '$.build')))), '|', -1),
  SUBSTRING_INDEX(MAX(CONCAT(DATE_FORMAT(created_at, '%Y%m%d%H%i%s%f'), '|', JSON_UNQUOTE(JSON_EXTRACT(props_json, '$.build')))), '|', -1),
  LEFT(MAX(JSON_UNQUOTE(JSON_EXTRACT(props_json, '$.device_model'))), 64),
  LEFT(MAX(JSON_UNQUOTE(JSON_EXTRACT(props_json, '$.os_version'))), 32),
  NULL, 0, COUNT(*)
FROM telemetry_events
GROUP BY anon_id, app, platform
ON DUPLICATE KEY UPDATE
  first_seen_at = LEAST(install_devices.first_seen_at, VALUES(first_seen_at)),
  last_seen_at = GREATEST(install_devices.last_seen_at, VALUES(last_seen_at)),
  first_app_version = VALUES(first_app_version),
  first_build = VALUES(first_build),
  latest_app_version = COALESCE(install_devices.latest_app_version, VALUES(latest_app_version)),
  latest_build = COALESCE(install_devices.latest_build, VALUES(latest_build)),
  device_model = COALESCE(install_devices.device_model, VALUES(device_model)),
  os_version = COALESCE(install_devices.os_version, VALUES(os_version)),
  event_count = GREATEST(install_devices.event_count, VALUES(event_count))`

export async function ensureInstallDevicesWith(
  pool: Pick<Pool, 'query'>,
): Promise<{ ok: boolean; backfilled: number }> {
  try {
    await pool.query(INSTALL_DEVICES_DDL)
    // Idempotent: recomputes aggregates from telemetry_events every boot (small table).
    const [res] = (await pool.query(BACKFILL_SQL)) as unknown as [{ affectedRows?: number }]
    await pool.query(`UPDATE install_devices SET is_test = 1 WHERE ${IS_TEST_SQL}`)
    return { ok: true, backfilled: Number(res?.affectedRows) || 0 }
  } catch (err) {
    console.warn('[install_devices] ensure failed:', err instanceof Error ? err.message : err)
    return { ok: false, backfilled: 0 }
  }
}

export async function ensureInstallDevices() {
  const pool = getMysqlPool()
  if (!pool) return { ok: false, backfilled: 0 }
  return ensureInstallDevicesWith(pool)
}

export type DevicesSummary = {
  timezone: string
  definition: string
  totals: { real: number; test: number; realIos: number; realWeb: number; otherApps: number }
  today: { day: string; active: number; newInstalls: number; returning: number }
  newPerDay: Array<{ day: string; newInstalls: number }>
  recent: Array<{
    anonId: string
    app: string
    platform: string
    firstSeenAt: string
    lastSeenAt: string
    firstVersion: string | null
    latestVersion: string | null
    build: string | null
    deviceModel: string | null
    source: string | null
    isTest: boolean
    events: number
  }>
  error?: string
}

/** PT day helpers are passed in to avoid a circular import with telemetry.ts. */
export async function fetchDevicesSummary(opts: {
  dayBuckets: (days: number) => number[]
  ptOffsetSec: (tsSec: number) => number
  days?: number
}): Promise<DevicesSummary> {
  const days = opts.days ?? 14
  const buckets = opts.dayBuckets(days)
  const today = buckets[buckets.length - 1]!
  const dayStr = (b: number) => new Date(b * 1000).toISOString().slice(0, 10)
  const empty: DevicesSummary = {
    timezone: 'America/Los_Angeles',
    definition:
      'One row per install (anon_id × app × platform) in install_devices. New = first_seen_at on that PT day. Real = app photo-recipes, is_test=0 (excludes server pseudo-ids and 1.2(50) dev builds). anon_id resets on reinstall, so a reinstall counts as a new install.',
    totals: { real: 0, test: 0, realIos: 0, realWeb: 0, otherApps: 0 },
    today: { day: dayStr(today), active: 0, newInstalls: 0, returning: 0 },
    newPerDay: buckets.map((b) => ({ day: dayStr(b), newInstalls: 0 })),
    recent: [],
  }
  const pool = getMysqlPool()
  if (!pool) return empty
  const startSec = (b: number) => b - opts.ptOffsetSec(b + 12 * 3600)
  try {
    const [[t]] = (await pool.query(
      `SELECT
         SUM(app = ? AND is_test = 0) AS real_n,
         SUM(is_test = 1) AS test_n,
         SUM(app = ? AND is_test = 0 AND platform = 'ios') AS real_ios,
         SUM(app = ? AND is_test = 0 AND platform = 'web') AS real_web,
         SUM(app <> ? AND is_test = 0) AS other_apps
       FROM install_devices`,
      [REAL_APP, REAL_APP, REAL_APP, REAL_APP],
    )) as unknown as [Array<Record<string, number>>]
    const newPerDay = await Promise.all(
      buckets.map(async (b) => {
        const [[r]] = (await pool.query(
          `SELECT COUNT(*) AS n FROM install_devices
           WHERE app = ? AND platform = 'ios' AND is_test = 0
             AND first_seen_at >= FROM_UNIXTIME(?) AND first_seen_at < FROM_UNIXTIME(?)`,
          [REAL_APP, startSec(b), startSec(b + 86400)],
        )) as unknown as [Array<{ n: number }>]
        return { day: dayStr(b), newInstalls: Number(r?.n) || 0 }
      }),
    )
    const [[a]] = (await pool.query(
      `SELECT COUNT(*) AS active,
              SUM(first_seen_at >= FROM_UNIXTIME(?)) AS new_n
       FROM install_devices
       WHERE app = ? AND platform = 'ios' AND is_test = 0 AND last_seen_at >= FROM_UNIXTIME(?)`,
      [startSec(today), REAL_APP, startSec(today)],
    )) as unknown as [Array<{ active: number; new_n: number }>]
    const [recentRows] = await pool.query(
      `SELECT anon_id, app, platform, first_seen_at, last_seen_at, first_app_version,
              latest_app_version, latest_build, device_model, source, is_test, event_count
       FROM install_devices ORDER BY first_seen_at DESC LIMIT 40`,
    )
    const iso = (v: unknown) => (v instanceof Date ? v.toISOString() : String(v))
    const active = Number(a?.active) || 0
    const newN = Number(a?.new_n) || 0
    return {
      ...empty,
      totals: {
        real: Number(t?.real_n) || 0,
        test: Number(t?.test_n) || 0,
        realIos: Number(t?.real_ios) || 0,
        realWeb: Number(t?.real_web) || 0,
        otherApps: Number(t?.other_apps) || 0,
      },
      today: { day: dayStr(today), active, newInstalls: newN, returning: Math.max(0, active - newN) },
      newPerDay,
      recent: (recentRows as Array<Record<string, unknown>>).map((r) => ({
        anonId: String(r.anon_id).slice(0, 8),
        app: String(r.app),
        platform: String(r.platform),
        firstSeenAt: iso(r.first_seen_at),
        lastSeenAt: iso(r.last_seen_at),
        firstVersion: (r.first_app_version as string) ?? null,
        latestVersion: (r.latest_app_version as string) ?? null,
        build: (r.latest_build as string) ?? null,
        deviceModel: (r.device_model as string) ?? null,
        source: (r.source as string) ?? null,
        isTest: Number(r.is_test) === 1,
        events: Number(r.event_count) || 0,
      })),
    }
  } catch (err) {
    console.warn('[install_devices] summary failed:', err instanceof Error ? err.message : err)
    return { ...empty, error: 'query_failed' }
  }
}
