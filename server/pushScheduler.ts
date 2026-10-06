/**
 * Push schedulers:
 * 1) Come-shoot / D1 return nudges — no shootWindow required (primary path).
 * 2) Push Experiment 1 — pre-alarm shoot brief when user set a shoot window.
 * Both respect quiet hours / weekly caps / feature flag, send via APNs.
 */
import crypto from 'node:crypto'
import { sendApns, type ApnsPayload } from './apns.ts'
import { pickRecipeChips } from './pushCatalog.ts'
import {
  BRIEF_LEAD_MAX,
  BRIEF_LEAD_MIN,
  DEFAULT_WEEKLY_CAP_FREE,
  DEFAULT_WEEKLY_CAP_PRO,
  getPushPrefs,
  listAllPushPrefs,
  pruneSentThisWeek,
  recordBriefSent,
  recordNudgeSent,
  removeApnsTokenEverywhere,
  type PushPrefs,
} from './pushPrefs.ts'
import {
  deletePushTokenEverywhere,
  listPushTokensForGuest,
  mergeApnsTokens,
} from './pushDevices.ts'
import {
  findEntitlementByGuestId,
  isProStatus,
  type Entitlement,
} from './entitlements.ts'

export const DEEP_LINK = 'photo-recipes://auto-optimize'

/** APNs 410 / Unregistered → the token is permanently dead; stop sending to it. */
export function isUnregisteredApnsError(r: { ok: boolean; error?: string; status?: number }): boolean {
  if (r.ok) return false
  if (r.status === 410) return true
  return /Unregistered/.test(r.error ?? '')
}

async function pruneDeadToken(token: string): Promise<void> {
  removeApnsTokenEverywhere(token)
  await deletePushTokenEverywhere(token)
  console.info(JSON.stringify({ event: 'push_token_pruned', reason: 'unregistered', tokenHint: token.slice(0, 8) }))
}

export type EntitlementTier = 'free' | 'trial' | 'pro'

export function isPushExp1Enabled(): boolean {
  return process.env.PUSH_EXP1_ENABLED?.trim().toLowerCase() === 'true'
}

/** Stable 50% treatment when flag enabled; holdout bit or hash → control. */
export function inTreatment(guestId: string, prefs: PushPrefs): boolean {
  if (prefs.experimentHoldout) return false
  const digest = crypto.createHash('sha256').update(`push_exp1:${guestId}`).digest()
  return (digest[0]! & 1) === 1
}

export function tierFromEntitlement(ent: Entitlement | null): EntitlementTier {
  if (!ent || !isProStatus(ent.status)) return 'free'
  if (ent.status === 'trialing') return 'trial'
  return 'pro'
}

function minutesToHHMM(mins: number): string {
  const m = ((mins % (24 * 60)) + 24 * 60) % (24 * 60)
  const h = Math.floor(m / 60)
  const mm = m % 60
  return `${String(h).padStart(2, '0')}:${String(mm).padStart(2, '0')}`
}

function hhmmToMinutes(hhmm: string): number {
  const [h, m] = hhmm.split(':').map(Number)
  return (h ?? 0) * 60 + (m ?? 0)
}

/** Local wall parts in user timezone. */
function localParts(now: Date, timeZone: string): {
  hhmm: string
  dayOfWeek: number
  minutes: number
} {
  const fmt = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
    weekday: 'short',
  })
  const parts = fmt.formatToParts(now)
  const hour = parts.find((p) => p.type === 'hour')?.value ?? '00'
  const minute = parts.find((p) => p.type === 'minute')?.value ?? '00'
  const weekday = parts.find((p) => p.type === 'weekday')?.value ?? 'Mon'
  const map: Record<string, number> = {
    Sun: 0,
    Mon: 1,
    Tue: 2,
    Wed: 3,
    Thu: 4,
    Fri: 5,
    Sat: 6,
  }
  const hhmm = `${hour.padStart(2, '0')}:${minute.padStart(2, '0')}`
  return {
    hhmm,
    dayOfWeek: map[weekday] ?? now.getUTCDay(),
    minutes: hhmmToMinutes(hhmm),
  }
}

