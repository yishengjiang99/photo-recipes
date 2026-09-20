/**
 * Push Experiment 1 HTTP surface — register, prefs, events, cron tick.
 */
import crypto from 'node:crypto'
import type { Express, Request, Response } from 'express'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { findEntitlementByGuestId, getGuestId } from './entitlements.ts'
import {
  getPushPrefs,
  listAllPushPrefs,
  publicPrefsView,
  registerApnsToken,
  updatePushPrefs,
} from './pushPrefs.ts'
import { upsertDeviceAndPushToken } from './pushDevices.ts'
import {
  DEEP_LINK,
  isPushExp1Enabled,
  runPushExp1Tick,
  tierFromEntitlement,
} from './pushScheduler.ts'
import { sendApns, isApnsEnvPresent, type ApnsPayload } from './apns.ts'
import { pickRecipeChips } from './pushCatalog.ts'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const EVENTS_LOG = path.resolve(__dirname, 'data/push-events.jsonl')

/** Client analytics events allowed from the Biz Dev memo (+ attribution helpers). */
const EVENT_ALLOWLIST = new Set([
  'push_permission_prompt_shown',
  'push_permission_accepted',
  'push_permission_denied',
  'push_sent',
  'push_opened',
  'auto_optimize_started',
  'paywall_from_push',
  'trial_start',
  'day_pass_purchase',
  'subscribe',
  'push_opt_out',
  'push_prefs_updated',
  // Build 23: APNs registration observability (iOS → nginx)
  'apns_token_received',
  'apns_register_failed',
])

function appendEventLine(line: string) {
  fs.mkdirSync(path.dirname(EVENTS_LOG), { recursive: true })
  fs.appendFileSync(EVENTS_LOG, line + '\n', 'utf8')
}

function cronAuthorized(req: Request): boolean {
  const secret = process.env.PUSH_CRON_SECRET?.trim()
  if (!secret) return false
  const hdr = req.headers['x-push-cron-secret']
  const val = Array.isArray(hdr) ? hdr[0] : hdr
  if (!val) return false
  try {
    const a = Buffer.from(val)
    const b = Buffer.from(secret)
    if (a.length !== b.length) return false
    return crypto.timingSafeEqual(a, b)
  } catch {
    return false
  }
}

/** Explicit allow header required for production APNs test-send (in addition to cron secret). */
export const PUSH_TEST_ALLOW_PRODUCTION_HEADER = 'x-push-test-allow-production'

/** True when X-Push-Test-Allow-Production is a clear truthy allow (1/true/yes). */
export function productionTestSendAllowed(req: Request): boolean {
  const hdr = req.headers[PUSH_TEST_ALLOW_PRODUCTION_HEADER]
  const val = (Array.isArray(hdr) ? hdr[0] : hdr)?.trim().toLowerCase()
  return val === '1' || val === 'true' || val === 'yes'
}

