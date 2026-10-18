/**
 * Per-app scoping for admin / telemetry reads.
 * `app` is the telemetry_events.app / install_devices.app column (e.g. photo-recipes, finalcap, omr).
 * Query-string value `all` means "no app filter". The value is validated against a
 * conservative pattern AND always bound as a SQL parameter (never interpolated).
 */
/** The primary product audience counted as "real users" on the admin (re-exported by installDevices). */
export const REAL_APP = 'photo-recipes'

/** Query value meaning every app. */
export const ALL_APPS = 'all'

/** Same-ish as what POST /api/telemetry stores (≤64 chars), minus anything exotic. */
export const APP_PARAM_RE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/

/** null = all apps; otherwise a validated app name. */
export type AppScope = string | null

export type ParsedApp = { ok: true; app: AppScope } | { ok: false }

/**
 * Parse an optional `app` query value.
 * - missing / empty → `defaultApp` (admin: photo-recipes; telemetry funnels API: all)
 * - `all` → null (all apps)
 * - anything else must match APP_PARAM_RE, otherwise { ok: false }.
 */
export function parseAppParam(raw: unknown, defaultApp: AppScope = REAL_APP): ParsedApp {
  if (raw === undefined || raw === null) return { ok: true, app: defaultApp }
  if (typeof raw !== 'string') return { ok: false } // ?app=a&app=b or ?app[x]=y
  const v = raw.trim()
  if (!v) return { ok: true, app: defaultApp }
  if (v.toLowerCase() === ALL_APPS) return { ok: true, app: null }
  if (!APP_PARAM_RE.test(v)) return { ok: false }
  return { ok: true, app: v }
}

/**
 * `AND <col> = ?` fragment (leading space, empty when all apps) plus its bound params.
 * `col` is a trusted code-side identifier such as `app` or `e.app`.
 */
export function appAnd(col: string, app: AppScope): { and: string; params: string[] } {
  if (app === null) return { and: '', params: [] }
  return { and: ` AND ${col} = ?`, params: [app] }
}

/**
 * The "real iOS ProTune" DAU definition is specific to photo-recipes; other apps
 * (and "all apps") count real non-test installs on any platform.
 */
export function iosOnlyScope(app: AppScope): boolean {
  return app === REAL_APP
}

export function appLabel(app: AppScope): string {
  return app === null ? 'all apps' : app
}
