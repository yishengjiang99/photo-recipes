import { Loader2, Lock, LogOut, RefreshCw } from 'lucide-react'
import { useCallback, useEffect, useState, type FormEvent } from 'react'

type SessionResp = {
  ok?: boolean
  configured?: boolean
  authenticated?: boolean
}

type Summary = {
  ok: boolean
  generatedAt: string
  /** Selected app scope echoed by the API (`all` or an app name). */
  app?: string
  /** Distinct apps seen in telemetry / install_devices. */
  apps?: string[]
  telemetry: {
    configured: boolean
    app?: string
    events8h: number
    events24h: number
    events7d: number
    dau: number
    wau: number
    active8h: number
    topEvents: Array<{ event: string; count: number }>
    topEvents8h: Array<{ event: string; count: number }>
    platformSplit: Array<{ platform: string; count: number }>
    eventsByPlatform8h: Record<string, number>
    activeByPlatform8h: Record<string, number>
    topEventsByPlatform: Record<string, Array<{ event: string; count: number }>>
    topEvents8hByPlatform: Record<string, Array<{ event: string; count: number }>>
    hourlyActive?: {
      hours: number
      timezone?: string
      definition: string
      series: Array<{ bucket: number; users: number }>
      error?: string
    }
    dailyActive?: {
      days: number
      timezone?: string
      definition: string
      series: Array<{ bucket: number; day: string; users: number; newUsers?: number; returning?: number }>
      error?: string
    }
    dauRaw?: number
    error?: string
    canonicalFunnel?: {
      name: string
      unit: string
      timezone: string
      days: number
      windowStart: string
      windowEndExclusive: string
      windowStartDay: string
      windowEndDayExclusive: string
      definition: string
      stages: string[]
      counts: {
        sessions: number
        camera_open: number
        auto_optimize_start: number
        auto_optimize_success: number
      }
      conversions: {
        sessionsToCamera: number | null
        cameraToOptimizeStart: number | null
        optimizeStartToSuccess: number | null
      }
      error?: string
    } | null
  }
  devices?: {
    timezone: string
    definition: string
    totals: { real: number; test: number; realIos: number; realWeb: number; otherApps: number }
    today: { day: string; active: number; newInstalls: number; returning: number }
    newPerDay: Array<{ day: string; newInstalls: number }>
    recent: Array<{
      anonId: string
      app: string
      platform: string
      firstSeenAt: string
      lastSeenAt: string
      firstVersion: string | null
      latestVersion: string | null
      build: string | null
      deviceModel: string | null
      source: string | null
      isTest: boolean
      events: number
    }>
    error?: string
  }
  stripe: {
    configured: boolean
    activeSubscriptions: number
    trialingSubscriptions: number
    approxMrrCents: number
    recentCharges: Array<{
      id: string
      amountCents: number
      currency: string
      created: number
      status: string
    }>
    note?: string
    error?: string
  }
  entitlements: {
    proTotal: number
    proActive: number
    proTrialing: number
    stripePro: number
    iapPro: number
    iapNote: string
    byPlan: { monthly: number; yearly: number; unknown: number }
    iapByPlan: { monthly: number; yearly: number; unknown: number }
    iapApproxMrrCents: number
    iapMrrNote: string
    totalRecords: number
  }
  quota?: {
    freeDailyLimit: number
    freePhoneTargetsEnabled: boolean
    freeAssistPerDay: number
    unlimitedEmails: string[]
    unlimitedDeviceIdCount: number
    sources?: {
      freeDailyLimit: 'override' | 'env' | 'default'
      freePhoneTargetsEnabled: 'override' | 'env' | 'default'
    }
    overrides?: {
      freeDailyLimit?: number
      freePhoneTargetsEnabled?: boolean
    }
    env: {
      FREE_DAILY_LIMIT: string | null
      FREE_PHONE_TARGETS_ENABLED?: string | null
      FREE_UNLIMITED_EMAILS: string | null
      UNLIMITED_DEVICE_IDS: string | null
    }
  }
  push: {
    experimentEnabled: boolean
    apnsEnvConfigured: boolean
    days: number
    registry: {
      guests: number
      withToken: number
      optIn: number
      holdout: number
      withShootWindow: number
      briefsSentThisWeek: number
    }
    funnel: {
      permissionPrompt: number
      permissionAccepted: number
      permissionDenied: number
      acceptRate: number | null
      pushSent: number
      pushOpened: number
      openRate: number | null
      paywallFromPush: number
      subscribe: number
    }
    note: string
  }
  recentErrors?: Array<{
    createdAt: string
    event: string
    platform: string
    route: string
    status: number | null
    message: string
    method: string | null
    contentLength: string | null
  }>
}

/** FinalCap usage — separate data source (FinalCap's own server DB), see /api/admin/finalcap-usage. */
type FinalcapUsage = {
  configured: boolean
  days: number
  timezone: string
  definitions: { dailyActive: string; chat: string; subscribers: string }
  dailyUsage: Array<{ day: string; activeUsers: number; inferences: number }>
  chatByDay: Array<{
    day: string
    human2ai: number
    ai2human: number
    error: number
    total: number
  }>
  totals: {
    registeredUsers: number
    activeSubscribers: number
    subscribersByUserFlag: number
    activeUsersInWindow: number
    inferencesInWindow: number
    chatInWindow: number
  }
  error?: string
}

/**
 * FinalCap funnels — FinalCap client app telemetry (app = 'finalcap') read from THIS
 * panel's telemetry_events, see /api/admin/finalcap-funnels. NOT the FinalCap server
 * database above; NOT the canonical ProTune funnel.
 */
type FinalcapFunnelStep = {
  stage: string
  sessions: number
  conversionFromPrev: number | null
  conversionFromFirst: number | null
}
type FinalcapFunnelGroup = {
  stages: string[]
  counts: Record<string, number>
  steps: FinalcapFunnelStep[]
}
type FinalcapFunnels = {
  app: string
  unit: string
  days: number
  timezone: string
  windowStartDay: string
  windowEndDayExclusive: string
  definition: string
  revenueNote: string
  core: FinalcapFunnelGroup
  export: FinalcapFunnelGroup
  revenue: FinalcapFunnelGroup
  error?: string
}

/**
 * GBK Composer billing funnel — GBK server billing tables on this host
 * (billing_daily + billing_log), see /api/admin/gbk-billing. NOT this panel's
 * telemetry; NOT the FinalCap sources above.
 */
type GbkBilling = {
  available: boolean
  days: number
  totals: Record<string, number>
  byDay: Array<{ day: string; counts: Record<string, number> }>
  steps: {
    overall: { paywall_view: number; checkout_start: number; purchase: number }
    bySurface: Array<{
      surface: string
      platform: string
      paywall_view: number
      checkout_start: number
      purchase: number
    }>
  }
  recent: Array<{
    ts: number
    account: string
    event: string
    plan: string
    surface: string
    platform: string
    detail: string
  }>
}

const DEFAULT_APP = 'photo-recipes'
const ALL_APPS = 'all'
const APP_STORAGE_KEY = 'admin.app'
// Mirrors the server's APP_PARAM_RE; anything else falls back to the default.
const APP_RE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/

function sanitizeApp(v: string | null | undefined): string | null {
  const t = (v ?? '').trim()
  if (!t) return null
  if (t.toLowerCase() === ALL_APPS) return ALL_APPS
  return APP_RE.test(t) ? t : null
}

/** URL ?app= wins, then localStorage, then photo-recipes (the original app-specific scope). */
function initialApp(): string {
  try {
    const fromUrl = sanitizeApp(new URLSearchParams(window.location.search).get('app'))
    if (fromUrl) return fromUrl
    const fromStore = sanitizeApp(window.localStorage.getItem(APP_STORAGE_KEY))
    if (fromStore) return fromStore
  } catch {
    /* storage / URL unavailable */
  }
  return DEFAULT_APP
}

function persistApp(app: string) {
  try {
    window.localStorage.setItem(APP_STORAGE_KEY, app)
  } catch {
    /* ignore */
  }
  try {
    const url = new URL(window.location.href)
    url.searchParams.set('app', app)
    window.history.replaceState(window.history.state, '', url)
  } catch {
    /* ignore */
  }
}

function appName(app: string): string {
  return app === ALL_APPS ? 'All apps' : app
}

function AppSelector({
  apps,
  value,
  onChange,
  disabled,
}: {
  apps: string[]
  value: string
  onChange: (app: string) => void
  disabled?: boolean
}) {
  const options = Array.from(new Set([DEFAULT_APP, ...apps, ...(value === ALL_APPS ? [] : [value])]))
  return (
    <label className="inline-flex items-center gap-2 text-xs text-[var(--color-ink-tertiary)]">
      App
      <select
        value={value}
        disabled={disabled}
        onChange={(e) => onChange(e.target.value)}
        aria-label="Filter telemetry by app"
        className="rounded-[var(--radius-pill)] border border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-1.5 text-sm text-[var(--color-ink)] outline-none focus:border-[var(--color-tip)]"
      >
        <option value={ALL_APPS}>All apps</option>
        {options.map((a) => (
          <option key={a} value={a}>
            {a}
          </option>
        ))}
      </select>
    </label>
  )
}

function money(cents: number, currency = 'usd'): string {
  try {
    return new Intl.NumberFormat(undefined, {
      style: 'currency',
      currency: currency.toUpperCase(),
    }).format(cents / 100)
  } catch {
    return `$${(cents / 100).toFixed(2)}`
  }
}