export function mountPushRoutes(app: Express) {
  /** POST /api/push/register — iOS device token */
  app.post('/api/push/register', (req: Request, res: Response) => {
    const guestId = getGuestId(req, res)
    const body = (req.body ?? {}) as Record<string, unknown>
    try {
      const token = String(body.token ?? '')
      const platform = String(body.platform ?? '')
      const bundleId = String(body.bundleId ?? '')
      const environment = String(body.environment ?? '')
      const appVersion =
        typeof body.appVersion === 'string' ? body.appVersion : undefined
      registerApnsToken(guestId, {
        token,
        platform,
        bundleId,
        environment,
        appVersion,
      })
      // Dual-write MySQL devices + push_tokens when pool is configured (soft-fail).
      if (
        platform === 'ios' &&
        (environment === 'sandbox' || environment === 'production')
      ) {
        void upsertDeviceAndPushToken({
          guestId,
          platform: 'ios',
          bundleId: bundleId.trim() || 'com.ragnus.mvp',
          environment,
          token: token.trim().toLowerCase(),
          appVersion,
        })
      }
      res.json({ ok: true, guestId })
    } catch (err) {
      res.status(400).json({
        error: err instanceof Error ? err.message : 'register_failed',
      })
    }
  })

  /** GET /api/push/prefs */
  app.get('/api/push/prefs', (req: Request, res: Response) => {
    const guestId = getGuestId(req, res)
    res.json({
      ok: true,
      prefs: publicPrefsView(getPushPrefs(guestId)),
      experiment: {
        name: 'push_exp1',
        enabled: isPushExp1Enabled(),
      },
    })
  })

  /** PUT /api/push/prefs */
  app.put('/api/push/prefs', (req: Request, res: Response) => {
    const guestId = getGuestId(req, res)
    const body = (req.body ?? {}) as Record<string, unknown>
    try {
      const patch: Parameters<typeof updatePushPrefs>[1] = {}
      if ('shootWindow' in body) {
        patch.shootWindow =
          body.shootWindow === null
            ? null
            : (body.shootWindow as {
                start: string
                end: string
                daysOfWeek?: number[]
              })
      }
      if ('quietHours' in body && body.quietHours && typeof body.quietHours === 'object') {
        patch.quietHours = body.quietHours as { start: string; end: string }
      }
      if ('weeklyCap' in body) {
        patch.weeklyCap =
          body.weeklyCap === null ? null : Number(body.weeklyCap)
      }
      if (typeof body.pushOptIn === 'boolean') patch.pushOptIn = body.pushOptIn
      if (typeof body.experimentHoldout === 'boolean') {
        patch.experimentHoldout = body.experimentHoldout
      }
      if (typeof body.timezone === 'string') patch.timezone = body.timezone

      const prefs = updatePushPrefs(guestId, patch)
      res.json({ ok: true, prefs: publicPrefsView(prefs) })
    } catch (err) {
      res.status(400).json({
        error: err instanceof Error ? err.message : 'prefs_update_failed',
      })
    }
  })

  /** POST /api/push/events — allowlisted client analytics (guest id only, no PII) */
  app.post('/api/push/events', (req: Request, res: Response) => {
    const guestId = getGuestId(req, res)
    const body = (req.body ?? {}) as Record<string, unknown>
    const eventsIn = Array.isArray(body.events)
      ? body.events
      : body.event
        ? [body]
        : []

    if (!eventsIn.length) {
      res.status(400).json({ error: 'Provide "event" or "events[]"' })
      return
    }

    const accepted: string[] = []
    const rejected: string[] = []

    for (const raw of eventsIn) {
      if (!raw || typeof raw !== 'object') {
        rejected.push('invalid')
        continue
      }
      const ev = raw as Record<string, unknown>
      const name = typeof ev.event === 'string' ? ev.event.trim() : ''
      if (!EVENT_ALLOWLIST.has(name)) {
        rejected.push(name || 'unknown')
        continue
      }
      const rawProps =
        ev.props && typeof ev.props === 'object' && !Array.isArray(ev.props)
          ? (ev.props as Record<string, unknown>)
          : ev.properties &&
              typeof ev.properties === 'object' &&
              !Array.isArray(ev.properties)
            ? (ev.properties as Record<string, unknown>)
            : undefined
      const line = JSON.stringify({
        at: new Date().toISOString(),
        guestId,
        event: name,
        type: typeof ev.type === 'string' ? ev.type : undefined,
        stage: typeof ev.stage === 'string' ? ev.stage : undefined,
        // attribution helpers — no email/name/token
        props: rawProps ? sanitizeProps(rawProps) : undefined,
      })
      appendEventLine(line)
      console.info(line)
      accepted.push(name)
    }

    res.json({ ok: true, accepted, rejected })
  })

  /**
   * POST /api/push/tick — external cron (Ubuntu). Header: X-Push-Cron-Secret.
   * Prefer this over in-process setInterval.
   */
  app.post('/api/push/tick', async (req: Request, res: Response) => {
    if (!cronAuthorized(req)) {
      res.status(401).json({ error: 'unauthorized' })
      return
    }
    try {
      const tick = await runPushExp1Tick(new Date())
      res.json({ ok: true, tick })
    } catch (err) {
      console.error('[push/tick]', err instanceof Error ? err.message : err)
      res.status(500).json({ error: 'tick_failed' })
    }
  })

  /**
   * POST /api/push/test-send — secret-gated APNs proof (does NOT require PUSH_EXP1_ENABLED).
   * Headers: X-Push-Cron-Secret (same as /tick). For production APNs targets also require
   * X-Push-Test-Allow-Production: 1. Sandbox remains secret-only.
   * Body: { guestId?, token?, environment?, title?, body? }.
   * Resolve token from body.token or guestId's pushPrefs registry. Never puts Stripe/IAP URLs in payload.
   */
  app.post('/api/push/test-send', async (req: Request, res: Response) => {
    if (!cronAuthorized(req)) {
      res.status(401).json({ error: 'unauthorized' })
      return
    }
    const body = (req.body ?? {}) as Record<string, unknown>
    const guestId =
      typeof body.guestId === 'string' ? body.guestId.trim() : ''
    const tokenDirect =
      typeof body.token === 'string' ? body.token.trim() : ''
    const envOverride =
      body.environment === 'production' || body.environment === 'sandbox'
        ? (body.environment as 'sandbox' | 'production')
        : undefined
    const title =
      typeof body.title === 'string' && body.title.trim()
        ? body.title.trim()
        : 'Shoot brief ready'
    const alertBody =
      typeof body.body === 'string' && body.body.trim()
        ? body.body.trim()
        : 'Test send — open Auto Optimize when ready.'

    type Tok = { token: string; environment: 'sandbox' | 'production' }
    let targets: Tok[] = []

    if (tokenDirect) {
      targets = [
        {
          token: tokenDirect,
          environment: envOverride ?? 'sandbox',
        },
      ]
    } else if (guestId) {
      const prefs = getPushPrefs(guestId)
      targets = prefs.apnsDeviceTokens.map((t) => ({
        token: t.token,
        environment: envOverride ?? t.environment,
      }))
    } else {
      res.status(400).json({ error: 'Provide token or guestId' })
      return
    }

    if (!targets.length) {
      res.status(404).json({ error: 'no_device_token' })
      return
    }

    const hitsProduction = targets.some((t) => t.environment === 'production')
    if (hitsProduction && !productionTestSendAllowed(req)) {
      res.status(403).json({
        error: 'production_test_send_refused',
        message:
          'Production APNs test-send requires X-Push-Test-Allow-Production: 1 (in addition to X-Push-Cron-Secret). Sandbox needs the cron secret only.',
      })
      return
    }

    const chips = pickRecipeChips(guestId || 'test-send', 3)
    const ent = guestId ? findEntitlementByGuestId(guestId) : null
    const tier = guestId ? tierFromEntitlement(ent) : 'free'

    const payload: ApnsPayload = {
      aps: {
        alert: { title, body: alertBody },
        sound: 'default',
      },
      type: 'pre_alarm_shoot_brief',
      deepLink: DEEP_LINK,
      recipeChips: chips,
      entitlementTier: tier,
      experiment: 'push_exp1',
    }

    try {
      const results = []
      for (const t of targets) {
        const r = await sendApns(t.token, payload, {
          environment: t.environment,
        })
        results.push({
          environment: t.environment,
          tokenHint: t.token.slice(0, 8),
          ...r,
        })
      }
      const primary = results[0]!
      res.json({
        ok: primary.ok,
        apnsConfigured: isApnsEnvPresent(),
        deepLink: DEEP_LINK,
        entitlementTier: tier,
        chipIds: chips.map((c) => c.id),
        results,
      })
    } catch (err) {
      console.error(
        '[push/test-send]',
        err instanceof Error ? err.message : err,
      )
      res.status(500).json({ error: 'test_send_failed' })
    }
  })

}

