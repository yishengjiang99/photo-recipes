/**
 * In-house funnel telemetry — POST /api/telemetry, GET /api/telemetry/funnels.
 * Allowlisted events only; no photos/PII. Soft no-op when MySQL unset.
 */
import crypto from 'node:crypto'
import type { Express, Request, Response } from 'express'
import { getMysqlPool, isMysqlConfigured } from './mysql.ts'

export const TELEMETRY_EVENT_ALLOWLIST = new Set([
  // Acquisition (web)
  'landing_view',
  'landing_cta_camera',
  'landing_cta_waitlist',
  'waitlist_submit',
  'waitlist_success',
  'waitlist_fail',
  'landing_cta_testflight',
  // Shell / session
  'app_open',
  'session_start',
  'session_end',
  'tab_library',
  'tab_camera',
  'tab_pro',
  // Activation
  'camera_open',
  'camera_permission_granted',
  'camera_permission_denied',
  'camera_start_ok',
  'camera_start_fail',
  'auto_optimize_start',
  'auto_optimize_success',
  'auto_optimize_fail',
  'look_suggested',
  'look_applied',
  'look_dismissed',
  'shutter_tap',
  'capture_success',
  'recipe_open',
  'teach_open',
  // Monetization
  'paywall_view',
  'paywall_plan_select',
  'purchase_start',
  'purchase_success',
  'purchase_fail',
  'purchase_restore',
  'trial_start',
  'checkout_redirect',
  // Push (mirror; PushAnalytics allowlist stays separate)
  'push_opened',
])

const BLOCKED_PROP_KEYS = /^(email|e_?mail|phone|password|token|authorization|cookie|image|photo|frame|base64|gps|lat|lng|longitude|latitude|ssn|name|full.?name)$/i
const MAX_PROP_KEYS = 24
const MAX_PROP_STRING = 200
const MAX_ANON = 64
const MAX_SESSION = 64

function sanitizeProps(raw: unknown): Record<string, string | number | boolean> | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null
  const out: Record<string, string | number | boolean> = {}
  let n = 0
  for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
    if (n >= MAX_PROP_KEYS) break
    if (BLOCKED_PROP_KEYS.test(k)) continue
    if (typeof v === 'string') {
      if (v.length > 4000) continue // likely payload
      if (/^data:image\//i.test(v) || /^[A-Za-z0-9+/=]{200,}$/.test(v)) continue
      out[k] = v.slice(0, MAX_PROP_STRING)
      n++
    } else if (typeof v === 'number' && Number.isFinite(v)) {
      out[k] = v
      n++
    } else if (typeof v === 'boolean') {
      out[k] = v
      n++
    }
  }
  return Object.keys(out).length ? out : null
}

function clientIp(req: Request): string | null {
  const xf = req.headers['x-forwarded-for']
  if (typeof xf === 'string' && xf.trim()) return xf.split(',')[0]!.trim()
  if (Array.isArray(xf) && xf[0]) return xf[0].split(',')[0]!.trim()
  return req.socket.remoteAddress ?? null
}

function ipHash(req: Request): string | null {
  const ip = clientIp(req)
  if (!ip) return null
  const salt =
    process.env.TELEMETRY_IP_SALT?.trim() ||
    process.env.SESSION_SECRET?.trim() ||
    'dev-telemetry-salt'
  return crypto.createHash('sha256').update(`${salt}|${ip}`).digest('hex')
}

function readKeyOk(req: Request): boolean {
  const key = process.env.TELEMETRY_READ_KEY?.trim()
  if (!key) return false
  const hdr = req.headers['x-telemetry-read-key']
  const q = typeof req.query.key === 'string' ? req.query.key : undefined
  const val = (Array.isArray(hdr) ? hdr[0] : hdr) || q
  if (!val) return false
  try {
    const a = Buffer.from(val)
    const b = Buffer.from(key)
    if (a.length !== b.length) return false
    return crypto.timingSafeEqual(a, b)
  } catch {
    return false
  }
}

export type TelemetryRow = {
  app: string
  platform: string
  event: string
  anon_id: string
  session_id: string | null
  props: Record<string, string | number | boolean> | null
  ip_hash: string | null
}

