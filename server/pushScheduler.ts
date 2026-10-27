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
import { generateCopy, type CopyResult } from './lifecycleCopy.ts'
import {
  SEGMENTS,
  prettyLook,
  type CopyFacts,
  type SegmentDef,
} from './lifecycleSegments.ts'

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
  // Shipped features are on for everyone; only an explicit PUSH_EXP1_ENABLED=false (kill switch) disables.
  return process.env.PUSH_EXP1_ENABLED?.trim().toLowerCase() !== 'false'
}

/** No cohort split any more: every opted-in install is treated (kept for API compatibility). */
export function inTreatment(_guestId: string, _prefs: PushPrefs): boolean {
  return true
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

/** Facts source for nudge copy (wired in push.ts to the lifecycle engine's telemetry-derived
 * facts; tests and other callers may omit it and get conservative defaults). */
export type NudgeFactsProvider = (
  prefs: PushPrefs,
  tier: EntitlementTier,
  segment: SegmentDef,
  now: Date,
) => Promise<CopyFacts>

function defaultNudgeFacts(tier: EntitlementTier): CopyFacts {
  return { tier, capturesLastWeek: '0', usedAutoOptimize: false, favoriteLook: null, awayFor: null }
}

/**
 * Pre-approved rotation pool — used ONLY when the AI pipeline would repeat the exact text this
 * user received last time (e.g. Grok unreachable and the template is a repeat). Every variant
 * names the user's recipe chips; the tests hold all of them to validateCopy for every chip.
 */
export function nudgeFallbackPool(
  kind: 'd1_return' | 'come_shoot_nudge',
  chips: Array<{ id: string; title: string }>,
): Array<{ title: string; body: string }> {
  const names = chips.map((c) => prettyLook(c.id)).filter((n): n is string => !!n)
  const a = names[0] ?? 'a recipe'
  const b = names[1] ?? 'a portrait recipe'
  const c = names[2] ?? 'a landscape recipe'
  return kind === 'd1_return'
    ? [
        { title: 'Come shoot tonight', body: `Golden light is waiting — try ${a}. Open ProTune and tap Auto Optimize.` },
        { title: 'An evening idea', body: `${a} is an easy first recipe. Open the camera and tap Auto Optimize.` },
        { title: 'Tonight, one tap', body: `Open the camera, load ${a} and tap Auto Optimize for tuned settings.` },
      ]
    : [
        { title: 'Golden hour', body: `Light is soft right now — try ${a} and Auto Optimize a frame.` },
        { title: 'Evening light', body: `${a}, ${b} and ${c} all suit this light. Open the camera and Auto Optimize one.` },
        { title: 'Soft light outside', body: `A good evening for ${a}. Open the camera and let Auto Optimize set it up.` },
        { title: 'This evening', body: `Point at the soft light and try ${a}. Auto Optimize dials in the settings.` },
      ]
}

export function nudgeFallbackCopy(
  kind: 'd1_return' | 'come_shoot_nudge',
  chips: Array<{ id: string; title: string }>,
  avoid: { title: string; body: string } | null,
): { title: string; body: string } {
  const pool = nudgeFallbackPool(kind, chips)
  return pool.find((v) => !avoid || v.title !== avoid.title || v.body !== avoid.body) ?? pool[0]!
}

/**
 * Nudge copy comes from the same AI pipeline as the lifecycle pushes (Grok draft → guardrail
 * validation → cache → template), personalized with the user's facts and tonight's recipe chips.
 * Two guarantees on top of the pipeline: (1) the text names tonight's lead recipe chip — the goal
 * steers the draft, and a draft that still omits it is regenerated; (2) rotation — the exact text
 * a user received last time is never sent again back-to-back. If regeneration still fails either
 * check, the pre-approved pool supplies a variant that satisfies both.
 */
export async function buildNudgeCopy(
  kind: 'd1_return' | 'come_shoot_nudge',
  prefs: PushPrefs,
  tier: EntitlementTier,
  chips: Array<{ id: string; title: string }>,
  now: Date,
  factsProvider?: NudgeFactsProvider,
): Promise<CopyResult> {
  const segment = SEGMENTS[kind === 'd1_return' ? 'onboarding_d1' : 'weekly_tip']
  let facts = defaultNudgeFacts(tier)
  if (factsProvider) {
    try {
      facts = await factsProvider(prefs, tier, segment, now)
    } catch {
      /* keep defaults — copy generation must never block the send */
    }
  }
  // The chips riding in this push's payload are the suggestion the text should name.
  const leadName = prettyLook(chips[0]?.id ?? null)
  facts = { ...facts, favoriteLook: leadName ?? facts.favoriteLook }
  const goal = `${segment.goal} Name tonight's recipe pick (given as the favorite look in the facts) in the title or body.`
  const last = prefs.lastNudgeCopy
  const sameAsLast = (c: { title: string; body: string }) =>
    !!last && c.title === last.title && c.body === last.body
  const namesLead = (c: { title: string; body: string }) =>
    !leadName || `${c.title} ${c.body}`.toLowerCase().includes(leadName.toLowerCase())
  const unusable = (c: { title: string; body: string }) => sameAsLast(c) || !namesLead(c)
  let res = await generateCopy(segment.id, goal, facts, { now })
  if (unusable(res)) {
    // A repeat of last time, or a draft that never names the recipe pick: regenerate fresh.
    res = await generateCopy(segment.id, goal, facts, { now, bypassCache: true })
  }
  if (unusable(res)) {
    return { ...nudgeFallbackCopy(kind, chips, last), source: 'template' }
  }
  return res
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
 * Enabled unless PUSH_EXP1_ENABLED is explicitly false (same ops flag / cron).
 */
export async function runComeShootNudgeTick(
  now = new Date(),
  opts: { copyFacts?: NudgeFactsProvider } = {},
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

      const chips = pickRecipeChips(guestId, 3)
      const copy = await buildNudgeCopy(kind, prefs, tier, chips, now, opts.copyFacts)
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
        recordNudgeSent(guestId, now, copy)
        result.sent += 1
        console.info(
          JSON.stringify({
            event: 'push_sent',
            type: kind,
            stage: kind === 'd1_return' ? 'activation' : 'habit',
            guestId,
            tier,
            deepLink: DEEP_LINK,
            copySource: copy.source,
            copyTitle: copy.title,
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
