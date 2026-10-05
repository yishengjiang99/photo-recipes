/**
 * Password-protected admin dashboard APIs.
 * Env: ADMIN_PASSWORD (required). Optional ADMIN_TOKEN as Bearer alternate.
 * Soft-empty telemetry when MySQL unset — never 500 for missing MySQL/Stripe.
 */
import crypto from 'node:crypto'
import type { Express, NextFunction, Request, Response } from 'express'
import { getEntitlementIncomeSnapshot, getQuotaConfigSnapshot } from './entitlements.ts'
import { patchOpsConfig, resolveOpsConfig } from './opsConfig.ts'
import { getMysqlPool, isMysqlConfigured } from './mysql.ts'
import { getStripe, MONTHLY_CENTS, YEARLY_CENTS } from './stripe.ts'
import { getPushFunnelSnapshot } from './push.ts'
import { sendApns, type ApnsPayload, getDefaultApnsEnvironment } from './apns.ts'
import { getPushPrefs } from './pushPrefs.ts'
import {
  listPushTokensForGuest,
  mergeApnsTokens,
} from './pushDevices.ts'
import { fetchRecentApiErrors } from './telemetry.ts'

const ADMIN_COOKIE = 'pr_admin'
const COOKIE_MAX_MS = 7 * 24 * 60 * 60 * 1000

function adminPassword(): string | null {
  const p = process.env.ADMIN_PASSWORD?.trim()
  return p || null
}

function adminToken(): string | null {
  const t = process.env.ADMIN_TOKEN?.trim()
  return t || null
}

function sessionSecret(): string {
  return (
    process.env.SESSION_SECRET?.trim() ||
    process.env.ADMIN_PASSWORD?.trim() ||
    'photo-recipes-dev-admin-secret'
  )
}

function sign(value: string): string {
  const sig = crypto.createHmac('sha256', sessionSecret()).update(value).digest('base64url')
  return `${value}.${sig}`
}

function unsign(signed: string): string | null {
  const i = signed.lastIndexOf('.')
  if (i <= 0) return null
  const value = signed.slice(0, i)
  const sig = signed.slice(i + 1)
  const expected = crypto.createHmac('sha256', sessionSecret()).update(value).digest('base64url')
  try {
    const a = Buffer.from(sig)
    const b = Buffer.from(expected)
    if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null
    return value
  } catch {
    return null
  }
}

function timingSafeEqualStr(a: string, b: string): boolean {
  try {
    const ba = Buffer.from(a)
    const bb = Buffer.from(b)
    if (ba.length !== bb.length) return false
    return crypto.timingSafeEqual(ba, bb)
  } catch {
    return false
  }
}

function cookieOpts() {
  return {
    httpOnly: true,
    sameSite: 'lax' as const,
    secure: process.env.NODE_ENV === 'production',
    maxAge: COOKIE_MAX_MS,
    path: '/',
  }
}

function bearerToken(req: Request): string | null {
  const hdr = req.headers.authorization
  if (typeof hdr !== 'string') return null
  const m = /^Bearer\s+(.+)$/i.exec(hdr.trim())
  return m?.[1]?.trim() || null
}

export function isAdminAuthenticated(req: Request): boolean {
  if (!adminPassword() && !adminToken()) return false

  const token = adminToken()
  const bearer = bearerToken(req)
  if (token && bearer && timingSafeEqualStr(bearer, token)) return true

  // Also accept ADMIN_TOKEN via X-Admin-Token
  const hdr = req.headers['x-admin-token']
  const hdrVal = Array.isArray(hdr) ? hdr[0] : hdr
  if (token && typeof hdrVal === 'string' && timingSafeEqualStr(hdrVal.trim(), token)) {
    return true
  }

  const raw = req.cookies?.[ADMIN_COOKIE] as string | undefined
  if (!raw) return false
  const value = unsign(raw)
  if (!value) return false
  // value format: admin.<issuedAtMs>
  if (!value.startsWith('admin.')) return false
  const issued = Number(value.slice('admin.'.length))
  if (!Number.isFinite(issued)) return false
  if (Date.now() - issued > COOKIE_MAX_MS) return false
  return true
}

export function requireAdmin(req: Request, res: Response, next: NextFunction) {
  if (!adminPassword() && !adminToken()) {
    res.status(503).json({
      error: 'admin_not_configured',
      hint: 'Set ADMIN_PASSWORD (and optionally ADMIN_TOKEN) in the server environment.',
    })
    return
  }
  if (!isAdminAuthenticated(req)) {
    res.status(401).json({ error: 'unauthorized' })
    return
  }
  next()
}