export async function insertTelemetry(row: TelemetryRow): Promise<boolean> {
  const pool = getMysqlPool()
  if (!pool) return false
  try {
    await pool.execute(
      `INSERT INTO telemetry_events
        (app, platform, event, anon_id, session_id, props, ip_hash)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [
        row.app,
        row.platform,
        row.event,
        row.anon_id,
        row.session_id,
        row.props ? JSON.stringify(row.props) : null,
        row.ip_hash,
      ],
    )
    return true
  } catch (err) {
    console.warn(
      '[telemetry] insert failed:',
      err instanceof Error ? err.message : err,
    )
    return false
  }
}

const FUNNEL_WEB_ACTIVATION = [
  'landing_view',
  'landing_cta_camera',
  'camera_open',
  'auto_optimize_start',
  'auto_optimize_success',
] as const

const FUNNEL_IOS_CAPTURE = [
  'camera_open',
  'auto_optimize_success',
  'capture_success',
] as const

const FUNNEL_MONETIZATION = [
  'paywall_view',
  'paywall_plan_select',
  'purchase_start',
  'checkout_redirect',
  'purchase_success',
] as const

async function countEvents(
  days: number,
  events: readonly string[],
  platform?: string,
): Promise<Record<string, number>> {
  const pool = getMysqlPool()
  const out: Record<string, number> = {}
  for (const e of events) out[e] = 0
  if (!pool) return out
  try {
    const [rows] = await pool.query(
      `SELECT event, COUNT(*) AS c
       FROM telemetry_events
       WHERE ts >= (NOW(3) - INTERVAL ? DAY)
         AND event IN (${events.map(() => '?').join(',')})
         ${platform ? 'AND platform = ?' : ''}
       GROUP BY event`,
      platform ? [days, ...events, platform] : [days, ...events],
    )
    for (const r of rows as Array<{ event: string; c: number }>) {
      out[r.event] = Number(r.c) || 0
    }
  } catch (err) {
    console.warn('[telemetry] funnel count failed:', err instanceof Error ? err.message : err)
  }
  return out
}

async function dauWau(days: number): Promise<{ dau: number; wau: number; events: number }> {
  const pool = getMysqlPool()
  if (!pool) return { dau: 0, wau: 0, events: 0 }
  try {
    const [[dauRow]] = (await pool.query(
      `SELECT COUNT(DISTINCT anon_id) AS n FROM telemetry_events
       WHERE ts >= (NOW(3) - INTERVAL 1 DAY)`,
    )) as unknown as [Array<{ n: number }>]
    const [[wauRow]] = (await pool.query(
      `SELECT COUNT(DISTINCT anon_id) AS n FROM telemetry_events
       WHERE ts >= (NOW(3) - INTERVAL 7 DAY)`,
    )) as unknown as [Array<{ n: number }>]
    const [[evRow]] = (await pool.query(
      `SELECT COUNT(*) AS n FROM telemetry_events
       WHERE ts >= (NOW(3) - INTERVAL ? DAY)`,
      [days],
    )) as unknown as [Array<{ n: number }>]
    return {
      dau: Number(dauRow?.n) || 0,
      wau: Number(wauRow?.n) || 0,
      events: Number(evRow?.n) || 0,
    }
  } catch {
    return { dau: 0, wau: 0, events: 0 }
  }
}

async function conversionByPlan(days: number) {
  const pool = getMysqlPool()
  if (!pool) return []
  try {
    const [rows] = await pool.query(
      `SELECT
         COALESCE(JSON_UNQUOTE(JSON_EXTRACT(props, '$.plan')), 'unknown') AS plan,
         SUM(event = 'paywall_view') AS paywall_view,
         SUM(event = 'purchase_success') AS purchase_success,
         SUM(event = 'checkout_redirect') AS checkout_redirect
       FROM telemetry_events
       WHERE ts >= (NOW(3) - INTERVAL ? DAY)
         AND event IN ('paywall_view','purchase_success','checkout_redirect','purchase_start','paywall_plan_select')
       GROUP BY plan`,
      [days],
    )
    return rows
  } catch {
    return []
  }
}

export function telemetryHealthSnippet(): {
  telemetry: boolean
  telemetryMysql: boolean
} {
  return {
    telemetry: true,
    telemetryMysql: isMysqlConfigured() && Boolean(getMysqlPool()),
  }
}

export function mountTelemetryRoutes(app: Express) {
  app.post('/api/telemetry', (req: Request, res: Response) => {
    void (async () => {
      const body = (req.body ?? {}) as Record<string, unknown>
      const event = typeof body.event === 'string' ? body.event.trim() : ''
      if (!event || !TELEMETRY_EVENT_ALLOWLIST.has(event)) {
        res.status(400).json({ error: 'unknown_or_missing_event', allowlist: [...TELEMETRY_EVENT_ALLOWLIST].sort() })
        return
      }
      const anon =
        typeof body.anon_id === 'string' ? body.anon_id.trim().slice(0, MAX_ANON) : ''
      if (!anon || anon.length < 8) {
        res.status(400).json({ error: 'anon_id_required' })
        return
      }
      const platformRaw =
        typeof body.platform === 'string' ? body.platform.trim().toLowerCase() : 'web'
      const platform = ['ios', 'web', 'android', 'server'].includes(platformRaw)
        ? platformRaw
        : 'web'
      const session_id =
        typeof body.session_id === 'string'
          ? body.session_id.trim().slice(0, MAX_SESSION) || null
          : null
      const appName =
        typeof body.app === 'string' && body.app.trim()
          ? body.app.trim().slice(0, 64)
          : 'photo-recipes'
      const props = sanitizeProps(body.props)

      const stored = await insertTelemetry({
        app: appName,
        platform,
        event,
        anon_id: anon,
        session_id,
        props,
        ip_hash: ipHash(req),
      })

      res.status(202).json({
        ok: true,
        stored,
        mysql: isMysqlConfigured(),
      })
    })()
  })

  app.get('/api/telemetry/funnels', (req: Request, res: Response) => {
    void (async () => {
      if (!readKeyOk(req)) {
        res.status(401).json({ error: 'unauthorized', hint: 'X-Telemetry-Read-Key or ?key=' })
        return
      }
      const days = Math.min(90, Math.max(1, Number(req.query.days) || 7))
      const [webActivation, iosCapture, monetization, activity, byPlan] =
        await Promise.all([
          countEvents(days, FUNNEL_WEB_ACTIVATION, undefined),
          countEvents(days, FUNNEL_IOS_CAPTURE, 'ios'),
          countEvents(days, FUNNEL_MONETIZATION, undefined),
          dauWau(days),
          conversionByPlan(days),
        ])
      res.json({
        ok: true,
        days,
        mysql: isMysqlConfigured() && Boolean(getMysqlPool()),
        activity,
        funnels: {
          web_activation: webActivation,
          ios_capture: iosCapture,
          monetization,
          conversion_by_plan: byPlan,
        },
      })
    })()
  })
}