/** True if `t` (minutes) falls inside quiet [start,end) allowing overnight wrap. */
export function inQuietHours(
  tMinutes: number,
  quiet: { start: string; end: string },
): boolean {
  const s = hhmmToMinutes(quiet.start)
  const e = hhmmToMinutes(quiet.end)
  if (s === e) return false
  if (s < e) return tMinutes >= s && tMinutes < e
  // overnight e.g. 21:00–07:00
  return tMinutes >= s || tMinutes < e
}

/**
 * Quiet-hours rule (spec): no pushes during quiet hours UNLESS the shoot
 * alarm (window start) itself falls inside the quiet window.
 */
export function quietHoursBlocks(
  nowLocalMinutes: number,
  shootStartMinutes: number,
  quiet: { start: string; end: string },
): boolean {
  const nowQuiet = inQuietHours(nowLocalMinutes, quiet)
  if (!nowQuiet) return false
  const shootInsideQuiet = inQuietHours(shootStartMinutes, quiet)
  return !shootInsideQuiet
}

/** Minutes until next shoot start today (or null if not today / past). */
function minutesUntilShootStart(
  nowMinutes: number,
  shootStart: string,
  dayOfWeek: number,
  daysOfWeek?: number[],
): number | null {
  if (daysOfWeek && daysOfWeek.length && !daysOfWeek.includes(dayOfWeek)) {
    return null
  }
  const start = hhmmToMinutes(shootStart)
  let delta = start - nowMinutes
  // Allow small negative only if we already passed? No — only forward today.
  if (delta < 0) return null
  return delta
}

function buildCopy(
  tier: EntitlementTier,
  chips: Array<{ id: string; title: string }>,
): { title: string; body: string } {
  const names = chips.map((c) => c.title).join(' · ')
  if (tier === 'pro') {
    return {
      title: 'Shoot brief ready',
      body: `Three recipes for your window: ${names}. Open Auto Optimize whenever you’re ready.`,
    }
  }
  if (tier === 'trial') {
    return {
      title: 'Shoot brief ready',
      body: `Three recipes for your window: ${names}. Open Auto Optimize — your trial includes unlimited Optimize.`,
    }
  }
  // Free Peek — useful, no Unlimited promise
  return {
    title: 'Shoot brief ready',
    body: `Three recipes for your window: ${names}. Open Auto Optimize (Free Peek: limited Optimize/day).`,
  }
}

export type TickResult = {
  enabled: boolean
  scanned: number
  sent: number
  skipped: Array<{ guestId: string; reason: string }>
  errors: Array<{ guestId: string; error: string }>
}