async function telemetrySummary() {
  const configured = isMysqlConfigured() && Boolean(getMysqlPool())
  const empty = {
    configured,
    events8h: 0,
    events24h: 0,
    events7d: 0,
    dau: 0,
    wau: 0,
    active8h: 0,
    topEvents: [] as Array<{ event: string; count: number }>,
    topEvents8h: [] as Array<{ event: string; count: number }>,
    platformSplit: [] as Array<{ platform: string; count: number }>,
    eventsByPlatform8h: {} as Record<string, number>,
    activeByPlatform8h: {} as Record<string, number>,
    topEventsByPlatform: {} as Record<string, Array<{ event: string; count: number }>>,
    topEvents8hByPlatform: {} as Record<string, Array<{ event: string; count: number }>>,
  }
  const pool = getMysqlPool()
  if (!pool) return empty

  try {
    const [[e8]] = (await pool.query(
      `SELECT COUNT(*) AS n FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 8 HOUR)`,
    )) as unknown as [Array<{ n: number }>]
    const [[e24]] = (await pool.query(
      `SELECT COUNT(*) AS n FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 1 DAY)`,
    )) as unknown as [Array<{ n: number }>]
    const [[e7]] = (await pool.query(
      `SELECT COUNT(*) AS n FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 7 DAY)`,
    )) as unknown as [Array<{ n: number }>]
    const [[dau]] = (await pool.query(
      `SELECT COUNT(DISTINCT anon_id) AS n FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 1 DAY)`,
    )) as unknown as [Array<{ n: number }>]
    const [[wau]] = (await pool.query(
      `SELECT COUNT(DISTINCT anon_id) AS n FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 7 DAY)`,
    )) as unknown as [Array<{ n: number }>]
    const [[a8]] = (await pool.query(
      `SELECT COUNT(DISTINCT anon_id) AS n FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 8 HOUR)`,
    )) as unknown as [Array<{ n: number }>]
    const [topRows] = await pool.query(
      `SELECT event, COUNT(*) AS c FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 7 DAY)
       GROUP BY event ORDER BY c DESC LIMIT 15`,
    )
    const [topRows8h] = await pool.query(
      `SELECT event, COUNT(*) AS c FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 8 HOUR)
       GROUP BY event ORDER BY c DESC LIMIT 15`,
    )
    const [platRows] = await pool.query(
      `SELECT platform, COUNT(*) AS c FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 7 DAY)
       GROUP BY platform ORDER BY c DESC`,
    )
    const [evPlat8h] = await pool.query(
      `SELECT platform, COUNT(*) AS n FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 8 HOUR)
       GROUP BY platform`,
    )
    const [actPlat8h] = await pool.query(
      `SELECT platform, COUNT(DISTINCT anon_id) AS n FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 8 HOUR)
       GROUP BY platform`,
    )
    const [topPlatRows] = await pool.query(
      `SELECT platform, event, COUNT(*) AS c FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 7 DAY)
       GROUP BY platform, event`,
    )
    const [topPlatRows8h] = await pool.query(
      `SELECT platform, event, COUNT(*) AS c FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 8 HOUR)
       GROUP BY platform, event`,
    )
    const topByPlatform = (
      rows: Array<{ platform: string; event: string; c: number }>,
    ): Record<string, Array<{ event: string; count: number }>> => {
      const grouped: Record<string, Array<{ event: string; count: number }>> = {}
      for (const r of rows) {
        const p = r.platform || 'unknown'
        ;(grouped[p] ??= []).push({ event: r.event, count: Number(r.c) || 0 })
      }
      for (const p of Object.keys(grouped)) {
        grouped[p].sort((a, b) => b.count - a.count)
        grouped[p] = grouped[p].slice(0, 15)
      }
      return grouped
    }
    return {
      configured: true,
      events8h: Number(e8?.n) || 0,
      events24h: Number(e24?.n) || 0,
      events7d: Number(e7?.n) || 0,
      dau: Number(dau?.n) || 0,
      wau: Number(wau?.n) || 0,
      active8h: Number(a8?.n) || 0,
      topEvents: (topRows as Array<{ event: string; c: number }>).map((r) => ({
        event: r.event,
        count: Number(r.c) || 0,
      })),
      topEvents8h: (topRows8h as Array<{ event: string; c: number }>).map((r) => ({
        event: r.event,
        count: Number(r.c) || 0,
      })),
      platformSplit: (platRows as Array<{ platform: string; c: number }>).map((r) => ({
        platform: r.platform,
        count: Number(r.c) || 0,
      })),
      eventsByPlatform8h: Object.fromEntries(
        (evPlat8h as Array<{ platform: string; n: number }>).map((r) => [
          r.platform || 'unknown',
          Number(r.n) || 0,
        ]),
      ),
      activeByPlatform8h: Object.fromEntries(
        (actPlat8h as Array<{ platform: string; n: number }>).map((r) => [
          r.platform || 'unknown',
          Number(r.n) || 0,
        ]),
      ),
      topEventsByPlatform: topByPlatform(
        topPlatRows as Array<{ platform: string; event: string; c: number }>,
      ),
      topEvents8hByPlatform: topByPlatform(
        topPlatRows8h as Array<{ platform: string; event: string; c: number }>,
      ),
    }
  } catch (err) {
    console.warn(
      '[admin] telemetry summary failed:',
      err instanceof Error ? err.message : err,
    )
    return { ...empty, configured: true, error: 'query_failed' }
  }
}

