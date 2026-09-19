/**
 * Push Experiment 1 — per-user prefs + APNs token registry (file-backed).
 * Store path: server/data/push-prefs.json (gitignored like entitlements/waitlist).
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const DATA_DIR = path.resolve(__dirname, 'data')
const STORE_PATH = path.join(DATA_DIR, 'push-prefs.json')

/** Default quiet hours (user local): 21:00–07:00 */
export const DEFAULT_QUIET = { start: '21:00', end: '07:00' } as const
export const DEFAULT_WEEKLY_CAP_FREE = 3
export const DEFAULT_WEEKLY_CAP_PRO = 5
/** Minutes before shoot window start to send the brief (inclusive window). */
export const BRIEF_LEAD_MIN = 60
export const BRIEF_LEAD_MAX = 90

export type ApnsEnvironment = 'sandbox' | 'production'

export type ApnsDeviceToken = {
  token: string
  platform: 'ios'
  bundleId: string
  environment: ApnsEnvironment
  appVersion?: string
  updatedAt: string
}

export type ShootWindow = {
  /** Local wall-clock HH:MM */
  start: string
  end: string
  /** Optional: weekdays 0=Sun … 6=Sat; omit = every day */
  daysOfWeek?: number[]
}

export type QuietHours = {
  start: string
  end: string
}

export type PushPrefs = {
  guestId: string
  shootWindow: ShootWindow | null
  quietHours: QuietHours
  /** User override; null → use Free/Pro defaults at send time */
  weeklyCap: number | null
  pushOptIn: boolean
  apnsDeviceTokens: ApnsDeviceToken[]
  /** Explicit holdout override; if true, never treat even when flag on */
  experimentHoldout: boolean
  /** IANA timezone, e.g. America/Los_Angeles */
  timezone: string
  /** ISO timestamps of Exp1 briefs sent this UTC week (for caps) */
  sentThisWeek: string[]
  /** Last Exp1 brief send ISO (dedupe same window) */
  lastBriefAt: string | null
  updatedAt: string
}

type Store = {
  prefs: Record<string, PushPrefs>
}

function ensureDataDir() {
  if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true })
}

function emptyStore(): Store {
  return { prefs: {} }
}

function readStore(): Store {
  ensureDataDir()
  try {
    if (!fs.existsSync(STORE_PATH)) return emptyStore()
    const raw = fs.readFileSync(STORE_PATH, 'utf8')
    const parsed = JSON.parse(raw) as Partial<Store>
    return { prefs: parsed.prefs ?? {} }
  } catch {
    return emptyStore()
  }
}

function writeStore(store: Store) {
  ensureDataDir()
  const tmp = `${STORE_PATH}.${process.pid}.tmp`
  fs.writeFileSync(tmp, JSON.stringify(store, null, 2), 'utf8')
  fs.renameSync(tmp, STORE_PATH)
}

function defaultPrefs(guestId: string): PushPrefs {
  const now = new Date().toISOString()
  return {
    guestId,
    shootWindow: null,
    quietHours: { ...DEFAULT_QUIET },
    weeklyCap: null,
    pushOptIn: false,
    apnsDeviceTokens: [],
    experimentHoldout: false,
    timezone: 'UTC',
    sentThisWeek: [],
    lastBriefAt: null,
    updatedAt: now,
  }
}

export function getPushPrefs(guestId: string): PushPrefs {
  const store = readStore()
  return store.prefs[guestId] ?? defaultPrefs(guestId)
}

export function listAllPushPrefs(): PushPrefs[] {
  return Object.values(readStore().prefs)
}

const HHMM = /^([01]\d|2[0-3]):([0-5]\d)$/

function parseHHMM(s: unknown): string | null {
  if (typeof s !== 'string' || !HHMM.test(s.trim())) return null
  return s.trim()
}

