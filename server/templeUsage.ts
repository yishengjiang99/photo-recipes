/**
 * Temple of the High Priestess telemetry for the admin dashboard — derived
 * entirely from the Temple game's own database (see server/templeMysql.ts).
 * This is a SEPARATE data source from this app's telemetry_events and from
 * FinalCap's database: Temple never sends client events to the shared table;
 * its iOS app posts to temple-api, which stores them in the `temple` DB.
 * Never mix the sources in one figure.
 *
 * Metric definitions mirror temple-api's own /v1/admin/metrics endpoint
 * (server/src/iap.js in yishengjiang99/seal-of-the-high-priestess):
 * - Day keys are UTC dates (DATE(created_at); the droplet's MySQL session
 *   timezone is UTC, same as temple-api's own queries).
 * - The funnel is production-only by default: an event counts only when its
 *   props carry no env (session_start, region_complete) or env = 'production',
 *   AND its verified transaction env (props.txEnv, when present) is
 *   'production'. An App Store install signed into a sandbox tester still
 *   buys in Sandbox — the Nov 8 2026 $6.99 purchase was sandbox, and the
 *   funnel must never count it as revenue.
 * - Purchases / revenue come from the entitlements table (server-verified
 *   transactions), split by entitlements.environment ('Production' vs
 *   'Sandbox'). Revenue sums the price inside each stored signed transaction
 *   (JWS payload, same decode temple-api's priceTest uses) for production,
 *   non-revoked rows only. Sandbox rows are shown separately as test
 *   purchases, never as revenue.
 * - Only aggregates are returned. No player identifiers, install ids,
 *   secrets, tokens, or signed transactions ever leave the server: the
 *   recent-events list carries name / time / app version / props only.
 *
 * Read-only: every query below is a SELECT.
 */
import type mysql from 'mysql2/promise'
import { parseDaysParam, utcDayKeys } from './finalcapUsage.ts'
import { getTempleMysqlPool, isTempleMysqlConfigured } from './templeMysql.ts'

export const TEMPLE_DEFAULT_DAYS = 30
export const TEMPLE_MAX_DAYS = 90

/** Funnel steps in order, mirroring temple-api's funnel(). */
export const TEMPLE_FUNNEL_STEPS = [
  'session_start',
  'region_complete',
  'paywall_shown',
  'purchase_started',
  'purchase',
  'purchase_cancelled',
  'purchase_failed',
  'paywall_dismissed',
  'restore',
] as const

export interface TempleFunnelStep {
  name: string
  events: number
  players: number
  conversionFromPrev: number | null
}

export interface TemplePurchaseRow {
  product: string
  environment: string
  count: number
  revoked: number
  revenueUsd: number
}

export interface TemplePerfByMap {
  map: string
  samples: number
  medianFps: number | null
  medianMedMs: number | null
  medianP95Ms: number | null
}

export interface TempleTelemetry {
  configured: boolean
  days: number
  timezone: string
  generatedAt: string
  definitions: {
    installs: string
    sessions: string
    funnel: string
    purchases: string
    perf: string
    diagnostics: string
  }
  totals: {
    installs: number
    players: number
    eventsAllTime: number
    eventsInWindow: number
    sessionsInWindow: number
    dauInWindow: number
    purchasesProduction: number
    purchasesSandbox: number
    revenueUsd: number
    sandboxRevenueUsd: number
    cloudSavePlayers: number
    cloudSaveSlots: number
  }
  installsByDay: Array<{ day: string; installs: number }>
  installsByVersion: Array<{ version: string; devices: number }>
  dauByDay: Array<{ day: string; sessions: number; dau: number }>
  eventsByDay: Array<{ day: string; total: number }>
  eventsByName: Array<{ name: string; count: number }>
  funnel: TempleFunnelStep[]
  purchases: TemplePurchaseRow[]
  perf: {
    samples: number
    medianFps: number | null
    medianMedMs: number | null
    medianP95Ms: number | null
    byMap: TemplePerfByMap[]
  }
  diagnostics: Array<{ kind: string; count: number }>
  errorsByDay: Array<{ day: string; count: number }>
  errorKinds: Array<{ kind: string; count: number }>
  recentEvents: Array<{
    createdAt: string
    name: string
    appVersion: string | null
    props: string | null
  }>
  error?: string
}