function mrrCentsFromSub(sub: {
  items: { data: Array<{ price?: { unit_amount?: number | null; recurring?: { interval?: string } | null } | null }> }
}): number {
  const price = sub.items.data[0]?.price
  const amount = price?.unit_amount ?? 0
  const interval = price?.recurring?.interval
  if (interval === 'month') return amount
  if (interval === 'year') return Math.round(amount / 12)
  if (amount === YEARLY_CENTS) return Math.round(YEARLY_CENTS / 12)
  if (amount === MONTHLY_CENTS) return MONTHLY_CENTS
  return 0
}

async function stripeIncomeSnapshot() {
  const s = getStripe()
  if (!s) {
    return {
      configured: false,
      activeSubscriptions: 0,
      trialingSubscriptions: 0,
      recentCharges: [] as Array<{
        id: string
        amountCents: number
        currency: string
        created: number
        status: string
      }>,
      approxMrrCents: 0,
      note: 'STRIPE_SECRET_KEY unset',
    }
  }

  try {
    const [activeList, trialingList, charges] = await Promise.all([
      s.subscriptions.list({ status: 'active', limit: 100 }),
      s.subscriptions.list({ status: 'trialing', limit: 100 }),
      s.charges.list({ limit: 10 }),
    ])

    let approxMrrCents = 0
    for (const sub of [...activeList.data, ...trialingList.data]) {
      approxMrrCents += mrrCentsFromSub(sub)
    }

    const recentCharges = charges.data.map((c) => ({
      id: c.id,
      amountCents: c.amount,
      currency: c.currency,
      created: c.created,
      status: c.status,
    }))

    return {
      configured: true,
      activeSubscriptions: activeList.data.length,
      trialingSubscriptions: trialingList.data.length,
      recentCharges,
      approxMrrCents,
      note: 'approx MRR = sum of active/trialing recurring items (yearly ÷ 12); first page ≤100 each',
    }
  } catch (err) {
    console.warn('[admin] stripe snapshot failed:', err instanceof Error ? err.message : err)
    return {
      configured: true,
      activeSubscriptions: 0,
      trialingSubscriptions: 0,
      recentCharges: [],
      approxMrrCents: 0,
      error: err instanceof Error ? err.message : 'stripe_error',
    }
  }
}

