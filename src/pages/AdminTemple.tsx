import { ArrowLeft, Loader2, Lock } from 'lucide-react'
import { useCallback, useEffect, useState } from 'react'

/**
 * Temple of the High Priestess telemetry (/admin/temple).
 * Presentation only — all aggregation happens server-side in
 * server/templeUsage.ts behind requireAdmin, reading the Temple game's own
 * `temple` MySQL database (see server/templeMysql.ts). Temple never sends
 * client events to this app's shared telemetry_events table, so these numbers
 * must not be mixed with the Photo-Recipes / FinalCap figures on /admin or
 * /admin/analytics.
 *
 * Read-only aggregates only: no player identifiers, install ids, secrets,
 * tokens, or signed transactions ever reach this page. Purchases are split
 * by VERIFIED environment (entitlements.environment): Production rows are
 * revenue, Sandbox rows are test purchases and are never counted as revenue.
 * Charts are inline SVG (no chart library in this repo).
 */

type TempleTelemetry = {
  configured: boolean
  days: number
  timezone: string
  generatedAt: string
  definitions: Record<string, string>
  totals: {
    installs: number
    players: number
    eventsAllTime: number
    eventsInWindow: number
    sessionsInWindow: number
    dauInWindow: number
    purchasesProduction: number
    purchasesSandbox: number
    revenueUsd: number
    sandboxRevenueUsd: number
    cloudSavePlayers: number
    cloudSaveSlots: number
  }
  installsByDay: Array<{ day: string; installs: number }>
  installsByVersion: Array<{ version: string; devices: number }>
  dauByDay: Array<{ day: string; sessions: number; dau: number }>
  eventsByDay: Array<{ day: string; total: number }>
  eventsByName: Array<{ name: string; count: number }>
  funnel: Array<{ name: string; events: number; players: number; conversionFromPrev: number | null }>
  purchases: Array<{ product: string; environment: string; count: number; revoked: number; revenueUsd: number }>
  perf: {
    samples: number
    medianFps: number | null
    medianMedMs: number | null
    medianP95Ms: number | null
    byMap: Array<{ map: string; samples: number; medianFps: number | null; medianMedMs: number | null; medianP95Ms: number | null }>
  }
  diagnostics: Array<{ kind: string; count: number }>
  errorsByDay: Array<{ day: string; count: number }>
  errorKinds: Array<{ kind: string; count: number }>
  recentEvents: Array<{ createdAt: string; name: string; appVersion: string | null; props: string | null }>
  error?: string
}

type Envelope = { ok: boolean; temple: TempleTelemetry }

const fmtNum = (v: number | null | undefined): string =>
  v === null || v === undefined ? '—' : Intl.NumberFormat('en-US').format(v)
