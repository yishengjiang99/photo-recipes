import { AlertTriangle, ArrowLeft, Download, Loader2, Lock } from 'lucide-react'
import { useCallback, useEffect, useMemo, useState } from 'react'

/**
 * Admin analytics & experiment monitoring panel (/admin/analytics).
 * Presentation only — all aggregation happens server-side in
 * server/adminAnalytics.ts behind requireAdmin. See docs/admin-analytics.md.
 * Charts are inline SVG (no chart library in this repo).
 */

type Kpi = {
  value: number | null
  previous: number | null
  delta: number | null
  deltaRel: number | null
  numerator: number | null
  denominator: number | null
  n: number
  unit: string
  instrumented: boolean
  note?: string
}

type Envelope = {
  ok: boolean
  period: { start: string; end: string }
  previousPeriod: { start: string; end: string }
  timezone: string
  displayTimezone: string
  data_freshness: string | null
  generatedAt: string
  partial: boolean
  warnings: string[]
  sample_sizes: Record<string, number>
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  metrics: Record<string, any>
}

type TabId = 'overview' | 'activation' | 'capture' | 'paywall' | 'reconciliation' | 'optimize'
const TABS: Array<{ id: TabId; label: string; endpoint: string; exportView: string }> = [
  { id: 'overview', label: 'Overview', endpoint: 'overview', exportView: 'overview' },
  { id: 'activation', label: 'Activation experiment', endpoint: 'activation', exportView: 'activation' },
  { id: 'capture', label: 'Capture-ready', endpoint: 'capture', exportView: 'capture' },
  { id: 'paywall', label: 'Paywall & revenue', endpoint: 'paywall', exportView: 'paywall' },
  { id: 'reconciliation', label: 'Purchase reconciliation', endpoint: 'reconciliation', exportView: 'reconciliation' },
  { id: 'optimize', label: 'Optimize performance', endpoint: 'optimize-performance', exportView: 'optimize-performance' },
]

const fmtPct = (v: number | null | undefined): string =>
  v === null || v === undefined ? '—' : `${(v * 100).toFixed(1)}%`
const fmtNum = (v: number | null | undefined): string =>
  v === null || v === undefined ? '—' : Intl.NumberFormat('en-US').format(v)
const fmtMs = (v: number | null | undefined): string =>
  v === null || v === undefined ? '—' : `${Intl.NumberFormat('en-US').format(Math.round(v))} ms`
const fmtDelta = (k: Kpi, pct: boolean): string => {
  if (k.delta === null) return 'no previous-period value'
  const d = pct ? `${k.delta >= 0 ? '+' : ''}${(k.delta * 100).toFixed(1)} pp` : `${k.delta >= 0 ? '+' : ''}${fmtNum(k.delta)}`
  return `${d} vs previous period`
}

// --- Accessible inline-SVG charts -------------------------------------------

function Sparkline({ values, label }: { values: Array<number | null>; label: string }) {
  const pts = values.filter((v): v is number => v !== null)
  if (pts.length < 2) return <p className="text-xs text-[var(--color-ink-tertiary)]">Not enough points for a trend.</p>
  const max = Math.max(...pts, 1)
  const w = 260
  const h = 56
  const coords = values
    .map((v, i) => (v === null ? null : `${((i / (values.length - 1)) * w).toFixed(1)},${(h - 4 - (v / max) * (h - 10)).toFixed(1)}`))
    .filter(Boolean)
    .join(' ')
  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="h-14 w-full" role="img" aria-label={label}>
      <title>{label}</title>
      <polyline points={coords} fill="none" stroke="var(--color-tip)" strokeWidth="2" />
    </svg>
  )
}

function BarChart({ data, label, format }: { data: Array<{ label: string; value: number | null }>; label: string; format: (v: number | null) => string }) {
  const max = Math.max(...data.map((d) => d.value ?? 0), 1)
  return (
    <div>
      <svg viewBox="0 0 520 120" className="w-full" role="img" aria-label={label}>
        <title>{label}</title>
        {data.map((d, i) => {
          const bw = 520 / Math.max(data.length, 1)
          const bh = d.value === null ? 0 : Math.max(2, (d.value / max) * 96)
          return (
            <g key={d.label}>
              <rect x={i * bw + 2} y={104 - bh} width={Math.max(2, bw - 4)} height={bh} fill="var(--color-tip)" opacity={d.value === null ? 0.15 : 0.85}>
                <title>{`${d.label}: ${format(d.value)}`}</title>
              </rect>
              <text x={i * bw + bw / 2} y={116} textAnchor="middle" fontSize="8" fill="var(--color-ink-tertiary)">
                {d.label.slice(5)}
              </text>
            </g>
          )
        })}
      </svg>
      <p className="sr-only">{data.map((d) => `${d.label}: ${format(d.value)}`).join('; ')}</p>
    </div>
  )
}

// --- Small building blocks ----------------------------------------------------

function NotInstrumented({ note }: { note?: string }) {
  return (
    <p className="rounded-[var(--radius-sm)] border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-sm text-amber-600 dark:text-amber-400">
      <strong>Not instrumented.</strong> {note ?? 'The events behind this metric do not exist in this period — this is missing data, not a zero.'}
    </p>
  )
}