const DEFINITIONS = {
  installs:
    'Devices ever registered in the temple DB (devices.created_at, UTC days); by version counts devices by app_version. Installs are cumulative — every row is a distinct install.',
  sessions:
    'Sessions = session_start events; DAU = distinct players in session_start per UTC day. session_start fires on launch and on foreground after 30+ min in the background.',
  funnel:
    "Production-only, mirroring temple-api's funnel(): session_start → region_complete → paywall_shown → purchase_started → purchase, plus cancelled / failed / dismissed / restore. An event counts only when props.env is absent or 'production' AND props.txEnv (when present) is 'production' — sandbox test purchases never enter the funnel.",
  purchases:
    'Verified purchases from the entitlements table (server-verified App Store transactions), split by entitlements.environment. Revenue sums the price inside each stored signed transaction for Production, non-revoked rows only; Sandbox rows are test purchases and are never revenue.',
  perf:
    'perf_sample events (frame-time medians over 600 frames, max 3 per session). Medians computed over samples in the window; fps / med / p95 are per-sample values from the event props.',
  diagnostics:
    'diagnostic events are MetricKit crash/hang counts by kind (no stack traces); error events are non-fatal client errors (save / storage / content), counted by kind and by day.',
}

type Row = Record<string, unknown>
type QueryFn = (sql: string, params?: unknown[]) => Promise<[unknown, unknown]>

const num = (v: unknown): number => Number(v) || 0
const dayStr = (v: unknown): string =>
  v instanceof Date ? v.toISOString().slice(0, 10) : String(v ?? '').slice(0, 10)

function median(values: number[]): number | null {
  if (!values.length) return null
  const sorted = [...values].sort((a, b) => a - b)
  const mid = Math.floor(sorted.length / 2)
  if (sorted.length % 2 === 1) return sorted[mid] ?? null
  return ((sorted[mid - 1] ?? 0) + (sorted[mid] ?? 0)) / 2
}

function round1(v: number | null): number | null {
  return v === null ? null : Math.round(v * 10) / 10
}

/**
 * Decode the payload of a stored signed transaction (JWS). The row exists
 * only because temple-api already verified the full chain to Apple's root,
 * so reading the price out of the stored payload is reading server-verified
 * data — this decode performs no trust decision of its own.
 */
function decodeJwsPayload(jws: unknown): Record<string, unknown> | null {
  try {
    const parts = String(jws ?? '').split('.')
    if (parts.length !== 3 || !parts[1]) return null
    const json = Buffer.from(
      parts[1].replace(/-/g, '+').replace(/_/g, '/'),
      'base64',
    ).toString('utf8')
    const parsed: unknown = JSON.parse(json)
    if (parsed && typeof parsed === 'object') return parsed as Record<string, unknown>
    return null
  } catch {
    return null
  }
}

function emptyTelemetry(days: number, keys: string[], configured: boolean): TempleTelemetry {
  return {
    configured,
    days,
    timezone: 'UTC',
    generatedAt: new Date().toISOString(),
    definitions: DEFINITIONS,
    totals: {
      installs: 0,
      players: 0,
      eventsAllTime: 0,
      eventsInWindow: 0,
      sessionsInWindow: 0,
      dauInWindow: 0,
      purchasesProduction: 0,
      purchasesSandbox: 0,
      revenueUsd: 0,
      sandboxRevenueUsd: 0,
      cloudSavePlayers: 0,
      cloudSaveSlots: 0,
    },
    installsByDay: [],
    installsByVersion: [],
    dauByDay: keys.map((day) => ({ day, sessions: 0, dau: 0 })),
    eventsByDay: keys.map((day) => ({ day, total: 0 })),
    eventsByName: [],
    funnel: TEMPLE_FUNNEL_STEPS.map((name) => ({
      name,
      events: 0,
      players: 0,
      conversionFromPrev: null,
    })),
    purchases: [],
    perf: { samples: 0, medianFps: null, medianMedMs: null, medianP95Ms: null, byMap: [] },
    diagnostics: [],
    errorsByDay: keys.map((day) => ({ day, count: 0 })),
    errorKinds: [],
    recentEvents: [],
  }
}

