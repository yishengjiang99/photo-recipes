import { Loader2, RefreshCw } from 'lucide-react'
import { useCallback, useEffect, useState, type ReactNode } from 'react'

/**
 * GBK Composer live telemetry on /admin — read-only, proxied server-side from
 * compose.grepawk.com by /api/admin/gbk (server/gbkTelemetry.ts). Each GBK
 * section can fail alone ({ error }); a failed section shows its error and
 * the rest still render. Separate from this panel's own telemetry.
 */
type Err = { error: string }
type Metrics = {
  days: number; impressions: number; sessions: number; actors: number; avg_dwell_ms: number
  skip_rate: number; completion_rate: number; engaged_rate: number; d1_retention: number | null
}
type Funnel = { since: string; totals: Record<string, number>; conversion: Record<string, number | null> }
type Billing = {
  since: string; totals: Record<string, number>
  steps: { overall: { paywall_view: number; checkout_start: number; purchase: number } }
}
type LogRow = { id: number; ts: number; account: string; event: string; plan: string; provider: string; value_cents: number | null; surface: string; platform: string }
type ClientErrors = { total: number; errors: Array<{ id: number; createdAt: string; kind: string; message: string; url: string; release: string; count: number }> }
type Report = { id: number; kind: string; target: string; reason: string; created_at: number }
type Data = {
  generatedAt: string; days: number
  metrics: Metrics | Err; funnel: Funnel | Err; billing: Billing | Err
  billingLog: LogRow[] | Err; clientErrors: ClientErrors | Err; reports: Report[] | Err
}
type Resp = { ok: boolean; configured?: boolean; error?: string; data?: Data }

const isErr = (v: unknown): v is Err => !!v && typeof v === 'object' && 'error' in (v as object)
const pct = (n: number | null | undefined) => (n == null ? '—' : `${(n * 100).toFixed(1)}%`)
const card = 'rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface)] p-3'
const box = 'overflow-hidden rounded-[var(--radius-md)] border border-[var(--color-border)]'
const boxHead = 'border-b border-[var(--color-border)] bg-[var(--color-surface)] px-3 py-2 text-xs uppercase tracking-wide text-[var(--color-ink-tertiary)]'

function Stat({ label, value, hint }: { label: string; value: ReactNode; hint?: string }) {
  return (
    <div className={card}>
      <p className="text-xs text-[var(--color-ink-tertiary)]">{label}</p>
      <p className="mt-1 text-xl font-medium text-[var(--color-ink)]">{value}</p>
      {hint ? <p className="mt-0.5 text-xs text-[var(--color-ink-secondary)]">{hint}</p> : null}
    </div>
  )
}

function Part({ title, v, children }: { title: string; v: unknown; children: () => ReactNode }) {
  return (
    <div className={box}>
      <div className={boxHead}>{title}</div>
      {isErr(v) ? <p className="px-3 py-2 text-sm text-[var(--color-danger)]">Failed: {v.error}</p> : <div className="overflow-x-auto">{children()}</div>}
    </div>
  )
}

const th = 'px-3 py-1.5 text-left text-xs font-medium text-[var(--color-ink-tertiary)]'
const td = 'px-3 py-1.5 align-top'