export function updatePushPrefs(
  guestId: string,
  patch: Partial<{
    shootWindow: ShootWindow | null
    quietHours: QuietHours
    weeklyCap: number | null
    pushOptIn: boolean
    experimentHoldout: boolean
    timezone: string
  }>,
): PushPrefs {
  const store = readStore()
  const prev = store.prefs[guestId] ?? defaultPrefs(guestId)
  const next: PushPrefs = { ...prev, guestId, updatedAt: new Date().toISOString() }

  if ('shootWindow' in patch) {
    if (patch.shootWindow === null) {
      next.shootWindow = null
    } else if (patch.shootWindow) {
      const start = parseHHMM(patch.shootWindow.start)
      const end = parseHHMM(patch.shootWindow.end)
      if (!start || !end) throw new Error('shootWindow.start/end must be HH:MM (24h)')
      const days = patch.shootWindow.daysOfWeek
      if (days !== undefined) {
        if (
          !Array.isArray(days) ||
          !days.every((d) => Number.isInteger(d) && d >= 0 && d <= 6)
        ) {
          throw new Error('shootWindow.daysOfWeek must be integers 0–6')
        }
      }
      next.shootWindow = {
        start,
        end,
        ...(days && days.length ? { daysOfWeek: [...days] } : {}),
      }
    }
  }

  if (patch.quietHours) {
    const start = parseHHMM(patch.quietHours.start)
    const end = parseHHMM(patch.quietHours.end)
    if (!start || !end) throw new Error('quietHours.start/end must be HH:MM (24h)')
    next.quietHours = { start, end }
  }

  if ('weeklyCap' in patch) {
    if (patch.weeklyCap === null) {
      next.weeklyCap = null
    } else if (
      typeof patch.weeklyCap === 'number' &&
      Number.isInteger(patch.weeklyCap) &&
      patch.weeklyCap >= 0 &&
      patch.weeklyCap <= 21
    ) {
      next.weeklyCap = patch.weeklyCap
    } else {
      throw new Error('weeklyCap must be integer 0–21 or null')
    }
  }

  if (typeof patch.pushOptIn === 'boolean') next.pushOptIn = patch.pushOptIn
  if (typeof patch.experimentHoldout === 'boolean') {
    next.experimentHoldout = patch.experimentHoldout
  }
  if (typeof patch.timezone === 'string' && patch.timezone.trim()) {
    // Basic validation — Intl will throw on bogus zones at format time
    const tz = patch.timezone.trim()
    try {
      Intl.DateTimeFormat('en-US', { timeZone: tz }).format(new Date())
      next.timezone = tz
    } catch {
      throw new Error(`Invalid timezone: ${tz}`)
    }
  }

  store.prefs[guestId] = next
  writeStore(store)
  return next
}

const HEX_TOKEN = /^[0-9a-fA-F]{64,}$/
const EXPECTED_BUNDLE = 'com.ragnus.mvp'

export function registerApnsToken(
  guestId: string,
  input: {
    token: string
    platform: string
    bundleId: string
    environment: string
    appVersion?: string
  },
): PushPrefs {
  if (input.platform !== 'ios') throw new Error('platform must be "ios"')
  const token = typeof input.token === 'string' ? input.token.trim() : ''
  if (!HEX_TOKEN.test(token)) {
    throw new Error('token must be hex device token (≥64 chars)')
  }
  const bundleId =
    typeof input.bundleId === 'string' ? input.bundleId.trim() : ''
  if (bundleId !== EXPECTED_BUNDLE) {
    throw new Error(`bundleId must be ${EXPECTED_BUNDLE}`)
  }
  if (input.environment !== 'sandbox' && input.environment !== 'production') {
    throw new Error('environment must be "sandbox" or "production"')
  }

  const store = readStore()
  const prev = store.prefs[guestId] ?? defaultPrefs(guestId)
  const entry: ApnsDeviceToken = {
    token: token.toLowerCase(),
    platform: 'ios',
    bundleId,
    environment: input.environment,
    ...(typeof input.appVersion === 'string' && input.appVersion.trim()
      ? { appVersion: input.appVersion.trim() }
      : {}),
    updatedAt: new Date().toISOString(),
  }
  const others = prev.apnsDeviceTokens.filter((t) => t.token !== entry.token)
  const next: PushPrefs = {
    ...prev,
    guestId,
    apnsDeviceTokens: [...others, entry],
    updatedAt: new Date().toISOString(),
  }
  store.prefs[guestId] = next
  writeStore(store)
  return next
}

/** UTC ISO week key YYYY-Www */
export function utcWeekKey(d = new Date()): string {
  const date = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()))
  const dayNum = date.getUTCDay() || 7
  date.setUTCDate(date.getUTCDate() + 4 - dayNum)
  const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
  const weekNo = Math.ceil(((date.getTime() - yearStart.getTime()) / 86400000 + 1) / 7)
  return `${date.getUTCFullYear()}-W${String(weekNo).padStart(2, '0')}`
}

export function pruneSentThisWeek(prefs: PushPrefs, now = new Date()): string[] {
  const key = utcWeekKey(now)
  return (prefs.sentThisWeek || []).filter((iso) => {
    try {
      return utcWeekKey(new Date(iso)) === key
    } catch {
      return false
    }
  })
}

export function recordBriefSent(guestId: string, at = new Date()): PushPrefs {
  const store = readStore()
  const prev = store.prefs[guestId] ?? defaultPrefs(guestId)
  const iso = at.toISOString()
  const sentThisWeek = [...pruneSentThisWeek(prev, at), iso]
  const next: PushPrefs = {
    ...prev,
    guestId,
    sentThisWeek,
    lastBriefAt: iso,
    updatedAt: iso,
  }
  store.prefs[guestId] = next
  writeStore(store)
  return next
}

export function publicPrefsView(p: PushPrefs) {
  return {
    guestId: p.guestId,
    shootWindow: p.shootWindow,
    quietHours: p.quietHours,
    weeklyCap: p.weeklyCap,
    pushOptIn: p.pushOptIn,
    experimentHoldout: p.experimentHoldout,
    timezone: p.timezone,
    tokenCount: p.apnsDeviceTokens.length,
    sentThisWeekCount: pruneSentThisWeek(p).length,
    lastBriefAt: p.lastBriefAt,
    updatedAt: p.updatedAt,
  }
}
