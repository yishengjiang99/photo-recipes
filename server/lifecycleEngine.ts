/**
 * Push lifecycle engine — evaluate segments per opted-in install, write copy with Grok
 * (guardrailed), and either log a dry-run decision or send via APNs.
 *
 * SAFETY DEFAULTS
 *  - Mode comes from PUSH_LIFECYCLE_MODE (default "live"). Modes, least → most permissive:
 *      off        nothing runs
 *      dry_run    evaluate + generate copy + log "would_send"; never calls APNs
 *      sandbox    real sends only to tokens registered as APNs *sandbox* (Xcode debug builds)
 *      allowlist  real sends only to guest ids in PUSH_LIFECYCLE_ALLOWLIST (e.g. your TestFlight
 *                 device); everyone else stays dry-run
 *      live       real sends to every eligible install   (DEFAULT)
 *  - Kill switch: PUSH_KILL_SWITCH=true (env) or POST /api/push/lifecycle/ops {killSwitch:true}
 *    (runtime, no redeploy) stops lifecycle AND legacy come-shoot sends.
 *    The runtime override can only make things *safer* (downgrade the mode), never upgrade.
 *  - Caps (all push types combined): 1/day, 3/rolling 7 days; send window 10:00–20:00 and the
 *    user's quiet hours, both in the install's own time zone.
 *  - Dedupe: a (install, dedupeKey) pair is sent at most once, ever.
 *  - Consent: feature pushes need push permission; promotional pushes also need marketingOptIn.
 *  - Dead tokens: APNs 410 / Unregistered / BadDeviceToken → token pruned, install skipped.
 */
import crypto from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { sendApns, isApnsEnvPresent, type ApnsPayload } from './apns.ts'
import { findEntitlementByGuestId } from './entitlements.ts'
import { getMysqlPool } from './mysql.ts'
import { listAllPushPrefs, pruneSentThisWeek, recordNudgeSent, removeApnsTokenEverywhere, type PushPrefs } from './pushPrefs.ts'
import { deletePushTokenEverywhere, listPushTokensForGuest, mergeApnsTokens } from './pushDevices.ts'
import { tierFromEntitlement } from './pushScheduler.ts'
import {
  copyFactsFor,
  featuresFromEvents,
  emptyFeatures,
  matchSegments,
  type ActivityFeatures,
  type SegmentMatch,
  type TelemetryEventRow,
  type Tier,
} from './lifecycleSegments.ts'
import { generateCopy, type CopyResult } from './lifecycleCopy.ts'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const DATA_DIR = path.resolve(__dirname, 'data')

export type LifecycleMode = 'off' | 'dry_run' | 'sandbox' | 'allowlist' | 'live'
const MODE_RANK: Record<LifecycleMode, number> = { off: 0, dry_run: 1, sandbox: 2, allowlist: 3, live: 4 }

export const CAPS = { perDay: 1, perWeek: 3, sendWindow: { start: 10 * 60, end: 20 * 60 }, maxSendsPerTick: 200 }

function p(name: string, envKey: string): string {
  return process.env[envKey]?.trim() || path.join(DATA_DIR, name)
}
const statePath = (dry: boolean) => p(dry ? 'push-lifecycle-state.dryrun.json' : 'push-lifecycle-state.json', dry ? 'PUSH_LIFECYCLE_DRY_STATE_PATH' : 'PUSH_LIFECYCLE_STATE_PATH')
const logPath = () => p('push-lifecycle-log.jsonl', 'PUSH_LIFECYCLE_LOG_PATH')
const opsPath = () => p('push-lifecycle-ops.json', 'PUSH_LIFECYCLE_OPS_PATH')
const pushEventsPath = () => p('push-events.jsonl', 'PUSH_EVENTS_LOG_PATH')

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------

type Ops = { killSwitch?: boolean; mode?: LifecycleMode; updatedAt?: string; liveSince?: string; autoKill?: { at: string; reason: string } }

function readJson<T>(file: string, fallback: T): T {
  try {
    if (!fs.existsSync(file)) return fallback
    return JSON.parse(fs.readFileSync(file, 'utf8')) as T
  } catch {
    return fallback
  }
}

