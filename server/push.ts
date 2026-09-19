/**
 * Push Experiment 1 HTTP surface — register, prefs, events, cron tick.
 */
import crypto from 'node:crypto'
import type { Express, Request, Response } from 'express'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { getGuestId } from './entitlements.ts'
import {
  getPushPrefs,
  publicPrefsView,
  registerApnsToken,
  updatePushPrefs,
} from './pushPrefs.ts'
import { isPushExp1Enabled, runPushExp1Tick } from './pushScheduler.ts'
import { isApnsEnvPresent } from './apns.ts'

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

export function mountPushRoutes(app: Express) {
  /** POST /api/push/register — iOS device token */
  app.post('/api/push/register', (req: Request, res: Response) => {
    const guestId = getGuestId(req, res)
    const body = (req.body ?? {}) as Record<string, unknown>
    try {
      registerApnsToken(guestId, {
        token: String(body.token ?? ''),
        platform: String(body.platform ?? ''),
        bundleId: String(body.bundleId ?? ''),
        environment: String(body.environment ?? ''),
        appVersion:
          typeof body.appVersion === 'string' ? body.appVersion : undefined,
      })
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
      const line = JSON.stringify({
        at: new Date().toISOString(),
        guestId,
        event: name,
        type: typeof ev.type === 'string' ? ev.type : undefined,
        stage: typeof ev.stage === 'string' ? ev.stage : undefined,
        // attribution helpers — no email/name/token
        props:
          ev.props && typeof ev.props === 'object' && !Array.isArray(ev.props)
            ? sanitizeProps(ev.props as Record<string, unknown>)
            : undefined,
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

export function pushHealthSnippet() {
  return {
    pushExp1: isPushExp1Enabled(),
    apnsEnv: isApnsEnvPresent(),
    cronSecret: Boolean(process.env.PUSH_CRON_SECRET?.trim()),
  }
}