function KpiCard({
  title,
  kpi,
  format,
  onDrill,
  children,
}: {
  title: string
  kpi: Kpi
  format: (v: number | null) => string
  onDrill?: () => void
  children?: React.ReactNode
}) {
  return (
    <section className="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface)] p-4" aria-label={title}>
      <h3 className="text-sm font-medium text-[var(--color-ink-secondary)]">{title}</h3>
      {!kpi.instrumented ? (
        <div className="mt-2">
          <NotInstrumented note={kpi.note} />
        </div>
      ) : (
        <>
          <p className="mt-1 font-display text-3xl text-[var(--color-ink)]">{format(kpi.value)}</p>
          <p className="text-xs text-[var(--color-ink-tertiary)]">{fmtDelta(kpi, kpi.value !== null && kpi.value <= 1 && kpi.denominator !== null)}</p>
          <p className="mt-1 text-xs text-[var(--color-ink-tertiary)]">
            {kpi.numerator !== null && kpi.denominator !== null ? `${fmtNum(kpi.numerator)} / ${fmtNum(kpi.denominator)} · ` : ''}n = {fmtNum(kpi.n)} · {kpi.unit}
          </p>
          {kpi.note ? <p className="mt-1 text-xs text-[var(--color-ink-tertiary)]">{kpi.note}</p> : null}
        </>
      )}
      {children}
      {onDrill ? (
        <button type="button" onClick={onDrill} className="mt-2 text-sm font-medium text-[var(--color-tip)] underline">
          Detailed analysis →
        </button>
      ) : null}
    </section>
  )
}