const PROP_DENY = new Set([
  'email',
  'name',
  'token',
  'deviceToken',
  'authorization',
  'password',
])

function sanitizeProps(props: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {}
  for (const [k, v] of Object.entries(props)) {
    if (PROP_DENY.has(k.toLowerCase())) continue
    if (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean') {
      out[k] = v
    } else if (v === null) {
      out[k] = null
    }
  }
  return out
}


const FUNNEL_EVENTS = [
  'push_permission_prompt_shown',
  'push_permission_accepted',
  'push_permission_denied',
  'push_sent',
  'push_opened',
  'paywall_from_push',
  'trial_start',
  'day_pass_purchase',
  'subscribe',
  'push_opt_out',
  'auto_optimize_started',
] as const

/** Admin KPIs: local prefs registry + push-events.jsonl (not ASC). Soft-empty on errors. */
export function getPushFunnelSnapshot(days = 7) {
  const prefs = listAllPushPrefs()
  let withToken = 0
  let optIn = 0
  let holdout = 0
  let withShootWindow = 0
  let briefsSentThisWeek = 0
  for (const p of prefs) {
    if (p.apnsDeviceTokens?.length) withToken++
    if (p.pushOptIn) optIn++
    if (p.experimentHoldout) holdout++
    if (p.shootWindow) withShootWindow++
    briefsSentThisWeek += p.sentThisWeek?.length ?? 0
  }

  const eventCounts: Record<string, number> = {}
  for (const e of FUNNEL_EVENTS) eventCounts[e] = 0
  let eventsScanned = 0
  let eventsInWindow = 0
  const cutoff = Date.now() - days * 24 * 60 * 60 * 1000

  try {
    if (fs.existsSync(EVENTS_LOG)) {
      const raw = fs.readFileSync(EVENTS_LOG, 'utf8')
      for (const line of raw.split('\n')) {
        if (!line.trim()) continue
        eventsScanned++
        try {
          const row = JSON.parse(line) as { at?: string; event?: string }
          const t = row.at ? Date.parse(row.at) : NaN
          if (!Number.isFinite(t) || t < cutoff) continue
          eventsInWindow++
          const name = typeof row.event === 'string' ? row.event : ''
          if (name && name in eventCounts) eventCounts[name]++
          else if (name) eventCounts[name] = (eventCounts[name] ?? 0) + 1
        } catch {
          /* skip bad line */
        }
      }
    }
  } catch (err) {
    console.warn(
      '[admin/push] events read failed:',
      err instanceof Error ? err.message : err,
    )
  }

  const prompt = eventCounts.push_permission_prompt_shown || 0
  const accepted = eventCounts.push_permission_accepted || 0
  const denied = eventCounts.push_permission_denied || 0
  const opened = eventCounts.push_opened || 0
  const sent = eventCounts.push_sent || 0

  return {
    experimentEnabled: isPushExp1Enabled(),
    apnsEnvConfigured: isApnsEnvPresent(),
    days,
    registry: {
      guests: prefs.length,
      withToken,
      optIn,
      holdout,
      withShootWindow,
      briefsSentThisWeek,
    },
    events7d: eventCounts,
    funnel: {
      permissionPrompt: prompt,
      permissionAccepted: accepted,
      permissionDenied: denied,
      acceptRate: prompt > 0 ? accepted / prompt : null,
      pushSent: sent,
      pushOpened: opened,
      openRate: sent > 0 ? opened / sent : null,
      paywallFromPush: eventCounts.paywall_from_push || 0,
      subscribe: eventCounts.subscribe || 0,
    },
    eventsScanned,
    eventsInWindow,
    note: 'Push funnel from local push-events.jsonl + prefs registry — not App Store analytics.',
  }
}

export function pushHealthSnippet() {
  return {
    pushExp1: isPushExp1Enabled(),
    apnsEnv: isApnsEnvPresent(),
    cronSecret: Boolean(process.env.PUSH_CRON_SECRET?.trim()),
  }
}