export async function runPushExp1Tick(now = new Date()): Promise<TickResult> {
  const result: TickResult = {
    enabled: isPushExp1Enabled(),
    scanned: 0,
    sent: 0,
    skipped: [],
    errors: [],
  }

  if (!result.enabled) {
    return result
  }

  const all = listAllPushPrefs()
  result.scanned = all.length

  for (const prefs of all) {
    const guestId = prefs.guestId
    try {
      if (!prefs.pushOptIn) {
        result.skipped.push({ guestId, reason: 'not_opted_in' })
        continue
      }
      if (!prefs.shootWindow) {
        result.skipped.push({ guestId, reason: 'no_shoot_window' })
        continue
      }
      const mysqlTokens = await listPushTokensForGuest(guestId)
      const tokens = mergeApnsTokens(prefs.apnsDeviceTokens, mysqlTokens)
      if (!tokens.length) {
        result.skipped.push({ guestId, reason: 'no_device_token' })
        continue
      }
      if (!inTreatment(guestId, prefs)) {
        result.skipped.push({ guestId, reason: 'holdout' })
        continue
      }

      const local = localParts(now, prefs.timezone || 'UTC')
      const until = minutesUntilShootStart(
        local.minutes,
        prefs.shootWindow.start,
        local.dayOfWeek,
        prefs.shootWindow.daysOfWeek,
      )
      if (until === null || until < BRIEF_LEAD_MIN || until > BRIEF_LEAD_MAX) {
        result.skipped.push({ guestId, reason: 'outside_lead_window' })
        continue
      }

      const shootStartMin = hhmmToMinutes(prefs.shootWindow.start)
      if (quietHoursBlocks(local.minutes, shootStartMin, prefs.quietHours)) {
        result.skipped.push({ guestId, reason: 'quiet_hours' })
        continue
      }

      // Dedupe: already sent a brief in the last lead window for this start
      if (prefs.lastBriefAt) {
        const last = Date.parse(prefs.lastBriefAt)
        if (Number.isFinite(last) && now.getTime() - last < BRIEF_LEAD_MAX * 60 * 1000) {
          result.skipped.push({ guestId, reason: 'already_sent_recently' })
          continue
        }
      }

      const ent = findEntitlementByGuestId(guestId)
      const tier = tierFromEntitlement(ent)
      const defaultCap =
        tier === 'free' ? DEFAULT_WEEKLY_CAP_FREE : DEFAULT_WEEKLY_CAP_PRO
      const cap = prefs.weeklyCap ?? defaultCap
      const sentWeek = pruneSentThisWeek(prefs, now)
      if (sentWeek.length >= cap) {
        result.skipped.push({ guestId, reason: 'weekly_cap' })
        continue
      }

      const chips = pickRecipeChips(guestId, 3)
      const copy = buildCopy(tier, chips)
      const payload: ApnsPayload = {
        aps: {
          alert: { title: copy.title, body: copy.body },
          sound: 'default',
        },
        type: 'pre_alarm_shoot_brief',
        deepLink: DEEP_LINK,
        recipeChips: chips,
        entitlementTier: tier,
        experiment: 'push_exp1',
      }

      let anyOk = false
      for (const device of tokens) {
        const r = await sendApns(device.token, payload, {
          environment: device.environment,
        })
        if (r.ok) anyOk = true
        else {
          result.errors.push({
            guestId,
            error: 'error' in r ? r.error : 'send_failed',
          })
        }
      }

      if (anyOk) {
        recordBriefSent(guestId, now)
        result.sent += 1
        console.info(
          JSON.stringify({
            event: 'push_sent',
            type: 'pre_alarm_shoot_brief',
            stage: 'habit',
            guestId,
            tier,
            deepLink: DEEP_LINK,
            chipIds: chips.map((c) => c.id),
            untilMinutes: until,
          }),
        )
      }
    } catch (err) {
      result.errors.push({
        guestId,
        error: err instanceof Error ? err.message : 'tick_error',
      })
    }
  }

  return result
}



/** Local minutes for a loose "golden hour / evening shoot" window. */
export const COME_SHOOT_START_MIN = 16 * 60 + 30 // 16:30
export const COME_SHOOT_END_MIN = 19 * 60 // 19:00
/** D1 return: hours since first opt-in. */
export const D1_MIN_HOURS = 20
export const D1_MAX_HOURS = 48
/** Evening window for D1 copy (local). */
export const D1_EVENING_START_MIN = 17 * 60
export const D1_EVENING_END_MIN = 21 * 60

function sameUtcDay(a: Date, b: Date): boolean {
  return (
    a.getUTCFullYear() === b.getUTCFullYear() &&
    a.getUTCMonth() === b.getUTCMonth() &&
    a.getUTCDate() === b.getUTCDate()
  )
}

function hoursSince(iso: string | null | undefined, now: Date): number | null {
  if (!iso) return null
  const t = Date.parse(iso)
  if (!Number.isFinite(t)) return null
  return (now.getTime() - t) / (60 * 60 * 1000)
}

function nudgedToday(prefs: PushPrefs, now: Date): boolean {
  if (!prefs.lastNudgeAt) return false
  const t = Date.parse(prefs.lastNudgeAt)
  if (!Number.isFinite(t)) return false
  return sameUtcDay(new Date(t), now) || now.getTime() - t < 18 * 60 * 60 * 1000
}

function comeShootCopy(kind: 'd1_return' | 'come_shoot_nudge'): {
  title: string
  body: string
} {
  if (kind === 'd1_return') {
    return {
      title: 'Come shoot tonight',
      body: 'Golden light is waiting — open ProTune and tap Auto Optimize.',
    }
  }
  return {
    title: 'Golden hour',
    body: 'Light is soft right now — open the camera and Auto Optimize a frame.',
  }
}

export type NudgeTickResult = {
  enabled: boolean
  scanned: number
  sent: number
  skipped: Array<{ guestId: string; reason: string }>
  errors: Array<{ guestId: string; error: string }>
}

