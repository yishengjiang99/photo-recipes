/**
 * In-house funnel telemetry → POST /api/telemetry.
 * No third-party SDKs. Never send photos, base64, email, or GPS.
 */

const ANON_KEY = 'pr.telemetry.anon'
const SESSION_KEY = 'pr.telemetry.session'
const SESSION_TS_KEY = 'pr.telemetry.session.ts'
const SESSION_TTL_MS = 30 * 60 * 1000

export type TelemetryProps = Record<string, string | number | boolean | undefined | null>

function uuid(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) {
    return crypto.randomUUID()
  }
  return `id-${Date.now()}-${Math.random().toString(36).slice(2, 12)}`
}

function storageGet(key: string): string | null {
  try {
    return localStorage.getItem(key)
  } catch {
    return null
  }
}

function storageSet(key: string, value: string) {
  try {
    localStorage.setItem(key, value)
  } catch {
    /* private mode */
  }
}

export function getAnonId(): string {
  let id = storageGet(ANON_KEY)
  if (!id || id.length < 8) {
    id = uuid()
    storageSet(ANON_KEY, id)
  }
  return id
}

export function getSessionId(): string {
  const now = Date.now()
  const prevTs = Number(storageGet(SESSION_TS_KEY) || 0)
  let sid = storageGet(SESSION_KEY)
  if (!sid || !prevTs || now - prevTs > SESSION_TTL_MS) {
    sid = uuid()
    storageSet(SESSION_KEY, sid)
  }
  storageSet(SESSION_TS_KEY, String(now))
  return sid
}

function cleanProps(props?: TelemetryProps): Record<string, string | number | boolean> | undefined {
  if (!props) return undefined
  const out: Record<string, string | number | boolean> = {}
  for (const [k, v] of Object.entries(props)) {
    if (v == null) continue
    if (/email|phone|image|photo|base64|gps|lat|lng|token|password/i.test(k)) continue
    if (typeof v === 'string') {
      if (v.startsWith('data:image') || v.length > 200) continue
      out[k] = v.slice(0, 200)
    } else if (typeof v === 'number' || typeof v === 'boolean') {
      out[k] = v
    }
  }
  return Object.keys(out).length ? out : undefined
}

let booted = false

/** Call once from app entry. Fires session_start + app_open. */
export function initAnalytics(extra?: TelemetryProps) {
  if (booted || typeof window === 'undefined') return
  booted = true
  const appVersion =
    typeof import.meta !== 'undefined' && import.meta.env?.VITE_APP_VERSION
      ? String(import.meta.env.VITE_APP_VERSION)
      : undefined
  track('session_start', { ...extra })
  track('app_open', { platform: 'web', app_version: appVersion, ...extra })
}

export function track(event: string, props?: TelemetryProps) {
  if (typeof window === 'undefined') return
  const body = {
    event,
    anon_id: getAnonId(),
    session_id: getSessionId(),
    platform: 'web',
    app: 'photo-recipes',
    props: cleanProps(props),
  }
  const json = JSON.stringify(body)
  try {
    if (navigator.sendBeacon) {
      const blob = new Blob([json], { type: 'application/json' })
      if (navigator.sendBeacon('/api/telemetry', blob)) return
    }
  } catch {
    /* fall through */
  }
  void fetch('/api/telemetry', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: json,
    keepalive: true,
    credentials: 'same-origin',
  }).catch(() => {
    /* soft-fail */
  })
}
