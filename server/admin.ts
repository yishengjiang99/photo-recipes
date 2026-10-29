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
import {
  dayBuckets,
  fetchCanonicalFunnel,
  fetchDailyActiveUsers,
  fetchHourlyActiveUsers,
  fetchRecentApiErrors,
  ptOffsetSec,
  type CanonicalFunnel,
} from './telemetry.ts'
import { fetchDevicesSummary, fetchKnownApps } from './installDevices.ts'
import { fetchFinalcapUsage, parseDaysParam } from './finalcapUsage.ts'
import { fetchFinalcapFunnels } from './finalcapFunnels.ts'
import { fetchGbkBilling } from './gbkBilling.ts'
import {
  applyFilters,
  buildAggregateCsv,
  byEvent,
  computeActivation,
  computeCapture,
  computeExperiments,
  computeOptimizePerformance,
  computeOverview,
  computePaywall,
  computeReconciliation,
  distinctAnons,
  envelope,
  fetchAnalyticsDataset,
  inWindow,
  parseAnalyticsQuery,
  prevPeriod,
  propStr,
  warningsFor,
  type AnalyticsFilters,
  type Period,
} from './adminAnalytics.ts'
import { ALL_APPS, appAnd, iosOnlyScope, parseAppParam, type AppScope } from './appFilter.ts'

const appKey = (app: AppScope): string => app ?? ALL_APPS

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