/**
 * Primary engagement path: D1 return + evening come-shoot.
 * Does NOT require shootWindow (Exp1's missing piece that caused 0 sends).
 * Enabled whenever PUSH_EXP1_ENABLED is true (same ops flag / cron).
 */
export async function runComeShootNudgeTick(
  now = new Date(),
): Promise<NudgeTickResult> {
  const result: NudgeTickResult = {
    enabled: isPushExp1Enabled(),
    scanned: 0,
    sent: 0,
    skipped: [],
    errors: [],
  }
  if (!result.enabled) return result

  const all = listAllPushPrefs()
  result.scanned = all.length

  for (const prefs of all) {
    const guestId = prefs.guestId
    try {
      if (!prefs.pushOptIn) {
        result.skipped.push({ guestId, reason: 'not_opted_in' })
        continue
      }
      const mysqlTokens = await listPushTokensForGuest(guestId)
      const tokens = mergeApnsTokens(prefs.apnsDeviceTokens, mysqlTokens)
      if (!tokens.length) {
        result.skipped.push({ guestId, reason: 'no_device_token' })
        continue
      }
      if (nudgedToday(prefs, now)) {
        result.skipped.push({ guestId, reason: 'already_nudged_today' })
        continue
      }

      const local = localParts(now, prefs.timezone || 'UTC')
      if (inQuietHours(local.minutes, prefs.quietHours)) {
        result.skipped.push({ guestId, reason: 'quiet_hours' })
        continue
      }

      const ent = findEntitlementByGuestId(guestId)
      const tier = tierFromEntitlement(ent)
      const defaultCap =
        tier === 'free' ? DEFAULT_WEEKLY_CAP_FREE : DEFAULT_WEEKLY_CAP_PRO
      const cap = prefs.weeklyCap ?? defaultCap
      const sentWeek = pruneSentThisWeek(prefs, now)
      if (sentWeek.length >= cap) {
        result.skipped.push({ guestId, reason: 'weekly_cap' })
        continue
      }

      const hours = hoursSince(prefs.optedInAt ?? prefs.updatedAt, now)
      let kind: 'd1_return' | 'come_shoot_nudge' | null = null

      // D1 return: 20–48h after opt-in, evening local window.
      if (
        hours !== null &&
        hours >= D1_MIN_HOURS &&
        hours <= D1_MAX_HOURS &&
        local.minutes >= D1_EVENING_START_MIN &&
        local.minutes < D1_EVENING_END_MIN &&
        !prefs.lastNudgeAt
      ) {
        kind = 'd1_return'
      } else if (
        local.minutes >= COME_SHOOT_START_MIN &&
        local.minutes < COME_SHOOT_END_MIN
      ) {
        // Evening golden-hour come-shoot for anyone opted in with a token.
        kind = 'come_shoot_nudge'
      }

      if (!kind) {
        result.skipped.push({ guestId, reason: 'outside_nudge_window' })
        continue
      }

      const copy = comeShootCopy(kind)
      const chips = pickRecipeChips(guestId, 3)
      const payload: ApnsPayload = {
        aps: {
          alert: { title: copy.title, body: copy.body },
          sound: 'default',
        },
        type: kind,
        deepLink: DEEP_LINK,
        recipeChips: chips,
        entitlementTier: tier,
        experiment: kind === 'd1_return' ? 'd1_return' : 'come_shoot',
      }

      let anyOk = false
      for (const device of tokens) {
        const r = await sendApns(device.token, payload, {
          environment: device.environment,
        })
        if (r.ok) anyOk = true
        else {
          result.errors.push({
            guestId,
            error: 'error' in r ? r.error : 'send_failed',
          })
          if (isUnregisteredApnsError(r)) await pruneDeadToken(device.token)
        }
      }

      if (anyOk) {
        recordNudgeSent(guestId, now)
        result.sent += 1
        console.info(
          JSON.stringify({
            event: 'push_sent',
            type: kind,
            stage: kind === 'd1_return' ? 'activation' : 'habit',
            guestId,
            tier,
            deepLink: DEEP_LINK,
          }),
        )
      }
    } catch (err) {
      result.errors.push({
        guestId,
        error: err instanceof Error ? err.message : 'tick_error',
      })
    }
  }

  return result
}

/** Test helper — re-export minutes formatting for docs */
export { minutesToHHMM, hhmmToMinutes, getPushPrefs }