// Production-only filter for event rows, verbatim from temple-api's funnel().
const PROD_ENV_SQL = ` AND (props IS NULL OR JSON_EXTRACT(props, '$.env') IS NULL OR JSON_UNQUOTE(JSON_EXTRACT(props, '$.env')) = 'production') AND (JSON_EXTRACT(props, '$.txEnv') IS NULL OR JSON_UNQUOTE(JSON_EXTRACT(props, '$.txEnv')) = 'production')`

export async function fetchTempleTelemetry(
  days: number,
  poolArg?: mysql.Pool | null,
  nowMs = Date.now(),
): Promise<TempleTelemetry> {
  const windowDays = Math.min(TEMPLE_MAX_DAYS, Math.max(1, Math.floor(days)))
  const keys = utcDayKeys(windowDays, nowMs)
  const pool = poolArg === undefined ? getTempleMysqlPool() : poolArg
  if (!pool) return emptyTelemetry(windowDays, keys, isTempleMysqlConfigured())
  const query = pool.query.bind(pool) as unknown as QueryFn

  try {
    const [
      [deviceTotal],
      [playerTotal],
      [eventTotal],
      [saveTotal],
      [eventsWindow],
      [sessionsWindow],
      [installsByDayRows],
      [installsByVersionRows],
      [dauRows],
      [eventsByDayNameRows],
      [funnelRows],
      [entitlementRows],
      [perfRows],
      [diagnosticRows],
      [errorsByDayRows],
      [errorKindRows],
      [recentRows],
    ] = (await Promise.all([
      query(`SELECT COUNT(*) AS n FROM devices`),
      query(`SELECT COUNT(*) AS n FROM players`),
      query(`SELECT COUNT(*) AS n FROM events`),
      query(`SELECT COUNT(*) AS n, COUNT(DISTINCT player_id) AS players FROM saves`),
      query(`SELECT COUNT(*) AS n FROM events WHERE created_at >= NOW() - INTERVAL ? DAY`, [windowDays]),
      query(
        `SELECT COUNT(*) AS n, COUNT(DISTINCT player_id) AS players FROM events
         WHERE name = 'session_start' AND created_at >= NOW() - INTERVAL ? DAY`,
        [windowDays],
      ),
      query(
        `SELECT DATE(created_at) AS day, COUNT(*) AS n FROM devices
         GROUP BY day ORDER BY day ASC`,
      ),
      query(
        `SELECT COALESCE(app_version, 'unknown') AS version, COUNT(*) AS n FROM devices
         GROUP BY version ORDER BY n DESC`,
      ),
      query(
        `SELECT DATE(created_at) AS day, COUNT(*) AS sessions, COUNT(DISTINCT player_id) AS dau
         FROM events WHERE name = 'session_start' AND created_at >= NOW() - INTERVAL ? DAY
         GROUP BY day ORDER BY day ASC`,
        [windowDays],
      ),
      query(
        `SELECT DATE(created_at) AS day, name, COUNT(*) AS n FROM events
         WHERE created_at >= NOW() - INTERVAL ? DAY GROUP BY day, name ORDER BY day ASC`,
        [windowDays],
      ),
      query(
        `SELECT name, COUNT(*) AS n, COUNT(DISTINCT player_id) AS players FROM events
         WHERE created_at >= NOW() - INTERVAL ? DAY${PROD_ENV_SQL} GROUP BY name`,
        [windowDays],
      ),
      query(
        `SELECT product_id, environment, revoked_at, signed_transaction FROM entitlements`,
      ),
      query(
        `SELECT props FROM events WHERE name = 'perf_sample'
         AND created_at >= NOW() - INTERVAL ? DAY LIMIT 5000`,
        [windowDays],
      ),
      query(
        `SELECT JSON_UNQUOTE(JSON_EXTRACT(props, '$.kind')) AS kind, COUNT(*) AS n FROM events
         WHERE name = 'diagnostic' AND created_at >= NOW() - INTERVAL ? DAY GROUP BY kind ORDER BY n DESC`,
        [windowDays],
      ),
      query(
        `SELECT DATE(created_at) AS day, COUNT(*) AS n FROM events
         WHERE name = 'error' AND created_at >= NOW() - INTERVAL ? DAY GROUP BY day ORDER BY day ASC`,
        [windowDays],
      ),
      query(
        `SELECT JSON_UNQUOTE(JSON_EXTRACT(props, '$.kind')) AS kind, COUNT(*) AS n FROM events
         WHERE name = 'error' AND created_at >= NOW() - INTERVAL ? DAY GROUP BY kind ORDER BY n DESC`,
        [windowDays],
      ),
      query(
        `SELECT name, app_version, props, created_at FROM events
         ORDER BY created_at DESC LIMIT 20`,
      ),
    ])) as [
      [Row[], unknown],
      [Row[], unknown],
      [Row[], unknown],
      [Row[], unknown],
      [Row[], unknown],
      [Row[], unknown],
      [Row[], unknown],
      [Row[], unknown],
      [Row[], unknown],
      [Row[], unknown],
      [Row[], unknown],
      [Row[], unknown],
      [Row[], unknown],
      [Row[], unknown],
      [Row[], unknown],
      [Row[], unknown],
      [Row[], unknown],
    ]

    const dauByDayMap = new Map<string, { sessions: number; dau: number }>()
    for (const r of dauRows ?? []) {
      dauByDayMap.set(dayStr(r.day), { sessions: num(r.sessions), dau: num(r.dau) })
    }
    const eventsByDayMap = new Map<string, number>()
    const eventsByNameMap = new Map<string, number>()
    for (const r of eventsByDayNameRows ?? []) {
      const day = dayStr(r.day)
      eventsByDayMap.set(day, (eventsByDayMap.get(day) ?? 0) + num(r.n))
      eventsByNameMap.set(String(r.name ?? ''), (eventsByNameMap.get(String(r.name ?? '')) ?? 0) + num(r.n))
    }
    const funnelByName = new Map<string, { n: number; players: number }>()
    for (const r of funnelRows ?? []) {
      funnelByName.set(String(r.name ?? ''), { n: num(r.n), players: num(r.players) })
    }
    const funnel: TempleFunnelStep[] = TEMPLE_FUNNEL_STEPS.map((name, i) => {
      const step = funnelByName.get(name) ?? { n: 0, players: 0 }
      const prev = i === 0 ? null : (funnelByName.get(TEMPLE_FUNNEL_STEPS[i - 1]!)?.n ?? 0)
      return {
        name,
        events: step.n,
        players: step.players,
        conversionFromPrev: prev === null ? null : prev > 0 ? step.n / prev : null,
      }
    })

    // Purchases: group verified entitlements by product × environment; revenue
    // is production, non-revoked only, from the stored JWS price (milliunits).
    const purchaseMap = new Map<string, TemplePurchaseRow>()
    let purchasesProduction = 0
    let purchasesSandbox = 0
    let revenueUsd = 0
    let sandboxRevenueUsd = 0
    for (const r of entitlementRows ?? []) {
      const product = String(r.product_id ?? 'unknown')
      const env = String(r.environment ?? 'unknown')
      const key = `${product}||${env}`
      const row = purchaseMap.get(key) ?? {
        product,
        environment: env,
        count: 0,
        revoked: 0,
        revenueUsd: 0,
      }
      row.count += 1
      const revoked = r.revoked_at !== null && r.revoked_at !== undefined
      if (revoked) row.revoked += 1
      if (!revoked) {
        const payload = decodeJwsPayload(r.signed_transaction)
        const price = typeof payload?.price === 'number' ? payload.price / 1000 : 0
        const currency = typeof payload?.currency === 'string' ? payload.currency : ''
        if (currency === 'USD' && price > 0) {
          if (env === 'Production') {
            row.revenueUsd = Math.round((row.revenueUsd + price) * 100) / 100
            revenueUsd = Math.round((revenueUsd + price) * 100) / 100
          } else {
            // Sandbox rows carry a price but it is a test purchase, never revenue.
            sandboxRevenueUsd = Math.round((sandboxRevenueUsd + price) * 100) / 100
          }
        }
      }
      if (env === 'Production' && !revoked) purchasesProduction += 1
      if (env === 'Sandbox' && !revoked) purchasesSandbox += 1
      purchaseMap.set(key, row)
    }

    // Perf medians in-process (sample counts are small; cap is 5000 rows).
    const fpsAll: number[] = []
    const medAll: number[] = []
    const p95All: number[] = []
    const byMap = new Map<string, { fps: number[]; med: number[]; p95: number[] }>()
    for (const r of perfRows ?? []) {
      let props: Record<string, unknown> | null = null
      try {
        props = typeof r.props === 'string' ? (JSON.parse(r.props) as Record<string, unknown>) : null
      } catch {
        props = null
      }
      if (!props) continue
      const fps = typeof props.fps === 'number' ? props.fps : null
      const med = typeof props.med === 'number' ? props.med : null
      const p95 = typeof props.p95 === 'number' ? props.p95 : null
      if (fps !== null) fpsAll.push(fps)
      if (med !== null) medAll.push(med)
      if (p95 !== null) p95All.push(p95)
      const map = typeof props.map === 'string' && props.map ? props.map : 'unknown'
      const entry = byMap.get(map) ?? { fps: [], med: [], p95: [] }
      if (fps !== null) entry.fps.push(fps)
      if (med !== null) entry.med.push(med)
      if (p95 !== null) entry.p95.push(p95)
      byMap.set(map, entry)
    }
    const perfByMap: TemplePerfByMap[] = [...byMap.entries()]
      .map(([map, v]) => ({
        map,
        samples: v.fps.length,
        medianFps: round1(median(v.fps)),
        medianMedMs: round1(median(v.med)),
        medianP95Ms: round1(median(v.p95)),
      }))
      .sort((a, b) => b.samples - a.samples)

    const errorsByDayMap = new Map<string, number>()
    for (const r of errorsByDayRows ?? []) {
      errorsByDayMap.set(dayStr(r.day), num(r.n))
    }

    return {
      configured: true,
      days: windowDays,
      timezone: 'UTC',
      generatedAt: new Date().toISOString(),
      definitions: DEFINITIONS,
      totals: {
        installs: num(deviceTotal?.[0]?.n),
        players: num(playerTotal?.[0]?.n),
        eventsAllTime: num(eventTotal?.[0]?.n),
        eventsInWindow: num(eventsWindow?.[0]?.n),
        sessionsInWindow: num(sessionsWindow?.[0]?.n),
        dauInWindow: num(sessionsWindow?.[0]?.players),
        purchasesProduction,
        purchasesSandbox,
        revenueUsd,
        sandboxRevenueUsd,
        cloudSavePlayers: num(saveTotal?.[0]?.players),
        cloudSaveSlots: num(saveTotal?.[0]?.n),
      },
      installsByDay: (installsByDayRows ?? []).map((r) => ({
        day: dayStr(r.day),
        installs: num(r.n),
      })),
      installsByVersion: (installsByVersionRows ?? []).map((r) => ({
        version: String(r.version ?? 'unknown'),
        devices: num(r.n),
      })),
      dauByDay: keys.map((day) => {
        const v = dauByDayMap.get(day)
        return { day, sessions: v?.sessions ?? 0, dau: v?.dau ?? 0 }
      }),
      eventsByDay: keys.map((day) => ({ day, total: eventsByDayMap.get(day) ?? 0 })),
      eventsByName: [...eventsByNameMap.entries()]
        .map(([name, count]) => ({ name, count }))
        .sort((a, b) => b.count - a.count),
      funnel,
      purchases: [...purchaseMap.values()].sort((a, b) => b.count - a.count),
      perf: {
        samples: fpsAll.length,
        medianFps: round1(median(fpsAll)),
        medianMedMs: round1(median(medAll)),
        medianP95Ms: round1(median(p95All)),
        byMap: perfByMap,
      },
      diagnostics: (diagnosticRows ?? []).map((r) => ({
        kind: String(r.kind ?? 'unknown'),
        count: num(r.n),
      })),
      errorsByDay: keys.map((day) => ({ day, count: errorsByDayMap.get(day) ?? 0 })),
      errorKinds: (errorKindRows ?? []).map((r) => ({
        kind: String(r.kind ?? 'unknown'),
        count: num(r.n),
      })),
      recentEvents: (recentRows ?? []).map((r) => ({
        createdAt:
          r.created_at instanceof Date
            ? r.created_at.toISOString()
            : String(r.created_at ?? ''),
        name: String(r.name ?? ''),
        appVersion: r.app_version === null || r.app_version === undefined ? null : String(r.app_version),
        props:
          typeof r.props === 'string' ? r.props.slice(0, 200) : r.props == null ? null : String(r.props).slice(0, 200),
      })),
    }
  } catch (err) {
    console.warn(
      '[admin] temple telemetry query failed:',
      err instanceof Error ? err.message : err,
    )
    return { ...emptyTelemetry(windowDays, keys, true), error: 'query_failed' }
  }
}