async function telemetrySummary(app: AppScope) {
  const configured = isMysqlConfigured() && Boolean(getMysqlPool())
  const empty = {
    configured,
    app: appKey(app),
    events8h: 0,
    events24h: 0,
    events7d: 0,
    dau: 0,
    dauRaw: 0,
    wau: 0,
    active8h: 0,
    topEvents: [] as Array<{ event: string; count: number }>,
    topEvents8h: [] as Array<{ event: string; count: number }>,
    platformSplit: [] as Array<{ platform: string; count: number }>,
    eventsByPlatform8h: {} as Record<string, number>,
    activeByPlatform8h: {} as Record<string, number>,
    topEventsByPlatform: {} as Record<string, Array<{ event: string; count: number }>>,
    topEvents8hByPlatform: {} as Record<string, Array<{ event: string; count: number }>>,
    hourlyActive: {
      hours: 168,
      timezone: 'America/Los_Angeles',
      definition: '',
      series: [] as Array<{ bucket: number; users: number }>,
      error: undefined as string | undefined,
    },
    dailyActive: {
      days: 30,
      timezone: 'America/Los_Angeles',
      definition: '',
      series: [] as Array<{ bucket: number; day: string; users: number }>,
      error: undefined as string | undefined,
    },
    canonicalFunnel: null as CanonicalFunnel | null,
  }
  const pool = getMysqlPool()
  if (!pool) return { ...empty, canonicalFunnel: await fetchCanonicalFunnel(7, app) }
  const af = appAnd('app', app)
  const afE = appAnd('e.app', app)
  const platE = iosOnlyScope(app) ? " AND e.platform = 'ios'" : ''

  try {
    const [[e8]] = (await pool.query(
      `SELECT COUNT(*) AS n FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 8 HOUR)${af.and}`,
      af.params,
    )) as unknown as [Array<{ n: number }>]
    const [[e24]] = (await pool.query(
      `SELECT COUNT(*) AS n FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 1 DAY)${af.and}`,
      af.params,
    )) as unknown as [Array<{ n: number }>]
    const [[e7]] = (await pool.query(
      `SELECT COUNT(*) AS n FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 7 DAY)${af.and}`,
      af.params,
    )) as unknown as [Array<{ n: number }>]
    const [[dau]] = (await pool.query(
      `SELECT COUNT(DISTINCT e.anon_id) AS n FROM telemetry_events e
       JOIN install_devices d ON d.anon_id = e.anon_id AND d.app = e.app AND d.platform = e.platform
       WHERE e.created_at >= (NOW(3) - INTERVAL 1 DAY)
         AND d.is_test = 0${platE}${afE.and}`,
      afE.params,
    )) as unknown as [Array<{ n: number }>]
    const [[dauRaw]] = (await pool.query(
      `SELECT COUNT(DISTINCT anon_id) AS n FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 1 DAY)${af.and}`,
      af.params,
    )) as unknown as [Array<{ n: number }>]
    const [[wau]] = (await pool.query(
      `SELECT COUNT(DISTINCT anon_id) AS n FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 7 DAY)${af.and}`,
      af.params,
    )) as unknown as [Array<{ n: number }>]
    const [[a8]] = (await pool.query(
      `SELECT COUNT(DISTINCT anon_id) AS n FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 8 HOUR)${af.and}`,
      af.params,
    )) as unknown as [Array<{ n: number }>]
    const [topRows] = await pool.query(
      `SELECT event, COUNT(*) AS c FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 7 DAY)${af.and}
       GROUP BY event ORDER BY c DESC LIMIT 15`,
      af.params,
    )
    const [topRows8h] = await pool.query(
      `SELECT event, COUNT(*) AS c FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 8 HOUR)${af.and}
       GROUP BY event ORDER BY c DESC LIMIT 15`,
      af.params,
    )
    const [platRows] = await pool.query(
      `SELECT platform, COUNT(*) AS c FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 7 DAY)${af.and}
       GROUP BY platform ORDER BY c DESC`,
      af.params,
    )
    const [evPlat8h] = await pool.query(
      `SELECT platform, COUNT(*) AS n FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 8 HOUR)${af.and}
       GROUP BY platform`,
      af.params,
    )
    const [actPlat8h] = await pool.query(
      `SELECT platform, COUNT(DISTINCT anon_id) AS n FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 8 HOUR)${af.and}
       GROUP BY platform`,
      af.params,
    )
    const [topPlatRows] = await pool.query(
      `SELECT platform, event, COUNT(*) AS c FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 7 DAY)${af.and}
       GROUP BY platform, event`,
      af.params,
    )
    const [topPlatRows8h] = await pool.query(
      `SELECT platform, event, COUNT(*) AS c FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL 8 HOUR)${af.and}
       GROUP BY platform, event`,
      af.params,
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
    const [hourlyActive, dailyActive, canonicalFunnel] = await Promise.all([
      fetchHourlyActiveUsers(168, app),
      fetchDailyActiveUsers(30, app),
      fetchCanonicalFunnel(7, app),
    ])

    return {
      configured: true,
      app: appKey(app),
      events8h: Number(e8?.n) || 0,
      events24h: Number(e24?.n) || 0,
      events7d: Number(e7?.n) || 0,
      dau: Number(dau?.n) || 0,
      dauRaw: Number(dauRaw?.n) || 0,
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
      hourlyActive,
      dailyActive,
      canonicalFunnel,
    }
  } catch (err) {
    console.warn(
      '[admin] telemetry summary failed:',
      err instanceof Error ? err.message : err,
    )
    return {
      ...empty,
      configured: true,
      error: 'query_failed',
      canonicalFunnel: await fetchCanonicalFunnel(7, app),
    }
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

  /**
   * GET /api/admin/summary[?app=<name>|all]
   * `app` scopes the telemetry-derived sections (events, DAU/WAU, hourly/daily active,
   * devices, recent errors) to telemetry_events.app / install_devices.app.
   * Omitted → photo-recipes (the dashboard's original app-specific scope); `all` → every app.
   * Stripe / IAP entitlements / quota / push funnel are NOT per-telemetry-app and ignore it.
   */
  app.get('/api/admin/summary', requireAdmin, (req, res) => {
    const parsed = parseAppParam(req.query.app)
    if (!parsed.ok) {
      res.status(400).json({ error: 'invalid_app', hint: 'app must match [A-Za-z0-9][A-Za-z0-9._-]{0,63} or "all".' })
      return
    }
    const scope = parsed.app
    void (async () => {
      const [telemetry, stripe, entitlements, push, recentErrors, devices, apps] = await Promise.all([
        telemetrySummary(scope),
        stripeIncomeSnapshot(),
        Promise.resolve(getEntitlementIncomeSnapshot()),
        Promise.resolve(getPushFunnelSnapshot(7)),
        fetchRecentApiErrors(40, scope),
        fetchDevicesSummary({ dayBuckets: (n) => dayBuckets(n), ptOffsetSec, days: 14, app: scope }),
        fetchKnownApps(),
      ])
      res.json({
        ok: true,
        generatedAt: new Date().toISOString(),
        app: appKey(scope),
        apps,
        telemetry,
        stripe,
        entitlements,
        quota: getQuotaConfigSnapshot(),
        push,
        recentErrors,
        devices,
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
   * GET /api/admin/finalcap-usage[?days=30]
   * FinalCap usage from the FinalCap server's OWN database (daily inference
   * usage, chat interactions, registered users, Apple subscribers) — a
   * separate data source from this app's telemetry_events; never merged into
   * the summary figures above. Soft-empty when FINALCUT_MYSQL_* is unset.
   */
  app.get('/api/admin/finalcap-usage', requireAdmin, (req, res) => {
    const parsed = parseDaysParam(req.query.days)
    if (!parsed.ok) {
      res.status(400).json({
        error: 'invalid_days',
        hint: 'days must be an integer between 1 and 90 (default 30).',
      })
      return
    }
    void (async () => {
      const finalcap = await fetchFinalcapUsage(parsed.days)
      res.json({ ok: true, generatedAt: new Date().toISOString(), finalcap })
    })().catch((err: Error) => {
      console.error('[admin] finalcap-usage:', err.message)
      res.status(500).json({ error: err.message || 'finalcap_usage_failed' })
    })
  })

  /**
   * GET /api/admin/finalcap-funnels[?days=30]
   * FinalCap app funnels from THIS app's telemetry_events (app = 'finalcap'
   * client events, distinct session_id, trailing complete PT days) — a
   * separate data source from /api/admin/finalcap-usage above (FinalCap's
   * own database) and never merged into the ProTune figures. Soft-zero
   * until FinalCap v1.0.1 ships and its events land. A sibling endpoint
   * (rather than a field on finalcap-usage) keeps the two sources' config
   * and failure domains separate: this one reads the panel's primary
   * MySQL, not FINALCUT_MYSQL_*.
   */
  app.get('/api/admin/finalcap-funnels', requireAdmin, (req, res) => {
    const parsed = parseDaysParam(req.query.days)
    if (!parsed.ok) {
      res.status(400).json({
        error: 'invalid_days',
        hint: 'days must be an integer between 1 and 90 (default 30).',
      })
      return
    }
    void (async () => {
      const funnels = await fetchFinalcapFunnels(parsed.days)
      res.json({ ok: true, generatedAt: new Date().toISOString(), funnels })
    })().catch((err: Error) => {
      console.error('[admin] finalcap-funnels:', err.message)
      res.status(500).json({ error: err.message || 'finalcap_funnels_failed' })
    })
  })

  /**
   * GET /api/admin/gbk-billing[?days=30]
   * GBK Composer billing funnel from the GBK server's own SQLite tables on
   * this host (billing_daily aggregates + billing_log recents), read by
   * server/gbkBilling.ts. A separate data source from this panel's
   * telemetry and from the FinalCap sections — never merged. Soft-zero
   * (`available: false`) when the GBK files are absent on the host.
   */
  app.get('/api/admin/gbk-billing', requireAdmin, (req, res) => {
    const parsed = parseDaysParam(req.query.days)
    if (!parsed.ok) {
      res.status(400).json({
        error: 'invalid_days',
        hint: 'days must be an integer between 1 and 90 (default 30).',
      })
      return
    }
    try {
      const billing = fetchGbkBilling(parsed.days)
      res.json({ ok: true, generatedAt: new Date().toISOString(), billing })
    } catch (err) {
      console.error('[admin] gbk-billing:', (err as Error).message)
      res.status(500).json({ error: (err as Error).message || 'gbk_billing_failed' })
    }
  })

  /**
   * Admin analytics & experiment monitoring — see server/adminAnalytics.ts
   * and docs/admin-analytics.md. All routes are requireAdmin, read-only,
   * bounded (92-day max range, 200k row cap), and scoped to
   * app='photo-recipes' telemetry only. Revenue figures attached to the
   * overview/paywall responses come from the existing local entitlement +
   * Stripe snapshots (estimates, NOT App Store Connect) — never from
   * telemetry event counts.
   */
  async function loadAnalytics(q: {
    startMs: number
    endMs: number
    rangeLabel: string
    filters: AnalyticsFilters
  }) {
    const period: Period = { startMs: q.startMs, endMs: q.endMs }
    const prev = prevPeriod(period)
    const dataset = await fetchAnalyticsDataset(prev.startMs, period.endMs, q.filters)
    const rowFilters: AnalyticsFilters = { ...q.filters, appVersion: null } // app_version already applied in SQL
    const cur = applyFilters(inWindow(dataset.rows, period.startMs, period.endMs), rowFilters)
    const prevRows = applyFilters(inWindow(dataset.rows, prev.startMs, prev.endMs), rowFilters)
    const installsIn = (p: Period) =>
      dataset.installs === null
        ? null
        : dataset.installs.filter((i) => i.first_seen_ms >= p.startMs && i.first_seen_ms < p.endMs)
    const installsCur = installsIn(period)
    const installsPrev = installsIn(prev)
    const overview = computeOverview(cur, prevRows, installsCur, installsPrev, dataset.installs, period)
    const prevOverview = computeOverview(prevRows, [], installsPrev, null, dataset.installs, prev)
    const activation = computeActivation(cur, period)
    const capture = computeCapture(cur)
    const paywall = computePaywall(cur)
    const reconciliation = computeReconciliation(cur)
    const perf = computeOptimizePerformance(cur, prevRows, period)
    const prevPerf = computeOptimizePerformance(prevRows, [], prev)
    const prevVerificationFailures = byEvent(prevRows, 'purchase_failed').filter(
      (r) => propStr(r, 'stage') === 'verification' || propStr(r, 'error_category') === 'verification',
    ).length
    const experiments = computeExperiments(
      cur,
      activation,
      overview,
      perf,
      prevPerf,
      reconciliation,
      prevOverview,
      prevVerificationFailures,
      dataset.dataFreshness ? Date.parse(dataset.dataFreshness) : null,
      period,
    )
    const sampleSizes = {
      rows: cur.length,
      previousRows: prevRows.length,
      distinctUsers: distinctAnons(cur).size,
      distinctUsersPrevious: distinctAnons(prevRows).size,
    }
    const env = (metrics: Record<string, unknown>, extraWarnings: string[] = []) =>
      envelope({
        period,
        rangeLabel: q.rangeLabel,
        filters: q.filters,
        dataset,
        metrics,
        sampleSizes,
        extraWarnings: [...warningsFor(cur), ...extraWarnings],
      })
    return { period, prev, dataset, cur, prevRows, overview, prevOverview, activation, capture, paywall, reconciliation, perf, prevPerf, experiments, env }
  }

  const analyticsRoute =
    (view: string, pick: (ctx: Awaited<ReturnType<typeof loadAnalytics>>) => Record<string, unknown>) =>
    (req: Request, res: Response) => {
      const parsed = parseAnalyticsQuery(req.query as Record<string, unknown>)
      if (!parsed.ok) {
        res.status(400).json({ error: parsed.error, hint: parsed.hint })
        return
      }
      void (async () => {
        const ctx = await loadAnalytics(parsed.value)
        const revenue = {
          entitlements: getEntitlementIncomeSnapshot(),
          stripe: await stripeIncomeSnapshot(),
          note: 'Authoritative ledgers are App Store Connect (IAP) and Stripe (web). The figures here are the existing LOCAL snapshots: IAP = estimated MRR from local StoreKit-verified entitlements (gross, before Apple cut); Stripe = approx MRR from active/trialing subscriptions. Neither is derived from telemetry purchase events.',
        }
        const metrics = pick(ctx)
        if (view === 'overview' || view === 'paywall') metrics.revenue = revenue
        res.json(ctx.env(metrics))
      })().catch((err: Error) => {
        console.error(`[admin] analytics/${view}:`, err.message)
        res.status(500).json({ error: err.message || 'analytics_failed' })
      })
    }

  app.get('/api/admin/analytics/overview', requireAdmin, analyticsRoute('overview', (ctx) => ({ overview: ctx.overview, experiments: ctx.experiments.experiments, alerts: ctx.experiments.alerts, alertingNote: ctx.experiments.alertingNote })))
  app.get('/api/admin/analytics/activation', requireAdmin, analyticsRoute('activation', (ctx) => ({ activation: ctx.activation })))
  app.get('/api/admin/analytics/capture', requireAdmin, analyticsRoute('capture', (ctx) => ({ capture: ctx.capture })))
  app.get('/api/admin/analytics/paywall', requireAdmin, analyticsRoute('paywall', (ctx) => ({ paywall: ctx.paywall })))
  app.get('/api/admin/analytics/purchases', requireAdmin, analyticsRoute('purchases', (ctx) => ({ reconciliation: ctx.reconciliation })))
  app.get('/api/admin/analytics/reconciliation', requireAdmin, analyticsRoute('reconciliation', (ctx) => ({ reconciliation: ctx.reconciliation })))
  app.get('/api/admin/analytics/optimize-performance', requireAdmin, analyticsRoute('optimize-performance', (ctx) => ({ optimizePerformance: ctx.perf })))
  app.get('/api/admin/analytics/experiments', requireAdmin, analyticsRoute('experiments', (ctx) => ({ experiments: ctx.experiments.experiments, alerts: ctx.experiments.alerts, alertingNote: ctx.experiments.alertingNote })))

  /**
   * GET /api/admin/analytics/export?view=<view>&format=csv[&range&filters]
   * Aggregate-only CSV. Transaction-level reconciliation rows are never
   * exported. Every export is audit-logged (view + period + row count).
   */
  app.get('/api/admin/analytics/export', requireAdmin, (req, res) => {
    const view = typeof req.query.view === 'string' ? req.query.view : ''
    const format = typeof req.query.format === 'string' ? req.query.format : 'csv'
    const views = ['overview', 'activation', 'capture', 'paywall', 'purchases', 'reconciliation', 'optimize-performance']
    if (!views.includes(view)) {
      res.status(400).json({ error: 'invalid_view', hint: `view must be one of ${views.join(', ')}` })
      return
    }
    if (format !== 'csv') {
      res.status(400).json({ error: 'invalid_format', hint: 'only format=csv is supported' })
      return
    }
    const parsed = parseAnalyticsQuery(req.query as Record<string, unknown>)
    if (!parsed.ok) {
      res.status(400).json({ error: parsed.error, hint: parsed.hint })
      return
    }
    void (async () => {
      const ctx = await loadAnalytics(parsed.value)
      const metrics: Record<string, unknown> =
        view === 'overview'
          ? { overview: ctx.overview }
          : view === 'activation'
            ? { activation: ctx.activation }
            : view === 'capture'
              ? { capture: ctx.capture }
              : view === 'paywall'
                ? { paywall: ctx.paywall }
                : view === 'optimize-performance'
                  ? { optimizePerformance: ctx.perf }
                  : { reconciliation: ctx.reconciliation }
      const env = ctx.env(metrics)
      const csv = buildAggregateCsv(view, env)
      console.info(
        '[admin-analytics] export',
        JSON.stringify({ view, period: env.period, rows: ctx.cur.length, at: new Date().toISOString() }),
      )
      res.setHeader('Content-Type', 'text/csv; charset=utf-8')
      res.setHeader('Content-Disposition', `attachment; filename="admin-analytics-${view}.csv"`)
      res.send(csv)
    })().catch((err: Error) => {
      console.error('[admin] analytics/export:', err.message)
      res.status(500).json({ error: err.message || 'analytics_export_failed' })
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