function fmtTime(unixOrIso: number | string): string {
  const d =
    typeof unixOrIso === 'number' ? new Date(unixOrIso * 1000) : new Date(unixOrIso)
  return d.toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

function Kpi({
  label,
  value,
  hint,
}: {
  label: string
  value: string | number
  hint?: string
}) {
  return (
    <div className="rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface)] p-4">
      <div className="text-xs uppercase tracking-wide text-[var(--color-ink-tertiary)]">
        {label}
      </div>
      <div className="mt-1 font-display text-3xl text-[var(--color-tip)]">{value}</div>
      {hint ? (
        <div className="mt-1 text-xs text-[var(--color-ink-tertiary)]">{hint}</div>
      ) : null}
    </div>
  )
}

function platformLabel(p: string): string {
  const lower = p.toLowerCase()
  if (lower === 'ios') return 'iOS'
  return p.charAt(0).toUpperCase() + p.slice(1)
}

function PlatformFilter({
  platforms,
  value,
  onChange,
}: {
  platforms: string[]
  value: string
  onChange: (p: string) => void
}) {
  const options = ['all', ...platforms]
  return (
    <div
      className="inline-flex items-center gap-1 rounded-[var(--radius-pill)] border border-[var(--color-border)] bg-[var(--color-surface)] p-1"
      role="group"
      aria-label="Filter by platform"
    >
      {options.map((p) => {
        const active = value === p
        return (
          <button
            key={p}
            type="button"
            onClick={() => onChange(p)}
            aria-pressed={active}
            className={`rounded-[var(--radius-pill)] px-3 py-1 text-xs font-medium transition-colors ${
              active
                ? 'bg-[var(--color-tip)] text-black'
                : 'text-[var(--color-ink-secondary)] hover:text-[var(--color-ink)]'
            }`}
          >
            {p === 'all' ? 'All' : platformLabel(p)}
          </button>
        )
      })}
    </div>
  )
}


const PT = 'America/Los_Angeles'
const ptHourFmt = new Intl.DateTimeFormat('en-US', {
  timeZone: PT,
  weekday: 'short',
  month: 'short',
  day: 'numeric',
  hour: 'numeric',
})
const ptDayTick = new Intl.DateTimeFormat('en-US', { timeZone: PT, month: 'numeric', day: 'numeric' })
const ptHour23 = new Intl.DateTimeFormat('en-US', { timeZone: PT, hour: 'numeric', hourCycle: 'h23' })
// Daily buckets are PT date keys (00:00 UTC of the PT date) → format in UTC.
const dayKeyFmt = new Intl.DateTimeFormat('en-US', {
  timeZone: 'UTC',
  weekday: 'short',
  month: 'short',
  day: 'numeric',
})
const dayKeyTick = new Intl.DateTimeFormat('en-US', { timeZone: 'UTC', month: 'numeric', day: 'numeric' })

type Bar = { key: number; value: number; tooltip: string; tick?: string; divider?: boolean }

/** CSS bar histogram — no chart library; matches admin card styling. */
function BarHistogram({
  title,
  windowLabel,
  definition,
  error,
  bars,
  peakLabel,
  dense,
}: {
  title: string
  windowLabel: string
  definition: string
  error?: string
  bars: Bar[]
  peakLabel?: (b: Bar) => string
  dense?: boolean
}) {
  const max = Math.max(1, ...bars.map((b) => b.value))
  const peak = bars.reduce<Bar | null>((m, b) => (!m || b.value > m.value ? b : m), null)
  return (
    <div className="mt-4 overflow-hidden rounded-[var(--radius-md)] border border-[var(--color-border)]">
      <div className="border-b border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-2">
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <div className="text-sm text-[var(--color-ink-secondary)]">
            {title}
            <span className="ml-2 text-xs text-[var(--color-ink-tertiary)]">{windowLabel}</span>
          </div>
          {peak && peak.value > 0 ? (
            <span className="text-xs text-[var(--color-ink-tertiary)]">
              peak <span className="font-mono text-[var(--color-tip)]">{peak.value}</span>
              {peakLabel ? ` · ${peakLabel(peak)}` : ''}
            </span>
          ) : null}
        </div>
        <p className="mt-0.5 text-xs text-[var(--color-ink-tertiary)]">{definition}</p>
        {error ? (
          <p className="mt-1 text-xs text-[var(--color-danger)]">
            Query failed ({error}) — bars below are placeholders, not real zeros.
          </p>
        ) : null}
      </div>
      {bars.length === 0 ? (
        <p className="px-3 py-6 text-sm text-[var(--color-ink-tertiary)]">No data</p>
      ) : (
        <div className="px-3 pb-2 pt-4">
          <div
            className={`flex h-40 items-end ${dense ? 'gap-px' : 'gap-1'}`}
            role="img"
            aria-label={`${title}, ${windowLabel}`}
          >
            {bars.map((b) => (
              <div
                key={b.key}
                className={`flex h-full min-w-0 flex-1 flex-col justify-end ${
                  b.divider ? 'border-l border-[var(--color-border)]' : ''
                }`}
                title={b.tooltip}
              >
                <div
                  className="w-full rounded-t-[2px] bg-[var(--color-tip)] hover:opacity-80"
                  style={{
                    height: b.value <= 0 ? '0%' : `${Math.max(3, Math.round((b.value / max) * 100))}%`,
                  }}
                />
              </div>
            ))}
          </div>
          <div className={`mt-1 flex border-t border-[var(--color-border)] pt-1 ${dense ? 'gap-px' : 'gap-1'}`}>
            {bars.map((b) => (
              <div
                key={b.key}
                className="relative min-w-0 flex-1 text-[9px] leading-tight text-[var(--color-ink-tertiary)] sm:text-[10px]"
              >
                {b.tick ? <span className="absolute left-0 whitespace-nowrap">{b.tick}</span> : null}
                {'\u00a0'}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

function hourlyBars(series: Array<{ bucket: number; users: number }>): Bar[] {
  return series.map((p) => {
    const d = new Date(p.bucket * 1000)
    const midnight = ptHour23.format(d) === '0'
    return {
      key: p.bucket,
      value: p.users,
      tooltip: `${ptHourFmt.format(d)} PT: ${p.users} active`,
      tick: midnight ? ptDayTick.format(d) : undefined,
      divider: midnight,
    }
  })
}

/** 0.756 -> "75.6%" (one decimal, matching the canonical funnel hints); null when undefined. */
function pct1(r: number | null | undefined): string | null {
  return r == null ? null : `${Math.round(r * 1000) / 10}%`
}

function finalcapBars(series: Array<{ day: string; activeUsers: number; inferences: number }>): Bar[] {
  const every = Math.max(1, Math.ceil(series.length / 6))
  return series.map((p, i) => {
    const [y, m, d] = p.day.split('-').map(Number)
    const label = new Date(Date.UTC(y ?? 1970, (m ?? 1) - 1, d ?? 1)).toLocaleDateString('en-US', {
      timeZone: 'UTC',
      weekday: 'short',
      month: 'short',
      day: 'numeric',
    })
    return {
      key: i,
      value: p.activeUsers,
      tooltip: `${label} (UTC): ${p.activeUsers} active users · ${p.inferences} inferences`,
      tick: i % every === 0 || i === series.length - 1 ? `${m}/${d}` : undefined,
    }
  })
}

function dailyBars(
  series: Array<{ bucket: number; users: number; newUsers?: number; returning?: number }>,
): Bar[] {
  const every = Math.max(1, Math.ceil(series.length / 6))
  return series.map((p, i) => {
    const d = new Date(p.bucket * 1000)
    return {
      key: p.bucket,
      value: p.users,
      tooltip: `${dayKeyFmt.format(d)} (PT): ${p.users} DAU · ${p.newUsers ?? 0} new · ${p.returning ?? 0} returning`,
      tick: i % every === 0 || i === series.length - 1 ? dayKeyTick.format(d) : undefined,
    }
  })
}

export function Admin() {
  const [checking, setChecking] = useState(true)
  const [configured, setConfigured] = useState(true)
  const [authed, setAuthed] = useState(false)
  const [password, setPassword] = useState('')
  const [loginError, setLoginError] = useState('')
  const [loggingIn, setLoggingIn] = useState(false)
  const [summary, setSummary] = useState<Summary | null>(null)
  const [finalcap, setFinalcap] = useState<FinalcapUsage | null>(null)
  const [finalcapError, setFinalcapError] = useState('')
  const [loadingFinalcap, setLoadingFinalcap] = useState(false)
  const [finalcapFunnels, setFinalcapFunnels] = useState<FinalcapFunnels | null>(null)
  const [finalcapFunnelsError, setFinalcapFunnelsError] = useState('')
  const [gbkBilling, setGbkBilling] = useState<GbkBilling | null>(null)
  const [gbkBillingError, setGbkBillingError] = useState('')
  const [loadingGbkBilling, setLoadingGbkBilling] = useState(false)
  const [loadingFinalcapFunnels, setLoadingFinalcapFunnels] = useState(false)
  const [loadError, setLoadError] = useState('')
  const [loadingSummary, setLoadingSummary] = useState(false)
  const [draftLimit, setDraftLimit] = useState('5')
  const [draftDials, setDraftDials] = useState(true)
  const [savingQuota, setSavingQuota] = useState(false)
  const [quotaSaveMsg, setQuotaSaveMsg] = useState('')
  const [quotaSaveError, setQuotaSaveError] = useState('')
  const [platformFilter, setPlatformFilter] = useState('all')
  const [appFilter, setAppFilter] = useState<string>(initialApp)
  const [knownApps, setKnownApps] = useState<string[]>([])

  const refreshSession = useCallback(async () => {
    try {
      const res = await fetch('/api/admin/session', { credentials: 'include' })
      const data = (await res.json()) as SessionResp
      setConfigured(Boolean(data.configured))
      setAuthed(Boolean(data.authenticated))
      return Boolean(data.authenticated)
    } catch {
      setConfigured(false)
      setAuthed(false)
      return false
    } finally {
      setChecking(false)
    }
  }, [])

  const loadSummary = useCallback(async (app: string) => {
    setLoadingSummary(true)
    setLoadError('')
    try {
      const res = await fetch(`/api/admin/summary?app=${encodeURIComponent(app)}`, {
        credentials: 'include',
      })
      if (res.status === 401) {
        setAuthed(false)
        setSummary(null)
        setLoadError('Session expired — sign in again.')
        return
      }
      const data = (await res.json()) as Summary & { error?: string }
      if (!res.ok) {
        setLoadError(data.error || `Failed (${res.status})`)
        return
      }
      setSummary(data)
      if (data.apps?.length) setKnownApps(data.apps)
      setAuthed(true)
      if (data.quota) {
        setDraftLimit(String(data.quota.freeDailyLimit))
        setDraftDials(Boolean(data.quota.freePhoneTargetsEnabled))
        setQuotaSaveMsg('')
        setQuotaSaveError('')
      }
    } catch (err) {
      setLoadError(err instanceof Error ? err.message : 'Failed to load summary')
    } finally {
      setLoadingSummary(false)
    }
  }, [])

  const loadFinalcap = useCallback(async () => {
    setLoadingFinalcap(true)
    setFinalcapError('')
    try {
      const res = await fetch('/api/admin/finalcap-usage?days=30', {
        credentials: 'include',
      })
      if (res.status === 401) {
        setFinalcap(null)
        return
      }
      const data = (await res.json()) as {
        finalcap?: FinalcapUsage
        error?: string
      }
      if (!res.ok || !data.finalcap) {
        setFinalcapError(data.error || `Failed (${res.status})`)
        return
      }
      setFinalcap(data.finalcap)
    } catch (err) {
      setFinalcapError(err instanceof Error ? err.message : 'Failed to load FinalCap usage')
    } finally {
      setLoadingFinalcap(false)
    }
  }, [])

  const loadFinalcapFunnels = useCallback(async () => {
    setLoadingFinalcapFunnels(true)
    setFinalcapFunnelsError('')
    try {
      const res = await fetch('/api/admin/finalcap-funnels?days=30', {
        credentials: 'include',
      })
      if (res.status === 401) {
        setFinalcapFunnels(null)
        return
      }
      const data = (await res.json()) as {
        funnels?: FinalcapFunnels
        error?: string
      }
      if (!res.ok || !data.funnels) {
        setFinalcapFunnelsError(data.error || `Failed (${res.status})`)
        return
      }
      setFinalcapFunnels(data.funnels)
    } catch (err) {
      setFinalcapFunnelsError(
        err instanceof Error ? err.message : 'Failed to load FinalCap funnels',
      )
    } finally {
      setLoadingFinalcapFunnels(false)
    }
  }, [])

  const loadGbkBilling = useCallback(async () => {
    setLoadingGbkBilling(true)
    setGbkBillingError('')
    try {
      const res = await fetch('/api/admin/gbk-billing?days=30', {
        credentials: 'include',
      })
      if (res.status === 401) {
        setGbkBilling(null)
        return
      }
      const data = (await res.json()) as {
        billing?: GbkBilling
        error?: string
      }
      if (!res.ok || !data.billing) {
        setGbkBillingError(data.error || `Failed (${res.status})`)
        return
      }
      setGbkBilling(data.billing)
    } catch (err) {
      setGbkBillingError(
        err instanceof Error ? err.message : 'Failed to load GBK billing funnel',
      )
    } finally {
      setLoadingGbkBilling(false)
    }
  }, [])

  useEffect(() => {
    void (async () => {
      const ok = await refreshSession()
      if (ok) {
        await loadSummary(appFilter)
        await loadFinalcap()
        await loadFinalcapFunnels()
        await loadGbkBilling()
      }
    })()
    // Initial load only; app changes go through onAppChange.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [refreshSession, loadSummary, loadFinalcap, loadFinalcapFunnels, loadGbkBilling])

  function onAppChange(next: string) {
    if (next === appFilter) return
    setAppFilter(next)
    persistApp(next)
    setPlatformFilter('all')
    void loadSummary(next)
  }

  async function saveQuota() {
    setSavingQuota(true)
    setQuotaSaveMsg('')
    setQuotaSaveError('')
    try {
      const n = Number.parseInt(draftLimit.trim(), 10)
      if (!Number.isFinite(n) || !Number.isInteger(n) || n < 0) {
        setQuotaSaveError('Daily limit must be an integer ≥ 0 (0 = no free peeks).')
        return
      }
      const res = await fetch('/api/admin/quota-config', {
        method: 'PATCH',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          freeDailyLimit: n,
          freePhoneTargetsEnabled: draftDials,
        }),
      })
      const data = (await res.json()) as {
        ok?: boolean
        error?: string
        details?: string
        quota?: Summary['quota']
      }
      if (res.status === 401) {
        setAuthed(false)
        setQuotaSaveError('Session expired — sign in again.')
        return
      }
      if (!res.ok || !data.ok) {
        setQuotaSaveError(data.details || data.error || `Save failed (${res.status})`)
        return
      }
      if (data.quota) {
        setSummary((prev) => (prev ? { ...prev, quota: data.quota } : prev))
        setDraftLimit(String(data.quota.freeDailyLimit))
        setDraftDials(Boolean(data.quota.freePhoneTargetsEnabled))
      }
      setQuotaSaveMsg('Saved — takes effect immediately for quota checks and dial writes.')
    } catch (err) {
      setQuotaSaveError(err instanceof Error ? err.message : 'Save failed')
    } finally {
      setSavingQuota(false)
    }
  }

  async function onLogin(e: FormEvent) {
    e.preventDefault()
    setLoggingIn(true)
    setLoginError('')
    try {
      const res = await fetch('/api/admin/login', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password }),
      })
      const data = (await res.json().catch(() => ({}))) as {
        error?: string
        hint?: string
      }
      if (!res.ok) {
        setLoginError(
          data.error === 'invalid_password'
            ? 'Wrong password.'
            : data.hint || data.error || `Login failed (${res.status})`,
        )
        return
      }
      setPassword('')
      setAuthed(true)
      await loadSummary(appFilter)
      await loadFinalcap()
    } catch (err) {
      setLoginError(err instanceof Error ? err.message : 'Login failed')
    } finally {
      setLoggingIn(false)
    }
  }

  async function onLogout() {
    await fetch('/api/admin/logout', {
      method: 'POST',
      credentials: 'include',
    })
    setAuthed(false)
    setSummary(null)
    setFinalcap(null)
  }

  // Platform filter: separate iOS from web events across the telemetry views.
  const filterPlatforms: string[] = summary
    ? Array.from(
        new Set([
          ...Object.keys(summary.telemetry.topEventsByPlatform ?? {}),
          ...Object.keys(summary.telemetry.topEvents8hByPlatform ?? {}),
          ...summary.telemetry.platformSplit.map((r) => r.platform),
        ]),
      ).sort()
    : []
  const pf = platformFilter === 'all' ? null : platformFilter
  const events8hShown = pf
    ? (summary?.telemetry.eventsByPlatform8h[pf] ?? 0)
    : (summary?.telemetry.events8h ?? 0)
  const active8hShown = pf
    ? (summary?.telemetry.activeByPlatform8h[pf] ?? 0)
    : (summary?.telemetry.active8h ?? 0)
  const topEvents8hShown = pf
    ? (summary?.telemetry.topEvents8hByPlatform[pf] ?? [])
    : (summary?.telemetry.topEvents8h ?? [])
  const topEventsShown = pf
    ? (summary?.telemetry.topEventsByPlatform[pf] ?? [])
    : (summary?.telemetry.topEvents ?? [])

  if (checking) {
    return (
      <div className="flex min-h-dvh items-center justify-center bg-[var(--color-bg)] text-[var(--color-ink-secondary)]">
        <Loader2 className="h-6 w-6 animate-spin text-[var(--color-tip)]" />
      </div>
    )
  }

  if (!authed) {
    return (
      <div className="flex min-h-dvh items-center justify-center bg-[var(--color-bg)] px-4">
        <div className="w-full max-w-sm rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface)] p-6 shadow-[var(--shadow-card)]">
          <div className="mb-4 flex items-center gap-2 text-[var(--color-tip)]">
            <Lock className="h-5 w-5" />
            <h1 className="font-display text-2xl text-[var(--color-ink)]">Admin</h1>
          </div>
          <p className="mb-4 text-sm text-[var(--color-ink-secondary)]">
            ProTune AI Camera safelight desk — telemetry &amp; income snapshot.
          </p>
          {!configured ? (
            <p className="rounded-[var(--radius-sm)] border border-[var(--color-danger)]/40 bg-[var(--color-danger)]/10 px-3 py-2 text-sm text-[var(--color-danger)]">
              ADMIN_PASSWORD is not set on this server. Add it to the environment and
              restart the API.
            </p>
          ) : (
            <form onSubmit={onLogin} className="space-y-3">
              <label className="block text-sm text-[var(--color-ink-secondary)]">
                Password
                <input
                  type="password"
                  autoComplete="current-password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  className="mt-1 w-full rounded-[var(--radius-sm)] border border-[var(--color-border)] bg-[var(--color-bg)] px-3 py-2 text-[var(--color-ink)] outline-none focus:border-[var(--color-tip)]"
                  required
                />
              </label>
              {loginError ? (
                <p className="text-sm text-[var(--color-danger)]">{loginError}</p>
              ) : null}
              <button
                type="submit"
                disabled={loggingIn}
                className="flex w-full items-center justify-center gap-2 rounded-[var(--radius-pill)] bg-[var(--color-tip)] px-4 py-2.5 font-medium text-black disabled:opacity-60"
              >
                {loggingIn ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
                Sign in
              </button>
            </form>
          )}
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-dvh bg-[var(--color-bg)] text-[var(--color-ink)]">
      <header className="border-b border-[var(--color-border)] bg-[var(--color-bg-elevated)]">
        <div className="mx-auto flex max-w-5xl items-center justify-between gap-3 px-4 py-4">
          <div>
            <h1 className="font-display text-2xl text-[var(--color-tip)]">
              Safelight admin
            </h1>
            <p className="text-xs text-[var(--color-ink-tertiary)]">
              {summary?.generatedAt
                ? `Updated ${fmtTime(summary.generatedAt)}`
                : 'ProTune AI Camera · /admin'}
              {` · ${appName(appFilter)}`}
            </p>
          </div>
          <div className="flex flex-wrap items-center justify-end gap-2">
            <AppSelector
              apps={knownApps}
              value={appFilter}
              onChange={onAppChange}
              disabled={loadingSummary}
            />
            <button
              type="button"
              onClick={() => {
                void loadSummary(appFilter)
                void loadFinalcap()
              }}
              disabled={loadingSummary}
              className="inline-flex items-center gap-1.5 rounded-[var(--radius-pill)] border border-[var(--color-border)] px-3 py-1.5 text-sm text-[var(--color-ink-secondary)] hover:border-[var(--color-tip)] hover:text-[var(--color-tip)]"
            >
              <RefreshCw className={`h-3.5 w-3.5 ${loadingSummary ? 'animate-spin' : ''}`} />
              Refresh
            </button>
            <button
              type="button"
              onClick={() => void onLogout()}
              className="inline-flex items-center gap-1.5 rounded-[var(--radius-pill)] border border-[var(--color-border)] px-3 py-1.5 text-sm text-[var(--color-ink-secondary)] hover:border-[var(--color-danger)] hover:text-[var(--color-danger)]"
            >
              <LogOut className="h-3.5 w-3.5" />
              Log out
            </button>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-5xl space-y-8 px-4 py-6">
        {loadError ? (
          <p className="rounded-[var(--radius-sm)] border border-[var(--color-danger)]/40 bg-[var(--color-danger)]/10 px-3 py-2 text-sm text-[var(--color-danger)]">
            {loadError}
          </p>
        ) : null}

        {!summary && loadingSummary ? (
          <div className="flex justify-center py-16 text-[var(--color-ink-tertiary)]">
            <Loader2 className="h-6 w-6 animate-spin text-[var(--color-tip)]" />
          </div>
        ) : null}

        {summary ? (
          <>
            <section>
              <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
                <h2 className="text-sm font-medium uppercase tracking-wide text-[var(--color-ink-tertiary)]">
                  Last 8 hours · {appName(appFilter)}
                  {!summary.telemetry.configured ? (
                    <span className="ml-2 rounded-full bg-[var(--color-tip-bg)] px-2 py-0.5 text-[var(--color-tip)] normal-case">
                      MySQL unset — empty snapshot
                    </span>
                  ) : null}
                </h2>
                <PlatformFilter
                  platforms={filterPlatforms}
                  value={platformFilter}
                  onChange={setPlatformFilter}
                />
              </div>
              <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                <Kpi label="Events 8h" value={events8hShown} />
                <Kpi
                  label="Active users 8h"
                  value={active8hShown}
                  hint="Distinct anon_id · 8h"
                />
              </div>
              <div className="mt-4 overflow-hidden rounded-[var(--radius-md)] border border-[var(--color-border)]">
                <div className="border-b border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-2 text-sm text-[var(--color-ink-secondary)]">
                  Top events (8h)
                </div>
                <table className="w-full text-left text-sm">
                  <thead>
                    <tr className="text-xs text-[var(--color-ink-tertiary)]">
                      <th className="px-3 py-2 font-medium">Event</th>
                      <th className="px-3 py-2 font-medium">Count</th>
                    </tr>
                  </thead>
                  <tbody>
                    {topEvents8hShown.length === 0 ? (
                      <tr>
                        <td colSpan={2} className="px-3 py-3 text-[var(--color-ink-tertiary)]">
                          No events
                        </td>
                      </tr>
                    ) : (
                      topEvents8hShown.map((row) => (
                        <tr
                          key={row.event}
                          className="border-t border-[var(--color-border)]"
                        >
                          <td className="px-3 py-2 font-mono text-xs">{row.event}</td>
                          <td className="px-3 py-2">{row.count}</td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            </section>

            <section>
              <h2 className="mb-3 text-sm font-medium uppercase tracking-wide text-[var(--color-ink-tertiary)]">
                Telemetry · {appName(appFilter)}
                {!summary.telemetry.configured ? (
                  <span className="ml-2 rounded-full bg-[var(--color-tip-bg)] px-2 py-0.5 text-[var(--color-tip)] normal-case">
                    MySQL unset — empty snapshot
                  </span>
                ) : null}
              </h2>
              <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                <Kpi label="Events 24h" value={summary.telemetry.events24h} />
                <Kpi label="Events 7d" value={summary.telemetry.events7d} />
                <Kpi
                  label={appFilter === DEFAULT_APP ? 'DAU (real iOS)' : 'DAU (real installs)'}
                  value={summary.telemetry.dau}
                  hint={`Distinct non-test ${
                    appFilter === DEFAULT_APP
                      ? 'ProTune iOS installs'
                      : appFilter === ALL_APPS
                        ? 'installs, all apps & platforms'
                        : `${appFilter} installs, any platform`
                  } · rolling 24h · raw ${appName(appFilter)} traffic ${summary.telemetry.dauRaw ?? '—'}`}
                />
                <Kpi
                  label="WAU"
                  value={summary.telemetry.wau}
                  hint={`Distinct anon_id · 7d · ${appName(appFilter)}`}
                />
              </div>
              {summary.telemetry.canonicalFunnel ? (
                <div className="mt-4 overflow-hidden rounded-[var(--radius-md)] border border-[var(--color-border)]">
                  <div className="border-b border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-2">
                    <div className="text-sm text-[var(--color-ink-secondary)]">
                      Canonical funnel — THE ProTune funnel
                      <span className="ml-2 text-xs text-[var(--color-ink-tertiary)]">
                        trailing {summary.telemetry.canonicalFunnel.days} complete days ·{' '}
                        {summary.telemetry.canonicalFunnel.windowStartDay} →{' '}
                        {summary.telemetry.canonicalFunnel.windowEndDayExclusive} (exclusive) ·{' '}
                        {summary.telemetry.canonicalFunnel.timezone} · {appName(appFilter)}
                      </span>
                    </div>
                    <p className="mt-0.5 text-xs text-[var(--color-ink-tertiary)]">
                      {summary.telemetry.canonicalFunnel.definition}
                    </p>
                    {summary.telemetry.canonicalFunnel.error ? (
                      <p className="mt-1 text-xs text-[var(--color-danger)]">
                        Query failed ({summary.telemetry.canonicalFunnel.error}) — counts below are
                        placeholders, not real zeros.
                      </p>
                    ) : null}
                  </div>
                  <div className="grid gap-3 p-3 sm:grid-cols-2 lg:grid-cols-4">
                    <Kpi
                      label="1 · Sessions (any event)"
                      value={summary.telemetry.canonicalFunnel.counts.sessions}
                      hint="Distinct session_id"
                    />
                    <Kpi
                      label="2 · Camera open"
                      value={summary.telemetry.canonicalFunnel.counts.camera_open}
                      hint={
                        summary.telemetry.canonicalFunnel.conversions.sessionsToCamera != null
                          ? `${Math.round(summary.telemetry.canonicalFunnel.conversions.sessionsToCamera * 1000) / 10}% of sessions`
                          : 'Distinct session_id'
                      }
                    />
                    <Kpi
                      label="3 · Auto Optimize start"
                      value={summary.telemetry.canonicalFunnel.counts.auto_optimize_start}
                      hint={
                        summary.telemetry.canonicalFunnel.conversions.cameraToOptimizeStart != null
                          ? `${Math.round(summary.telemetry.canonicalFunnel.conversions.cameraToOptimizeStart * 1000) / 10}% of camera sessions`
                          : 'Distinct session_id'
                      }
                    />
                    <Kpi
                      label="4 · Auto Optimize success"
                      value={summary.telemetry.canonicalFunnel.counts.auto_optimize_success}
                      hint={
                        summary.telemetry.canonicalFunnel.conversions.optimizeStartToSuccess != null
                          ? `${Math.round(summary.telemetry.canonicalFunnel.conversions.optimizeStartToSuccess * 1000) / 10}% of start sessions`
                          : 'Distinct session_id'
                      }
                    />
                  </div>
                  <p className="px-3 pb-3 text-xs text-[var(--color-ink-tertiary)]">
                    Alternate cuts on this page — raw event counts (Top events, Platform split) and
                    user-level distinct anon_id (DAU/WAU, hourly/daily active) — are not the canonical
                    funnel and are not comparable with the numbers above.
                  </p>
                </div>
              ) : null}
              {summary.telemetry.dailyActive ? (
                <BarHistogram
                  title="Daily active users"
                  windowLabel={`last ${summary.telemetry.dailyActive.days} days · PT calendar days · ${appName(appFilter)} · ${appFilter === DEFAULT_APP ? 'real iOS installs' : 'real installs'} (hover: new/returning)`}
                  definition={summary.telemetry.dailyActive.definition}
                  error={summary.telemetry.dailyActive.error}
                  bars={dailyBars(summary.telemetry.dailyActive.series)}
                  peakLabel={(b) => dayKeyFmt.format(new Date(b.key * 1000))}
                />
              ) : null}
              {summary.devices ? (
                <div className="mt-4 overflow-hidden rounded-[var(--radius-md)] border border-[var(--color-border)]">
                  <div className="border-b border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-2 text-sm text-[var(--color-ink-secondary)]">
                    Devices (installs) · {appName(appFilter)} · PT days{summary.devices.error ? ` · ${summary.devices.error}` : ''}
                    <div className="text-xs text-[var(--color-ink-tertiary)]">{summary.devices.definition}</div>
                  </div>
                  <div className="grid gap-3 p-3 sm:grid-cols-2 lg:grid-cols-4">
                    <Kpi label={`Today ${summary.devices.today.day} active`} value={summary.devices.today.active} hint="Real iOS installs seen today (PT)" />
                    <Kpi label="New today" value={summary.devices.today.newInstalls} hint="First seen today (PT)" />
                    <Kpi label="Returning today" value={summary.devices.today.returning} hint="First seen before today" />
                    <Kpi
                      label="Total real installs"
                      value={summary.devices.totals.real}
                      hint={`iOS ${summary.devices.totals.realIos} · web ${summary.devices.totals.realWeb} · test ${summary.devices.totals.test} · other apps ${summary.devices.totals.otherApps}`}
                    />
                  </div>
                  <div className="px-3 pb-2 text-xs text-[var(--color-ink-secondary)]">
                    New real iOS installs / PT day:{' '}
                    {summary.devices.newPerDay.map((d) => `${d.day.slice(5)}: ${d.newInstalls}`).join(' · ')}
                  </div>
                  <div className="max-h-80 overflow-auto">
                    <table className="w-full text-left text-xs">
                      <thead className="text-[var(--color-ink-tertiary)]">
                        <tr>
                          <th className="px-3 py-1">First seen (PT)</th>
                          <th className="px-3 py-1">Last seen (PT)</th>
                          <th className="px-3 py-1">anon</th>
                          <th className="px-3 py-1">App / platform</th>
                          <th className="px-3 py-1">Version</th>
                          <th className="px-3 py-1">Model</th>
                          <th className="px-3 py-1">Events</th>
                          <th className="px-3 py-1">Test</th>
                        </tr>
                      </thead>
                      <tbody>
                        {summary.devices.recent.map((r) => (
                          <tr key={`${r.anonId}-${r.app}-${r.platform}-${r.firstSeenAt}`} className="border-t border-[var(--color-border)]">
                            <td className="px-3 py-1">{ptHourFmt.format(new Date(r.firstSeenAt))}</td>
                            <td className="px-3 py-1">{ptHourFmt.format(new Date(r.lastSeenAt))}</td>
                            <td className="px-3 py-1 font-mono">{r.anonId}</td>
                            <td className="px-3 py-1">{r.app} / {r.platform}</td>
                            <td className="px-3 py-1">
                              {r.firstVersion ?? '—'}
                              {r.latestVersion && r.latestVersion !== r.firstVersion ? ` → ${r.latestVersion}` : ''}
                              {r.build ? ` (${r.build})` : ''}
                            </td>
                            <td className="px-3 py-1">{r.deviceModel ?? '—'}</td>
                            <td className="px-3 py-1">{r.events}</td>
                            <td className="px-3 py-1">{r.isTest ? 'test' : ''}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </div>
              ) : null}
              {summary.telemetry.hourlyActive ? (
                <BarHistogram
                  title="Hourly active users"
                  windowLabel={`last ${Math.round(summary.telemetry.hourlyActive.hours / 24)} days · ${summary.telemetry.hourlyActive.hours} hours · PT`}
                  definition={summary.telemetry.hourlyActive.definition}
                  error={summary.telemetry.hourlyActive.error}
                  bars={hourlyBars(summary.telemetry.hourlyActive.series)}
                  peakLabel={(b) => `${ptHourFmt.format(new Date(b.key * 1000))} PT`}
                  dense
                />
              ) : null}
              <div className="mt-4 grid gap-4 lg:grid-cols-2">
                <div className="overflow-hidden rounded-[var(--radius-md)] border border-[var(--color-border)]">
                  <div className="flex items-center justify-between gap-2 border-b border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-2">
                    <span className="text-sm text-[var(--color-ink-secondary)]">
                      Top events (7d) — raw counts, alternate cut (not the canonical funnel)
                    </span>
                    <PlatformFilter
                      platforms={filterPlatforms}
                      value={platformFilter}
                      onChange={setPlatformFilter}
                    />
                  </div>
                  <table className="w-full text-left text-sm">
                    <thead>
                      <tr className="text-xs text-[var(--color-ink-tertiary)]">
                        <th className="px-3 py-2 font-medium">Event</th>
                        <th className="px-3 py-2 font-medium">Count</th>
                      </tr>
                    </thead>
                    <tbody>
                      {topEventsShown.length === 0 ? (
                        <tr>
                          <td colSpan={2} className="px-3 py-3 text-[var(--color-ink-tertiary)]">
                            No events
                          </td>
                        </tr>
                      ) : (
                        topEventsShown.map((row) => (
                          <tr
                            key={row.event}
                            className="border-t border-[var(--color-border)]"
                          >
                            <td className="px-3 py-2 font-mono text-xs">{row.event}</td>
                            <td className="px-3 py-2">{row.count}</td>
                          </tr>
                        ))
                      )}
                    </tbody>
                  </table>
                </div>
                <div className="overflow-hidden rounded-[var(--radius-md)] border border-[var(--color-border)]">
                  <div className="border-b border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-2 text-sm text-[var(--color-ink-secondary)]">
                    Platform split (7d)
                  </div>
                  <table className="w-full text-left text-sm">
                    <thead>
                      <tr className="text-xs text-[var(--color-ink-tertiary)]">
                        <th className="px-3 py-2 font-medium">Platform</th>
                        <th className="px-3 py-2 font-medium">Count</th>
                      </tr>
                    </thead>
                    <tbody>
                      {summary.telemetry.platformSplit.length === 0 ? (
                        <tr>
                          <td colSpan={2} className="px-3 py-3 text-[var(--color-ink-tertiary)]">
                            No events
                          </td>
                        </tr>
                      ) : (
                        summary.telemetry.platformSplit.map((row) => (
                          <tr
                            key={row.platform}
                            className="border-t border-[var(--color-border)]"
                          >
                            <td className="px-3 py-2">{row.platform}</td>
                            <td className="px-3 py-2">{row.count}</td>
                          </tr>
                        ))
                      )}
                    </tbody>
                  </table>
                </div>
              </div>
            </section>

            <section>
              <h2 className="mb-3 text-sm font-medium uppercase tracking-wide text-[var(--color-ink-tertiary)]">
                Income snapshot
                <span className="ml-2 rounded-full bg-[var(--color-tip-bg)] px-2 py-0.5 text-[var(--color-tip)] normal-case">
                  global · Stripe + IAP, all apps — not filtered by app
                </span>
              </h2>
              <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                <Kpi
                  label="Stripe active"
                  value={
                    summary.stripe.configured
                      ? summary.stripe.activeSubscriptions
                      : '—'
                  }
                  hint={summary.stripe.configured ? undefined : 'Stripe unset'}
                />
                <Kpi
                  label="Stripe trialing"
                  value={
                    summary.stripe.configured
                      ? summary.stripe.trialingSubscriptions
                      : '—'
                  }
                />
                <Kpi
                  label="Approx MRR"
                  value={
                    summary.stripe.configured ||
                    summary.entitlements.iapApproxMrrCents > 0
                      ? money(
                          (summary.stripe.configured
                            ? summary.stripe.approxMrrCents
                            : 0) + summary.entitlements.iapApproxMrrCents,
                        )
                      : '—'
                  }
                  hint={
                    summary.stripe.configured
                      ? `Stripe ${money(summary.stripe.approxMrrCents)} + IAP est. ${money(summary.entitlements.iapApproxMrrCents)}`
                      : `IAP est. ${money(summary.entitlements.iapApproxMrrCents)} (Stripe unset)`
                  }
                />
                <Kpi
                  label="Local Pro total"
                  value={summary.entitlements.proTotal}
                  hint={`${summary.entitlements.proActive} active · ${summary.entitlements.proTrialing} trial`}
                />
              </div>

              <div className="mt-4 grid gap-4 lg:grid-cols-2">
                <div className="rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface)] p-4">
                  <h3 className="text-sm font-medium text-[var(--color-ink-secondary)]">
                    Local entitlements
                  </h3>
                  <ul className="mt-3 space-y-2 text-sm">
                    <li className="flex justify-between">
                      <span>Stripe Pro (web)</span>
                      <span className="font-mono">{summary.entitlements.stripePro}</span>
                    </li>
                    <li className="flex justify-between">
                      <span>IAP Pro (StoreKit verify)</span>
                      <span className="font-mono">{summary.entitlements.iapPro}</span>
                    </li>
                    <li className="flex justify-between">
                      <span>IAP est. MRR</span>
                      <span className="font-mono">
                        {money(summary.entitlements.iapApproxMrrCents)}
                      </span>
                    </li>
                    <li className="flex justify-between text-[var(--color-ink-tertiary)]">
                      <span>IAP plan · monthly / yearly / ?</span>
                      <span className="font-mono">
                        {summary.entitlements.iapByPlan.monthly} /{' '}
                        {summary.entitlements.iapByPlan.yearly} /{' '}
                        {summary.entitlements.iapByPlan.unknown}
                      </span>
                    </li>
                    <li className="flex justify-between text-[var(--color-ink-tertiary)]">
                      <span>Plan · monthly / yearly / ?</span>
                      <span className="font-mono">
                        {summary.entitlements.byPlan.monthly} /{' '}
                        {summary.entitlements.byPlan.yearly} /{' '}
                        {summary.entitlements.byPlan.unknown}
                      </span>
                    </li>
                  </ul>
                  <p className="mt-3 text-xs leading-relaxed text-[var(--color-tip)]">
                    {summary.entitlements.iapNote}
                  </p>
                  {summary.quota ? (
                    <div className="mt-4 border-t border-[var(--color-border)] pt-3">
                      <h4 className="text-xs font-medium uppercase tracking-wide text-[var(--color-ink-tertiary)]">
                        Free Peek quota
                      </h4>
                      <div className="mt-3 space-y-3 text-sm">
                        <label className="flex flex-col gap-1">
                          <span className="text-xs text-[var(--color-ink-tertiary)]">
                            Daily Ask / Vision / Auto Optimize limit
                          </span>
                          <div className="flex items-center gap-2">
                            <input
                              type="number"
                              min={0}
                              step={1}
                              value={draftLimit}
                              onChange={(e) => setDraftLimit(e.target.value)}
                              className="w-24 rounded border border-[var(--color-border)] bg-[var(--color-bg)] px-2 py-1.5 font-mono text-sm text-[var(--color-ink)]"
                            />
                            <span className="text-xs text-[var(--color-ink-tertiary)]">
                              effective{' '}
                              <span className="font-mono">{summary.quota.freeDailyLimit}</span>
                              {summary.quota.sources ? (
                                <>
                                  {' '}
                                  (
                                  {summary.quota.sources.freeDailyLimit})
                                </>
                              ) : null}
                            </span>
                          </div>
                          <span className="text-xs text-[var(--color-ink-tertiary)]">
                            0 = no free peeks (paywall immediately).
                          </span>
                        </label>
                        <label className="flex items-start gap-2">
                          <input
                            type="checkbox"
                            checked={draftDials}
                            onChange={(e) => setDraftDials(e.target.checked)}
                            className="mt-1"
                          />
                          <span>
                            <span className="block">Free users can apply camera dials</span>
                            <span className="text-xs text-[var(--color-ink-tertiary)]">
                              phoneTargets / manual dial writes. Effective:{' '}
                              <span className="font-mono">
                                {summary.quota.freePhoneTargetsEnabled ? 'on' : 'off'}
                              </span>
                              {summary.quota.sources ? (
                                <>
                                  {' '}
                                  ({summary.quota.sources.freePhoneTargetsEnabled})
                                </>
                              ) : null}
                            </span>
                          </span>
                        </label>
                        <button
                          type="button"
                          onClick={() => void saveQuota()}
                          disabled={savingQuota}
                          className="inline-flex items-center gap-2 rounded-[var(--radius-md)] bg-[var(--color-tip)] px-3 py-1.5 text-sm font-medium text-black disabled:opacity-60"
                        >
                          {savingQuota ? (
                            <Loader2 className="h-4 w-4 animate-spin" />
                          ) : null}
                          Save Free Peek settings
                        </button>
                        {quotaSaveMsg ? (
                          <p className="text-xs text-[var(--color-tip)]">{quotaSaveMsg}</p>
                        ) : null}
                        {quotaSaveError ? (
                          <p className="text-xs text-red-500">{quotaSaveError}</p>
                        ) : null}
                      </div>
                      <ul className="mt-3 space-y-2 text-sm text-[var(--color-ink-tertiary)]">
                        <li className="flex justify-between">
                          <span>Unlimited emails</span>
                          <span className="max-w-[60%] truncate text-right font-mono text-xs">
                            {summary.quota.unlimitedEmails.join(', ') || '—'}
                          </span>
                        </li>
                        <li className="flex justify-between">
                          <span>Unlimited device ids</span>
                          <span className="font-mono">{summary.quota.unlimitedDeviceIdCount}</span>
                        </li>
                      </ul>
                      <p className="mt-2 text-xs text-[var(--color-tip)]">
                        Runtime overrides persist in{' '}
                        <code className="font-mono">server/data/ops-config.json</code>
                        {' '}(no restart). Env fallback{' '}
                        <code className="font-mono">FREE_DAILY_LIMIT</code>
                        {summary.quota.env.FREE_DAILY_LIMIT
                          ? `=${summary.quota.env.FREE_DAILY_LIMIT}`
                          : ' unset (default 5)'}
                        ; dials default on.
                      </p>
                    </div>
                  ) : null}
                </div>

                <div className="overflow-hidden rounded-[var(--radius-md)] border border-[var(--color-border)]">
                  <div className="border-b border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-2 text-sm text-[var(--color-ink-secondary)]">
                    Recent Stripe charges
                  </div>
                  <table className="w-full text-left text-sm">
                    <thead>
                      <tr className="text-xs text-[var(--color-ink-tertiary)]">
                        <th className="px-3 py-2 font-medium">When</th>
                        <th className="px-3 py-2 font-medium">Amount</th>
                        <th className="px-3 py-2 font-medium">Status</th>
                      </tr>
                    </thead>
                    <tbody>
                      {!summary.stripe.configured ? (
                        <tr>
                          <td colSpan={3} className="px-3 py-3 text-[var(--color-ink-tertiary)]">
                            Stripe not configured
                          </td>
                        </tr>
                      ) : summary.stripe.recentCharges.length === 0 ? (
                        <tr>
                          <td colSpan={3} className="px-3 py-3 text-[var(--color-ink-tertiary)]">
                            No recent charges
                          </td>
                        </tr>
                      ) : (
                        summary.stripe.recentCharges.map((c) => (
                          <tr key={c.id} className="border-t border-[var(--color-border)]">
                            <td className="px-3 py-2 text-xs">{fmtTime(c.created)}</td>
                            <td className="px-3 py-2 font-mono text-xs">
                              {money(c.amountCents, c.currency)}
                            </td>
                            <td className="px-3 py-2 text-xs">{c.status}</td>
                          </tr>
                        ))
                      )}
                    </tbody>
                  </table>
                </div>
              </div>
            </section>

            <section>
              <h2 className="mb-3 text-sm font-medium uppercase tracking-wide text-[var(--color-ink-tertiary)]">
                Push funnel (Exp1)
                <span className="ml-2 rounded-full bg-[var(--color-surface)] px-2 py-0.5 text-[var(--color-ink-tertiary)] normal-case">
                  global · {DEFAULT_APP} push registry — not filtered by app
                </span>
                <span className="ml-2 rounded-full bg-[var(--color-tip-bg)] px-2 py-0.5 text-[var(--color-tip)] normal-case">
                  {summary.push.experimentEnabled ? 'flag on' : 'flag off'}
                  {summary.push.apnsEnvConfigured ? ' · APNs env' : ' · APNs unset'}
                </span>
              </h2>
              <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                <Kpi
                  label="Devices w/ token"
                  value={summary.push.registry.withToken}
                  hint={`${summary.push.registry.guests} prefs · ${summary.push.registry.optIn} opt-in`}
                />
                <Kpi
                  label="Permission accept"
                  value={
                    summary.push.funnel.acceptRate != null
                      ? `${Math.round(summary.push.funnel.acceptRate * 100)}%`
                      : '—'
                  }
                  hint={`${summary.push.funnel.permissionAccepted} / ${summary.push.funnel.permissionPrompt} prompts · 7d`}
                />
                <Kpi
                  label="Push open rate"
                  value={
                    summary.push.funnel.openRate != null
                      ? `${Math.round(summary.push.funnel.openRate * 100)}%`
                      : '—'
                  }
                  hint={`${summary.push.funnel.pushOpened} opens / ${summary.push.funnel.pushSent} sent · 7d`}
                />
                <Kpi
                  label="Paywall from push"
                  value={summary.push.funnel.paywallFromPush}
                  hint={`${summary.push.funnel.subscribe} subscribe events · 7d`}
                />
              </div>
              <div className="mt-4 overflow-hidden rounded-[var(--radius-md)] border border-[var(--color-border)]">
                <div className="border-b border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-2 text-sm text-[var(--color-ink-secondary)]">
                  Registry &amp; 7d events
                </div>
                <div className="grid gap-2 p-3 text-sm sm:grid-cols-2">
                  <div className="flex justify-between">
                    <span className="text-[var(--color-ink-tertiary)]">Shoot window set</span>
                    <span className="font-mono">{summary.push.registry.withShootWindow}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-[var(--color-ink-tertiary)]">Holdout</span>
                    <span className="font-mono">{summary.push.registry.holdout}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-[var(--color-ink-tertiary)]">Briefs sent this week</span>
                    <span className="font-mono">{summary.push.registry.briefsSentThisWeek}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-[var(--color-ink-tertiary)]">Permission denied (7d)</span>
                    <span className="font-mono">{summary.push.funnel.permissionDenied}</span>
                  </div>
                </div>
                <p className="border-t border-[var(--color-border)] px-3 py-2 text-xs text-[var(--color-tip)]">
                  {summary.push.note}
                </p>
              </div>
            </section>

            <section>
              <h2 className="mb-3 text-sm font-medium uppercase tracking-wide text-[var(--color-ink-tertiary)]">
                Recent API / upload errors · {appName(appFilter)}
                <span className="ml-2 rounded-full bg-[var(--color-tip-bg)] px-2 py-0.5 text-[var(--color-tip)] normal-case">
                  api_error · optimize_error
                </span>
              </h2>
              <div className="overflow-hidden rounded-[var(--radius-md)] border border-[var(--color-border)]">
                <table className="w-full text-left text-sm">
                  <thead>
                    <tr className="text-xs text-[var(--color-ink-tertiary)]">
                      <th className="px-3 py-2 font-medium">When</th>
                      <th className="px-3 py-2 font-medium">Status</th>
                      <th className="px-3 py-2 font-medium">Route</th>
                      <th className="px-3 py-2 font-medium">Platform</th>
                      <th className="px-3 py-2 font-medium">Message</th>
                    </tr>
                  </thead>
                  <tbody>
                    {!summary.recentErrors || summary.recentErrors.length === 0 ? (
                      <tr>
                        <td
                          colSpan={5}
                          className="px-3 py-3 text-[var(--color-ink-tertiary)]"
                        >
                          No recent errors
                          {!summary.telemetry.configured
                            ? ' (MySQL unset — errors are not persisted)'
                            : ''}
                        </td>
                      </tr>
                    ) : (
                      summary.recentErrors.map((row, i) => (
                        <tr
                          key={`${row.createdAt}-${row.route}-${i}`}
                          className="border-t border-[var(--color-border)] align-top"
                        >
                          <td className="whitespace-nowrap px-3 py-2 text-xs">
                            {fmtTime(row.createdAt)}
                          </td>
                          <td className="px-3 py-2 font-mono text-xs">
                            {row.status ?? '—'}
                            <div className="text-[var(--color-ink-tertiary)]">
                              {row.event}
                            </div>
                          </td>
                          <td className="px-3 py-2 font-mono text-xs">
                            {row.method ? `${row.method} ` : ''}
                            {row.route || '—'}
                          </td>
                          <td className="px-3 py-2 text-xs">{row.platform}</td>
                          <td className="max-w-xs px-3 py-2 text-xs text-[var(--color-ink-secondary)]">
                            {row.message || '—'}
                            {row.contentLength ? (
                              <div className="mt-0.5 text-[var(--color-ink-tertiary)]">
                                content-length {row.contentLength}
                              </div>
                            ) : null}
                          </td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
              <p className="mt-2 text-xs text-[var(--color-ink-tertiary)]">
                nginx-level 413 HTML never reaches Node — after deploy, body limits are
                100MB so normal phone JPEGs should hit JSON errors here instead.
              </p>
            </section>
          </>
        ) : null}

        {finalcap || loadingFinalcap || finalcapError ? (
          <section>
            <h2 className="mb-3 text-sm font-medium uppercase tracking-wide text-[var(--color-ink-tertiary)]">
              FinalCap usage
              <span className="ml-2 rounded-full bg-[var(--color-surface)] px-2 py-0.5 text-[var(--color-ink-tertiary)] normal-case">
                FinalCap app · its own server database — separate from the telemetry above
              </span>
              {finalcap ? (
                <span className="ml-2 rounded-full bg-[var(--color-tip-bg)] px-2 py-0.5 text-[var(--color-tip)] normal-case">
                  last {finalcap.days} days · UTC
                </span>
              ) : null}
            </h2>
            {finalcapError ? (
              <p className="rounded-[var(--radius-sm)] border border-[var(--color-danger)]/40 bg-[var(--color-danger)]/10 px-3 py-2 text-sm text-[var(--color-danger)]">
                FinalCap usage failed to load: {finalcapError}
              </p>
            ) : null}
            {!finalcap && loadingFinalcap ? (
              <div className="flex justify-center py-8 text-[var(--color-ink-tertiary)]">
                <Loader2 className="h-5 w-5 animate-spin text-[var(--color-tip)]" />
              </div>
            ) : null}
            {finalcap && !finalcap.configured ? (
              <p className="rounded-[var(--radius-sm)] border border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-2 text-sm text-[var(--color-ink-secondary)]">
                FinalCap database is not configured on this server. Set FINALCUT_MYSQL_*
                in /etc/photo-recipes.env (the FinalCap app&apos;s own MySQL credentials)
                and restart the API.
              </p>
            ) : null}
            {finalcap && finalcap.configured ? (
              <>
                <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                  <Kpi
                    label="Active users (30d)"
                    value={finalcap.totals.activeUsersInWindow}
                    hint={`${finalcap.totals.inferencesInWindow} inferences in window`}
                  />
                  <Kpi
                    label="Chat interactions (30d)"
                    value={finalcap.totals.chatInWindow}
                    hint="human + assistant + error rows"
                  />
                  <Kpi
                    label="Registered users"
                    value={finalcap.totals.registeredUsers}
                    hint="FinalCap users table, all time"
                  />
                  <Kpi
                    label="Active subscribers"
                    value={finalcap.totals.activeSubscribers}
                    hint={`Apple transactions · ${finalcap.totals.subscribersByUserFlag} by user flag`}
                  />
                </div>
                <BarHistogram
                  title="FinalCap daily active users"
                  windowLabel={`last ${finalcap.days} days`}
                  definition={finalcap.definitions.dailyActive}
                  error={finalcap.error}
                  bars={finalcapBars(finalcap.dailyUsage)}
                />
                <div className="mt-4 overflow-hidden rounded-[var(--radius-md)] border border-[var(--color-border)]">
                  <div className="border-b border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-2">
                    <div className="text-sm text-[var(--color-ink-secondary)]">
                      Chat interactions by type
                    </div>
                    <p className="mt-0.5 text-xs text-[var(--color-ink-tertiary)]">
                      {finalcap.definitions.chat}
                    </p>
                    <p className="mt-0.5 text-xs text-[var(--color-ink-tertiary)]">
                      {finalcap.definitions.subscribers}
                    </p>
                  </div>
                  <table className="w-full text-left text-sm">
                    <thead>
                      <tr className="text-xs text-[var(--color-ink-tertiary)]">
                        <th className="px-3 py-2 font-medium">Day (UTC)</th>
                        <th className="px-3 py-2 font-medium">Active users</th>
                        <th className="px-3 py-2 font-medium">Inferences</th>
                        <th className="px-3 py-2 font-medium">User msgs</th>
                        <th className="px-3 py-2 font-medium">Replies</th>
                        <th className="px-3 py-2 font-medium">Errors</th>
                      </tr>
                    </thead>
                    <tbody>
                      {[...finalcap.chatByDay].reverse().map((row, i) => {
                        const usage = finalcap.dailyUsage[finalcap.dailyUsage.length - 1 - i]
                        return (
                          <tr
                            key={row.day}
                            className="border-t border-[var(--color-border)] align-top"
                          >
                            <td className="whitespace-nowrap px-3 py-2 font-mono text-xs">{row.day}</td>
                            <td className="px-3 py-2 font-mono text-xs">{usage?.activeUsers ?? 0}</td>
                            <td className="px-3 py-2 font-mono text-xs">{usage?.inferences ?? 0}</td>
                            <td className="px-3 py-2 font-mono text-xs">{row.human2ai}</td>
                            <td className="px-3 py-2 font-mono text-xs">{row.ai2human}</td>
                            <td className="px-3 py-2 font-mono text-xs">{row.error}</td>
                          </tr>
                        )
                      })}
                    </tbody>
                  </table>
                </div>
              </>
            ) : null}
          </section>
        ) : null}

        {gbkBilling || loadingGbkBilling || gbkBillingError ? (
          <section>
            <h2 className="mb-3 text-sm font-medium uppercase tracking-wide text-[var(--color-ink-tertiary)]">
              GBK Composer — billing funnel
              <span className="ml-2 rounded-full bg-[var(--color-surface)] px-2 py-0.5 text-[var(--color-ink-tertiary)] normal-case">
                GBK server billing tables on this host (billing_daily +
                billing_log) — separate from this panel&apos;s telemetry;
                Stripe web money events land only once the checkout webhook
                hop is wired
              </span>
              {gbkBilling ? (
                <span className="ml-2 rounded-full bg-[var(--color-tip-bg)] px-2 py-0.5 text-[var(--color-tip)] normal-case">
                  trailing {gbkBilling.days} days · UTC days
                </span>
              ) : null}
            </h2>
            {gbkBillingError ? (
              <p className="rounded-[var(--radius-sm)] border border-[var(--color-danger)]/40 bg-[var(--color-danger)]/10 px-3 py-2 text-sm text-[var(--color-danger)]">
                GBK billing funnel failed to load: {gbkBillingError}
              </p>
            ) : null}
            {!gbkBilling && loadingGbkBilling ? (
              <div className="flex justify-center py-8 text-[var(--color-ink-tertiary)]">
                <Loader2 className="h-5 w-5 animate-spin text-[var(--color-tip)]" />
              </div>
            ) : null}
            {gbkBilling && !gbkBilling.available ? (
              <p className="text-sm text-[var(--color-ink-tertiary)]">
                GBK billing data not found on this host.
              </p>
            ) : null}
            {gbkBilling && gbkBilling.available ? (
              <div className="space-y-4">
                <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                  <Kpi label="Signups" value={gbkBilling.totals.signup ?? 0} />
                  <Kpi
                    label="Compositions"
                    value={gbkBilling.totals.composition_created ?? 0}
                    hint={`${gbkBilling.totals.first_composition ?? 0} first compositions`}
                  />
                  <Kpi
                    label="Paywall views"
                    value={gbkBilling.totals.paywall_view ?? 0}
                    hint={`${gbkBilling.totals.paywall_dismiss ?? 0} dismissals`}
                  />
                  <Kpi
                    label="Checkouts started"
                    value={gbkBilling.totals.checkout_start ?? 0}
                  />
                  <Kpi
                    label="Purchases"
                    value={gbkBilling.totals.purchase ?? 0}
                    hint={`${gbkBilling.totals.trial_start ?? 0} trials · ${gbkBilling.totals.renewal ?? 0} renewals · ${gbkBilling.totals.trial_convert ?? 0} trial converts`}
                  />
                  <Kpi
                    label="Cancels"
                    value={gbkBilling.totals.cancel ?? 0}
                    hint={`${gbkBilling.totals.refund ?? 0} refunds · ${gbkBilling.totals.restore ?? 0} restores`}
                  />
                  <Kpi
                    label="Exports"
                    value={gbkBilling.totals.export ?? 0}
                    hint={`${gbkBilling.totals.share_published ?? 0} shares published`}
                  />
                  <Kpi
                    label="Funnel (overall)"
                    value={`${gbkBilling.steps.overall.paywall_view} → ${gbkBilling.steps.overall.checkout_start} → ${gbkBilling.steps.overall.purchase}`}
                    hint="paywall views → checkouts → purchases"
                  />
                </div>
                {gbkBilling.steps.bySurface.length ? (
                  <div className="overflow-hidden rounded-[var(--radius-md)] border border-[var(--color-border)]">
                    <div className="border-b border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-2 text-xs uppercase tracking-wide text-[var(--color-ink-tertiary)]">
                      Funnel steps by surface / platform
                    </div>
                    <table className="w-full text-sm">
                      <thead>
                        <tr className="text-left text-xs text-[var(--color-ink-tertiary)]">
                          <th className="px-3 py-2 font-medium">Surface</th>
                          <th className="px-3 py-2 font-medium">Platform</th>
                          <th className="px-3 py-2 font-medium">Paywall views</th>
                          <th className="px-3 py-2 font-medium">Checkouts</th>
                          <th className="px-3 py-2 font-medium">Purchases</th>
                        </tr>
                      </thead>
                      <tbody>
                        {gbkBilling.steps.bySurface.map((r) => (
                          <tr
                            key={`${r.surface}/${r.platform}`}
                            className="border-t border-[var(--color-border)]"
                          >
                            <td className="px-3 py-2">{r.surface || '—'}</td>
                            <td className="px-3 py-2">{r.platform || '—'}</td>
                            <td className="px-3 py-2">{r.paywall_view}</td>
                            <td className="px-3 py-2">{r.checkout_start}</td>
                            <td className="px-3 py-2">{r.purchase}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                ) : null}
                <div className="overflow-hidden rounded-[var(--radius-md)] border border-[var(--color-border)]">
                  <div className="border-b border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-2 text-xs uppercase tracking-wide text-[var(--color-ink-tertiary)]">
                    Per day (UTC)
                  </div>
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="text-left text-xs text-[var(--color-ink-tertiary)]">
                        <th className="px-3 py-2 font-medium">Day</th>
                        <th className="px-3 py-2 font-medium">Signups</th>
                        <th className="px-3 py-2 font-medium">Compositions</th>
                        <th className="px-3 py-2 font-medium">Paywall views</th>
                        <th className="px-3 py-2 font-medium">Checkouts</th>
                        <th className="px-3 py-2 font-medium">Purchases</th>
                      </tr>
                    </thead>
                    <tbody>
                      {[...gbkBilling.byDay].reverse().map((d) => (
                        <tr
                          key={d.day}
                          className="border-t border-[var(--color-border)]"
                        >
                          <td className="px-3 py-2">{d.day}</td>
                          <td className="px-3 py-2">{d.counts.signup ?? 0}</td>
                          <td className="px-3 py-2">{d.counts.composition_created ?? 0}</td>
                          <td className="px-3 py-2">{d.counts.paywall_view ?? 0}</td>
                          <td className="px-3 py-2">{d.counts.checkout_start ?? 0}</td>
                          <td className="px-3 py-2">{d.counts.purchase ?? 0}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                {gbkBilling.recent.length ? (
                  <div className="overflow-hidden rounded-[var(--radius-md)] border border-[var(--color-border)]">
                    <div className="border-b border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-2 text-xs uppercase tracking-wide text-[var(--color-ink-tertiary)]">
                      Latest billing events (per account)
                    </div>
                    <ul className="divide-y divide-[var(--color-border)] text-sm">
                      {gbkBilling.recent.map((e, i) => (
                        <li key={`${e.ts}-${i}`} className="px-3 py-2">
                          <span className="text-[var(--color-ink-tertiary)]">
                            {new Date(e.ts).toLocaleString()}
                          </span>{' '}
                          · <span className="font-medium">{e.event}</span> ·{' '}
                          {e.account}
                          {e.plan ? ` · ${e.plan}` : ''}
                          {e.surface || e.platform
                            ? ` · ${e.surface || '—'}/${e.platform || '—'}`
                            : ''}
                          {e.detail ? (
                            <span className="text-[var(--color-ink-tertiary)]">
                              {' '}
                              · {e.detail}
                            </span>
                          ) : null}
                        </li>
                      ))}
                    </ul>
                  </div>
                ) : null}
              </div>
            ) : null}
          </section>
        ) : null}

        {finalcapFunnels || loadingFinalcapFunnels || finalcapFunnelsError ? (
          <section>
            <h2 className="mb-3 text-sm font-medium uppercase tracking-wide text-[var(--color-ink-tertiary)]">
              FinalCap funnels (app events)
              <span className="ml-2 rounded-full bg-[var(--color-surface)] px-2 py-0.5 text-[var(--color-ink-tertiary)] normal-case">
                FinalCap app · client telemetry (app = &apos;finalcap&apos;) in this
                panel&apos;s telemetry_events — separate from the FinalCap server database
                above
              </span>
              {finalcapFunnels ? (
                <span className="ml-2 rounded-full bg-[var(--color-tip-bg)] px-2 py-0.5 text-[var(--color-tip)] normal-case">
                  trailing {finalcapFunnels.days} complete days ·{' '}
                  {finalcapFunnels.windowStartDay} → {finalcapFunnels.windowEndDayExclusive}{' '}
                  (exclusive) · {finalcapFunnels.timezone}
                </span>
              ) : null}
            </h2>
            {finalcapFunnelsError ? (
              <p className="rounded-[var(--radius-sm)] border border-[var(--color-danger)]/40 bg-[var(--color-danger)]/10 px-3 py-2 text-sm text-[var(--color-danger)]">
                FinalCap funnels failed to load: {finalcapFunnelsError}
              </p>
            ) : null}
            {!finalcapFunnels && loadingFinalcapFunnels ? (
              <div className="flex justify-center py-8 text-[var(--color-ink-tertiary)]">
                <Loader2 className="h-5 w-5 animate-spin text-[var(--color-tip)]" />
              </div>
            ) : null}
            {finalcapFunnels ? (
              <div className="overflow-hidden rounded-[var(--radius-md)] border border-[var(--color-border)]">
                <div className="border-b border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-2">
                  <div className="text-sm text-[var(--color-ink-secondary)]">
                    Session funnel — distinct session_id (one per cold launch)
                  </div>
                  <p className="mt-0.5 text-xs text-[var(--color-ink-tertiary)]">
                    {finalcapFunnels.definition}
                  </p>
                  {finalcapFunnels.error ? (
                    <p className="mt-1 text-xs text-[var(--color-danger)]">
                      Query failed ({finalcapFunnels.error}) — counts below are
                      placeholders, not real zeros.
                    </p>
                  ) : finalcapFunnels.core.counts.app_open === 0 ? (
                    <p className="mt-1 text-xs text-[var(--color-ink-tertiary)]">
                      No FinalCap app events in this window yet — client telemetry arrives
                      with FinalCap v1.0.1. Counts will populate as sessions are recorded.
                    </p>
                  ) : null}
                </div>
                <div className="grid gap-3 p-3 sm:grid-cols-2 lg:grid-cols-4">
                  <Kpi
                    label="1 · App open"
                    value={finalcapFunnels.core.counts.app_open ?? 0}
                    hint="Distinct session_id"
                  />
                  <Kpi
                    label="2 · Editor open"
                    value={finalcapFunnels.core.counts.editor_open ?? 0}
                    hint={
                      pct1(finalcapFunnels.core.steps[1]?.conversionFromPrev) != null
                        ? `${pct1(finalcapFunnels.core.steps[1]?.conversionFromPrev)} of app-open sessions`
                        : 'Distinct session_id'
                    }
                  />
                  <Kpi
                    label="3 · Edit start"
                    value={finalcapFunnels.core.counts.edit_start ?? 0}
                    hint={
                      pct1(finalcapFunnels.core.steps[2]?.conversionFromPrev) != null
                        ? `${pct1(finalcapFunnels.core.steps[2]?.conversionFromPrev)} of editor sessions`
                        : 'Distinct session_id'
                    }
                  />
                  <Kpi
                    label="4 · Edit success"
                    value={finalcapFunnels.core.counts.edit_success ?? 0}
                    hint={
                      pct1(finalcapFunnels.core.steps[3]?.conversionFromPrev) != null
                        ? `${pct1(finalcapFunnels.core.steps[3]?.conversionFromPrev)} of edit-start sessions`
                        : 'Distinct session_id'
                    }
                  />
                </div>
                <div className="border-t border-[var(--color-border)] px-3 pt-3 text-xs font-medium uppercase tracking-wide text-[var(--color-ink-tertiary)]">
                  Export
                </div>
                <div className="grid gap-3 p-3 sm:grid-cols-2 lg:grid-cols-4">
                  <Kpi
                    label="Export start"
                    value={finalcapFunnels.export.counts.export_start ?? 0}
                    hint="Distinct session_id"
                  />
                  <Kpi
                    label="Export success"
                    value={finalcapFunnels.export.counts.export_success ?? 0}
                    hint={
                      pct1(finalcapFunnels.export.steps[1]?.conversionFromPrev) != null
                        ? `${pct1(finalcapFunnels.export.steps[1]?.conversionFromPrev)} of export starts`
                        : 'Distinct session_id'
                    }
                  />
                </div>
                <div className="border-t border-[var(--color-border)] px-3 pt-3 text-xs font-medium uppercase tracking-wide text-[var(--color-ink-tertiary)]">
                  Revenue
                </div>
                <div className="grid gap-3 p-3 sm:grid-cols-2 lg:grid-cols-3">
                  <Kpi
                    label="Paywall views"
                    value={finalcapFunnels.revenue.counts.paywall_view ?? 0}
                    hint="Distinct session_id"
                  />
                  <Kpi
                    label="Trial starts"
                    value={finalcapFunnels.revenue.counts.trial_start ?? 0}
                    hint={
                      pct1(finalcapFunnels.revenue.steps[1]?.conversionFromPrev) != null
                        ? `${pct1(finalcapFunnels.revenue.steps[1]?.conversionFromPrev)} of paywall views`
                        : 'Distinct session_id'
                    }
                  />
                  <Kpi
                    label="Purchase success"
                    value={finalcapFunnels.revenue.counts.purchase_success ?? 0}
                    hint={
                      pct1(finalcapFunnels.revenue.steps[2]?.conversionFromFirst) != null
                        ? `${pct1(finalcapFunnels.revenue.steps[2]?.conversionFromFirst)} of paywall views`
                        : 'Distinct session_id'
                    }
                  />
                </div>
                <p className="px-3 pb-3 text-xs text-[var(--color-ink-tertiary)]">
                  {finalcapFunnels.revenueNote}
                </p>
              </div>
            ) : null}
          </section>
        ) : null}
      </main>
    </div>
  )
}