export function AdminGbkSection() {
  const [resp, setResp] = useState<Resp | null>(null)
  const [loading, setLoading] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const res = await fetch('/api/admin/gbk?days=30', { credentials: 'include' })
      setResp(res.ok ? ((await res.json()) as Resp) : { ok: false, error: `Failed (${res.status})` })
    } catch (err) {
      setResp({ ok: false, error: err instanceof Error ? err.message : 'Failed to load' })
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  const d = resp?.ok ? resp.data : undefined
  return (
    <section>
      <h2 className="mb-3 flex flex-wrap items-center gap-2 text-sm font-medium uppercase tracking-wide text-[var(--color-ink-tertiary)]">
        GBK Composer — live telemetry
        <span className="rounded-full bg-[var(--color-surface)] px-2 py-0.5 normal-case">
          read-only from compose.grepawk.com{d ? ` · ${d.days}d · ${new Date(d.generatedAt).toLocaleTimeString()}` : ''}
        </span>
        <button
          type="button"
          onClick={() => void load()}
          disabled={loading}
          className="ml-auto inline-flex items-center gap-1 rounded-full border border-[var(--color-border)] px-2 py-0.5 normal-case text-[var(--color-ink-secondary)] disabled:opacity-50"
        >
          {loading ? <Loader2 className="h-3 w-3 animate-spin" /> : <RefreshCw className="h-3 w-3" />} Refresh
        </button>
      </h2>
      {!resp && loading ? (
        <div className="flex justify-center py-6"><Loader2 className="h-5 w-5 animate-spin text-[var(--color-tip)]" /></div>
      ) : null}
      {resp && !resp.ok ? (
        <p className="rounded-[var(--radius-sm)] border border-[var(--color-danger)]/40 bg-[var(--color-danger)]/10 px-3 py-2 text-sm text-[var(--color-danger)]">
          GBK telemetry unavailable: {resp.error}
        </p>
      ) : null}
      {d ? (
        <div className="space-y-4">
          <Part title={`Feed (last ${isErr(d.metrics) ? '' : d.metrics.days}d)`} v={d.metrics}>
            {() => {
              const m = d.metrics as Metrics
              return (
                <div className="grid gap-2 p-3 sm:grid-cols-3 lg:grid-cols-6">
                  <Stat label="Impressions" value={m.impressions} hint={`${m.sessions} sessions · ${m.actors} listeners`} />
                  <Stat label="Avg dwell" value={`${(m.avg_dwell_ms / 1000).toFixed(1)}s`} />
                  <Stat label="Completion" value={pct(m.completion_rate)} />
                  <Stat label="Fast skip" value={pct(m.skip_rate)} />
                  <Stat label="Engaged" value={pct(m.engaged_rate)} />
                  <Stat label="D1 retention" value={pct(m.d1_retention)} />
                </div>
              )
            }}
          </Part>
          <div className="grid gap-4 lg:grid-cols-2">
            <Part title="Funnel (totals)" v={d.funnel}>
              {() => {
                const f = d.funnel as Funnel
                const rows = Object.entries(f.totals).filter(([, n]) => n > 0)
                return (
                  <table className="w-full text-sm">
                    <tbody>
                      {rows.length ? rows.map(([k, n]) => (
                        <tr key={k} className="border-t border-[var(--color-border)] first:border-t-0"><td className={td}>{k}</td><td className={`${td} text-right`}>{n}</td></tr>
                      )) : <tr><td className={td}>No funnel events since {f.since}</td></tr>}
                    </tbody>
                  </table>
                )
              }}
            </Part>
            <Part title="Billing (totals)" v={d.billing}>
              {() => {
                const b = d.billing as Billing
                const o = b.steps.overall
                const rows = Object.entries(b.totals).filter(([, n]) => n > 0)
                return (
                  <>
                    <p className="px-3 py-2 text-sm">Paywall → checkout → purchase: <b>{o.paywall_view} → {o.checkout_start} → {o.purchase}</b></p>
                    <table className="w-full text-sm">
                      <tbody>
                        {rows.map(([k, n]) => (
                          <tr key={k} className="border-t border-[var(--color-border)]"><td className={td}>{k}</td><td className={`${td} text-right`}>{n}</td></tr>
                        ))}
                      </tbody>
                    </table>
                  </>
                )
              }}
            </Part>
          </div>
          <Part title="Billing log (latest)" v={d.billingLog}>
            {() => {
              const rows = d.billingLog as LogRow[]
              return rows.length ? (
                <table className="w-full text-sm">
                  <thead><tr><th className={th}>When</th><th className={th}>Event</th><th className={th}>Account</th><th className={th}>Plan</th><th className={th}>Via</th></tr></thead>
                  <tbody>
                    {rows.map((r) => (
                      <tr key={r.id} className="border-t border-[var(--color-border)]">
                        <td className={`${td} whitespace-nowrap`}>{new Date(r.ts).toLocaleString()}</td>
                        <td className={td}>{r.event}{r.value_cents ? ` · $${(r.value_cents / 100).toFixed(2)}` : ''}</td>
                        <td className={`${td} max-w-[12rem] truncate`}>{r.account}</td>
                        <td className={td}>{r.plan || '—'}</td>
                        <td className={td}>{[r.provider, r.surface, r.platform].filter(Boolean).join(' · ') || '—'}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              ) : <p className="px-3 py-2 text-sm text-[var(--color-ink-tertiary)]">No billing events.</p>
            }}
          </Part>
          <Part title={`Client errors${isErr(d.clientErrors) ? '' : ` (${d.clientErrors.total} total)`}`} v={d.clientErrors}>
            {() => {
              const c = d.clientErrors as ClientErrors
              return c.errors.length ? (
                <table className="w-full text-sm">
                  <thead><tr><th className={th}>When</th><th className={th}>Kind</th><th className={th}>Message</th><th className={th}>×</th><th className={th}>Release</th></tr></thead>
                  <tbody>
                    {c.errors.map((e) => (
                      <tr key={e.id} className="border-t border-[var(--color-border)]">
                        <td className={`${td} whitespace-nowrap`}>{new Date(e.createdAt).toLocaleString()}</td>
                        <td className={td}>{e.kind}</td>
                        <td className={`${td} max-w-[28rem] break-words`} title={e.url}>{e.message}</td>
                        <td className={td}>{e.count}</td>
                        <td className={`${td} whitespace-nowrap`}>{e.release || '—'}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              ) : <p className="px-3 py-2 text-sm text-[var(--color-ink-tertiary)]">No client errors.</p>
            }}
          </Part>
          <Part title="Open reports" v={d.reports}>
            {() => {
              const r = d.reports as Report[]
              return r.length ? (
                <table className="w-full text-sm">
                  <tbody>
                    {r.map((x) => (
                      <tr key={x.id} className="border-t border-[var(--color-border)] first:border-t-0">
                        <td className={`${td} whitespace-nowrap`}>{new Date(x.created_at).toLocaleString()}</td>
                        <td className={td}>{x.kind}</td><td className={td}>{x.target}</td><td className={td}>{x.reason}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              ) : <p className="px-3 py-2 text-sm text-[var(--color-ink-tertiary)]">No open reports.</p>
            }}
          </Part>
        </div>
      ) : null}
    </section>
  )
}