function writeJson(file: string, v: unknown) {
  fs.mkdirSync(path.dirname(file), { recursive: true })
  const tmp = `${file}.${process.pid}.tmp`
  fs.writeFileSync(tmp, JSON.stringify(v, null, 2), 'utf8')
  fs.renameSync(tmp, file)
}

function parseMode(v: unknown): LifecycleMode | null {
  return typeof v === 'string' && v.trim() in MODE_RANK ? (v.trim() as LifecycleMode) : null
}

export function envLifecycleMode(): LifecycleMode {
  // Shipped → on for everyone by default; set PUSH_LIFECYCLE_MODE=off|dry_run to turn it down.
  return parseMode(process.env.PUSH_LIFECYCLE_MODE?.toLowerCase()) ?? 'live'
}

export function readOps(): Ops {
  return readJson<Ops>(opsPath(), {})
}

/** Runtime ops: kill switch and/or mode downgrade. */
export function patchOps(patch: { killSwitch?: boolean; mode?: string | null }): Ops {
  const cur = readOps()
  const next: Ops = { ...cur, updatedAt: new Date().toISOString() }
  if (typeof patch.killSwitch === 'boolean') next.killSwitch = patch.killSwitch
  if (patch.mode === null) delete next.mode
  else if (patch.mode !== undefined) {
    const m = parseMode(patch.mode)
    if (!m) throw new Error('mode must be off|dry_run|sandbox|allowlist|live')
    next.mode = m
  }
  writeJson(opsPath(), next)
  return next
}

export function isKillSwitchOn(): boolean {
  if (process.env.PUSH_KILL_SWITCH?.trim().toLowerCase() === 'true') return true
  return readOps().killSwitch === true
}

export function effectiveMode(): LifecycleMode {
  if (isKillSwitchOn()) return 'off'
  const env = envLifecycleMode()
  const ops = readOps().mode
  if (ops && MODE_RANK[ops] < MODE_RANK[env]) return ops
  return env
}

function allowlist(): Set<string> {
  return new Set((process.env.PUSH_LIFECYCLE_ALLOWLIST ?? '').split(',').map((s) => s.trim()).filter(Boolean))
}

// ---------------------------------------------------------------------------
// State (per install send history) — separate files for dry-run and real sends
// ---------------------------------------------------------------------------

type SendRec = { at: string; segment: string; key: string; sendId: string }
type GuestState = { sends: SendRec[]; keys: Record<string, string> }
type State = { guests: Record<string, GuestState> }

function readState(dry: boolean): State {
  const s = readJson<State>(statePath(dry), { guests: {} })
  return s.guests ? s : { guests: {} }
}

function appendLog(row: Record<string, unknown>) {
  try {
    fs.mkdirSync(path.dirname(logPath()), { recursive: true })
    fs.appendFileSync(logPath(), JSON.stringify(row) + '\n', 'utf8')
  } catch (err) {
    console.warn('[lifecycle] log append failed', err instanceof Error ? err.message : err)
  }
}

// ---------------------------------------------------------------------------
// Activity (first-party anonymous telemetry → features)
// ---------------------------------------------------------------------------

export type EventLoader = (anonId: string, now: Date) => Promise<{ rows: TelemetryEventRow[]; firstSeen: Date | null } | null>

const mysqlLoader: EventLoader = async (anonId) => {
  const pool = getMysqlPool()
  if (!pool) return null
  const [rows] = await pool.query(
    `SELECT event, created_at AS at, JSON_UNQUOTE(JSON_EXTRACT(props_json, '$.look_id')) AS lookId
       FROM telemetry_events
      WHERE anon_id = ? AND created_at >= (NOW(3) - INTERVAL 60 DAY)
      ORDER BY created_at DESC LIMIT 5000`,
    [anonId],
  )
  const [first] = await pool.query(`SELECT MIN(created_at) AS first FROM telemetry_events WHERE anon_id = ?`, [anonId])
  const f = (first as Array<{ first: Date | null }>)[0]?.first ?? null
  return {
    rows: (rows as Array<{ event: string; at: Date; lookId: string | null }>).map((r) => ({ event: r.event, at: new Date(r.at), lookId: r.lookId })),
    firstSeen: f ? new Date(f) : null,
  }
}

let loader: EventLoader = mysqlLoader
export function setLifecycleEventLoaderForTests(l: EventLoader | null) {
  loader = l ?? mysqlLoader
}

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------