const fmtUsd = (v: number | null | undefined): string =>
  v === null || v === undefined
    ? '—'
    : `$${v.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
const fmtPct = (v: number | null | undefined): string =>
  v === null || v === undefined ? '—' : `${(v * 100).toFixed(1)}%`
const fmtOne = (v: number | null | undefined): string =>
  v === null || v === undefined ? '—' : v.toFixed(1)

function Section({ title, children, note }: { title: string; children: React.ReactNode; note?: string }) {
  return (
    <section className="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface)] p-4">
      <h2 className="font-display text-lg text-[var(--color-ink)]">{title}</h2>
      {note ? <p className="mt-0.5 text-xs text-[var(--color-ink-tertiary)]">{note}</p> : null}
      <div className="mt-3">{children}</div>
    </section>
  )
}

function Kpi({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface)] p-4">
      <p className="text-xs text-[var(--color-ink-tertiary)]">{label}</p>
      <p className="mt-1 font-display text-2xl text-[var(--color-ink)]">{value}</p>
      {sub ? <p className="mt-0.5 text-xs text-[var(--color-ink-secondary)]">{sub}</p> : null}
    </div>
  )
}

function BarChart({ data, label }: { data: Array<{ label: string; value: number }>; label: string }) {
  const max = Math.max(...data.map((d) => d.value), 1)
  const w = 520
  const h = 120
  return (
    <div>
      <svg viewBox={`0 0 ${w} ${h}`} className="w-full" role="img" aria-label={label}>
        <title>{label}</title>
        {data.map((d, i) => {
          const bw = w / Math.max(data.length, 1)
          const bh = Math.max(2, (d.value / max) * 96)
          return (
            <g key={d.label}>
              <rect x={i * bw + 2} y={104 - bh} width={Math.max(2, bw - 4)} height={bh} fill="var(--color-tip)" opacity={d.value === 0 ? 0.15 : 0.85}>
                <title>{`${d.label}: ${d.value}`}</title>
              </rect>
              {data.length <= 31 ? (
                <text x={i * bw + bw / 2} y={116} textAnchor="middle" fontSize="8" fill="var(--color-ink-tertiary)">
                  {d.label.slice(5)}
                </text>
              ) : null}
            </g>
          )
        })}
      </svg>
      <p className="sr-only">{data.map((d) => `${d.label}: ${d.value}`).join('; ')}</p>
    </div>
  )
}

function SimpleTable({ head, rows }: { head: string[]; rows: Array<Array<React.ReactNode>> }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="text-left text-xs text-[var(--color-ink-tertiary)]">
            {head.map((h) => (
              <th key={h} className="border-b border-[var(--color-border)] px-2 py-1.5 font-medium">
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((r, i) => (
            <tr key={i} className="border-b border-[var(--color-border)]/50 last:border-0">
              {r.map((c, j) => (
                <td key={j} className="px-2 py-1.5 text-[var(--color-ink)]">
                  {c}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

export function AdminTemple() {
  const [checking, setChecking] = useState(true)
  const [authed, setAuthed] = useState(false)
  const [days, setDays] = useState<7 | 30 | 90>(30)
  const [data, setData] = useState<TempleTelemetry | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    void (async () => {
      try {
        const res = await fetch('/api/admin/session', { credentials: 'include' })
        const j = (await res.json()) as { authenticated?: boolean }
        setAuthed(Boolean(j.authenticated))
      } catch {
        setAuthed(false)
      } finally {
        setChecking(false)
      }
    })()
  }, [])

  const load = useCallback(async () => {
    if (!authed) return
    setLoading(true)
    setError('')
    try {
      const res = await fetch(`/api/admin/temple?days=${days}`, { credentials: 'include' })
      if (res.status === 401) {
        setAuthed(false)
        setData(null)
        setError('Session expired — sign in again from the admin page.')
        return
      }
      const j = (await res.json()) as Envelope & { error?: string }
      if (!res.ok) {
        setError(j.error || `Failed (${res.status})`)
        setData(null)
        return
      }
      setData(j.temple)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load Temple telemetry')
      setData(null)
    } finally {
      setLoading(false)
    }
  }, [authed, days])

  useEffect(() => {
    void load()
  }, [load])

  if (checking) {
    return (
      <div className="flex min-h-dvh items-center justify-center bg-[var(--color-bg)]">
        <Loader2 className="h-6 w-6 animate-spin text-[var(--color-tip)]" />
      </div>
    )
  }

  if (!authed) {
    return (
      <div className="flex min-h-dvh items-center justify-center bg-[var(--color-bg)] px-4">
        <div className="w-full max-w-sm rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface)] p-6">
          <div className="mb-3 flex items-center gap-2 text-[var(--color-tip)]">
            <Lock className="h-5 w-5" />
            <h1 className="font-display text-2xl text-[var(--color-ink)]">Temple telemetry</h1>
          </div>
          <p className="text-sm text-[var(--color-ink-secondary)]">
            This panel is admin-only and enforced server-side. Sign in on the admin page first — this page never
            receives Temple data without a valid admin session.
          </p>
          <a href="/admin" className="mt-4 inline-block rounded-[var(--radius-pill)] bg-[var(--color-tip)] px-4 py-2 font-medium text-black">
            Go to admin sign-in
          </a>
        </div>
      </div>
    )
  }

  const t = data
  const funnelTotal = t?.funnel.find((s) => s.name === 'purchase')?.events ?? 0

  return (
    <div className="min-h-dvh bg-[var(--color-bg)] text-[var(--color-ink)]">
      <header className="border-b border-[var(--color-border)] bg-[var(--color-bg-elevated)]">
        <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-3 px-4 py-4">
          <div>
            <a href="/admin" className="inline-flex items-center gap-1 text-xs text-[var(--color-ink-tertiary)]">
              <ArrowLeft className="h-3.5 w-3.5" /> Safelight admin
            </a>
            <h1 className="font-display text-2xl text-[var(--color-tip)]">Temple telemetry</h1>
            <p className="text-xs text-[var(--color-ink-tertiary)]">
              Temple of the High Priestess — its own database, not the shared telemetry table · days are UTC
              {t ? ` · generated ${new Date(t.generatedAt).toLocaleString()}` : ''}
            </p>
          </div>
          <label className="text-sm text-[var(--color-ink-secondary)]">
            Window
            <select
              value={days}
              onChange={(e) => setDays(Number(e.target.value) as 7 | 30 | 90)}
              className="ml-2 rounded-[var(--radius-sm)] border border-[var(--color-border)] bg-[var(--color-surface)] px-2 py-1.5 text-[var(--color-ink)]"
            >
              <option value={7}>Last 7 days</option>
              <option value={30}>Last 30 days</option>
              <option value={90}>Last 90 days</option>
            </select>
          </label>
        </div>
      </header>

      <main className="mx-auto max-w-6xl space-y-6 px-4 py-6">
        {error ? (
          <p className="rounded-[var(--radius-sm)] border border-[var(--color-danger)]/40 bg-[var(--color-danger)]/10 px-3 py-2 text-sm text-[var(--color-danger)]">
            {error}
          </p>
        ) : null}
        {t && !t.configured ? (
          <p className="rounded-[var(--radius-sm)] border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-sm text-amber-600 dark:text-amber-400">
            <strong>Temple database not configured.</strong> Set TEMPLE_MYSQL_URL (or TEMPLE_MYSQL_HOST + TEMPLE_MYSQL_DATABASE)
            in the server environment and restart — the page shows zeros until then.
          </p>
        ) : null}
        {t?.error ? (
          <p className="rounded-[var(--radius-sm)] border border-[var(--color-danger)]/40 bg-[var(--color-danger)]/10 px-3 py-2 text-sm text-[var(--color-danger)]">
            Temple query failed — showing zeros. Check the server logs.
          </p>
        ) : null}
        {loading && !t ? (
          <p className="flex items-center gap-2 text-sm text-[var(--color-ink-secondary)]">
            <Loader2 className="h-4 w-4 animate-spin" /> Loading Temple telemetry…
          </p>
        ) : null}

        {t ? (
          <>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
              <Kpi label="Installs (all time)" value={fmtNum(t.totals.installs)} sub={`${fmtNum(t.totals.players)} players`} />
              <Kpi label={`Sessions (last ${t.days}d)`} value={fmtNum(t.totals.sessionsInWindow)} sub={`${fmtNum(t.totals.dauInWindow)} distinct players`} />
              <Kpi label={`Events (last ${t.days}d)`} value={fmtNum(t.totals.eventsInWindow)} sub={`${fmtNum(t.totals.eventsAllTime)} all time`} />
              <Kpi label="Production purchases" value={fmtNum(t.totals.purchasesProduction)} sub="verified, non-revoked" />
              <Kpi label="Revenue (verified, USD)" value={fmtUsd(t.totals.revenueUsd)} sub="Production only" />
              <Kpi label="Sandbox test purchases" value={fmtNum(t.totals.purchasesSandbox)} sub={`${fmtUsd(t.totals.sandboxRevenueUsd)} — not revenue`} />
              <Kpi label="Cloud saves" value={fmtNum(t.totals.cloudSaveSlots)} sub={`${fmtNum(t.totals.cloudSavePlayers)} players`} />
              <Kpi label="Funnel purchases" value={fmtNum(funnelTotal)} sub="production-only funnel" />
            </div>

            <Section title="Paywall funnel (production-only)" note={t.definitions.funnel}>
              <SimpleTable
                head={['Step', 'Events', 'Players', 'Conversion from previous']}
                rows={t.funnel.map((s) => [s.name, fmtNum(s.events), fmtNum(s.players), fmtPct(s.conversionFromPrev)])}
              />
            </Section>

            <Section title="Installs by day" note={t.definitions.installs}>
              <BarChart data={t.installsByDay.map((d) => ({ label: d.day, value: d.installs }))} label="Installs by day" />
              <div className="mt-3">
                <h3 className="mb-1 text-sm font-medium text-[var(--color-ink-secondary)]">By build version</h3>
                <SimpleTable
                  head={['Version', 'Devices']}
                  rows={t.installsByVersion.map((v) => [v.version, fmtNum(v.devices)])}
                />
              </div>
            </Section>

            <Section title="Sessions & daily active users" note={t.definitions.sessions}>
              <BarChart data={t.dauByDay.map((d) => ({ label: d.day, value: d.dau }))} label="Daily active users" />
              <div className="mt-3">
                <SimpleTable
                  head={['Day', 'Sessions', 'DAU']}
                  rows={t.dauByDay.map((d) => [d.day, fmtNum(d.sessions), fmtNum(d.dau)])}
                />
              </div>
            </Section>

            <Section title="Events" note="Events in the window, by day and by name.">
              <BarChart data={t.eventsByDay.map((d) => ({ label: d.day, value: d.total }))} label="Events by day" />
              <div className="mt-3">
                <SimpleTable
                  head={['Event', 'Count']}
                  rows={t.eventsByName.map((e) => [e.name, fmtNum(e.count)])}
                />
              </div>
            </Section>

            <Section title="Purchases by verified environment" note={t.definitions.purchases}>
              {t.purchases.length === 0 ? (
                <p className="text-sm text-[var(--color-ink-secondary)]">No verified purchases yet.</p>
              ) : (
                <SimpleTable
                  head={['Product', 'Environment', 'Count', 'Revoked', 'Revenue (USD)']}
                  rows={t.purchases.map((p) => [
                    p.product,
                    p.environment,
                    fmtNum(p.count),
                    fmtNum(p.revoked),
                    p.environment === 'Production' ? fmtUsd(p.revenueUsd) : '— (test)',
                  ])}
                />
              )}
            </Section>

            <Section title="Performance (perf_sample)" note={t.definitions.perf}>
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
                <Kpi label="Samples" value={fmtNum(t.perf.samples)} />
                <Kpi label="Median fps" value={fmtOne(t.perf.medianFps)} />
                <Kpi label="Median frame time" value={t.perf.medianMedMs === null ? '—' : `${fmtOne(t.perf.medianMedMs)} ms`} />
                <Kpi label="Median p95 frame time" value={t.perf.medianP95Ms === null ? '—' : `${fmtOne(t.perf.medianP95Ms)} ms`} />
              </div>
              {t.perf.byMap.length > 0 ? (
                <div className="mt-3">
                  <SimpleTable
                    head={['Map', 'Samples', 'Median fps', 'Median frame time', 'Median p95']}
                    rows={t.perf.byMap.map((m) => [
                      m.map,
                      fmtNum(m.samples),
                      fmtOne(m.medianFps),
                      m.medianMedMs === null ? '—' : `${fmtOne(m.medianMedMs)} ms`,
                      m.medianP95Ms === null ? '—' : `${fmtOne(m.medianP95Ms)} ms`,
                    ])}
                  />
                </div>
              ) : null}
            </Section>

            <Section title="Diagnostics & errors" note={t.definitions.diagnostics}>
              <div className="grid gap-4 sm:grid-cols-2">
                <div>
                  <h3 className="mb-1 text-sm font-medium text-[var(--color-ink-secondary)]">MetricKit diagnostics by kind</h3>
                  {t.diagnostics.length === 0 ? (
                    <p className="text-sm text-[var(--color-ink-secondary)]">None in window.</p>
                  ) : (
                    <SimpleTable head={['Kind', 'Count']} rows={t.diagnostics.map((d) => [d.kind, fmtNum(d.count)])} />
                  )}
                </div>
                <div>
                  <h3 className="mb-1 text-sm font-medium text-[var(--color-ink-secondary)]">Errors by kind</h3>
                  {t.errorKinds.length === 0 ? (
                    <p className="text-sm text-[var(--color-ink-secondary)]">None in window.</p>
                  ) : (
                    <SimpleTable head={['Kind', 'Count']} rows={t.errorKinds.map((d) => [d.kind, fmtNum(d.count)])} />
                  )}
                </div>
              </div>
              {t.errorsByDay.some((d) => d.count > 0) ? (
                <div className="mt-3">
                  <h3 className="mb-1 text-sm font-medium text-[var(--color-ink-secondary)]">Errors by day</h3>
                  <SimpleTable
                    head={['Day', 'Errors']}
                    rows={t.errorsByDay.filter((d) => d.count > 0).map((d) => [d.day, fmtNum(d.count)])}
                  />
                </div>
              ) : null}
            </Section>

            <Section title="Recent events" note="Latest 20 events. Aggregates only — no player identifiers, install ids, secrets, or tokens.">
              {t.recentEvents.length === 0 ? (
                <p className="text-sm text-[var(--color-ink-secondary)]">No events yet.</p>
              ) : (
                <SimpleTable
                  head={['Time (UTC)', 'Event', 'Version', 'Props']}
                  rows={t.recentEvents.map((e) => [
                    e.createdAt ? new Date(e.createdAt).toISOString().replace('T', ' ').slice(0, 19) : '—',
                    e.name,
                    e.appVersion ?? '—',
                    <code key="p" className="break-all text-xs text-[var(--color-ink-secondary)]">
                      {e.props ?? '—'}
                    </code>,
                  ])}
                />
              )}
            </Section>

            <details className="text-xs text-[var(--color-ink-tertiary)]">
              <summary className="cursor-pointer">How these numbers are defined</summary>
              <ul className="mt-2 list-disc space-y-1 pl-5">
                {Object.entries(t.definitions).map(([k, v]) => (
                  <li key={k}>
                    <strong>{k}:</strong> {v}
                  </li>
                ))}
              </ul>
            </details>
          </>
        ) : null}
      </main>
    </div>
  )
}
