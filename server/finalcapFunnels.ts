/**
 * FinalCap app funnels for the admin dashboard — computed from THIS app's
 * telemetry_events (the panel's own MySQL, server/mysql.ts) where
 * app = 'finalcap': client events sent by the FinalCap iOS app (v1.0.1+;
 * session_id is one per cold launch). The unit/window method matches the
 * canonical funnel machinery in server/telemetry.ts (distinct session_id,
 * trailing complete PT days) so the method is like-for-like, but the stages
 * are FinalCap's own — these are NOT the canonical ProTune funnel, and the
 * scope is always app='finalcap' no matter what the panel's app filter says.
 *
 * This is a SEPARATE data source from FinalCap's own server database used
 * by server/finalcapUsage.ts (daily_inference_usage, chat_interactions, …).
 * Never mix the two sources in one figure. Until FinalCap v1.0.1 ships
 * there are ~no 'finalcap' telemetry rows, so the honest result is a clean
 * zero state, not an error.
 */
import type mysql from 'mysql2/promise'
import {
  PURCHASE_TELEMETRY_NOTE,
  fetchSessionStageFunnel,
  type SessionStageStep,
} from './telemetry.ts'

export const FINALCAP_APP = 'finalcap'

/** Core funnel: app_open → editor_open → edit_start → edit_success. */
export const FINALCAP_FUNNEL_CORE_STAGES = [
  'app_open',
  'editor_open',
  'edit_start',
  'edit_success',
] as const

/** Export pair: export_start → export_success. */
export const FINALCAP_FUNNEL_EXPORT_STAGES = ['export_start', 'export_success'] as const

/** Revenue stages — same event names as ProTune's monetization events. */
export const FINALCAP_FUNNEL_REVENUE_STAGES = [
  'paywall_view',
  'trial_start',
  'purchase_success',
] as const

const ALL_STAGES: readonly string[] = [
  ...FINALCAP_FUNNEL_CORE_STAGES,
  ...FINALCAP_FUNNEL_EXPORT_STAGES,
  ...FINALCAP_FUNNEL_REVENUE_STAGES,
]

export interface FinalcapFunnelGroup {
  stages: string[]
  counts: Record<string, number>
  steps: SessionStageStep[]
}

export interface FinalcapFunnels {
  app: string
  unit: 'distinct session_id'
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

export const FINALCAP_FUNNEL_DEFINITION =
  "FinalCap funnel: unit = distinct session_id (one per app cold launch; rows with NULL/empty session_id excluded); " +
  "stages counted from this panel's telemetry_events where app = 'finalcap' — client events sent by the FinalCap app (v1.0.1+); " +
  'window = trailing complete days in America/Los_Angeles (PT calendar days, today excluded). ' +
  "Separate from the FinalCap server-database figures in the usage section (FinalCap's own DB) and from the canonical ProTune funnel."

const ratio = (a: number, b: number): number | null => (b > 0 ? a / b : null)

export async function fetchFinalcapFunnels(
  days: number,
  poolArg?: mysql.Pool | null,
  nowMs: number = Date.now(),
): Promise<FinalcapFunnels> {
  const f = await fetchSessionStageFunnel(days, FINALCAP_APP, ALL_STAGES, nowMs, poolArg)
  // Conversions are recomputed within each group: the combined query's
  // adjacent steps would chain across group boundaries (export_start after
  // edit_success, paywall_view after export_success), which is meaningless.
  const group = (stages: readonly string[]): FinalcapFunnelGroup => {
    const counts: Record<string, number> = {}
    for (const s of stages) counts[s] = f.counts[s] ?? 0
    const steps = stages.map((stage, i) => ({
      stage,
      sessions: counts[stage]!,
      conversionFromPrev: i === 0 ? null : ratio(counts[stage]!, counts[stages[i - 1]!]!),
      conversionFromFirst: i === 0 ? null : ratio(counts[stage]!, counts[stages[0]!]!),
    }))
    return { stages: [...stages], counts, steps }
  }
  return {
    app: FINALCAP_APP,
    unit: f.unit,
    days: f.days,
    timezone: f.timezone,
    windowStartDay: f.windowStartDay,
    windowEndDayExclusive: f.windowEndDayExclusive,
    definition: FINALCAP_FUNNEL_DEFINITION,
    revenueNote: PURCHASE_TELEMETRY_NOTE,
    core: group(FINALCAP_FUNNEL_CORE_STAGES),
    export: group(FINALCAP_FUNNEL_EXPORT_STAGES),
    revenue: group(FINALCAP_FUNNEL_REVENUE_STAGES),
    ...(f.error ? { error: f.error } : {}),
  }
}