function localMinutes(now: Date, tz: string): number {
  try {
    const parts = new Intl.DateTimeFormat('en-US', { timeZone: tz, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(now)
    const h = Number(parts.find((x) => x.type === 'hour')?.value ?? 0)
    const m = Number(parts.find((x) => x.type === 'minute')?.value ?? 0)
    return h * 60 + m
  } catch {
    return now.getUTCHours() * 60 + now.getUTCMinutes()
  }
}

function hhmm(s: string): number {
  const [h, m] = s.split(':').map(Number)
  return (h ?? 0) * 60 + (m ?? 0)
}

export function inQuiet(mins: number, q: { start: string; end: string }): boolean {
  const s = hhmm(q.start)
  const e = hhmm(q.end)
  if (s === e) return false
  return s < e ? mins >= s && mins < e : mins >= s || mins < e
}

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------

export type Decision = {
  guest: string // hashed for logs/reports
  decision: 'sent' | 'would_send' | 'skip' | 'error'
  reason?: string
  segment?: string
  cls?: string
  dedupeKey?: string
  copy?: CopyResult
  sendId?: string
  tier?: Tier
  results?: Array<{ env: string; ok: boolean; status?: number; error?: string }>
}

export function guestHash(guestId: string): string {
  return crypto.createHash('sha256').update(`lifecycle:${guestId}`).digest('hex').slice(0, 12)
}

const DAY = 24 * 60 * 60 * 1000

/** Gate checks independent of segment content. Returns a skip reason or null. */
export function capReason(prefs: PushPrefs, gs: GuestState | undefined, now: Date): string | null {
  const t = now.getTime()
  const sends = [
    ...(gs?.sends ?? []).map((s) => Date.parse(s.at)),
    ...(prefs.sentThisWeek ?? []).map((s) => Date.parse(s)),
    ...(prefs.lastNudgeAt ? [Date.parse(prefs.lastNudgeAt)] : []),
  ].filter((x) => Number.isFinite(x))
  const uniq = [...new Set(sends)]
  if (uniq.some((x) => t - x < DAY)) return 'cap_daily'
  if (uniq.filter((x) => t - x < 7 * DAY).length >= CAPS.perWeek) return 'cap_weekly'
  return null
}

type EvalCtx = { now: Date; mode: LifecycleMode; dry: State; real: State; allow: Set<string>; useGrok: boolean }

async function evaluateGuest(prefs: PushPrefs, ctx: EvalCtx): Promise<{ d: Decision; match?: SegmentMatch; features?: ActivityFeatures }> {
  const g = guestHash(prefs.guestId)
  const skip = (reason: string, extra: Partial<Decision> = {}) => ({ d: { guest: g, decision: 'skip' as const, reason, ...extra } })
  if (!prefs.pushOptIn) return skip('not_opted_in')
  const tokens = mergeApnsTokens(prefs.apnsDeviceTokens, await listPushTokensForGuest(prefs.guestId))
  if (!tokens.length) return skip('no_device_token')

  const ent = findEntitlementByGuestId(prefs.guestId)
  const tier = tierFromEntitlement(ent)
  // No telemetry link / store / events → fall back to the guest's own data (default campaign).
  const ev = prefs.telemetryAnonId ? await loader(prefs.telemetryAnonId, ctx.now).catch(() => null) : null
  const optedIn = prefs.optedInAt ? new Date(prefs.optedInAt) : null
  const features = ev && ev.rows.length
    ? featuresFromEvents(ev.rows, ctx.now, tier, ev.firstSeen)
    : emptyFeatures(tier, optedIn && Number.isFinite(optedIn.getTime()) ? optedIn : null, ctx.now)

  // Dry-run and real histories are separate so switching modes starts clean.
  const realMode = ctx.mode !== 'dry_run'
  const state = realMode ? ctx.real : ctx.dry
  const gs = state.guests[prefs.guestId]
  const usedAnn = new Set(Object.keys(gs?.keys ?? {}).filter((k) => k.startsWith('new_feature:')).map((k) => k.slice(12)))
  const matches = matchSegments(features, ctx.now, usedAnn)
  if (!matches.length) return skip('no_segment', { tier })

  let match: SegmentMatch | undefined
  let lastReason = 'no_segment'
  for (const m of matches) {
    if (gs?.keys[m.dedupeKey]) {
      lastReason = 'dedupe'
      continue
    }
    if (m.segment.cls === 'promotional' && !prefs.marketingOptIn) {
      lastReason = 'no_marketing_consent'
      continue
    }
    match = m
    break
  }
  if (!match) return skip(lastReason, { tier, segment: matches[0]!.segment.id })

  const base = { segment: match.segment.id, cls: match.segment.cls, dedupeKey: match.dedupeKey, tier }
  const cap = capReason(prefs, gs, ctx.now)
  if (cap) return skip(cap, base)
  const local = localMinutes(ctx.now, prefs.timezone || 'UTC')
  if (inQuiet(local, prefs.quietHours ?? { start: '21:00', end: '07:00' })) return skip('quiet_hours', base)
  if (local < CAPS.sendWindow.start || local >= CAPS.sendWindow.end) return skip('outside_send_window', base)

  return { d: { guest: g, decision: 'would_send', ...base }, match, features }
}

function record(state: State, guestId: string, rec: SendRec) {
  const gs = (state.guests[guestId] ??= { sends: [], keys: {} })
  gs.sends = [...gs.sends.filter((s) => Date.now() - Date.parse(s.at) < 30 * DAY), rec]
  gs.keys[rec.key] = rec.at
}

export function isDeadToken(r: { ok: boolean; status?: number; error?: string }): boolean {
  if (r.ok) return false
  return r.status === 410 || /Unregistered|BadDeviceToken/.test(r.error ?? '')
}

export type TickSummary = {
  mode: LifecycleMode
  at: string
  scanned: number
  wouldSend: number
  sent: number
  skipped: Record<string, number>
  bySegment: Record<string, number>
  errors: number
  decisions: Decision[]
}

let ticking = false

export async function runLifecycleTick(now = new Date(), opts: { useGrok?: boolean } = {}): Promise<TickSummary> {
  const mode = effectiveMode()
  const sum: TickSummary = { mode, at: now.toISOString(), scanned: 0, wouldSend: 0, sent: 0, skipped: {}, bySegment: {}, errors: 0, decisions: [] }
  if (mode === 'off' || ticking) {
    if (ticking) sum.skipped.tick_in_progress = 1
    return sum
  }
  ticking = true
  try {
    const ctx: EvalCtx = { now, mode, dry: readState(true), real: readState(false), allow: allowlist(), useGrok: opts.useGrok ?? true }
    const all = listAllPushPrefs()
    sum.scanned = all.length
    let realSends = 0
    for (const prefs of all) {
      let out: Awaited<ReturnType<typeof evaluateGuest>>
      try {
        out = await evaluateGuest(prefs, ctx)
      } catch (err) {
        sum.errors++
        sum.decisions.push({ guest: guestHash(prefs.guestId), decision: 'error', reason: err instanceof Error ? err.message : 'eval_error' })
        continue
      }
      const { d, match, features } = out
      if (d.decision === 'skip' || !match || !features) {
        sum.skipped[d.reason ?? 'skip'] = (sum.skipped[d.reason ?? 'skip'] ?? 0) + 1
        sum.decisions.push(d)
        continue
      }
      const facts = copyFactsFor(features, match)
      d.copy = await generateCopy(match.segment.id, match.segment.goal, facts, { useGrok: ctx.useGrok, now })
      d.sendId = crypto.randomUUID()
      sum.bySegment[match.segment.id] = (sum.bySegment[match.segment.id] ?? 0) + 1

      // Which tokens may receive a REAL push in this mode?
      const mysqlTokens = await listPushTokensForGuest(prefs.guestId)
      const tokens = mergeApnsTokens(prefs.apnsDeviceTokens, mysqlTokens).filter((t) => {
        if (mode === 'live') return true
        if (mode === 'sandbox') return t.environment === 'sandbox'
        if (mode === 'allowlist') return ctx.allow.has(prefs.guestId)
        return false
      })
      const rec: SendRec = { at: now.toISOString(), segment: match.segment.id, key: match.dedupeKey, sendId: d.sendId }

      if (!tokens.length || realSends >= CAPS.maxSendsPerTick || !isApnsEnvPresent()) {
        d.decision = 'would_send'
        if (mode !== 'dry_run') d.reason = !isApnsEnvPresent() ? 'apns_not_configured' : realSends >= CAPS.maxSendsPerTick ? 'tick_send_cap' : 'mode_excludes_token'
        sum.wouldSend++
        record(ctx.dry, prefs.guestId, rec)
        appendLog({ ...logRow(d, mode), event: 'lifecycle_would_send' })
        sum.decisions.push(d)
        continue
      }

      const payload: ApnsPayload = {
        aps: { alert: { title: d.copy.title, body: d.copy.body }, sound: 'default', 'thread-id': 'lifecycle' },
        type: 'lifecycle',
        deepLink: match.segment.deepLink,
        recipeChips: [],
        entitlementTier: features.tier,
        experiment: 'lifecycle',
        sendId: d.sendId,
        segment: match.segment.id,
      }
      d.results = []
      let anyOk = false
      for (const tok of tokens) {
        const r = await sendApns(tok.token, payload, { environment: tok.environment })
        d.results.push({ env: tok.environment, ok: r.ok, ...('status' in r && r.status ? { status: r.status } : {}), ...(!r.ok ? { error: r.error.slice(0, 80) } : {}) })
        if (r.ok) anyOk = true
        else if (isDeadToken(r)) {
          removeApnsTokenEverywhere(tok.token)
          await deletePushTokenEverywhere(tok.token)
          appendLog({ at: now.toISOString(), event: 'lifecycle_token_pruned', guest: d.guest, tokenHint: tok.token.slice(0, 6), status: r.status })
        }
      }
      if (anyOk) {
        realSends++
        d.decision = 'sent'
        sum.sent++
        record(ctx.real, prefs.guestId, rec)
        recordNudgeSent(prefs.guestId, now) // shared daily/weekly cap with legacy nudges
      } else {
        d.decision = 'error'
        sum.errors++
      }
      appendLog({ ...logRow(d, mode), event: anyOk ? 'lifecycle_sent' : 'lifecycle_send_failed' })
      sum.decisions.push(d)
    }
    writeJson(statePath(true), ctx.dry)
    writeJson(statePath(false), ctx.real)
    writeJson(p('push-lifecycle-last-tick.json', 'PUSH_LIFECYCLE_LAST_TICK_PATH'), { ...sum, decisions: sum.decisions.slice(0, 100) })
    if (mode !== 'dry_run') {
      const ops = readOps()
      if (!ops.liveSince) writeJson(opsPath(), { ...ops, liveSince: now.toISOString() })
      const g = autoGuard(now)
      if (g.tripped) sum.skipped.auto_kill_switch = 1
    }
    return sum
  } finally {
    ticking = false
  }
}

function logRow(d: Decision, mode: LifecycleMode) {
  return {
    at: new Date().toISOString(),
    mode,
    guest: d.guest,
    sendId: d.sendId,
    segment: d.segment,
    cls: d.cls,
    tier: d.tier,
    dedupeKey: d.dedupeKey,
    title: d.copy?.title,
    body: d.copy?.body,
    copySource: d.copy?.source,
    model: d.copy?.model,
    rejected: d.copy?.rejected,
    reason: d.reason,
    results: d.results,
  }
}

// ---------------------------------------------------------------------------
// Report (KPIs) — open rate via tap telemetry (push_opened with sendId)
// ---------------------------------------------------------------------------

function readJsonl(file: string, sinceMs: number): Array<Record<string, unknown>> {
  try {
    if (!fs.existsSync(file)) return []
    const out: Array<Record<string, unknown>> = []
    for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
      if (!line.trim()) continue
      try {
        const row = JSON.parse(line) as Record<string, unknown>
        const t = Date.parse(String(row.at ?? ''))
        if (Number.isFinite(t) && t >= sinceMs) out.push(row)
      } catch {
        /* skip */
      }
    }
    return out
  } catch {
    return []
  }
}

export function lifecycleReport(days = 14) {
  const since = Date.now() - days * DAY
  const log = readJsonl(logPath(), since)
  const sent = log.filter((r) => r.event === 'lifecycle_sent')
  const would = log.filter((r) => r.event === 'lifecycle_would_send')
  const sendIds = new Set(sent.map((r) => String(r.sendId)))
  const opens = new Set<string>()
  let optOuts = 0
  for (const e of readJsonl(pushEventsPath(), since)) {
    const props = (e.props ?? {}) as Record<string, unknown>
    const sid = typeof props.sendId === 'string' ? props.sendId : typeof props.send_id === 'string' ? props.send_id : null
    if (e.event === 'push_opened' && sid && sendIds.has(sid)) opens.add(sid)
    if (e.event === 'push_opt_out' || e.event === 'push_marketing_opt_out') optOuts++
  }
  const bySeg = (rows: Array<Record<string, unknown>>) =>
    rows.reduce<Record<string, number>>((acc, r) => {
      const k = String(r.segment ?? '?')
      acc[k] = (acc[k] ?? 0) + 1
      return acc
    }, {})
  const prefs = listAllPushPrefs()
  return {
    mode: effectiveMode(),
    envMode: envLifecycleMode(),
    killSwitch: isKillSwitchOn(),
    ops: readOps(),
    apnsConfigured: isApnsEnvPresent(),
    caps: CAPS,
    windowDays: days,
    audience: {
      installsWithPrefs: prefs.length,
      pushOptIn: prefs.filter((x) => x.pushOptIn).length,
      withToken: prefs.filter((x) => x.apnsDeviceTokens?.length).length,
      activityLinked: prefs.filter((x) => x.telemetryAnonId).length,
      marketingOptIn: prefs.filter((x) => x.marketingOptIn).length,
      sentThisWeekLegacy: prefs.reduce((n, x) => n + pruneSentThisWeek(x).length, 0),
    },
    kpis: {
      sent: sent.length,
      wouldSend: would.length,
      opened: opens.size,
      openRate: sent.length ? opens.size / sent.length : null,
      optOutEvents: optOuts,
      optOutRate: sent.length ? optOuts / sent.length : null,
      note: 'return_within_24h needs MySQL; see /api/push/lifecycle/report?kpi24h=1',
    },
    sentBySegment: bySeg(sent),
    wouldSendBySegment: bySeg(would),
    lastTick: readJson(p('push-lifecycle-last-tick.json', 'PUSH_LIFECYCLE_LAST_TICK_PATH'), null),
    guard: { ...GUARD, ...autoGuard(new Date(), { dryRun: true }) },
    recent: log.slice(-30),
  }
}

/** % of real sends whose install logged any telemetry event within 24h after the send. */
export async function returnWithin24h(days = 14): Promise<{ sends: number; returned: number; rate: number | null } | null> {
  const pool = getMysqlPool()
  if (!pool) return null
  const sent = readJsonl(logPath(), Date.now() - days * DAY).filter((r) => r.event === 'lifecycle_sent')
  const byGuest = new Map(listAllPushPrefs().map((x) => [guestHash(x.guestId), x.telemetryAnonId]))
  let returned = 0
  for (const r of sent) {
    const anon = byGuest.get(String(r.guest))
    if (!anon) continue
    const at = new Date(String(r.at))
    const [rows] = await pool.query(
      `SELECT COUNT(*) AS n FROM telemetry_events WHERE anon_id = ? AND created_at > ? AND created_at <= (? + INTERVAL 24 HOUR) AND event NOT IN ('push_opened','notification_opened')`,
      [anon, at, at],
    )
    if (Number((rows as Array<{ n: number }>)[0]?.n) > 0) returned++
  }
  return { sends: sent.length, returned, rate: sent.length ? returned / sent.length : null }
}

/**
 * Cohort preview: how many recent iOS installs (from telemetry alone, push or not) fall in each
 * segment right now. Sizing only — nobody is contacted. Tier unknown here → treated as free.
 */
export async function cohortPreview(now = new Date(), limit = 3000): Promise<{ installs: number; bySegment: Record<string, number>; none: number } | null> {
  const pool = getMysqlPool()
  if (!pool) return null
  const [rows] = await pool.query(
    `SELECT anon_id AS anon, event, created_at AS at, JSON_UNQUOTE(JSON_EXTRACT(props_json, '$.look_id')) AS lookId
       FROM telemetry_events
      WHERE platform = 'ios' AND created_at >= (NOW(3) - INTERVAL 60 DAY)
        AND anon_id IN (SELECT anon_id FROM (SELECT DISTINCT anon_id FROM telemetry_events WHERE platform = 'ios' AND created_at >= (NOW(3) - INTERVAL 60 DAY) LIMIT ?) t)`,
    [limit],
  )
  const per = new Map<string, TelemetryEventRow[]>()
  for (const r of rows as Array<{ anon: string; event: string; at: Date; lookId: string | null }>) {
    const list = per.get(r.anon) ?? []
    list.push({ event: r.event, at: new Date(r.at), lookId: r.lookId })
    per.set(r.anon, list)
  }
  const bySegment: Record<string, number> = {}
  let none = 0
  for (const list of per.values()) {
    const f = featuresFromEvents(list, now, 'free')
    const m = matchSegments(f, now)
    if (!m.length) none++
    else bySegment[m[0]!.segment.id] = (bySegment[m[0]!.segment.id] ?? 0) + 1
  }
  return { installs: per.size, bySegment, none }
}

// ---------------------------------------------------------------------------
// Automatic guardrail: flips the kill switch when opt-outs or APNs errors spike.
// ---------------------------------------------------------------------------

export const GUARD = {
  optOutRateMax: 0.02, // > 2% of push-enabled installs opting out within 7 days
  minOptOuts: Math.max(1, Number(process.env.PUSH_GUARD_MIN_OPTOUTS) || 2),
  apnsErrorRateMax: 0.2, // > 20% of real APNs attempts failing (excluding uninstalled tokens) in 24 h
  minApnsAttempts: 10,
}

export type GuardResult = {
  tripped: boolean
  reason: string | null
  windowStart: string
  optOuts: number
  optOutBase: number
  optOutRate: number | null
  apnsAttempts24h: number
  apnsErrors24h: number
  apnsErrorRate24h: number | null
}

/** Evaluates the guardrails; when one is exceeded, turns the kill switch on and logs it. */
export function autoGuard(now = new Date(), opts: { dryRun?: boolean } = {}): GuardResult {
  const ops = readOps()
  const since = Math.max(now.getTime() - 7 * DAY, ops.liveSince ? Date.parse(ops.liveSince) : now.getTime())
  const optedOut = new Set<string>() // distinct installs, so toggling twice counts once
  for (const e of readJsonl(pushEventsPath(), since)) {
    if (e.event === 'push_opt_out' || e.event === 'push_marketing_opt_out') optedOut.add(String(e.guestId ?? e.at))
  }
  const optOuts = optedOut.size
  const base = listAllPushPrefs().filter((x) => x.pushOptIn).length + optOuts
  const optOutRate = base ? optOuts / base : null
  let attempts = 0
  let errors = 0
  for (const r of readJsonl(logPath(), now.getTime() - DAY)) {
    if (r.event !== 'lifecycle_sent' && r.event !== 'lifecycle_send_failed') continue
    for (const x of (r.results as Array<{ ok: boolean; status?: number; error?: string }> | undefined) ?? []) {
      attempts++
      if (!x.ok && !isDeadToken(x)) errors++
    }
  }
  const apnsErrorRate = attempts ? errors / attempts : null
  let reason: string | null = null
  if (optOutRate !== null && optOuts >= GUARD.minOptOuts && optOutRate > GUARD.optOutRateMax) reason = `opt_out_rate ${(optOutRate * 100).toFixed(1)}% (${optOuts}/${base})`
  else if (apnsErrorRate !== null && attempts >= GUARD.minApnsAttempts && apnsErrorRate > GUARD.apnsErrorRateMax) reason = `apns_error_rate ${(apnsErrorRate * 100).toFixed(1)}% (${errors}/${attempts})`
  const tripped = Boolean(reason) && !opts.dryRun && !isKillSwitchOn()
  if (tripped) {
    writeJson(opsPath(), { ...readOps(), killSwitch: true, updatedAt: now.toISOString(), autoKill: { at: now.toISOString(), reason: reason! } })
    appendLog({ at: now.toISOString(), event: 'lifecycle_auto_kill_switch', reason })
    console.warn('[lifecycle] AUTO KILL SWITCH ON:', reason)
  }
  return {
    tripped, reason, windowStart: new Date(since).toISOString(), optOuts, optOutBase: base, optOutRate,
    apnsAttempts24h: attempts, apnsErrors24h: errors, apnsErrorRate24h: apnsErrorRate,
  }
}