export function mountAdminRoutes(app: Express) {
  app.get('/api/admin/session', (req, res) => {
    const configured = Boolean(adminPassword() || adminToken())
    res.json({
      ok: true,
      configured,
      authenticated: isAdminAuthenticated(req),
    })
  })

  app.post('/api/admin/login', (req, res) => {
    const pwd = adminPassword()
    if (!pwd) {
      res.status(503).json({
        error: 'admin_not_configured',
        hint: 'Set ADMIN_PASSWORD on the server.',
      })
      return
    }
    const body = (req.body ?? {}) as Record<string, unknown>
    const password = typeof body.password === 'string' ? body.password : ''
    if (!password || !timingSafeEqualStr(password, pwd)) {
      res.status(401).json({ error: 'invalid_password' })
      return
    }
    const value = `admin.${Date.now()}`
    res.cookie(ADMIN_COOKIE, sign(value), cookieOpts())
    res.json({ ok: true, authenticated: true })
  })

  app.post('/api/admin/logout', (_req, res) => {
    res.clearCookie(ADMIN_COOKIE, { path: '/' })
    res.json({ ok: true })
  })

  app.get('/api/admin/summary', requireAdmin, (_req, res) => {
    void (async () => {
      const [telemetry, stripe, entitlements, push, recentErrors] = await Promise.all([
        telemetrySummary(),
        stripeIncomeSnapshot(),
        Promise.resolve(getEntitlementIncomeSnapshot()),
        Promise.resolve(getPushFunnelSnapshot(7)),
        fetchRecentApiErrors(40),
      ])
      res.json({
        ok: true,
        generatedAt: new Date().toISOString(),
        telemetry,
        stripe,
        entitlements,
        quota: getQuotaConfigSnapshot(),
        push,
        recentErrors,
      })
    })().catch((err: Error) => {
      console.error('[admin] summary:', err.message)
      res.status(500).json({ error: err.message || 'summary_failed' })
    })
  })

  /** Effective Free Peek quota + dial flags (same shape as summary.quota). */
  app.get('/api/admin/quota-config', requireAdmin, (_req, res) => {
    res.json({ ok: true, quota: getQuotaConfigSnapshot(), config: resolveOpsConfig() })
  })

  /**
   * PATCH Free Peek ops overrides (persisted under server/data/ops-config.json).
   * Body: { freeDailyLimit?: number, freePhoneTargetsEnabled?: boolean }
   * Pass null for a key to clear that override (fall back to env/default).
   */
  app.patch('/api/admin/quota-config', requireAdmin, (req, res) => {
    const result = patchOpsConfig(req.body)
    if (!result.ok) {
      res.status(400).json({
        error: result.error,
        details: result.details,
      })
      return
    }
    res.json({
      ok: true,
      quota: getQuotaConfigSnapshot(),
      config: result.config,
    })
  })

  /**
   * POST /api/admin/push/test — send one APNs test notification (admin-only).
   * Body: { guestId?: string, token?: string, title?, body?, environment? }
   * Prefer guestId → prefs/devices token lookup; else raw token.
   */
  app.post('/api/admin/push/test', requireAdmin, (req, res) => {
    void (async () => {
      const body = (req.body ?? {}) as Record<string, unknown>
      const guestId =
        typeof body.guestId === 'string' ? body.guestId.trim() : ''
      const rawToken =
        typeof body.token === 'string' ? body.token.trim().toLowerCase() : ''
      const title =
        typeof body.title === 'string' && body.title.trim()
          ? body.title.trim()
          : 'Photo Recipes test'
      const alertBody =
        typeof body.body === 'string' && body.body.trim()
          ? body.body.trim()
          : 'Admin push test — tap to open Auto Optimize'
      const envRaw =
        typeof body.environment === 'string'
          ? body.environment.trim().toLowerCase()
          : ''
      const environment =
        envRaw === 'production' || envRaw === 'sandbox'
          ? (envRaw as 'sandbox' | 'production')
          : getDefaultApnsEnvironment()

      let token = rawToken
      let resolvedFrom: 'token' | 'guestId' | null = rawToken ? 'token' : null

      if (!token && guestId) {
        const prefs = getPushPrefs(guestId)
        const mysqlTokens = await listPushTokensForGuest(guestId)
        const tokens = mergeApnsTokens(prefs.apnsDeviceTokens, mysqlTokens)
        if (!tokens.length) {
          res.status(404).json({
            error: 'no_device_token',
            guestId,
            hint: 'Register via POST /api/push/register first.',
          })
          return
        }
        // Prefer matching environment when present
        const match =
          tokens.find((t) => t.environment === environment) ?? tokens[0]!
        token = match.token
        resolvedFrom = 'guestId'
      }

      if (!token) {
        res.status(400).json({
          error: 'missing_target',
          hint: 'Provide guestId (preferred) or token.',
        })
        return
      }

      if (!/^[0-9a-f]{64}$/.test(token)) {
        res.status(400).json({ error: 'invalid_token' })
        return
      }

      const payload: ApnsPayload = {
        aps: {
          alert: { title, body: alertBody },
          sound: 'default',
        },
        type: 'pre_alarm_shoot_brief',
        deepLink: 'photo-recipes://auto-optimize',
        recipeChips: [{ id: 'admin_test', title: 'Admin test' }],
        entitlementTier: 'free',
        experiment: 'push_exp1',
      }

      const result = await sendApns(token, payload, { environment })
      const base = {
        tokenHint: token.slice(0, 8),
        environment,
        resolvedFrom,
        guestId: guestId || undefined,
      }
      if (!result.ok) {
        res.json({
          ok: false,
          ...base,
          error: result.error,
          ...(result.status !== undefined ? { status: result.status } : {}),
        })
        return
      }
      if (result.stub) {
        res.json({ ok: true, stub: true as const, reason: result.reason, ...base })
        return
      }
      res.json({ ok: true, stub: false as const, status: result.status, ...base })
    })().catch((err: Error) => {
      console.error('[admin] push/test:', err.message)
      res.status(500).json({ error: err.message || 'push_test_failed' })
    })
  })
}

export { ADMIN_COOKIE }