function FunnelTable({ stages }: { stages: Array<{ stage: string; count: number | null; conversionFromPrev?: number | null }> }) {
  const max = Math.max(...stages.map((s) => s.count ?? 0), 1)
  return (
    <table className="w-full text-sm">
      <thead>
        <tr className="text-left text-[var(--color-ink-tertiary)]">
          <th className="py-1 pr-2 font-medium">Stage</th>
          <th className="py-1 pr-2 font-medium">Count</th>
          <th className="py-1 pr-2 font-medium">From previous</th>
          <th className="py-1 font-medium">Share of first stage</th>
        </tr>
      </thead>
      <tbody>
        {stages.map((s) => (
          <tr key={s.stage} className="border-t border-[var(--color-border)]">
            <td className="py-1.5 pr-2">{s.stage}</td>
            <td className="py-1.5 pr-2">{s.count === null ? 'n/a' : fmtNum(s.count)}</td>
            <td className="py-1.5 pr-2">{s.conversionFromPrev === null || s.conversionFromPrev === undefined ? '—' : fmtPct(s.conversionFromPrev)}</td>
            <td className="py-1.5">
              <div className="h-2.5 w-full max-w-[220px] rounded bg-[var(--color-bg)]" role="img" aria-label={`${s.stage}: ${s.count === null ? 'not applicable' : fmtNum(s.count)}`}>
                <div className="h-2.5 rounded bg-[var(--color-tip)]" style={{ width: `${s.count === null ? 0 : (s.count / max) * 100}%` }} />
              </div>
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}

function BreakdownTable({ title, rows }: { title: string; rows: Array<Record<string, unknown>> }) {
  if (!rows.length) return null
  const cols = Object.keys(rows[0]!)
  return (
    <div>
      <h4 className="mb-1 text-sm font-medium text-[var(--color-ink-secondary)]">{title}</h4>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-[var(--color-ink-tertiary)]">
              {cols.map((c) => (
                <th key={c} className="py-1 pr-3 font-medium">{c}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((r, i) => (
              <tr key={i} className="border-t border-[var(--color-border)]">
                {cols.map((c) => (
                  <td key={c} className="py-1 pr-3">
                    {r[c] === null || r[c] === undefined
                      ? <span title="Suppressed: fewer than 5 distinct users">suppressed (&lt;5 users)</span>
                      : typeof r[c] === 'number' && (c.toLowerCase().includes('rate') || c.toLowerCase().includes('conversion'))
                        ? fmtPct(r[c] as number)
                        : String(r[c])}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}

// --- Main page ------------------------------------------------------------------

export function AdminAnalytics() {
  const [checking, setChecking] = useState(true)
  const [authed, setAuthed] = useState(false)
  const [tab, setTab] = useState<TabId>('overview')
  const [range, setRange] = useState<'24h' | '7d' | '30d' | 'custom'>('7d')
  const [customStart, setCustomStart] = useState('')
  const [customEnd, setCustomEnd] = useState('')
  const [appVersion, setAppVersion] = useState('')
  const [arm, setArm] = useState('')
  const [lens, setLens] = useState('')
  const [compare, setCompare] = useState(true)
  const [data, setData] = useState<Envelope | null>(null)
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

  const queryString = useMemo(() => {
    const p = new URLSearchParams()
    if (range === 'custom' && customStart && customEnd) {
      p.set('start', new Date(customStart).toISOString())
      p.set('end', new Date(customEnd).toISOString())
    } else {
      p.set('range', range === 'custom' ? '7d' : range)
    }
    if (appVersion.trim()) p.set('app_version', appVersion.trim())
    if (arm) p.set('arm', arm)
    if (lens) p.set('lens', lens)
    if (!compare) p.set('compare', 'false')
    return p.toString()
  }, [range, customStart, customEnd, appVersion, arm, lens, compare])

  const load = useCallback(async () => {
    if (!authed) return
    const t = TABS.find((x) => x.id === tab)!
    setLoading(true)
    setError('')
    try {
      const res = await fetch(`/api/admin/analytics/${t.endpoint}?${queryString}`, { credentials: 'include' })
      if (res.status === 401) {
        setAuthed(false)
        setData(null)
        setError('Session expired — sign in again from the admin page.')
        return
      }
      const j = (await res.json()) as Envelope & { error?: string; hint?: string }
      if (!res.ok) {
        setError(j.hint ? `${j.error}: ${j.hint}` : j.error || `Failed (${res.status})`)
        setData(null)
        return
      }
      setData(j)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load analytics')
      setData(null)
    } finally {
      setLoading(false)
    }
  }, [authed, tab, queryString])

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
            <h1 className="font-display text-2xl text-[var(--color-ink)]">Analytics &amp; experiments</h1>
          </div>
          <p className="text-sm text-[var(--color-ink-secondary)]">
            This panel is admin-only and enforced server-side. Sign in on the admin page first — this page never
            receives analytics data without a valid admin session.
          </p>
          <a href="/admin" className="mt-4 inline-block rounded-[var(--radius-pill)] bg-[var(--color-tip)] px-4 py-2 font-medium text-black">
            Go to admin sign-in
          </a>
        </div>
      </div>
    )
  }

  const m = data?.metrics ?? {}
  const noData = data !== null && (data.sample_sizes.rows ?? 0) === 0
  const exportHref = `/api/admin/analytics/export?view=${TABS.find((x) => x.id === tab)!.exportView}&format=csv&${queryString}`

  return (
    <div className="min-h-dvh bg-[var(--color-bg)] text-[var(--color-ink)]">
      <header className="border-b border-[var(--color-border)] bg-[var(--color-bg-elevated)]">
        <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-3 px-4 py-4">
          <div>
            <a href="/admin" className="inline-flex items-center gap-1 text-xs text-[var(--color-ink-tertiary)]">
              <ArrowLeft className="h-3.5 w-3.5" /> Safelight admin
            </a>
            <h1 className="font-display text-2xl text-[var(--color-tip)]">Analytics &amp; experiments</h1>
            <p className="text-xs text-[var(--color-ink-tertiary)]">
              Photo-Recipes (app=photo-recipes) · storage UTC · display {data?.displayTimezone ?? 'America/Los_Angeles'} for daily buckets
              {data?.data_freshness ? ` · data fresh as of ${new Date(data.data_freshness).toLocaleString()}` : ''}
            </p>
          </div>
          <a href={exportHref} className="inline-flex items-center gap-2 rounded-[var(--radius-pill)] border border-[var(--color-border)] px-4 py-2 text-sm font-medium">
            <Download className="h-4 w-4" /> Export this view (CSV, aggregates only)
          </a>
        </div>
      </header>

      <div className="mx-auto max-w-6xl px-4 py-4">
        {/* Global controls */}
        <form className="flex flex-wrap items-end gap-3" aria-label="Global analytics filters" onSubmit={(e) => e.preventDefault()}>
          <label className="text-sm text-[var(--color-ink-secondary)]">
            Range
            <select value={range} onChange={(e) => setRange(e.target.value as typeof range)} className="mt-1 block rounded-[var(--radius-sm)] border border-[var(--color-border)] bg-[var(--color-surface)] px-2 py-1.5 text-[var(--color-ink)]">
              <option value="24h">Last 24 hours</option>
              <option value="7d">Last 7 days</option>
              <option value="30d">Last 30 days</option>
              <option value="custom">Custom</option>
            </select>
          </label>
          {range === 'custom' ? (
            <>
              <label className="text-sm text-[var(--color-ink-secondary)]">
                Start
                <input type="datetime-local" value={customStart} onChange={(e) => setCustomStart(e.target.value)} className="mt-1 block rounded-[var(--radius-sm)] border border-[var(--color-border)] bg-[var(--color-surface)] px-2 py-1.5 text-[var(--color-ink)]" />
              </label>
              <label className="text-sm text-[var(--color-ink-secondary)]">
                End
                <input type="datetime-local" value={customEnd} onChange={(e) => setCustomEnd(e.target.value)} className="mt-1 block rounded-[var(--radius-sm)] border border-[var(--color-border)] bg-[var(--color-surface)] px-2 py-1.5 text-[var(--color-ink)]" />
              </label>
            </>
          ) : null}
          <label className="text-sm text-[var(--color-ink-secondary)]">
            App version
            <input value={appVersion} onChange={(e) => setAppVersion(e.target.value)} placeholder="e.g. 1.5" className="mt-1 block w-24 rounded-[var(--radius-sm)] border border-[var(--color-border)] bg-[var(--color-surface)] px-2 py-1.5 text-[var(--color-ink)]" />
          </label>
          <label className="text-sm text-[var(--color-ink-secondary)]">
            Experiment arm
            <select value={arm} onChange={(e) => setArm(e.target.value)} className="mt-1 block rounded-[var(--radius-sm)] border border-[var(--color-border)] bg-[var(--color-surface)] px-2 py-1.5 text-[var(--color-ink)]">
              <option value="">All arms</option>
              <option value="post_capture_v1">post_capture_v1 (control)</option>
              <option value="pre_capture_guided_v1">pre_capture_guided_v1 (treatment)</option>
              <option value="paywall_control_v1">paywall_control_v1</option>
              <option value="paywall_value_v1">paywall_value_v1</option>
            </select>
          </label>
          <label className="text-sm text-[var(--color-ink-secondary)]">
            Lens
            <select value={lens} onChange={(e) => setLens(e.target.value)} className="mt-1 block rounded-[var(--radius-sm)] border border-[var(--color-border)] bg-[var(--color-surface)] px-2 py-1.5 text-[var(--color-ink)]">
              <option value="">All lenses</option>
              <option value="front">Front</option>
              <option value="rear">Rear</option>
            </select>
          </label>
          <label className="flex items-center gap-2 pb-2 text-sm text-[var(--color-ink-secondary)]">
            <input type="checkbox" checked={compare} onChange={(e) => setCompare(e.target.checked)} />
            Compare to previous period
          </label>
        </form>

        {/* Tabs */}
        <nav className="mt-4 flex flex-wrap gap-2" aria-label="Analytics views">
          {TABS.map((t) => (
            <button
              key={t.id}
              type="button"
              onClick={() => setTab(t.id)}
              aria-current={tab === t.id ? 'page' : undefined}
              className={`rounded-[var(--radius-pill)] px-3.5 py-1.5 text-sm font-medium ${tab === t.id ? 'bg-[var(--color-tip)] text-black' : 'border border-[var(--color-border)] text-[var(--color-ink-secondary)]'}`}
            >
              {t.label}
            </button>
          ))}
        </nav>

        {/* States */}
        {loading ? (
          <p className="mt-8 flex items-center gap-2 text-[var(--color-ink-secondary)]" role="status">
            <Loader2 className="h-5 w-5 animate-spin" /> Loading analytics…
          </p>
        ) : null}
        {error ? (
          <p className="mt-6 rounded-[var(--radius-sm)] border border-[var(--color-danger)]/40 bg-[var(--color-danger)]/10 px-3 py-2 text-sm text-[var(--color-danger)]" role="alert">
            {error}
          </p>
        ) : null}
        {data?.partial ? (
          <p className="mt-4 flex items-center gap-2 rounded-[var(--radius-sm)] border border-orange-500/40 bg-orange-500/10 px-3 py-2 text-sm text-orange-600 dark:text-orange-400" role="status">
            <AlertTriangle className="h-4 w-4" /> Partial data — the row cap was reached for this window; metrics cover the earliest rows only.
          </p>
        ) : null}
        {data?.warnings?.length ? (
          <ul className="mt-3 list-inside list-disc text-xs text-[var(--color-ink-tertiary)]" aria-label="Data warnings">
            {data.warnings.map((w) => (
              <li key={w}>{w}</li>
            ))}
          </ul>
        ) : null}
        {noData && !loading ? (
          <p className="mt-6 rounded-[var(--radius-sm)] border border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-3 text-sm text-[var(--color-ink-secondary)]" role="status">
            No telemetry rows for app=photo-recipes in this period. Views below show their explicit empty /
            not-instrumented states — nothing here is a measured zero.
          </p>
        ) : null}

        {/* Views */}
        {data && !loading ? (
          <main className="mt-5">
            {tab === 'overview' && m.overview ? <OverviewView m={m} go={setTab} compare={compare} /> : null}
            {tab === 'activation' && m.activation ? <ActivationView a={m.activation} /> : null}
            {tab === 'capture' && m.capture ? <CaptureView c={m.capture} /> : null}
            {tab === 'paywall' && m.paywall ? <PaywallView p={m.paywall} revenue={m.revenue} /> : null}
            {tab === 'reconciliation' && m.reconciliation ? <ReconciliationView r={m.reconciliation} /> : null}
            {tab === 'optimize' && m.optimizePerformance ? <OptimizeView o={m.optimizePerformance} /> : null}
          </main>
        ) : null}
      </div>
    </div>
  )
}

// --- Views ----------------------------------------------------------------------

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function OverviewView({ m, go, compare }: { m: Record<string, any>; go: (t: TabId) => void; compare: boolean }) {
  const o = m.overview
  void compare
  return (
    <div className="space-y-5">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <KpiCard title="Daily active users (last day)" kpi={o.dau} format={fmtNum} />
        <KpiCard title="Weekly active users (trailing 7d)" kpi={o.wau} format={fmtNum} />
        <KpiCard title="New installations" kpi={o.newInstalls} format={fmtNum} />
        <KpiCard title="Camera activation rate" kpi={o.cameraActivationRate} format={fmtPct} />
        <KpiCard title="First optimized photo within 5 min" kpi={o.firstOptimizedWithin5Min} format={fmtPct} onDrill={() => go('activation')} />
        <KpiCard title="Optimize → capture conversion (correlated)" kpi={o.optimizeToCapture} format={fmtPct} onDrill={() => go('capture')} />
        <KpiCard title="Paywall → verified purchase" kpi={o.paywallToPurchase} format={fmtPct} onDrill={() => go('paywall')} />
        <KpiCard title="Verified purchases (transactions, not revenue)" kpi={o.verifiedPurchases} format={fmtNum} onDrill={() => go('reconciliation')} />
        <KpiCard title="Capture failure rate" kpi={o.captureFailureRate} format={fmtPct} />
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <section className="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface)] p-4">
          <h3 className="text-sm font-medium text-[var(--color-ink-secondary)]">Retention (install cohorts)</h3>
          <p className="mt-2 text-sm">D1: {o.retentionD1.rate === null ? `insufficient data — ${o.retentionD1.reason ?? 'cohort unavailable'} (cohort n=${o.retentionD1.cohort})` : fmtPct(o.retentionD1.rate)}</p>
          <p className="mt-1 text-sm">D7: {o.retentionD7.rate === null ? `insufficient data — ${o.retentionD7.reason ?? 'cohort unavailable'} (cohort n=${o.retentionD7.cohort})` : fmtPct(o.retentionD7.rate)}</p>
          <h3 className="mt-4 text-sm font-medium text-[var(--color-ink-secondary)]">Auto Optimize latency (optimize_latency_summary.total_ms)</h3>
          {o.aoLatency.instrumented ? (
            <p className="mt-1 text-sm">
              p50 {fmtMs(o.aoLatency.p50)} · p95 {fmtMs(o.aoLatency.p95)} · p99 {fmtMs(o.aoLatency.p99)} · n={fmtNum(o.aoLatency.n)} runs
              <br />
              <span className="text-xs text-[var(--color-ink-tertiary)]">Previous: p95 {fmtMs(o.aoLatency.previous.p95)} (n={fmtNum(o.aoLatency.previous.n)}). {o.aoLatency.method}</span>
            </p>
          ) : (
            <div className="mt-2"><NotInstrumented note={o.aoLatency.note} /></div>
          )}
          <button type="button" onClick={() => go('optimize')} className="mt-2 text-sm font-medium text-[var(--color-tip)] underline">Latency &amp; reliability detail →</button>
        </section>
        <section className="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface)] p-4">
          <h3 className="text-sm font-medium text-[var(--color-ink-secondary)]">Daily trend (UTC days)</h3>
          <BarChart
            label="Daily active users by day"
            format={fmtNum}
            data={(o.trend as Array<{ day: string; dau: number }>).map((d) => ({ label: d.day, value: d.dau }))}
          />
          <p className="text-xs text-[var(--color-ink-tertiary)]">Verified purchases/day and 5-minute activations/day are in the exported CSV and the detailed views.</p>
          <Sparkline label="Daily active users trend line" values={(o.trend as Array<{ dau: number }>).map((d) => d.dau)} />
        </section>
      </div>

      <section className="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface)] p-4">
        <h3 className="text-sm font-medium text-[var(--color-ink-secondary)]">Legacy aggregates (NOT a funnel)</h3>
        <p className="mt-1 text-sm">
          auto_optimize_start {fmtNum(o.legacy.autoOptimizeStartEvents)} · auto_optimize_success {fmtNum(o.legacy.autoOptimizeSuccessEvents)} ·
          optimize_photo_captured {fmtNum(o.legacy.optimizePhotoCapturedEvents)} · optimize_capture_abandoned {fmtNum(o.legacy.optimizeCaptureAbandonedEvents)} ·
          shutter_tap {fmtNum(o.legacy.shutterTapEvents)} · capture_success {fmtNum(o.legacy.captureSuccessEvents)}
        </p>
        <p className="mt-1 text-xs text-[var(--color-ink-tertiary)]">{o.legacy.note}</p>
      </section>

      <ExperimentsPanel experiments={m.experiments} alerts={m.alerts} note={m.alertingNote} />
    </div>
  )
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function ExperimentsPanel({ experiments, alerts, note }: { experiments: any[]; alerts: any[]; note: string }) {
  if (!experiments) return null
  return (
    <section className="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface)] p-4" aria-label="Experiments and alerts">
      <h3 className="font-display text-lg text-[var(--color-ink)]">Experiments, feature flags &amp; alerts</h3>
      <p className="mt-1 text-xs text-[var(--color-ink-tertiary)]">
        Read-only. Flag values live in client UserDefaults — the server cannot read them, so status reflects observed events only. This panel never changes rollout.
      </p>
      <div className="mt-3 grid grid-cols-1 gap-3 lg:grid-cols-2">
        {experiments.map((e) => (
          <article key={e.flag} className="rounded-[var(--radius-sm)] border border-[var(--color-border)] p-3">
            <h4 className="text-sm font-medium">{e.flag}</h4>
            <p className="text-xs text-[var(--color-ink-tertiary)]">
              {e.experimentId} {e.version} · arms: {e.arms.join(' vs ')} · assignment: {e.assignment}
            </p>
            <p className="mt-1 text-xs">
              Status: <strong>{e.observedStatus === 'events_observed' ? 'events observed' : 'no data in period'}</strong> · config: unknown (client-side)
              <br />Start (first observed event): {e.startDate ? new Date(e.startDate).toLocaleDateString() : '—'} · n = {fmtNum(e.sampleSize)} · exposure = {fmtNum(e.exposure)}
              <br />Primary: {e.primaryMetric}
              <br />Guardrails: {e.guardrails.join(', ')}
              <br />Eligibility: {e.eligibility}
            </p>
          </article>
        ))}
      </div>
      <h4 className="mt-4 text-sm font-medium text-[var(--color-ink-secondary)]">Alert definitions (read-only, computed on load)</h4>
      <table className="mt-1 w-full text-sm">
        <thead>
          <tr className="text-left text-[var(--color-ink-tertiary)]">
            <th className="py-1 pr-2 font-medium">Metric</th>
            <th className="py-1 pr-2 font-medium">Condition</th>
            <th className="py-1 pr-2 font-medium">Current</th>
            <th className="py-1 pr-2 font-medium">Baseline</th>
            <th className="py-1 font-medium">Status</th>
          </tr>
        </thead>
        <tbody>
          {alerts.map((a) => {
            const fmtA = (v: number | null): string =>
              v === null ? '—' : a.unit === 'ms' ? fmtMs(v) : a.unit === 'count' ? fmtNum(v) : fmtPct(v)
            return (
            <tr key={a.id} className="border-t border-[var(--color-border)]">
              <td className="py-1.5 pr-2">{a.metric}</td>
              <td className="py-1.5 pr-2">{a.condition}</td>
              <td className="py-1.5 pr-2">{fmtA(a.current)}</td>
              <td className="py-1.5 pr-2">{fmtA(a.baseline)}</td>
              <td className="py-1.5">
                <span className={a.status === 'alert' ? 'font-semibold text-[var(--color-danger)]' : ''}>
                  {a.status === 'alert' ? '⚠ ALERT' : a.status === 'ok' ? 'OK' : 'Unknown (insufficient data / stale)'}
                </span>
                {a.note ? <span className="block text-xs text-[var(--color-ink-tertiary)]">{a.note}</span> : null}
              </td>
            </tr>
            )
          })}
        </tbody>
      </table>
      <p className="mt-2 text-xs text-[var(--color-ink-tertiary)]">{note}</p>
    </section>
  )
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function ActivationView({ a }: { a: any }) {
  if (!a.instrumented) {
    return <NotInstrumented note="No first_photo_experiment_assigned events in this period. Assignment happens client-side on first computation; until the experiment build is in users' hands there is nothing to compare — no rates are shown." />
  }
  return (
    <div className="space-y-5">
      <p className="text-sm text-[var(--color-ink-secondary)]">{a.eligibilityNote}</p>
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        {a.arms.map((arm: any) => (
          <section key={arm.arm} className="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface)] p-4" aria-label={`Funnel for ${arm.arm}`}>
            <h3 className="font-display text-lg">{arm.arm}</h3>
            <p className="text-sm">
              Primary metric: <strong>{fmtPct(arm.primary.rate)}</strong> ({fmtNum(arm.primary.numerator)} / {fmtNum(arm.primary.denominator)} eligible users)
              <br />Median time to first optimized photo: {arm.medianTimeToFirstOptimizedSec === null ? '—' : `${arm.medianTimeToFirstOptimizedSec}s`}
              <br />Capture failures: {arm.captureFailures === null ? 'not instrumented' : fmtNum(arm.captureFailures)}
              <br />Retention D1: {arm.retentionD1 === null ? 'insufficient data' : fmtPct(arm.retentionD1)} · D7: {arm.retentionD7 === null ? 'insufficient data' : fmtPct(arm.retentionD7)}
            </p>
            <div className="mt-2">
              <FunnelTable stages={arm.steps.map((s: any) => ({ stage: s.stage, count: s.users, conversionFromPrev: s.conversionFromAssigned }))} />
            </div>
            <p className="text-xs text-[var(--color-ink-tertiary)]">Funnel column shows conversion from assignment; stages marked n/a do not exist for this arm (guidance + pre-optimize are treatment-only).</p>
          </section>
        ))}
      </div>
      <section className="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface)] p-4">
        <h3 className="text-sm font-medium text-[var(--color-ink-secondary)]">Treatment − control (primary metric)</h3>
        <p className="mt-1 text-sm">
          Absolute difference: {a.difference.absolutePp === null ? '—' : `${(a.difference.absolutePp * 100).toFixed(2)} pp`} · Relative lift:{' '}
          {a.difference.relativeLift === null ? '—' : fmtPct(a.difference.relativeLift)}
        </p>
        <p className="mt-1 text-sm">
          {a.difference.significance
            ? `Significance: ${a.difference.significance.method}; z = ${a.difference.significance.z.toFixed(2)}, p = ${a.difference.significance.pValue.toFixed(4)} — ${a.difference.significance.significantAt95 ? 'significant at 95%' : 'not significant at 95%'}.`
            : 'Significance: not computed.'}{' '}
          {a.difference.significanceNote}
        </p>
        <p className="mt-1 text-xs text-[var(--color-ink-tertiary)]">No winner is declared from raw event counts; read the primary metric with its sample sizes and the guardrails on the Overview.</p>
      </section>
    </div>
  )
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function CaptureView({ c }: { c: any }) {
  if (!c.instrumented) {
    return (
      <div className="space-y-3">
        <NotInstrumented note="No run_id-correlated optimize/capture data in this period (optimize_latency_summary / capture_ready_view). The legacy optimize_photo_captured / optimize_capture_abandoned counters below are aggregates only and are NOT presented as a funnel." />
        <p className="text-sm">Legacy optimize_capture_abandoned events: {fmtNum(c.abandonedLegacyEvents)}</p>
      </div>
    )
  }
  return (
    <div className="space-y-5">
      <p className="text-sm text-[var(--color-ink-secondary)]">
        Correlated by run_id only, in order: terminal optimize summary → capture-ready view → shutter tap → capture classified afterComplete.
        run_id coverage: {fmtNum(c.runIdCoverage.summariesWithRunId)} / {fmtNum(c.runIdCoverage.summariesTotal)} latency summaries.
      </p>
      <section className="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface)] p-4">
        <FunnelTable stages={c.funnel.map((f: any) => ({ stage: f.stage, count: f.runs, conversionFromPrev: f.conversionFromPrev }))} />
        <p className="mt-2 text-sm">
          Median time optimize-complete → shutter: {c.medianSecondsOptimizeCompleteToShutter === null ? '—' : `${c.medianSecondsOptimizeCompleteToShutter}s`} ·
          Ready runs with no capture recorded: {fmtNum(c.noCaptureRecordedRuns)} · Legacy abandoned events: {fmtNum(c.abandonedLegacyEvents)} ·
          Capture errors: {c.captureErrors === null ? 'not instrumented' : fmtNum(c.captureErrors)} · Undo (optimize_undone): {fmtNum(c.undoEvents)} · Resets: {fmtNum(c.resetEvents)}
        </p>
      </section>
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <BreakdownTable title="By lens" rows={c.breakdowns.byLens} />
        <BreakdownTable title="By trigger" rows={c.breakdowns.byTrigger} />
        <BreakdownTable title="By app version" rows={c.breakdowns.byAppVersion} />
        <BreakdownTable title="By experiment arm" rows={c.breakdowns.byArm} />
      </div>
    </div>
  )
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function PaywallView({ p, revenue }: { p: any; revenue: any }) {
  const seg = (title: string, rows: any[]) => (
    <BreakdownTable
      title={title}
      rows={rows.map((s: any) => ({
        segment: s.key,
        viewers: s.viewers,
        verified: s.stages?.purchase_verified ?? null,
        conversionViewToVerified: s.conversionViewToVerified,
        suppressed: s.suppressed ? 'yes' : 'no',
      }))}
    />
  )
  return (
    <div className="space-y-5">
      <section className="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface)] p-4">
        <h3 className="font-display text-lg">Purchase funnel (ordered, same session)</h3>
        <FunnelTable stages={p.funnel.map((f: any) => ({ stage: f.stage, count: f.users, conversionFromPrev: f.conversionFromPrev }))} />
        <p className="mt-2 text-sm">
          Unique viewers {fmtNum(p.uniqueViewers)} · unique verified purchasers {fmtNum(p.uniquePurchasersVerified)} · view→verified {fmtPct(p.viewToVerifiedConversion)}
          <br />Cancellations {fmtNum(p.cancellations)} · pending {fmtNum(p.pending)} · failed {fmtNum(p.failed)} · restores {fmtNum(p.restores)} (events)
          <br />Verified trial starts: {p.verifiedTrialStarts === null ? 'not instrumented (no trial signal in verified-event props)' : fmtNum(p.verifiedTrialStarts)} · paid starts (distinct transaction_id): {fmtNum(p.paidStarts)}
        </p>
        <p className="mt-1 text-xs text-[var(--color-ink-tertiary)]">{p.legacyFallback.note} Legacy purchase_success events: {fmtNum(p.legacyFallback.purchaseSuccessEvents)} (v2: {fmtNum(p.legacyFallback.purchaseSuccessV2Events)}).</p>
      </section>
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        {seg('By experiment arm', p.segments.byArm)}
        {seg('By trigger / paywall', p.segments.byTrigger)}
        {seg('By product (from purchase_start)', p.segments.byProduct)}
        {seg('By app version', p.segments.byAppVersion)}
        {seg('By user type', p.segments.byUserType)}
      </div>
      {revenue ? (
        <section className="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface)] p-4">
          <h3 className="font-display text-lg">Revenue — authoritative ledgers only</h3>
          <p className="mt-1 text-sm">{revenue.note}</p>
          <p className="mt-2 text-sm">
            Local entitlements: {fmtNum(revenue.entitlements.proTotal)} Pro ({fmtNum(revenue.entitlements.iapPro)} IAP, {fmtNum(revenue.entitlements.stripePro)} Stripe) ·
            estimated IAP MRR ${(revenue.entitlements.iapApproxMrrCents / 100).toFixed(2)} · Stripe approx MRR: {revenue.stripe.configured ? `$${(revenue.stripe.approxMrrCents / 100).toFixed(2)} (${fmtNum(revenue.stripe.activeSubscriptions)} active)` : 'Stripe not configured on this server'}
          </p>
          <p className="mt-1 text-xs text-[var(--color-ink-tertiary)]">{revenue.entitlements.iapMrrNote} Telemetry purchase events are never converted into revenue figures.</p>
        </section>
      ) : null}
    </div>
  )
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function ReconciliationView({ r }: { r: any }) {
  return (
    <div className="space-y-5">
      {!r.instrumented ? <NotInstrumented note="Purchase telemetry v2 is not present in this period, so reconciliation cannot run. Legacy purchase_success counts cannot substitute." /> : null}
      <section className="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface)] p-4">
        <h3 className="font-display text-lg">Reconciliation by transaction_id</h3>
        <div className="mt-2 grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
          <p>Purchase starts<br /><strong>{fmtNum(r.counts.purchaseStarts)}</strong></p>
          <p>Starts without terminal outcome<br /><strong>{fmtNum(r.counts.startsWithoutTerminalOutcome)}</strong></p>
          <p>Verified transactions<br /><strong>{fmtNum(r.counts.verifiedTransactions)}</strong></p>
          <p>Entitlement activations<br /><strong>{fmtNum(r.counts.entitlementActivations)}</strong></p>
          <p>Verified without entitlement<br /><strong>{fmtNum(r.counts.verifiedWithoutEntitlement)}</strong></p>
          <p>Entitlement without verified/restore<br /><strong>{fmtNum(r.counts.entitlementWithoutVerifiedOrRestore)}</strong></p>
          <p>Duplicate purchase_success tx<br /><strong>{fmtNum(r.counts.duplicateSuccessTransactions)}</strong></p>
          <p>Discrepancy rate<br /><strong>{fmtPct(r.discrepancyRate)}</strong> (tolerance {fmtPct(r.tolerance)} — {r.withinTolerance === null ? 'unknown' : r.withinTolerance ? 'within tolerance' : 'OVER TOLERANCE'})</p>
        </div>
        <p className="mt-2 text-xs text-[var(--color-ink-tertiary)]">Stripe web transactions, when they exist, live in the Stripe/entitlement snapshot on the Paywall view — this table is StoreKit telemetry vs entitlement activations only. Rows below expose transaction_id + product + timestamps only: no receipts, no payment details.</p>
      </section>
      <section className="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface)] p-4">
        <h3 className="text-sm font-medium text-[var(--color-ink-secondary)]">Discrepancy rows (read-only diagnostics, max 200)</h3>
        {r.rows.length ? (
          <div className="mt-2 overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-[var(--color-ink-tertiary)]">
                  <th className="py-1 pr-3 font-medium">Transaction</th>
                  <th className="py-1 pr-3 font-medium">Product</th>
                  <th className="py-1 pr-3 font-medium">Verified at</th>
                  <th className="py-1 pr-3 font-medium">Entitlement at</th>
                  <th className="py-1 font-medium">Issue</th>
                </tr>
              </thead>
              <tbody>
                {r.rows.map((row: any) => (
                  <tr key={`${row.transaction_id}-${row.issue}`} className="border-t border-[var(--color-border)]">
                    <td className="py-1.5 pr-3 font-mono text-xs">{row.transaction_id}</td>
                    <td className="py-1.5 pr-3">{row.product_id ?? '—'}</td>
                    <td className="py-1.5 pr-3">{row.verified_at ?? '—'}</td>
                    <td className="py-1.5 pr-3">{row.entitlement_at ?? '—'}</td>
                    <td className="py-1.5">{row.issue}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="mt-1 text-sm">No discrepancies found in this period.</p>
        )}
        <ul className="mt-3 list-inside list-disc text-xs text-[var(--color-ink-tertiary)]">
          {r.notes.map((n: string) => (
            <li key={n}>{n}</li>
          ))}
        </ul>
      </section>
    </div>
  )
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function OptimizeView({ o }: { o: any }) {
  if (!o.instrumented) {
    return (
      <div className="space-y-3">
        <NotInstrumented note="No optimize_latency_summary events in this period — per-run stage timing (optimize_stage_timing_enabled) has not produced data here yet. Legacy unpaired counters are context only." />
        <p className="text-sm">Legacy: auto_optimize_start {fmtNum(o.legacy.autoOptimizeStart)} · success {fmtNum(o.legacy.autoOptimizeSuccess)} · fail {fmtNum(o.legacy.autoOptimizeFail)} · cancel {fmtNum(o.legacy.autoOptimizeCancel)}</p>
      </div>
    )
  }
  return (
    <div className="space-y-5">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <section className="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface)] p-4">
          <h3 className="text-sm font-medium text-[var(--color-ink-secondary)]">Runs &amp; outcomes</h3>
          <p className="mt-1 text-sm">
            {fmtNum(o.runs)} runs · success {fmtPct(o.rates.success)} · failure {fmtPct(o.rates.failure)} · cancelled {fmtPct(o.rates.cancelled)} · fallback {fmtPct(o.rates.fallback)}
          </p>
        </section>
        <section className="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface)] p-4">
          <h3 className="text-sm font-medium text-[var(--color-ink-secondary)]">Total latency (nearest-rank)</h3>
          <p className="mt-1 text-sm">p50 {fmtMs(o.totalLatency.p50)} · p95 {fmtMs(o.totalLatency.p95)} · p99 {fmtMs(o.totalLatency.p99)} · n={fmtNum(o.totalLatency.n)}</p>
          <p className="text-xs text-[var(--color-ink-tertiary)]">Runs over 10 s: {fmtPct(o.over10sShare)} (proposed alert threshold 2%)</p>
        </section>
        <section className="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface)] p-4">
          <h3 className="text-sm font-medium text-[var(--color-ink-secondary)]">Reliability</h3>
          <p className="mt-1 text-sm">
            AE timeouts {fmtPct(o.aeTimeoutRate)} · metering missing {fmtPct(o.meteringMissingRate)}
            <br />Exposure reverts: {o.reliabilityCounts.exposureReverts === null ? 'not instrumented' : fmtNum(o.reliabilityCounts.exposureReverts)} ·
            lens-flip invalidations: {o.reliabilityCounts.lensFlipInvalidations === null ? 'not instrumented' : fmtNum(o.reliabilityCounts.lensFlipInvalidations)} ·
            camera resets: {o.reliabilityCounts.cameraResets === null ? 'not instrumented' : fmtNum(o.reliabilityCounts.cameraResets)} ·
            capture failures after optimize: {o.reliabilityCounts.captureFailuresAfterOptimize === null ? 'not instrumented' : fmtNum(o.reliabilityCounts.captureFailuresAfterOptimize)}
          </p>
        </section>
        <section className="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface)] p-4">
          <h3 className="text-sm font-medium text-[var(--color-ink-secondary)]">Regressions vs previous period</h3>
          {o.regressions.map((r: any) => (
            <p key={r.metric} className="mt-1 text-sm">
              {r.metric}: {r.regression ? <strong className="text-[var(--color-danger)]">REGRESSION</strong> : 'no regression'} ({r.note})
            </p>
          ))}
        </section>
      </div>

      <section className="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface)] p-4">
        <h3 className="text-sm font-medium text-[var(--color-ink-secondary)]">Latency by day (p95) and stage breakdown — slowest stage: {o.slowestStage ?? '—'}</h3>
        <BarChart label="Daily p95 latency in milliseconds" format={fmtMs} data={o.series.map((d: any) => ({ label: d.day, value: d.p95 }))} />
        <table className="mt-3 w-full text-sm">
          <thead>
            <tr className="text-left text-[var(--color-ink-tertiary)]">
              <th className="py-1 pr-3 font-medium">Stage</th>
              <th className="py-1 pr-3 font-medium">p50</th>
              <th className="py-1 pr-3 font-medium">p95</th>
              <th className="py-1 pr-3 font-medium">p99</th>
              <th className="py-1 pr-3 font-medium">n</th>
              <th className="py-1 font-medium">Mean share of total</th>
            </tr>
          </thead>
          <tbody>
            {o.stageLatency.map((s: any) => (
              <tr key={s.stage} className="border-t border-[var(--color-border)]">
                <td className="py-1.5 pr-3">{s.stage}</td>
                <td className="py-1.5 pr-3">{fmtMs(s.p50)}</td>
                <td className="py-1.5 pr-3">{fmtMs(s.p95)}</td>
                <td className="py-1.5 pr-3">{fmtMs(s.p99)}</td>
                <td className="py-1.5 pr-3">{fmtNum(s.n)}</td>
                <td className="py-1.5">{fmtPct(s.meanShareOfTotal)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="text-xs text-[var(--color-ink-tertiary)]">Stage set comes from stage_*_ms props on optimize_latency_summary. cameraReadyWait and meteringPrep are not separately anchored in the controller today (inside the convergence segment) — see docs/activation-experiments.md §4.</p>
      </section>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <BreakdownTable title="By lens" rows={o.breakdowns.byLens} />
        <BreakdownTable title="By trigger" rows={o.breakdowns.byTrigger} />
        <BreakdownTable title="By app version (timing definitions may differ — compare within a version)" rows={o.breakdowns.byAppVersion} />
        <BreakdownTable title="By experiment arm" rows={o.breakdowns.byArm} />
      </div>
      <p className="text-xs text-[var(--color-ink-tertiary)]">{o.legacy.note} Legacy counters: start {fmtNum(o.legacy.autoOptimizeStart)}, success {fmtNum(o.legacy.autoOptimizeSuccess)}, fail {fmtNum(o.legacy.autoOptimizeFail)}, cancel {fmtNum(o.legacy.autoOptimizeCancel)}.</p>
    </div>
  )
}
