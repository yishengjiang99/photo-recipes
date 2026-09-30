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
  telemetry: {
    configured: boolean
    events24h: number
    events7d: number
    dau: number
    wau: number
    topEvents: Array<{ event: string; count: number }>
    platformSplit: Array<{ platform: string; count: number }>
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

export function Admin() {
  const [checking, setChecking] = useState(true)
  const [configured, setConfigured] = useState(true)
  const [authed, setAuthed] = useState(false)
  const [password, setPassword] = useState('')
  const [loginError, setLoginError] = useState('')
  const [loggingIn, setLoggingIn] = useState(false)
  const [summary, setSummary] = useState<Summary | null>(null)
  const [loadError, setLoadError] = useState('')
  const [loadingSummary, setLoadingSummary] = useState(false)
  const [draftLimit, setDraftLimit] = useState('5')
  const [draftDials, setDraftDials] = useState(true)
  const [savingQuota, setSavingQuota] = useState(false)
  const [quotaSaveMsg, setQuotaSaveMsg] = useState('')
  const [quotaSaveError, setQuotaSaveError] = useState('')

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

  const loadSummary = useCallback(async () => {
    setLoadingSummary(true)
    setLoadError('')
    try {
      const res = await fetch('/api/admin/summary', { credentials: 'include' })
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

  useEffect(() => {
    void (async () => {
      const ok = await refreshSession()
      if (ok) await loadSummary()
    })()
  }, [refreshSession, loadSummary])

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
      await loadSummary()
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
  }

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
            </p>
          </div>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => void loadSummary()}
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
              <h2 className="mb-3 text-sm font-medium uppercase tracking-wide text-[var(--color-ink-tertiary)]">
                Telemetry
                {!summary.telemetry.configured ? (
                  <span className="ml-2 rounded-full bg-[var(--color-tip-bg)] px-2 py-0.5 text-[var(--color-tip)] normal-case">
                    MySQL unset — empty snapshot
                  </span>
                ) : null}
              </h2>
              <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                <Kpi label="Events 24h" value={summary.telemetry.events24h} />
                <Kpi label="Events 7d" value={summary.telemetry.events7d} />
                <Kpi label="DAU" value={summary.telemetry.dau} hint="Distinct anon_id · 24h" />
                <Kpi label="WAU" value={summary.telemetry.wau} hint="Distinct anon_id · 7d" />
              </div>
              <div className="mt-4 grid gap-4 lg:grid-cols-2">
                <div className="overflow-hidden rounded-[var(--radius-md)] border border-[var(--color-border)]">
                  <div className="border-b border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-2 text-sm text-[var(--color-ink-secondary)]">
                    Top events (7d)
                  </div>
                  <table className="w-full text-left text-sm">
                    <thead>
                      <tr className="text-xs text-[var(--color-ink-tertiary)]">
                        <th className="px-3 py-2 font-medium">Event</th>
                        <th className="px-3 py-2 font-medium">Count</th>
                      </tr>
                    </thead>
                    <tbody>
                      {summary.telemetry.topEvents.length === 0 ? (
                        <tr>
                          <td colSpan={2} className="px-3 py-3 text-[var(--color-ink-tertiary)]">
                            No events
                          </td>
                        </tr>
                      ) : (
                        summary.telemetry.topEvents.map((row) => (
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
                    summary.stripe.configured
                      ? money(summary.stripe.approxMrrCents)
                      : '—'
                  }
                  hint={summary.stripe.note}
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
                Recent API / upload errors
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
      </main>
    </div>
  )
}
