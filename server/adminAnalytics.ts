/**
 * Admin analytics & experiment monitoring — analytics core + bounded DB layer.
 *
 * Architecture (see docs/admin-analytics.md):
 *   telemetry_events (existing ingestion, server/telemetry.ts)
 *     -> fetchAnalyticsDataset()  bounded, app='photo-recipes' ONLY (shared table)
 *     -> pure compute*() functions over normalized rows (this file, no DB)
 *     -> GET /api/admin/analytics/* in server/admin.ts (requireAdmin)
 *
 * Correctness rules enforced here:
 *  - Distinct-user vs event counts are always labeled; funnels that claim
 *    attribution are correlated by run_id / purchase_attempt_id /
 *    transaction_id and enforce event order within one session. Anything
 *    else lives in a clearly-labeled `legacy` block, never mixed in.
 *  - Missing instrumentation returns null + instrumented:false, never 0.
 *  - Breakdown cells with < 5 distinct users are suppressed.
 *  - Revenue NEVER comes from telemetry event counts. The only revenue
 *    figures surfaced are the existing local entitlement/Stripe snapshots
 *    (passed through by the route, labeled as estimates, not ASC).
 *  - Latency percentiles are nearest-rank over optimize_latency_summary
 *    .total_ms, and are split by app_version in breakdowns (timing
 *    definitions may differ across versions; the pooled figure is labeled).
 */
import type mysql from 'mysql2/promise'
import { getMysqlPool } from './mysql.ts'
import { REAL_APP } from './appFilter.ts'

export const ANALYTICS_APP = REAL_APP
export const ANALYTICS_TIMEZONE = 'UTC'
export const ANALYTICS_DISPLAY_TIMEZONE = 'America/Los_Angeles'
export const ROW_CAP = 200_000
export const MAX_RANGE_MS = 92 * 24 * 60 * 60 * 1000
export const SMALL_COHORT_MIN_USERS = 5
export const ALERT_MIN_N = 100
/** Reconciliation tolerance: discrepancies above 2% of verified purchases alert. */
export const RECONCILIATION_TOLERANCE = 0.02

// ---------------------------------------------------------------------------
// Normalized row + basic accessors
// ---------------------------------------------------------------------------

export interface AnalyticsRow {
  /** Epoch ms (UTC). Source column telemetry_events.created_at. */
  created_at: number
  event: string
  anon_id: string
  session_id: string | null
  app_version: string | null
  platform: string | null
  props: Record<string, string | number | boolean> | null
}

export interface InstallRow {
  anon_id: string
  first_seen_ms: number
}

export function propStr(r: AnalyticsRow, key: string): string | null {
  const v = r.props?.[key]
  if (typeof v === 'string' && v.trim()) return v.trim()
  if (typeof v === 'number' && Number.isFinite(v)) return String(v)
  if (typeof v === 'boolean') return v ? 'true' : 'false'
  return null
}

export function propNum(r: AnalyticsRow, key: string): number | null {
  const v = r.props?.[key]
  if (typeof v === 'number' && Number.isFinite(v)) return v
  if (typeof v === 'string' && v.trim() && Number.isFinite(Number(v))) return Number(v)
  return null
}

export function propBool(r: AnalyticsRow, key: string): boolean | null {
  const v = r.props?.[key]
  if (typeof v === 'boolean') return v
  if (typeof v === 'string') {
    if (v.toLowerCase() === 'true') return true
    if (v.toLowerCase() === 'false') return false
  }
  if (typeof v === 'number') return v !== 0
  return null
}

/** run_id lives on the v2 events; some carry it under optimize_run_id. */
export function rowRunId(r: AnalyticsRow): string | null {
  return propStr(r, 'run_id') ?? propStr(r, 'optimize_run_id')
}
export function rowTxId(r: AnalyticsRow): string | null {
  return propStr(r, 'transaction_id')
}
export function rowAttemptId(r: AnalyticsRow): string | null {
  return propStr(r, 'purchase_attempt_id')
}

/**
 * Arm normalization. The iOS assignment code emits the generic
 * ExperimentArm raw values 'control' | 'treatment' (see
 * ios/PhotoRecipes/Services/ExperimentAssignment.swift), while the
 * experiment contract (docs/activation-experiments.md) names the logical
 * arms. Map by experiment context and accept the long names verbatim so
 * either emission style lands in the same bucket.
 */
export function normalizeFirstPhotoArm(v: string | null): string | null {
  if (!v) return null
  if (v === 'control' || v === 'post_capture_v1') return 'post_capture_v1'
  if (v === 'treatment' || v === 'pre_capture_guided_v1') return 'pre_capture_guided_v1'
  return v
}
export function normalizePaywallArm(v: string | null): string | null {
  if (!v) return null
  if (v === 'control' || v === 'paywall_control_v1') return 'paywall_control_v1'
  if (v === 'treatment' || v === 'paywall_value_v1') return 'paywall_value_v1'
  return v
}
export function rowFirstPhotoArm(r: AnalyticsRow): string | null {
  return normalizeFirstPhotoArm(propStr(r, 'arm') ?? propStr(r, 'experiment_arm'))
}
export function rowPaywallArm(r: AnalyticsRow): string | null {
  return normalizePaywallArm(propStr(r, 'experiment_arm') ?? propStr(r, 'arm'))
}
export function rowLens(r: AnalyticsRow): string | null {
  return propStr(r, 'lens') ?? propStr(r, 'camera_position') ?? propStr(r, 'position')
}

// ---------------------------------------------------------------------------
// Small pure helpers (all unit-tested)
// ---------------------------------------------------------------------------

/** Nearest-rank percentile. Input need not be sorted. Null on empty input. */
export function percentileNearestRank(values: number[], p: number): number | null {
  const xs = values.filter((v) => Number.isFinite(v)).sort((a, b) => a - b)
  if (!xs.length) return null
  const rank = Math.max(1, Math.ceil((p / 100) * xs.length))
  return xs[Math.min(rank, xs.length) - 1]!
}

export function percentiles(values: number[]): {
  p50: number | null
  p95: number | null
  p99: number | null
  n: number
  method: 'nearest-rank'
} {
  const xs = values.filter((v) => Number.isFinite(v))
  return {
    p50: percentileNearestRank(xs, 50),
    p95: percentileNearestRank(xs, 95),
    p99: percentileNearestRank(xs, 99),
    n: xs.length,
    method: 'nearest-rank',
  }
}

export function median(values: number[]): number | null {
  return percentileNearestRank(values, 50)
}

export const ratio = (num: number, den: number): number | null =>
  den > 0 ? num / den : null

/** Standard normal CDF (Abramowitz–Stegun erf approximation). */
export function normalCdf(z: number): number {
  const t = 1 / (1 + 0.2316419 * Math.abs(z))
  const poly =
    t * (0.319381530 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))))
  const pdf = Math.exp(-(z * z) / 2) / Math.sqrt(2 * Math.PI)
  const cdf = 1 - pdf * poly
  return z >= 0 ? cdf : 1 - cdf
}

export interface TwoProportionResult {
  method: 'two-proportion z-test (normal approximation, two-sided)'
  z: number
  pValue: number
  significantAt95: boolean
  /** Minimum per-arm denominator before the approximation is offered at all. */
  minPerArm: 30
}

/**
 * Two-proportion z-test. Returns null when either arm is below the minimum
 * sample — callers must then report "insufficient data for significance"
 * rather than any winner claim.
 */
export function twoProportionZTest(
  x1: number,
  n1: number,
  x2: number,
  n2: number,
): TwoProportionResult | null {
  if (n1 < 30 || n2 < 30 || n1 <= 0 || n2 <= 0) return null
  const p1 = x1 / n1
  const p2 = x2 / n2
  const pooled = (x1 + x2) / (n1 + n2)
  const se = Math.sqrt(pooled * (1 - pooled) * (1 / n1 + 1 / n2))
  if (se === 0) return null
  const z = (p1 - p2) / se
  const pValue = 2 * (1 - normalCdf(Math.abs(z)))
  return {
    method: 'two-proportion z-test (normal approximation, two-sided)',
    z,
    pValue,
    significantAt95: pValue < 0.05,
    minPerArm: 30,
  }
}

/** Minimum-cohort protection: cells under 5 distinct users are suppressed. */
export function suppressSmall<T>(value: T, distinctUsers: number): T | null {
  return distinctUsers < SMALL_COHORT_MIN_USERS ? null : value
}

export const distinctAnons = (rows: AnalyticsRow[]): Set<string> =>
  new Set(rows.map((r) => r.anon_id).filter(Boolean))

export const byEvent = (rows: AnalyticsRow[], name: string): AnalyticsRow[] =>
  rows.filter((r) => r.event === name)

export const inWindow = (rows: AnalyticsRow[], startMs: number, endMs: number): AnalyticsRow[] =>
  rows.filter((r) => r.created_at >= startMs && r.created_at < endMs)

/**
 * Deduplicate retried analytics events: identical (event, anon, session,
 * timestamp, correlation ids + key props) rows collapse to one. Distinct
 * purchase_success rows sharing a transaction_id are handled separately by
 * the reconciliation logic (they are a discrepancy signal, not a retry).
 */
export function dedupeRows(rows: AnalyticsRow[]): AnalyticsRow[] {
  const seen = new Set<string>()
  const out: AnalyticsRow[] = []
  for (const r of rows) {
    const key = [
      r.event,
      r.anon_id,
      r.session_id ?? '',
      r.created_at,
      rowRunId(r) ?? '',
      rowTxId(r) ?? '',
      rowAttemptId(r) ?? '',
      propStr(r, 'stage') ?? '',
      propStr(r, 'classification') ?? '',
    ].join('|')
    if (seen.has(key)) continue
    seen.add(key)
    out.push(r)
  }
  return out
}

// ---------------------------------------------------------------------------
// Filters + query-param parsing
// ---------------------------------------------------------------------------

export interface AnalyticsFilters {
  appVersion: string | null
  /** First-photo arm filter (normalized long name) or raw paywall arm. */
  arm: string | null
  lens: string | null
}

export const NO_FILTERS: AnalyticsFilters = { appVersion: null, arm: null, lens: null }

export function applyFilters(rows: AnalyticsRow[], f: AnalyticsFilters): AnalyticsRow[] {
  return rows.filter((r) => {
    if (f.appVersion && r.app_version !== f.appVersion) return false
    if (f.lens) {
      const lens = rowLens(r)
      if (!lens || lens !== f.lens) return false
    }
    if (f.arm) {
      const a = rowFirstPhotoArm(r) ?? rowPaywallArm(r)
      // Rows that carry no arm attribution cannot be credited to an arm.
      if (!a || (a !== f.arm && propStr(r, 'arm') !== f.arm && propStr(r, 'experiment_arm') !== f.arm)) return false
    }
    return true
  })
}

export interface ParsedAnalyticsQuery {
  startMs: number
  endMs: number
  rangeLabel: string
  filters: AnalyticsFilters
  compare: boolean
}

const RANGE_MS: Record<string, number> = {
  '24h': 24 * 60 * 60 * 1000,
  '7d': 7 * 24 * 60 * 60 * 1000,
  '30d': 30 * 24 * 60 * 60 * 1000,
}

export function parseAnalyticsQuery(
  query: Record<string, unknown>,
  nowMs: number = Date.now(),
): { ok: true; value: ParsedAnalyticsQuery } | { ok: false; error: string; hint: string } {
  const single = (v: unknown): string | null => {
    if (Array.isArray(v)) return null
    return typeof v === 'string' && v.trim() ? v.trim() : null
  }
  // Repeated params arrive as arrays via Express — reject ambiguity.
  for (const k of ['range', 'start', 'end', 'app_version', 'arm', 'lens']) {
    if (Array.isArray(query[k])) {
      return { ok: false, error: 'invalid_params', hint: `Parameter "${k}" must be given at most once.` }
    }
  }
  const rangeRaw = single(query.range)
  const startRaw = single(query.start)
  const endRaw = single(query.end)
  let startMs: number
  let endMs: number
  let rangeLabel: string
  if (startRaw || endRaw) {
    if (!startRaw || !endRaw) {
      return { ok: false, error: 'invalid_range', hint: 'Custom ranges require both start and end (ISO-8601).' }
    }
    startMs = Date.parse(startRaw)
    endMs = Date.parse(endRaw)
    if (!Number.isFinite(startMs) || !Number.isFinite(endMs)) {
      return { ok: false, error: 'invalid_range', hint: 'start/end must be valid ISO-8601 timestamps.' }
    }
    rangeLabel = 'custom'
  } else {
    const range = rangeRaw ?? '7d'
    const dur = RANGE_MS[range]
    if (!dur) {
      return { ok: false, error: 'invalid_range', hint: 'range must be one of 24h, 7d, 30d — or pass start & end.' }
    }
    endMs = nowMs
    startMs = nowMs - dur
    rangeLabel = range
  }
  if (!(startMs < endMs)) {
    return { ok: false, error: 'invalid_range', hint: 'start must be before end.' }
  }
  if (endMs - startMs > MAX_RANGE_MS) {
    return { ok: false, error: 'range_too_large', hint: 'Range must not exceed 92 days.' }
  }
  if (startMs > nowMs + 24 * 60 * 60 * 1000) {
    return { ok: false, error: 'invalid_range', hint: 'start is in the future.' }
  }
  const appVersion = single(query.app_version)
  if (appVersion && (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$/.test(appVersion))) {
    return { ok: false, error: 'invalid_app_version', hint: 'app_version must match [A-Za-z0-9][A-Za-z0-9._-]{0,31}.' }
  }
  const arm = single(query.arm)
  if (arm && arm.length > 64) {
    return { ok: false, error: 'invalid_arm', hint: 'arm is too long.' }
  }
  const lens = single(query.lens)
  if (lens && lens.length > 32) {
    return { ok: false, error: 'invalid_lens', hint: 'lens is too long.' }
  }
  const compareRaw = single(query.compare)
  const compare = compareRaw === null ? true : compareRaw !== 'false' && compareRaw !== '0'
  return {
    ok: true,
    value: { startMs, endMs, rangeLabel, filters: { appVersion, arm, lens }, compare },
  }
}

// ---------------------------------------------------------------------------
// KPI shape + period plumbing
// ---------------------------------------------------------------------------

export interface Kpi {
  value: number | null
  previous: number | null
  /** value - previous (percentage points for rates). Null if either is null. */
  delta: number | null
  /** (value - previous) / |previous|. Null when undefined. */
  deltaRel: number | null
  numerator: number | null
  denominator: number | null
  /** Sample size behind the value (runs, attempts, users — labeled by `unit`). */
  n: number
  unit: string
  /** False = the underlying events do not exist in this period (≠ zero). */
  instrumented: boolean
  note?: string
}

export function makeKpi(args: {
  value: number | null
  previous?: number | null
  numerator?: number | null
  denominator?: number | null
  n: number
  unit: string
  instrumented?: boolean
  note?: string
}): Kpi {
  const value = args.value
  const previous = args.previous ?? null
  const delta = value !== null && previous !== null ? value - previous : null
  const deltaRel = delta !== null && previous !== null && previous !== 0 ? delta / Math.abs(previous) : null
  return {
    value,
    previous,
    delta,
    deltaRel,
    numerator: args.numerator ?? null,
    denominator: args.denominator ?? null,
    n: args.n,
    unit: args.unit,
    instrumented: args.instrumented ?? true,
    ...(args.note ? { note: args.note } : {}),
  }
}

export interface Period {
  startMs: number
  endMs: number
}

export const prevPeriod = (p: Period): Period => ({
  startMs: p.startMs - (p.endMs - p.startMs),
  endMs: p.startMs,
})

export const dayKey = (ms: number): string => new Date(ms).toISOString().slice(0, 10)

export function freshnessOf(rows: AnalyticsRow[]): string | null {
  if (!rows.length) return null
  return new Date(Math.max(...rows.map((r) => r.created_at))).toISOString()
}

export function warningsFor(rows: AnalyticsRow[], extra: string[] = []): string[] {
  const w = [...extra]
  if (!rows.length) w.push('no_data: no telemetry rows in this period for app=photo-recipes')
  return w
}

// ---------------------------------------------------------------------------
// Retention (cohort = install_devices.first_seen_at; activity = any event)
// ---------------------------------------------------------------------------

/**
 * Retention for the cohort installed on the UTC day starting `cohortDayMs`:
 * retained on day +offsetDays when the user has any event in that UTC day.
 * Returns nulls (not 0) when the cohort is too small (<30) or its retention
 * day has not fully elapsed by `nowMs` — a young cohort is "insufficient
 * data", not zero retention.
 */
export function cohortRetention(
  installs: InstallRow[] | null,
  allRows: AnalyticsRow[],
  cohortDayMs: number,
  offsetDays: number,
  nowMs: number,
): { rate: number | null; cohort: number; reason: string | null } {
  if (!installs) return { rate: null, cohort: 0, reason: 'install_devices unavailable' }
  const dayMs = 24 * 60 * 60 * 1000
  const cohort = installs.filter(
    (i) => i.first_seen_ms >= cohortDayMs && i.first_seen_ms < cohortDayMs + dayMs,
  )
  const retainStart = cohortDayMs + offsetDays * dayMs
  if (retainStart + dayMs > nowMs) {
    return { rate: null, cohort: cohort.length, reason: 'cohort retention day has not fully elapsed' }
  }
  if (cohort.length < 30) {
    return { rate: null, cohort: cohort.length, reason: 'cohort too small (<30 installs) for a retention rate' }
  }
  const activeThatDay = new Set(
    allRows
      .filter((r) => r.created_at >= retainStart && r.created_at < retainStart + dayMs)
      .map((r) => r.anon_id),
  )
  const retained = cohort.filter((i) => activeThatDay.has(i.anon_id)).length
  return { rate: ratio(retained, cohort.length), cohort: cohort.length, reason: null }
}

// ---------------------------------------------------------------------------
// A. Executive overview
// ---------------------------------------------------------------------------

export interface OverviewResult {
  dau: Kpi
  wau: Kpi
  newInstalls: Kpi
  cameraActivationRate: Kpi
  firstOptimizedWithin5Min: Kpi
  optimizeToCapture: Kpi
  retentionD1: { rate: number | null; cohort: number; reason: string | null }
  retentionD7: { rate: number | null; cohort: number; reason: string | null }
  paywallToPurchase: Kpi
  verifiedPurchases: Kpi
  aoLatency: {
    p50: number | null
    p95: number | null
    p99: number | null
    n: number
    previous: { p50: number | null; p95: number | null; p99: number | null; n: number }
    instrumented: boolean
    method: string
    note: string
  }
  captureFailureRate: Kpi
  trend: Array<{
    day: string
    dau: number
    verifiedPurchases: number
    activationsWithin5: number
  }>
  /** Legacy aggregates — NOT funnels; kept separate on purpose (see header). */
  legacy: {
    autoOptimizeStartEvents: number
    autoOptimizeSuccessEvents: number
    optimizePhotoCapturedEvents: number
    optimizeCaptureAbandonedEvents: number
    shutterTapEvents: number
    captureSuccessEvents: number
    note: string
  }
}

const CAPTURE_FAILURE_EVENTS = ['capture_failed', 'capture_failure', 'camera_capture_failed']

function dauOn(rows: AnalyticsRow[], dayStartMs: number): number {
  const dayMs = 24 * 60 * 60 * 1000
  return distinctAnons(rows.filter((r) => r.created_at >= dayStartMs && r.created_at < dayStartMs + dayMs)).size
}

function latencySummaryRows(rows: AnalyticsRow[]): AnalyticsRow[] {
  return byEvent(rows, 'optimize_latency_summary').filter((r) => propNum(r, 'total_ms') !== null)
}

export function isOptimizeSuccessOutcome(outcome: string | null): boolean {
  if (!outcome) return false
  const o = outcome.toLowerCase()
  return o === 'success' || o === 'succeeded' || o === 'complete' || o === 'completed' || o === 'ok'
}
export function isOptimizeFailureOutcome(outcome: string | null): boolean {
  if (!outcome) return false
  const o = outcome.toLowerCase()
  return o === 'failure' || o === 'failed' || o === 'error' || o === 'fail'
}
export function isOptimizeCancelledOutcome(outcome: string | null): boolean {
  if (!outcome) return false
  const o = outcome.toLowerCase()
  return o === 'cancelled' || o === 'canceled' || o === 'cancel' || o === 'cancelled_by_user'
}

/** Runs (by run_id) that succeeded per optimize_latency_summary. */
export function successfulRunIds(rows: AnalyticsRow[]): Map<string, AnalyticsRow> {
  const out = new Map<string, AnalyticsRow>()
  for (const r of latencySummaryRows(rows)) {
    const id = rowRunId(r)
    if (id && isOptimizeSuccessOutcome(propStr(r, 'outcome'))) out.set(id, r)
  }
  return out
}

/** Correlated optimize→capture: success runs with an afterComplete capture. */
export function correlatedCaptureRuns(rows: AnalyticsRow[]): {
  successRuns: number
  capturedRuns: number
  instrumented: boolean
} {
  const success = successfulRunIds(rows)
  const captured = new Set<string>()
  for (const r of byEvent(rows, 'capture_after_optimize')) {
    const id = rowRunId(r)
    if (!id || !success.has(id)) continue
    if (propStr(r, 'classification') !== 'afterComplete') continue
    // The capture must not precede the run's terminal summary.
    if (r.created_at < success.get(id)!.created_at) continue
    captured.add(id)
  }
  const instrumented = success.size > 0 || byEvent(rows, 'capture_after_optimize').length > 0
  return { successRuns: success.size, capturedRuns: captured.size, instrumented }
}

function firstOptimized5(rows: AnalyticsRow[], installs: InstallRow[] | null): {
  numerator: number
  denominator: number
  eligibleSource: string
  instrumented: boolean
} {
  const assigned = distinctAnons(byEvent(rows, 'first_photo_experiment_assigned'))
  const activations = byEvent(rows, 'first_photo_activation_complete').filter(
    (r) => propBool(r, 'within_window') === true,
  )
  let denominatorSet: Set<string>
  let eligibleSource: string
  if (assigned.size > 0) {
    denominatorSet = assigned
    eligibleSource = 'experiment_assignment'
  } else if (installs && installs.length) {
    denominatorSet = new Set(installs.map((i) => i.anon_id))
    eligibleSource = 'new_installs_in_period'
  } else {
    denominatorSet = new Set()
    eligibleSource = 'none'
  }
  const numerator = new Set(
    activations.filter((r) => denominatorSet.has(r.anon_id)).map((r) => r.anon_id),
  ).size
  return {
    numerator,
    denominator: denominatorSet.size,
    eligibleSource,
    instrumented: byEvent(rows, 'first_photo_activation_complete').length > 0 || assigned.size > 0,
  }
}

function captureFailure(rows: AnalyticsRow[]): { failures: number; attempts: number; instrumented: boolean } {
  const failures = rows.filter((r) => CAPTURE_FAILURE_EVENTS.includes(r.event)).length
  const successes = byEvent(rows, 'capture_success').length
  const instrumented = failures > 0 || rows.some((r) => CAPTURE_FAILURE_EVENTS.includes(r.event))
  // capture_success alone cannot yield a failure rate (no failure event is
  // emitted by the client today) — stay uninstrumented until it exists.
  return { failures, attempts: failures + successes, instrumented }
}

export function computeOverview(
  cur: AnalyticsRow[],
  prev: AnalyticsRow[],
  installsCur: InstallRow[] | null,
  installsPrev: InstallRow[] | null,
  allInstalls: InstallRow[] | null,
  period: Period,
  nowMs: number = Date.now(),
): OverviewResult {
  const dayMs = 24 * 60 * 60 * 1000
  const lastDayStart = Math.floor((period.endMs - 1) / dayMs) * dayMs
  const prevLastDayStart = Math.floor((prevPeriod(period).endMs - 1) / dayMs) * dayMs

  const dauCur = dauOn(cur, lastDayStart)
  const dauPrev = dauOn(prev, prevLastDayStart)
  const wauCur = distinctAnons(inWindow(cur, period.endMs - 7 * dayMs, period.endMs)).size
  const wauPrev = distinctAnons(inWindow(prev, period.startMs - 7 * dayMs, period.startMs)).size

  const newCur = installsCur ? installsCur.length : null
  const newPrev = installsPrev ? installsPrev.length : null

  const camUsers = (rows: AnalyticsRow[]) => distinctAnons(byEvent(rows, 'camera_open'))
  const sessionUsers = (rows: AnalyticsRow[]) => {
    const s = distinctAnons(byEvent(rows, 'session_start'))
    return s.size > 0 ? s : distinctAnons(rows)
  }
  const camRate = (rows: AnalyticsRow[]) => ratio(camUsers(rows).size, sessionUsers(rows).size)

  const foCur = firstOptimized5(cur, installsCur)
  const foPrev = firstOptimized5(prev, installsPrev)

  const ocCur = correlatedCaptureRuns(cur)
  const ocPrev = correlatedCaptureRuns(prev)

  const paywallUsers = (rows: AnalyticsRow[]) => distinctAnons(byEvent(rows, 'paywall_view'))
  const verifiedUsers = (rows: AnalyticsRow[]) =>
    distinctAnons([
      ...byEvent(rows, 'purchase_verified'),
      ...byEvent(rows, 'purchase_success').filter((r) => propNum(r, 'telemetry_v') === 2),
    ])
  const verifiedTx = (rows: AnalyticsRow[]) =>
    new Set(
      [...byEvent(rows, 'purchase_verified'), ...byEvent(rows, 'purchase_success')]
        .map((r) => rowTxId(r))
        .filter((x): x is string => Boolean(x)),
    )

  const latCur = percentiles(latencySummaryRows(cur).map((r) => propNum(r, 'total_ms')!))
  const latPrev = percentiles(latencySummaryRows(prev).map((r) => propNum(r, 'total_ms')!))

  const cfCur = captureFailure(cur)
  const cfPrev = captureFailure(prev)

  // Retention cohorts anchor on the last fully-elapsed days before period end.
  const d1 = cohortRetention(allInstalls, [...prev, ...cur], lastDayStart - 2 * dayMs, 1, nowMs)
  const d7 = cohortRetention(allInstalls, [...prev, ...cur], lastDayStart - 8 * dayMs, 7, nowMs)

  // Daily trend across the current period (UTC days).
  const trend: OverviewResult['trend'] = []
  for (let d = Math.floor(period.startMs / dayMs) * dayMs; d < period.endMs; d += dayMs) {
    const dayRows = inWindow(cur, d, d + dayMs)
    trend.push({
      day: dayKey(d),
      dau: distinctAnons(dayRows).size,
      verifiedPurchases: verifiedTx(dayRows).size,
      activationsWithin5: distinctAnons(
        byEvent(dayRows, 'first_photo_activation_complete').filter(
          (r) => propBool(r, 'within_window') === true,
        ),
      ).size,
    })
  }

  return {
    dau: makeKpi({
      value: dauCur, previous: dauPrev, n: dauCur, unit: 'distinct anon_id on the last day of the period',
    }),
    wau: makeKpi({
      value: wauCur, previous: wauPrev, n: wauCur, unit: 'distinct anon_id in the trailing 7 days of the period',
    }),
    newInstalls: makeKpi({
      value: newCur,
      previous: newPrev,
      n: newCur ?? 0,
      unit: 'install_devices rows first seen in the period',
      instrumented: installsCur !== null,
      note: installsCur === null ? 'install_devices unavailable — new installs are insufficient_data, not zero' : undefined,
    }),
    cameraActivationRate: makeKpi({
      value: camRate(cur),
      previous: camRate(prev),
      numerator: camUsers(cur).size,
      denominator: sessionUsers(cur).size,
      n: sessionUsers(cur).size,
      unit: 'distinct users with camera_open / distinct users with session_start (fallback: any event)',
    }),
    firstOptimizedWithin5Min: makeKpi({
      value: ratio(foCur.numerator, foCur.denominator),
      previous: ratio(foPrev.numerator, foPrev.denominator),
      numerator: foCur.numerator,
      denominator: foCur.denominator,
      n: foCur.denominator,
      unit: `unique users with first_photo_activation_complete(within_window=true) / eligible unique new users (source: ${foCur.eligibleSource})`,
      instrumented: foCur.instrumented,
      note: foCur.instrumented ? undefined : 'first_photo_activation_complete / assignment events not present in this period',
    }),
    optimizeToCapture: makeKpi({
      value: ratio(ocCur.capturedRuns, ocCur.successRuns),
      previous: ratio(ocPrev.capturedRuns, ocPrev.successRuns),
      numerator: ocCur.capturedRuns,
      denominator: ocCur.successRuns,
      n: ocCur.successRuns,
      unit: 'correlated runs: optimize_latency_summary(outcome=success) with capture_after_optimize(classification=afterComplete) on the same run_id',
      instrumented: ocCur.instrumented,
      note: ocCur.instrumented ? undefined : 'no run_id-correlated optimize/capture data in this period — see legacy aggregates (not a funnel)',
    }),
    retentionD1: d1,
    retentionD7: d7,
    paywallToPurchase: makeKpi({
      value: ratio(verifiedUsers(cur).size, paywallUsers(cur).size),
      previous: ratio(verifiedUsers(prev).size, paywallUsers(prev).size),
      numerator: verifiedUsers(cur).size,
      denominator: paywallUsers(cur).size,
      n: paywallUsers(cur).size,
      unit: 'distinct users with purchase_verified (or purchase_success telemetry_v=2) / distinct paywall_view users',
    }),
    verifiedPurchases: makeKpi({
      value: verifiedTx(cur).size,
      previous: verifiedTx(prev).size,
      n: verifiedTx(cur).size,
      unit: 'distinct transaction_id across purchase_verified + purchase_success — a count of transactions, NOT revenue',
    }),
    aoLatency: {
      p50: latCur.p50,
      p95: latCur.p95,
      p99: latCur.p99,
      n: latCur.n,
      previous: { p50: latPrev.p50, p95: latPrev.p95, p99: latPrev.p99, n: latPrev.n },
      instrumented: latCur.n > 0,
      method: 'nearest-rank over optimize_latency_summary.total_ms (pooled across versions — see per-version breakdowns in optimize-performance; do not compare pooled figures across version-mix changes)',
      note: latCur.n > 0 ? '' : 'optimize_latency_summary not present in this period',
    },
    captureFailureRate: makeKpi({
      value: cfCur.instrumented ? ratio(cfCur.failures, cfCur.attempts) : null,
      previous: cfPrev.instrumented ? ratio(cfPrev.failures, cfPrev.attempts) : null,
      numerator: cfCur.instrumented ? cfCur.failures : null,
      denominator: cfCur.instrumented ? cfCur.attempts : null,
      n: cfCur.attempts,
      unit: 'capture_failed events / (capture_failed + capture_success) events',
      instrumented: cfCur.instrumented,
      note: cfCur.instrumented
        ? undefined
        : 'the client emits capture_success but no capture-failure event today — a failure rate cannot be computed honestly',
    }),
    trend,
    legacy: {
      autoOptimizeStartEvents: byEvent(cur, 'auto_optimize_start').length,
      autoOptimizeSuccessEvents: byEvent(cur, 'auto_optimize_success').length,
      optimizePhotoCapturedEvents: byEvent(cur, 'optimize_photo_captured').length,
      optimizeCaptureAbandonedEvents: byEvent(cur, 'optimize_capture_abandoned').length,
      shutterTapEvents: byEvent(cur, 'shutter_tap').length,
      captureSuccessEvents: byEvent(cur, 'capture_success').length,
      note: 'Legacy aggregate event counts (mixed web/iOS emission, no run correlation). Never divide these into a funnel — see docs/activation-experiments.md §1.',
    },
  }
}

// ---------------------------------------------------------------------------
// B. First-photo activation experiment
// ---------------------------------------------------------------------------

export const FIRST_PHOTO_ARMS = ['post_capture_v1', 'pre_capture_guided_v1'] as const

export interface ActivationArmResult {
  arm: string
  eligibleUsers: number
  assignedUsers: number
  steps: Array<{ stage: string; users: number | null; applicable: boolean; conversionFromAssigned: number | null }>
  primary: { numerator: number; denominator: number; rate: number | null }
  medianTimeToFirstOptimizedSec: number | null
  captureFailures: number | null
  retentionD1: number | null
  retentionD7: number | null
}

export interface ActivationResult {
  arms: ActivationArmResult[]
  difference: {
    absolutePp: number | null
    relativeLift: number | null
    significance: TwoProportionResult | null
    significanceNote: string
  }
  instrumented: boolean
  eligibilityNote: string
}

function armRetention(
  assignedAt: Map<string, number>,
  allRows: AnalyticsRow[],
  offsetDays: number,
  periodEndMs: number,
): number | null {
  const dayMs = 24 * 60 * 60 * 1000
  const eligible = [...assignedAt.entries()].filter(
    ([, t]) => t + (offsetDays + 1) * dayMs <= periodEndMs,
  )
  if (eligible.length < 30) return null
  const retained = eligible.filter(([anon, t]) =>
    allRows.some(
      (r) => r.anon_id === anon && r.created_at >= t + offsetDays * dayMs && r.created_at < t + (offsetDays + 1) * dayMs,
    ),
  ).length
  return ratio(retained, eligible.length)
}

export function computeActivation(cur: AnalyticsRow[], period: Period): ActivationResult {
  const assignedRows = byEvent(cur, 'first_photo_experiment_assigned')
  const arms: ActivationArmResult[] = FIRST_PHOTO_ARMS.map((arm) => {
    const isTreatment = arm === 'pre_capture_guided_v1'
    const assigned = assignedRows.filter((r) => rowFirstPhotoArm(r) === arm)
    const assignedAt = new Map<string, number>()
    for (const r of assigned) {
      if (!assignedAt.has(r.anon_id) || r.created_at < assignedAt.get(r.anon_id)!) {
        assignedAt.set(r.anon_id, r.created_at)
      }
    }
    const eligible = new Set(assignedAt.keys())
    /** Users with `event` at/after their assignment (sequence enforced). */
    const afterAssigned = (event: string): AnalyticsRow[] =>
      cur.filter(
        (r) =>
          r.event === event &&
          eligible.has(r.anon_id) &&
          (rowFirstPhotoArm(r) === arm || rowFirstPhotoArm(r) === null) &&
          r.created_at >= (assignedAt.get(r.anon_id) ?? 0),
      )
    const usersOf = (rows: AnalyticsRow[]) => distinctAnons(rows).size
    const guidanceView = usersOf(afterAssigned('first_photo_guidance_view'))
    const guidanceSkip = usersOf(afterAssigned('first_photo_guidance_skip'))
    const start = usersOf(afterAssigned('first_photo_preoptimize_start'))
    const complete = usersOf(afterAssigned('first_photo_preoptimize_complete'))
    const activationRows = afterAssigned('first_photo_activation_complete')
    const activated = usersOf(activationRows)
    const within5 = usersOf(activationRows.filter((r) => propBool(r, 'within_window') === true))
    const elapsed = activationRows
      .map((r) => propNum(r, 'elapsed_sec'))
      .filter((x): x is number => x !== null)
    const failureEvents = afterAssigned('capture_failed')
    const hasFailureInstrumentation = cur.some((r) => r.event === 'capture_failed')
    const steps: ActivationArmResult['steps'] = [
      { stage: 'assigned_eligible', users: eligible.size, applicable: true, conversionFromAssigned: eligible.size ? 1 : null },
      { stage: 'guidance_view', users: isTreatment ? guidanceView : null, applicable: isTreatment, conversionFromAssigned: isTreatment ? ratio(guidanceView, eligible.size) : null },
      { stage: 'guidance_skip', users: isTreatment ? guidanceSkip : null, applicable: isTreatment, conversionFromAssigned: isTreatment ? ratio(guidanceSkip, eligible.size) : null },
      { stage: 'preoptimize_start', users: isTreatment ? start : null, applicable: isTreatment, conversionFromAssigned: isTreatment ? ratio(start, eligible.size) : null },
      { stage: 'preoptimize_complete', users: isTreatment ? complete : null, applicable: isTreatment, conversionFromAssigned: isTreatment ? ratio(complete, eligible.size) : null },
      { stage: 'activation_complete', users: activated, applicable: true, conversionFromAssigned: ratio(activated, eligible.size) },
      { stage: 'activation_within_5min', users: within5, applicable: true, conversionFromAssigned: ratio(within5, eligible.size) },
    ]
    return {
      arm,
      eligibleUsers: eligible.size,
      assignedUsers: eligible.size,
      steps,
      primary: { numerator: within5, denominator: eligible.size, rate: ratio(within5, eligible.size) },
      medianTimeToFirstOptimizedSec: median(elapsed),
      captureFailures: hasFailureInstrumentation ? failureEvents.length : null,
      retentionD1: armRetention(assignedAt, cur, 1, period.endMs),
      retentionD7: armRetention(assignedAt, cur, 7, period.endMs),
    }
  })
  const control = arms[0]!
  const treatment = arms[1]!
  const absolutePp =
    control.primary.rate !== null && treatment.primary.rate !== null
      ? treatment.primary.rate - control.primary.rate
      : null
  const relativeLift =
    absolutePp !== null && control.primary.rate !== null && control.primary.rate !== 0
      ? absolutePp / control.primary.rate
      : null
  const significance = twoProportionZTest(
    treatment.primary.numerator,
    treatment.primary.denominator,
    control.primary.numerator,
    control.primary.denominator,
  )
  return {
    arms,
    difference: {
      absolutePp,
      relativeLift,
      significance,
      significanceNote: significance
        ? 'Normal-approximation two-proportion z-test, two-sided, α=0.05. Assumes independent assignments and no peeking correction — treat as directional, not a ship decision on its own.'
        : 'insufficient data for significance: the z-test is only offered with ≥30 eligible users per arm; raw rates are shown without any winner claim',
    },
    instrumented: assignedRows.length > 0,
    eligibilityNote:
      'Denominator = unique users with a first_photo_experiment_assigned event in the period (the only server-visible eligibility signal). Users the client deemed ineligible never emit assignment, so they are excluded — but assignment is emitted at first computation, which may lag true eligibility; see docs/admin-analytics.md.',
  }
}

// ---------------------------------------------------------------------------
// C. Capture-ready (correlated by run_id ONLY)
// ---------------------------------------------------------------------------

export interface CaptureBreakdownCell {
  key: string
  runs: number
  capturedRuns: number | null
  conversion: number | null
  users: number
  suppressed: boolean
}

export interface CaptureResult {
  instrumented: boolean
  runIdCoverage: { summariesWithRunId: number; summariesTotal: number }
  funnel: Array<{ stage: string; runs: number; conversionFromPrev: number | null }>
  successRuns: number
  readyRuns: number
  shutterTapRuns: number
  capturedRuns: number
  abandonedLegacyEvents: number
  noCaptureRecordedRuns: number
  medianSecondsOptimizeCompleteToShutter: number | null
  captureErrors: number | null
  undoEvents: number
  resetEvents: number
  breakdowns: { byLens: CaptureBreakdownCell[]; byTrigger: CaptureBreakdownCell[]; byAppVersion: CaptureBreakdownCell[]; byArm: CaptureBreakdownCell[] }
}

function captureBreakdown(
  rows: AnalyticsRow[],
  success: Map<string, AnalyticsRow>,
  capturedIds: Set<string>,
  keyOf: (summary: AnalyticsRow) => string | null,
): CaptureBreakdownCell[] {
  const cells = new Map<string, { runs: Set<string>; captured: Set<string>; users: Set<string> }>()
  for (const [id, summary] of success) {
    const key = keyOf(summary) ?? 'unknown'
    const cell = cells.get(key) ?? { runs: new Set(), captured: new Set(), users: new Set() }
    cell.runs.add(id)
    cell.users.add(summary.anon_id)
    if (capturedIds.has(id)) cell.captured.add(id)
    cells.set(key, cell)
  }
  void rows
  return [...cells.entries()]
    .map(([key, c]) => {
      const suppressed = c.users.size < SMALL_COHORT_MIN_USERS
      return {
        key,
        runs: c.runs.size,
        capturedRuns: suppressed ? null : c.captured.size,
        conversion: suppressed ? null : ratio(c.captured.size, c.runs.size),
        users: c.users.size,
        suppressed,
      }
    })
    .sort((a, b) => b.runs - a.runs)
}

export function computeCapture(cur: AnalyticsRow[]): CaptureResult {
  const summaries = latencySummaryRows(cur)
  const success = successfulRunIds(cur)
  // Ordered, correlated chain per run: summary(terminal) ≤ ready ≤ tap ≤ capture.
  const readyAt = new Map<string, number>()
  for (const r of byEvent(cur, 'capture_ready_view')) {
    const id = rowRunId(r)
    if (!id || !success.has(id)) continue
    if (r.created_at < success.get(id)!.created_at) continue
    if (!readyAt.has(id) || r.created_at < readyAt.get(id)!) readyAt.set(id, r.created_at)
  }
  const tapAt = new Map<string, number>()
  for (const r of byEvent(cur, 'capture_ready_shutter_tap')) {
    const id = rowRunId(r)
    if (!id || !readyAt.has(id)) continue
    if (r.created_at < readyAt.get(id)!) continue
    if (!tapAt.has(id) || r.created_at < tapAt.get(id)!) tapAt.set(id, r.created_at)
  }
  const capturedIds = new Set<string>()
  const secondsAfterReady: number[] = []
  for (const r of byEvent(cur, 'capture_after_optimize')) {
    const id = rowRunId(r)
    if (!id || !readyAt.has(id)) continue
    if (propStr(r, 'classification') !== 'afterComplete') continue
    if (r.created_at < readyAt.get(id)!) continue
    capturedIds.add(id)
    const s = propNum(r, 'seconds_after_ready')
    if (s !== null) secondsAfterReady.push(s)
  }
  const funnelStages: Array<[string, number]> = [
    ['optimize_success_runs', success.size],
    ['capture_ready_view', readyAt.size],
    ['capture_ready_shutter_tap', tapAt.size],
    ['capture_after_optimize_afterComplete', capturedIds.size],
  ]
  const breakdownKey = {
    byLens: (s: AnalyticsRow) => rowLens(s),
    byTrigger: (s: AnalyticsRow) => propStr(s, 'trigger'),
    byAppVersion: (s: AnalyticsRow) => s.app_version,
    byArm: (s: AnalyticsRow) => rowFirstPhotoArm(s),
  }
  return {
    instrumented: success.size > 0 || readyAt.size > 0,
    runIdCoverage: {
      summariesWithRunId: summaries.filter((r) => rowRunId(r)).length,
      summariesTotal: summaries.length,
    },
    funnel: funnelStages.map(([stage, runs], i) => ({
      stage,
      runs,
      conversionFromPrev: i === 0 ? null : ratio(runs, funnelStages[i - 1]![1]),
    })),
    successRuns: success.size,
    readyRuns: readyAt.size,
    shutterTapRuns: tapAt.size,
    capturedRuns: capturedIds.size,
    abandonedLegacyEvents: byEvent(cur, 'optimize_capture_abandoned').length,
    noCaptureRecordedRuns: [...readyAt.keys()].filter((id) => !capturedIds.has(id)).length,
    medianSecondsOptimizeCompleteToShutter: median(secondsAfterReady),
    captureErrors: cur.some((r) => CAPTURE_FAILURE_EVENTS.includes(r.event))
      ? cur.filter((r) => CAPTURE_FAILURE_EVENTS.includes(r.event)).length
      : null,
    undoEvents: byEvent(cur, 'optimize_undone').length,
    resetEvents: cur.filter((r) => r.event === 'camera_reset' || r.event === 'ao_reset_on_flip').length,
    breakdowns: {
      byLens: captureBreakdown(cur, success, capturedIds, breakdownKey.byLens),
      byTrigger: captureBreakdown(cur, success, capturedIds, breakdownKey.byTrigger),
      byAppVersion: captureBreakdown(cur, success, capturedIds, breakdownKey.byAppVersion),
      byArm: captureBreakdown(cur, success, capturedIds, breakdownKey.byArm),
    },
  }
}

// ---------------------------------------------------------------------------
// D. Paywall & revenue (ordered funnel; revenue only via passed-in snapshots)
// ---------------------------------------------------------------------------

export const PAYWALL_STAGES = [
  'paywall_view',
  'paywall_plan_select',
  'purchase_start',
  'purchase_verified',
  'entitlement_activated',
] as const

export interface PaywallSegment {
  key: string
  viewers: number
  suppressed: boolean
  stages: Record<string, number | null>
  conversionViewToVerified: number | null
}

/**
 * Ordered funnel per (anon_id, session_id): a stage counts only when it
 * occurs after the previous stage within the SAME session — cross-session
 * progression is rejected (a purchase in a later session is not attributed
 * to an earlier session's paywall view). Rows without session_id form their
 * own per-anon group and are included only in the labeled legacy fallback.
 */
export function orderedPaywallFunnel(
  rows: AnalyticsRow[],
  groupFilter?: (viewRow: AnalyticsRow) => boolean,
): Record<string, Set<string>> {
  const reached: Record<string, Set<string>> = {}
  for (const s of PAYWALL_STAGES) reached[s] = new Set()
  const groups = new Map<string, AnalyticsRow[]>()
  for (const r of rows) {
    if (!PAYWALL_STAGES.includes(r.event as (typeof PAYWALL_STAGES)[number])) continue
    const key = `${r.anon_id}|${r.session_id ?? ''}`
    const arr = groups.get(key) ?? []
    arr.push(r)
    groups.set(key, arr)
  }
  for (const arr of groups.values()) {
    arr.sort((a, b) => a.created_at - b.created_at)
    const view = arr.find((r) => r.event === 'paywall_view')
    if (!view) continue
    if (groupFilter && !groupFilter(view)) continue
    let stageIdx = 0
    let lastTs = -Infinity
    const anon = arr[0]!.anon_id
    for (const r of arr) {
      if (stageIdx >= PAYWALL_STAGES.length) break
      if (r.event === PAYWALL_STAGES[stageIdx] && r.created_at >= lastTs) {
        reached[PAYWALL_STAGES[stageIdx]!]!.add(anon)
        lastTs = r.created_at
        stageIdx++
      }
    }
  }
  return reached
}

export interface PaywallResult {
  funnel: Array<{ stage: string; users: number; conversionFromPrev: number | null; conversionFromFirst: number | null }>
  uniqueViewers: number
  uniquePurchasersVerified: number
  viewToVerifiedConversion: number | null
  cancellations: number
  pending: number
  failed: number
  restores: number
  verifiedTrialStarts: number | null
  paidStarts: number
  segments: {
    byArm: PaywallSegment[]
    byTrigger: PaywallSegment[]
    byProduct: PaywallSegment[]
    byAppVersion: PaywallSegment[]
    byUserType: PaywallSegment[]
  }
  legacyFallback: { note: string; purchaseSuccessEvents: number; purchaseSuccessV2Events: number }
}

function segmentize(
  rows: AnalyticsRow[],
  keyOf: (viewRow: AnalyticsRow) => string | null,
): PaywallSegment[] {
  const keys = new Set<string>()
  for (const v of byEvent(rows, 'paywall_view')) keys.add(keyOf(v) ?? 'unknown')
  const out: PaywallSegment[] = []
  for (const key of keys) {
    const reached = orderedPaywallFunnel(rows, (v) => (keyOf(v) ?? 'unknown') === key)
    const viewers = reached['paywall_view']!.size
    const suppressed = viewers < SMALL_COHORT_MIN_USERS
    const stages: Record<string, number | null> = {}
    for (const s of PAYWALL_STAGES) stages[s] = suppressed ? null : reached[s]!.size
    out.push({
      key,
      viewers,
      suppressed,
      stages,
      conversionViewToVerified: suppressed
        ? null
        : ratio(reached['purchase_verified']!.size, viewers),
    })
  }
  return out.sort((a, b) => b.viewers - a.viewers)
}

export function computePaywall(cur: AnalyticsRow[]): PaywallResult {
  const reached = orderedPaywallFunnel(cur)
  const stagesCounts = PAYWALL_STAGES.map((s) => reached[s]!.size)
  const distinctAttempts = (event: string) => {
    const ids = new Set<string>()
    const anonFallback = new Set<string>()
    for (const r of byEvent(cur, event)) {
      const a = rowAttemptId(r)
      if (a) ids.add(a)
      else anonFallback.add(`${r.anon_id}|${r.session_id ?? ''}`)
    }
    return ids.size + anonFallback.size
  }
  const verifiedRows = byEvent(cur, 'purchase_verified')
  const trialStarts = verifiedRows.filter(
    (r) => propBool(r, 'is_trial') === true || propBool(r, 'trial') === true || propStr(r, 'entitlement_type') === 'trial',
  )
  const hasTrialSignal = verifiedRows.some(
    (r) => propBool(r, 'is_trial') !== null || propBool(r, 'trial') !== null || propStr(r, 'entitlement_type') !== null,
  )
  return {
    funnel: PAYWALL_STAGES.map((stage, i) => ({
      stage,
      users: stagesCounts[i]!,
      conversionFromPrev: i === 0 ? null : ratio(stagesCounts[i]!, stagesCounts[i - 1]!),
      conversionFromFirst: i === 0 ? null : ratio(stagesCounts[i]!, stagesCounts[0]!),
    })),
    uniqueViewers: stagesCounts[0]!,
    uniquePurchasersVerified: distinctAnons(verifiedRows).size,
    viewToVerifiedConversion: ratio(distinctAnons(verifiedRows).size, stagesCounts[0]!),
    cancellations: distinctAttempts('purchase_cancelled'),
    pending: distinctAttempts('purchase_pending'),
    failed: distinctAttempts('purchase_failed'),
    restores: byEvent(cur, 'purchase_restore').length,
    verifiedTrialStarts: hasTrialSignal ? new Set(trialStarts.map((r) => rowTxId(r) ?? r.anon_id)).size : null,
    paidStarts: new Set(verifiedRows.map((r) => rowTxId(r)).filter(Boolean)).size,
    segments: {
      byArm: segmentize(cur, (v) => rowPaywallArm(v)),
      byTrigger: segmentize(cur, (v) => propStr(v, 'trigger') ?? propStr(v, 'paywall_id')),
      byProduct: segmentize(cur, (v) => {
        const start = cur.find(
          (r) => r.event === 'purchase_start' && r.anon_id === v.anon_id && r.session_id === v.session_id,
        )
        return start ? propStr(start, 'product_id') : null
      }),
      byAppVersion: segmentize(cur, (v) => v.app_version),
      byUserType: segmentize(cur, (v) => {
        const n = propBool(v, 'is_new_user')
        return n === null ? null : n ? 'new' : 'returning'
      }),
    },
    legacyFallback: {
      note: 'purchase_success WITHOUT telemetry_v=2 is a legacy client event (fired on StoreKit return true, pre-verification gating). It is never used as revenue or as a verified-purchase count.',
      purchaseSuccessEvents: byEvent(cur, 'purchase_success').length,
      purchaseSuccessV2Events: byEvent(cur, 'purchase_success').filter((r) => propNum(r, 'telemetry_v') === 2).length,
    },
  }
}

// ---------------------------------------------------------------------------
// E. Purchase reconciliation (transaction_id sets; read-only, no receipts)
// ---------------------------------------------------------------------------

export interface ReconciliationRow {
  transaction_id: string
  product_id: string | null
  verified_at: string | null
  entitlement_at: string | null
  issue: 'verified_without_entitlement' | 'entitlement_without_verified' | 'duplicate_purchase_success'
}

export interface ReconciliationResult {
  counts: {
    purchaseStarts: number
    startsWithoutTerminalOutcome: number
    verifiedTransactions: number
    entitlementActivations: number
    purchaseSuccessV2Transactions: number
    duplicateSuccessTransactions: number
    verifiedWithoutEntitlement: number
    entitlementWithoutVerifiedOrRestore: number
  }
  discrepancyRate: number | null
  tolerance: number
  withinTolerance: boolean | null
  rows: ReconciliationRow[]
  instrumented: boolean
  notes: string[]
}

const TERMINAL_PURCHASE_EVENTS = [
  'purchase_verified',
  'purchase_success',
  'purchase_cancelled',
  'purchase_pending',
  'purchase_failed',
]

export function computeReconciliation(cur: AnalyticsRow[]): ReconciliationResult {
  const notes: string[] = []
  const verified = new Map<string, AnalyticsRow>()
  for (const r of byEvent(cur, 'purchase_verified')) {
    const tx = rowTxId(r)
    if (tx && !verified.has(tx)) verified.set(tx, r)
  }
  const entitlements = new Map<string, AnalyticsRow>()
  for (const r of byEvent(cur, 'entitlement_activated')) {
    const tx = rowTxId(r)
    if (tx && !entitlements.has(tx)) entitlements.set(tx, r)
  }
  const successByTx = new Map<string, AnalyticsRow[]>()
  for (const r of byEvent(cur, 'purchase_success')) {
    const tx = rowTxId(r)
    if (!tx) continue
    const arr = successByTx.get(tx) ?? []
    arr.push(r)
    successByTx.set(tx, arr)
  }
  const duplicates = [...successByTx.entries()].filter(([, arr]) => arr.length > 1)
  const restoreAnons = distinctAnons(byEvent(cur, 'purchase_restore'))

  const verifiedWithoutEntitlement = [...verified.entries()].filter(([tx]) => !entitlements.has(tx))
  const entitlementWithoutVerified = [...entitlements.entries()].filter(
    ([tx, r]) => !verified.has(tx) && !successByTx.has(tx) && !restoreAnons.has(r.anon_id),
  )

  // Starts (by purchase_attempt_id, falling back to anon+session) with no
  // terminal outcome anywhere in the period for the same attempt/anon.
  const terminalAttempts = new Set<string>()
  const terminalAnons = new Set<string>()
  for (const r of cur) {
    if (!TERMINAL_PURCHASE_EVENTS.includes(r.event)) continue
    const a = rowAttemptId(r)
    if (a) terminalAttempts.add(a)
    if (r.event !== 'purchase_start') terminalAnons.add(`${r.anon_id}|${r.session_id ?? ''}`)
  }
  let startsWithoutTerminalOutcome = 0
  const startKeys = new Set<string>()
  for (const r of byEvent(cur, 'purchase_start')) {
    const a = rowAttemptId(r)
    const key = a ?? `${r.anon_id}|${r.session_id ?? ''}`
    if (startKeys.has(key)) continue
    startKeys.add(key)
    const hasOutcome = a ? terminalAttempts.has(a) : terminalAnons.has(key)
    if (!hasOutcome) startsWithoutTerminalOutcome++
  }

  const rows: ReconciliationRow[] = [
    ...verifiedWithoutEntitlement.map(([tx, r]) => ({
      transaction_id: tx,
      product_id: propStr(r, 'product_id'),
      verified_at: new Date(r.created_at).toISOString(),
      entitlement_at: null,
      issue: 'verified_without_entitlement' as const,
    })),
    ...entitlementWithoutVerified.map(([tx, r]) => ({
      transaction_id: tx,
      product_id: propStr(r, 'product_id'),
      verified_at: null,
      entitlement_at: new Date(r.created_at).toISOString(),
      issue: 'entitlement_without_verified' as const,
    })),
    ...duplicates.map(([tx, arr]) => ({
      transaction_id: tx,
      product_id: propStr(arr[0]!, 'product_id'),
      verified_at: verified.has(tx) ? new Date(verified.get(tx)!.created_at).toISOString() : null,
      entitlement_at: entitlements.has(tx) ? new Date(entitlements.get(tx)!.created_at).toISOString() : null,
      issue: 'duplicate_purchase_success' as const,
    })),
  ].slice(0, 200)

  const discrepancies =
    verifiedWithoutEntitlement.length + entitlementWithoutVerified.length + duplicates.length
  const discrepancyRate = ratio(discrepancies, Math.max(verified.size, 1))
  const instrumented = verified.size > 0 || entitlements.size > 0 || byEvent(cur, 'purchase_start').length > 0
  if (!byEvent(cur, 'purchase_verified').length && !byEvent(cur, 'entitlement_activated').length) {
    notes.push(
      'purchase telemetry v2 events (purchase_verified / entitlement_activated) are absent in this period — purchase_telemetry_v2_enabled defaults OFF in the client, so reconciliation is not instrumented until it is enabled. Legacy purchase_success counts cannot substitute.',
    )
  }
  notes.push(
    'Renewals and refunds/revocations are NOT visible in client telemetry (activation-experiments.md §1 gap 4): they are counted from App Store Connect / server verify records only, and are never inferred here.',
  )
  notes.push(
    'App Store Connect records are not queryable from this server (no ASC API integration in the repo); the authoritative comparison is the weekly aggregate check in docs/activation-experiments.md §4.',
  )
  return {
    counts: {
      purchaseStarts: startKeys.size,
      startsWithoutTerminalOutcome,
      verifiedTransactions: verified.size,
      entitlementActivations: entitlements.size,
      purchaseSuccessV2Transactions: new Set(
        byEvent(cur, 'purchase_success')
          .filter((r) => propNum(r, 'telemetry_v') === 2)
          .map((r) => rowTxId(r))
          .filter(Boolean),
      ).size,
      duplicateSuccessTransactions: duplicates.length,
      verifiedWithoutEntitlement: verifiedWithoutEntitlement.length,
      entitlementWithoutVerifiedOrRestore: entitlementWithoutVerified.length,
    },
    discrepancyRate,
    tolerance: RECONCILIATION_TOLERANCE,
    withinTolerance: discrepancyRate === null ? null : discrepancyRate <= RECONCILIATION_TOLERANCE,
    rows,
    instrumented,
    notes,
  }
}

// ---------------------------------------------------------------------------
// F. Auto Optimize performance & reliability
// ---------------------------------------------------------------------------

export interface OptimizePerfResult {
  instrumented: boolean
  runs: number
  outcomes: { success: number; failure: number; cancelled: number; fallback: number; other: number }
  rates: { success: number | null; failure: number | null; cancelled: number | null; fallback: number | null }
  totalLatency: { p50: number | null; p95: number | null; p99: number | null; n: number; method: string }
  stageLatency: Array<{ stage: string; p50: number | null; p95: number | null; p99: number | null; n: number; meanShareOfTotal: number | null }>
  slowestStage: string | null
  over10sShare: number | null
  aeTimeoutRate: number | null
  meteringMissingRate: number | null
  reliabilityCounts: {
    exposureReverts: number | null
    lensFlipInvalidations: number | null
    cameraResets: number | null
    captureFailuresAfterOptimize: number | null
  }
  breakdowns: {
    byLens: Array<Record<string, unknown>>
    byTrigger: Array<Record<string, unknown>>
    byAppVersion: Array<Record<string, unknown>>
    byArm: Array<Record<string, unknown>>
  }
  series: Array<{ day: string; runs: number; p95: number | null; failureRate: number | null }>
  regressions: Array<{ metric: string; current: number | null; previous: number | null; deltaRel: number | null; regression: boolean; note: string }>
  legacy: { autoOptimizeStart: number; autoOptimizeSuccess: number; autoOptimizeFail: number; autoOptimizeCancel: number; note: string }
}

function stageKeysOf(rows: AnalyticsRow[]): string[] {
  const keys = new Set<string>()
  for (const r of rows) {
    for (const k of Object.keys(r.props ?? {})) {
      if (k.startsWith('stage_') && k.endsWith('_ms')) keys.add(k.slice('stage_'.length, -'_ms'.length))
    }
  }
  return [...keys].sort()
}

function perfBreakdown(
  rows: AnalyticsRow[],
  keyOf: (r: AnalyticsRow) => string | null,
): Array<Record<string, unknown>> {
  const cells = new Map<string, AnalyticsRow[]>()
  for (const r of rows) {
    const key = keyOf(r) ?? 'unknown'
    const arr = cells.get(key) ?? []
    arr.push(r)
    cells.set(key, arr)
  }
  return [...cells.entries()]
    .map(([key, cell]) => {
      const users = distinctAnons(cell).size
      const suppressed = users < SMALL_COHORT_MIN_USERS
      const lat = percentiles(cell.map((r) => propNum(r, 'total_ms')).filter((x): x is number => x !== null))
      const failures = cell.filter((r) => isOptimizeFailureOutcome(propStr(r, 'outcome'))).length
      return {
        key,
        users,
        suppressed,
        runs: suppressed ? null : cell.length,
        p50: suppressed ? null : lat.p50,
        p95: suppressed ? null : lat.p95,
        failureRate: suppressed ? null : ratio(failures, cell.length),
      }
    })
    .sort((a, b) => (b.users as number) - (a.users as number))
}

export function computeOptimizePerformance(cur: AnalyticsRow[], prev: AnalyticsRow[], period: Period): OptimizePerfResult {
  const summaries = latencySummaryRows(cur)
  const prevSummaries = latencySummaryRows(prev)
  const outcomes = { success: 0, failure: 0, cancelled: 0, fallback: 0, other: 0 }
  for (const r of summaries) {
    const o = propStr(r, 'outcome')
    if (isOptimizeSuccessOutcome(o)) outcomes.success++
    else if (isOptimizeFailureOutcome(o)) outcomes.failure++
    else if (isOptimizeCancelledOutcome(o)) outcomes.cancelled++
    else if (o?.toLowerCase() === 'fallback') outcomes.fallback++
    else outcomes.other++
  }
  const fallbackEvents = byEvent(cur, 'optimize_fallback').length
  const totalWithFallback = summaries.length + (outcomes.fallback === 0 ? fallbackEvents : 0)
  const totals = summaries.map((r) => propNum(r, 'total_ms')!)
  const totalLatency = percentiles(totals)
  const stages = stageKeysOf(summaries)
  const meanTotal = totals.length ? totals.reduce((a, b) => a + b, 0) / totals.length : null
  const stageLatency = stages
    .map((stage) => {
      const vals = summaries
        .map((r) => propNum(r, `stage_${stage}_ms`))
        .filter((x): x is number => x !== null)
      const p = percentiles(vals)
      const mean = vals.length ? vals.reduce((a, b) => a + b, 0) / vals.length : null
      return {
        stage,
        p50: p.p50,
        p95: p.p95,
        p99: p.p99,
        n: p.n,
        meanShareOfTotal: mean !== null && meanTotal ? mean / meanTotal : null,
      }
    })
    .sort((a, b) => (b.p95 ?? 0) - (a.p95 ?? 0))
  const aeTimeouts = byEvent(cur, 'ae_converge_timeout').length
  const meteringMissing = byEvent(cur, 'ao_metering_missing').length
  const countOrNull = (names: string[]): number | null =>
    cur.some((r) => names.includes(r.event)) ? cur.filter((r) => names.includes(r.event)).length : null

  const dayMs = 24 * 60 * 60 * 1000
  const series: OptimizePerfResult['series'] = []
  for (let d = Math.floor(period.startMs / dayMs) * dayMs; d < period.endMs; d += dayMs) {
    const daySummaries = latencySummaryRows(inWindow(cur, d, d + dayMs))
    const lat = percentiles(daySummaries.map((r) => propNum(r, 'total_ms')!))
    series.push({
      day: dayKey(d),
      runs: daySummaries.length,
      p95: lat.p95,
      failureRate: ratio(
        daySummaries.filter((r) => isOptimizeFailureOutcome(propStr(r, 'outcome'))).length,
        daySummaries.length,
      ),
    })
  }

  const prevLat = percentiles(prevSummaries.map((r) => propNum(r, 'total_ms')!))
  const prevFailRate = ratio(
    prevSummaries.filter((r) => isOptimizeFailureOutcome(propStr(r, 'outcome'))).length,
    prevSummaries.length,
  )
  const curFailRate = ratio(outcomes.failure, summaries.length)
  const rel = (c: number | null, p: number | null) =>
    c !== null && p !== null && p !== 0 ? (c - p) / Math.abs(p) : null
  const enoughN = totalLatency.n >= 30 && prevLat.n >= 30
  const regressions: OptimizePerfResult['regressions'] = [
    {
      metric: 'p95_total_ms',
      current: totalLatency.p95,
      previous: prevLat.p95,
      deltaRel: rel(totalLatency.p95, prevLat.p95),
      regression: enoughN && rel(totalLatency.p95, prevLat.p95) !== null && rel(totalLatency.p95, prevLat.p95)! > 0.2,
      note: enoughN ? 'regression = p95 up >20% vs previous period with n≥30 in both periods' : 'insufficient n (<30 in a period) to call a regression',
    },
    {
      metric: 'failure_rate',
      current: curFailRate,
      previous: prevFailRate,
      deltaRel: rel(curFailRate, prevFailRate),
      regression: enoughN && rel(curFailRate, prevFailRate) !== null && rel(curFailRate, prevFailRate)! > 0.5,
      note: 'regression = failure rate up >50% relative vs previous period with n≥30 runs in both',
    },
  ]

  return {
    instrumented: summaries.length > 0,
    runs: summaries.length,
    outcomes: { ...outcomes, fallback: outcomes.fallback + (outcomes.fallback === 0 ? fallbackEvents : 0) },
    rates: {
      success: ratio(outcomes.success, summaries.length),
      failure: ratio(outcomes.failure, summaries.length),
      cancelled: ratio(outcomes.cancelled, summaries.length),
      fallback: ratio(outcomes.fallback + (outcomes.fallback === 0 ? fallbackEvents : 0), totalWithFallback),
    },
    totalLatency: { ...totalLatency, method: 'nearest-rank' },
    stageLatency,
    slowestStage: stageLatency[0]?.stage ?? null,
    over10sShare: ratio(totals.filter((t) => t > 10_000).length, totals.length),
    aeTimeoutRate: ratio(aeTimeouts, summaries.length),
    meteringMissingRate: ratio(meteringMissing, summaries.length),
    reliabilityCounts: {
      exposureReverts: countOrNull(['ao_exposure_reverted']),
      lensFlipInvalidations: countOrNull(['ao_reset_on_flip']),
      cameraResets: countOrNull(['camera_reset', 'camera_exposure_reset']),
      captureFailuresAfterOptimize: countOrNull(CAPTURE_FAILURE_EVENTS),
    },
    breakdowns: {
      byLens: perfBreakdown(summaries, (r) => rowLens(r)),
      byTrigger: perfBreakdown(summaries, (r) => propStr(r, 'trigger')),
      byAppVersion: perfBreakdown(summaries, (r) => r.app_version),
      byArm: perfBreakdown(summaries, (r) => rowFirstPhotoArm(r)),
    },
    series,
    regressions,
    legacy: {
      autoOptimizeStart: byEvent(cur, 'auto_optimize_start').length,
      autoOptimizeSuccess: byEvent(cur, 'auto_optimize_success').length,
      autoOptimizeFail: byEvent(cur, 'auto_optimize_fail').length,
      autoOptimizeCancel: byEvent(cur, 'auto_optimize_cancel').length,
      note: 'Legacy event counters (unpaired, mixed web/iOS) — context only; rates come from optimize_latency_summary runs.',
    },
  }
}

// ---------------------------------------------------------------------------
// Experiments registry + read-only alerts
// ---------------------------------------------------------------------------

export interface ExperimentStatus {
  flag: string
  experimentId: string
  version: string
  arms: string[]
  assignment: string
  eligibility: string
  startDate: string | null
  sampleSize: number
  exposure: number
  primaryMetric: string
  guardrails: string[]
  configStatus: 'unknown_client_side'
  configNote: string
  observedStatus: 'events_observed' | 'no_data'
}

export interface AlertDefinition {
  id: string
  metric: string
  condition: string
  status: 'ok' | 'alert' | 'unknown'
  current: number | null
  baseline: number | null
  n: number
  unit?: 'rate' | 'ms' | 'count'
  note: string
}

const FLAG_DEFS: Array<Omit<ExperimentStatus, 'startDate' | 'sampleSize' | 'exposure' | 'configStatus' | 'configNote' | 'observedStatus'>> = [
  {
    flag: 'first_photo_preoptimize_enabled',
    experimentId: 'first_photo_v1',
    version: 'v1',
    arms: ['post_capture_v1', 'pre_capture_guided_v1'],
    assignment: '50/50, FNV-1a bucket of anon install id, persisted; kill switch never resets assignment',
    eligibility: 'New installs that never completed/declined/skipped, never activated, no undo opt-out',
    primaryMetric: 'first optimized photo within 5 min / eligible unique new users',
    guardrails: ['capture_success rate', 'optimize_capture_abandoned rate', 'ae_converge_timeout rate'],
  },
  {
    flag: 'capture_ready_ui_enabled',
    experimentId: 'capture_ready',
    version: 'v1',
    arms: ['n/a (UI + attribution, no arm split)'],
    assignment: 'flag-gated, no bucketing',
    eligibility: 'Runs reaching a terminal optimize outcome',
    primaryMetric: 'correlated optimize→capture conversion by run_id',
    guardrails: ['median seconds ready→shutter', 'capture errors'],
  },
  {
    flag: 'paywall_value_experiment_enabled',
    experimentId: 'paywall_v1',
    version: 'v1',
    arms: ['paywall_control_v1', 'paywall_value_v1'],
    assignment: '50/50, FNV-1a bucket, independent of first_photo_v1, persisted',
    eligibility: 'Paywall viewers with a genuine saved optimized result (proof only when one exists)',
    primaryMetric: 'paywall_view → purchase_verified conversion by arm',
    guardrails: ['purchase cancellations', 'restores', 'paywall dismissals'],
  },
  {
    flag: 'purchase_telemetry_v2_enabled',
    experimentId: 'purchase_telemetry',
    version: 'v2',
    arms: ['n/a (telemetry rollout, default OFF in client)'],
    assignment: 'flag-gated rollout',
    eligibility: 'All purchase attempts',
    primaryMetric: 'reconciliation discrepancy rate vs verified transactions',
    guardrails: ['verified-without-entitlement count', 'duplicate purchase_success count'],
  },
  {
    flag: 'optimize_stage_timing_enabled',
    experimentId: 'optimize_stage_timing',
    version: 'v1',
    arms: ['n/a (telemetry only)'],
    assignment: 'flag-gated, telemetry-only',
    eligibility: 'All optimize runs reaching a terminal outcome',
    primaryMetric: 'optimize_latency_summary p50/p95/p99 by app version',
    guardrails: ['runs >10s share', 'stage coverage (requested/aeConvergence/inference/apply/verify)'],
  },
  {
    flag: 'optimize_safe_timeout_enabled',
    experimentId: 'optimize_safe_timeout',
    version: 'v1',
    arms: ['n/a (default OFF; AE timeout deliberately unchanged)'],
    assignment: 'flag-gated',
    eligibility: 'Optimize runs with AE convergence',
    primaryMetric: 'ae_converge_timeout rate by lens',
    guardrails: ['exposure correctness (metering from converged state)', 'ao_metering_missing rate'],
  },
]

export function computeExperiments(
  cur: AnalyticsRow[],
  activation: ActivationResult,
  overview: OverviewResult,
  perf: OptimizePerfResult,
  prevPerf: OptimizePerfResult | null,
  reconciliation: ReconciliationResult,
  prevOverview: OverviewResult | null,
  prevVerificationFailures: number | null,
  dataFreshnessMs: number | null,
  period: Period,
  nowMs: number = Date.now(),
): { experiments: ExperimentStatus[]; alerts: AlertDefinition[]; alertingNote: string } {
  const firstAssign = (event: string): string | null => {
    const rows = byEvent(cur, event)
    if (!rows.length) return null
    return new Date(Math.min(...rows.map((r) => r.created_at))).toISOString()
  }
  const dynamic: Record<string, { startDate: string | null; sampleSize: number; exposure: number }> = {
    first_photo_preoptimize_enabled: {
      startDate: firstAssign('first_photo_experiment_assigned'),
      sampleSize: activation.arms.reduce((a, x) => a + x.assignedUsers, 0),
      exposure: distinctAnons(byEvent(cur, 'first_photo_guidance_view')).size,
    },
    capture_ready_ui_enabled: {
      startDate: firstAssign('capture_ready_view'),
      sampleSize: distinctAnons(byEvent(cur, 'capture_ready_view')).size,
      exposure: distinctAnons(byEvent(cur, 'capture_ready_view')).size,
    },
    paywall_value_experiment_enabled: {
      startDate: firstAssign('paywall_experiment_assigned'),
      sampleSize: distinctAnons(byEvent(cur, 'paywall_experiment_assigned')).size,
      exposure: distinctAnons(byEvent(cur, 'paywall_view')).size,
    },
    purchase_telemetry_v2_enabled: {
      startDate: firstAssign('purchase_verified'),
      sampleSize: byEvent(cur, 'purchase_start').length,
      exposure: distinctAnons(byEvent(cur, 'purchase_verified')).size,
    },
    optimize_stage_timing_enabled: {
      startDate: firstAssign('optimize_latency_summary'),
      sampleSize: latencySummaryRows(cur).length,
      exposure: latencySummaryRows(cur).length,
    },
    optimize_safe_timeout_enabled: {
      startDate: firstAssign('ae_converge_timeout'),
      sampleSize: byEvent(cur, 'ae_converge_timeout').length,
      exposure: byEvent(cur, 'ae_converge_timeout').length,
    },
  }
  const experiments: ExperimentStatus[] = FLAG_DEFS.map((d) => ({
    ...d,
    ...(dynamic[d.flag] ?? { startDate: null, sampleSize: 0, exposure: 0 }),
    configStatus: 'unknown_client_side' as const,
    configNote:
      'Flags are client UserDefaults (featureFlags.*) — the server cannot read their current value. Status below reflects observed events only; do not treat "no events" as proof a flag is off.',
    observedStatus: (dynamic[d.flag]?.sampleSize ?? 0) > 0 ? ('events_observed' as const) : ('no_data' as const),
  }))

  // Alerts: fire only with adequate n and (for current periods) fresh data.
  const periodIsCurrent = period.endMs >= nowMs - 24 * 60 * 60 * 1000
  const freshEnough = !periodIsCurrent || (dataFreshnessMs !== null && nowMs - dataFreshnessMs <= 24 * 60 * 60 * 1000)
  const gate = (n: number): boolean => n >= ALERT_MIN_N && freshEnough
  const actPrimary = activation.arms[1]!.primary.rate !== null || activation.arms[0]!.primary.rate !== null
  const actCur = overview.firstOptimizedWithin5Min.value
  const actPrev = prevOverview?.firstOptimizedWithin5Min.value ?? null
  const ocCur = overview.optimizeToCapture
  const cfCur = overview.captureFailureRate
  const cfPrev = prevOverview?.captureFailureRate ?? null
  const verificationFailures = byEvent(cur, 'purchase_failed').filter((r) => propStr(r, 'stage') === 'verification' || propStr(r, 'error_category') === 'verification').length
  const alerts: AlertDefinition[] = [
    {
      id: 'activation_decline',
      metric: 'First-photo activation (within 5 min)',
      condition: '>10% relative decline vs previous period',
      status: gate(overview.firstOptimizedWithin5Min.n) && actCur !== null && actPrev !== null && actPrev !== 0
        ? (actCur - actPrev) / actPrev < -0.1 ? 'alert' : 'ok'
        : 'unknown',
      current: actCur,
      baseline: actPrev,
      n: overview.firstOptimizedWithin5Min.n,
      note: actPrimary ? '' : 'activation events not instrumented in this period',
    },
    {
      id: 'optimize_to_capture_decline',
      metric: 'Optimize-to-capture conversion (correlated)',
      condition: '>10% relative decline vs previous period',
      status: gate(ocCur.n) && ocCur.value !== null && ocCur.previous !== null && ocCur.previous !== 0
        ? (ocCur.value - ocCur.previous) / ocCur.previous < -0.1 ? 'alert' : 'ok'
        : 'unknown',
      current: ocCur.value,
      baseline: ocCur.previous,
      n: ocCur.n,
      note: ocCur.instrumented ? '' : 'run_id-correlated capture data not instrumented',
    },
    {
      id: 'capture_failure_2x',
      metric: 'Capture failure rate',
      condition: '>2× previous-period baseline',
      status: gate(cfCur.n) && cfCur.value !== null && cfPrev?.value != null && cfPrev.value > 0
        ? cfCur.value > 2 * cfPrev.value ? 'alert' : 'ok'
        : 'unknown',
      current: cfCur.value,
      baseline: cfPrev?.value ?? null,
      n: cfCur.n,
      note: cfCur.instrumented ? '' : 'no capture-failure event is emitted by the client — cannot alert',
    },
    {
      id: 'ao_p95_over_5s',
      metric: 'Auto Optimize p95 latency',
      condition: 'p95 > 5000 ms',
      status: gate(perf.totalLatency.n) && perf.totalLatency.p95 !== null
        ? perf.totalLatency.p95 > 5000 ? 'alert' : 'ok'
        : 'unknown',
      current: perf.totalLatency.p95,
      baseline: 5000,
      n: perf.totalLatency.n,
      note: 'proposed threshold from the activation spec — not an established production baseline',
    },
    {
      id: 'ao_over_10s_share',
      metric: 'Optimize runs over 10 s',
      condition: '>2% of runs',
      status: gate(perf.totalLatency.n) && perf.over10sShare !== null
        ? perf.over10sShare > 0.02 ? 'alert' : 'ok'
        : 'unknown',
      current: perf.over10sShare,
      baseline: 0.02,
      n: perf.totalLatency.n,
      note: 'proposed threshold — not an established production baseline',
    },
    {
      id: 'ae_timeout_2x',
      metric: 'AE convergence timeout rate',
      condition: '>2× previous-period baseline',
      status:
        gate(perf.runs) && prevPerf !== null && prevPerf.runs >= ALERT_MIN_N &&
        perf.aeTimeoutRate !== null && prevPerf.aeTimeoutRate !== null && prevPerf.aeTimeoutRate > 0
          ? perf.aeTimeoutRate > 2 * prevPerf.aeTimeoutRate ? 'alert' : 'ok'
          : 'unknown',
      current: perf.aeTimeoutRate,
      baseline: prevPerf?.aeTimeoutRate ?? null,
      n: perf.runs,
      note: 'fires only when both periods have ≥100 optimize runs and the baseline rate is >0',
    },
    {
      id: 'verification_failures',
      metric: 'Purchase verification failures',
      condition: 'material increase (≥5 events and >50% relative vs previous period)',
      status:
        prevVerificationFailures === null
          ? 'unknown'
          : verificationFailures >= 5 &&
              (prevVerificationFailures === 0 || verificationFailures > 1.5 * prevVerificationFailures)
            ? 'alert'
            : 'ok',
      current: verificationFailures,
      baseline: prevVerificationFailures,
      n: byEvent(cur, 'purchase_failed').length,
      note: 'material increase = ≥5 verification failures and >50% relative vs previous period (or ≥5 from a zero baseline)',
    },
    {
      id: 'reconciliation_gap',
      metric: 'Purchase reconciliation gap',
      condition: `discrepancy rate > ${(RECONCILIATION_TOLERANCE * 100).toFixed(0)}% of verified transactions (documented tolerance)`,
      status: reconciliation.instrumented && reconciliation.counts.verifiedTransactions >= 20 && reconciliation.discrepancyRate !== null
        ? reconciliation.discrepancyRate > RECONCILIATION_TOLERANCE ? 'alert' : 'ok'
        : 'unknown',
      current: reconciliation.discrepancyRate,
      baseline: RECONCILIATION_TOLERANCE,
      n: reconciliation.counts.verifiedTransactions,
      note: reconciliation.instrumented ? '' : 'purchase telemetry v2 not instrumented in this period',
    },
  ]
  const alertUnits: Record<string, AlertDefinition['unit']> = {
    activation_decline: 'rate',
    optimize_to_capture_decline: 'rate',
    capture_failure_2x: 'rate',
    ao_p95_over_5s: 'ms',
    ao_over_10s_share: 'rate',
    ae_timeout_2x: 'rate',
    verification_failures: 'count',
    reconciliation_gap: 'rate',
  }
  for (const a of alerts) a.unit = alertUnits[a.id] ?? 'rate'
  return {
    experiments,
    alerts,
    alertingNote:
      'Alert definitions are read-only proposals (thresholds from the task spec, not established production baselines). No notification delivery infrastructure (email/Slack/scheduled job) exists in this repo for admin analytics — statuses are computed on page load only. An alert can only fire with n≥100 and fresh data; delayed ingestion yields "unknown", never a false alarm.',
  }
}

// ---------------------------------------------------------------------------
// DB fetch layer (bounded; app='photo-recipes' only) + envelope + CSV
// ---------------------------------------------------------------------------

export interface AnalyticsDataset {
  rows: AnalyticsRow[]
  /** Installs first seen in [fetchStart, end] — superset window for cohorts. */
  installs: InstallRow[] | null
  partial: boolean
  configured: boolean
  warnings: string[]
  dataFreshness: string | null
}

interface RawTelemetryRow {
  created_at: Date | string | number
  event: string
  anon_id: string
  session_id: string | null
  app_version: string | null
  platform: string | null
  props_json: unknown
}

function toMs(v: Date | string | number): number {
  if (v instanceof Date) return v.getTime()
  if (typeof v === 'number') return v
  const ms = Date.parse(v)
  return Number.isFinite(ms) ? ms : 0
}

function parseProps(v: unknown): Record<string, string | number | boolean> | null {
  if (!v) return null
  if (typeof v === 'object') return v as Record<string, string | number | boolean>
  if (typeof v === 'string') {
    try {
      const p = JSON.parse(v) as unknown
      return p && typeof p === 'object' ? (p as Record<string, string | number | boolean>) : null
    } catch {
      return null
    }
  }
  return null
}

/**
 * Load rows for [startMs, endMs) — callers pass the PREVIOUS period start as
 * startMs so current + previous come from one bounded query, and install
 * rows from 9 days before that (retention cohorts) in a second query.
 * Hard cap ROW_CAP+1 rows: on overflow the result is partial + warned,
 * never silently truncated. Soft-empty (configured:false) when MySQL is
 * unset, matching the rest of the admin panel.
 */
export async function fetchAnalyticsDataset(
  startMs: number,
  endMs: number,
  filters: AnalyticsFilters,
  poolArg?: mysql.Pool | null,
): Promise<AnalyticsDataset> {
  const warnings: string[] = []
  const pool = poolArg !== undefined ? poolArg : getMysqlPool()
  if (!pool) {
    return { rows: [], installs: null, partial: false, configured: false, warnings: ['mysql_not_configured'], dataFreshness: null }
  }
  try {
    const versionClause = filters.appVersion ? ' AND app_version = ?' : ''
    const params: unknown[] = [ANALYTICS_APP, startMs / 1000, endMs / 1000]
    if (filters.appVersion) params.push(filters.appVersion)
    const [raw] = await pool.query(
      `SELECT created_at, event, anon_id, session_id, app_version, platform, props_json
       FROM telemetry_events
       WHERE app = ? AND created_at >= FROM_UNIXTIME(?) AND created_at < FROM_UNIXTIME(?)${versionClause}
       ORDER BY created_at ASC
       LIMIT ${ROW_CAP + 1}`,
      params,
    )
    const rawRows = raw as RawTelemetryRow[]
    const partial = rawRows.length > ROW_CAP
    if (partial) {
      warnings.push(`partial_data: row cap ${ROW_CAP} reached — metrics cover the earliest rows in the window only`)
    }
    const rows: AnalyticsRow[] = rawRows.slice(0, ROW_CAP).map((r) => ({
      created_at: toMs(r.created_at),
      event: r.event,
      anon_id: r.anon_id,
      session_id: r.session_id ?? null,
      app_version: r.app_version ?? null,
      platform: r.platform ?? null,
      props: parseProps(r.props_json),
    }))
    let installs: InstallRow[] | null = null
    try {
      const installStart = startMs - 9 * 24 * 60 * 60 * 1000
      const [iraw] = await pool.query(
        `SELECT anon_id, first_seen_at FROM install_devices
         WHERE app = ? AND first_seen_at >= FROM_UNIXTIME(?) AND first_seen_at < FROM_UNIXTIME(?)
         LIMIT ${ROW_CAP}`,
        [ANALYTICS_APP, installStart / 1000, endMs / 1000],
      )
      installs = (iraw as Array<{ anon_id: string; first_seen_at: Date | string | number }>).map((r) => ({
        anon_id: r.anon_id,
        first_seen_ms: toMs(r.first_seen_at),
      }))
    } catch {
      installs = null
      warnings.push('insufficient_data: install_devices unavailable — new installs and retention are null, not zero')
    }
    return {
      rows: dedupeRows(rows),
      installs,
      partial,
      configured: true,
      warnings,
      dataFreshness: freshnessOf(rows),
    }
  } catch (err) {
    console.warn('[admin-analytics] dataset query failed:', err instanceof Error ? err.message : err)
    return {
      rows: [],
      installs: null,
      partial: false,
      configured: true,
      warnings: ['query_failed'],
      dataFreshness: null,
    }
  }
}

export interface AnalyticsEnvelope {
  ok: true
  period: { start: string; end: string }
  previousPeriod: { start: string; end: string }
  timezone: string
  displayTimezone: string
  range: string
  filters: AnalyticsFilters
  data_freshness: string | null
  generatedAt: string
  partial: boolean
  app: string
  warnings: string[]
  metrics: Record<string, unknown>
  sample_sizes: Record<string, number>
}

export function envelope(args: {
  period: Period
  rangeLabel: string
  filters: AnalyticsFilters
  dataset: AnalyticsDataset
  metrics: Record<string, unknown>
  sampleSizes: Record<string, number>
  extraWarnings?: string[]
}): AnalyticsEnvelope {
  const prev = prevPeriod(args.period)
  return {
    ok: true,
    period: { start: new Date(args.period.startMs).toISOString(), end: new Date(args.period.endMs).toISOString() },
    previousPeriod: { start: new Date(prev.startMs).toISOString(), end: new Date(prev.endMs).toISOString() },
    timezone: ANALYTICS_TIMEZONE,
    displayTimezone: ANALYTICS_DISPLAY_TIMEZONE,
    range: args.rangeLabel,
    filters: args.filters,
    data_freshness: args.dataset.dataFreshness,
    generatedAt: new Date().toISOString(),
    partial: args.dataset.partial,
    app: ANALYTICS_APP,
    warnings: [...args.dataset.warnings, ...(args.extraWarnings ?? [])],
    metrics: args.metrics,
    sample_sizes: args.sampleSizes,
  }
}

/** Aggregate-only CSV (no transaction ids, no anon ids, no receipts). */
export function buildAggregateCsv(view: string, env: AnalyticsEnvelope): string {
  const lines: string[] = []
  const esc = (v: unknown): string => {
    const s = v === null || v === undefined ? '' : String(v)
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
  }
  lines.push(['view', 'period_start', 'period_end', 'metric', 'value', 'previous', 'numerator', 'denominator', 'n', 'unit'].map(esc).join(','))
  const pushKpi = (name: string, k: Kpi) => {
    lines.push([view, env.period.start, env.period.end, name, k.value ?? '', k.previous ?? '', k.numerator ?? '', k.denominator ?? '', k.n, k.unit].map(esc).join(','))
  }
  const m = env.metrics as Record<string, unknown>
  if (view === 'overview') {
    for (const k of ['dau', 'wau', 'newInstalls', 'cameraActivationRate', 'firstOptimizedWithin5Min', 'optimizeToCapture', 'paywallToPurchase', 'verifiedPurchases', 'captureFailureRate'] as const) {
      const kpi = (m.overview as OverviewResult | undefined)?.[k] as Kpi | undefined
      if (kpi) pushKpi(k, kpi)
    }
  } else if (view === 'activation') {
    const act = m.activation as ActivationResult | undefined
    for (const arm of act?.arms ?? []) {
      lines.push([view, env.period.start, env.period.end, `primary_rate:${arm.arm}`, arm.primary.rate ?? '', '', arm.primary.numerator, arm.primary.denominator, arm.primary.denominator, 'rate'].map(esc).join(','))
    }
  } else if (view === 'paywall') {
    const pw = m.paywall as PaywallResult | undefined
    for (const f of pw?.funnel ?? []) {
      lines.push([view, env.period.start, env.period.end, `funnel_users:${f.stage}`, f.users, '', '', '', f.users, 'distinct users (ordered, same session)'].map(esc).join(','))
    }
  } else if (view === 'optimize-performance') {
    const perf = m.optimizePerformance as OptimizePerfResult | undefined
    if (perf) {
      lines.push([view, env.period.start, env.period.end, 'p50_total_ms', perf.totalLatency.p50 ?? '', '', '', '', perf.totalLatency.n, 'ms (nearest-rank)'].map(esc).join(','))
      lines.push([view, env.period.start, env.period.end, 'p95_total_ms', perf.totalLatency.p95 ?? '', '', '', '', perf.totalLatency.n, 'ms (nearest-rank)'].map(esc).join(','))
      lines.push([view, env.period.start, env.period.end, 'p99_total_ms', perf.totalLatency.p99 ?? '', '', '', '', perf.totalLatency.n, 'ms (nearest-rank)'].map(esc).join(','))
      lines.push([view, env.period.start, env.period.end, 'over10s_share', perf.over10sShare ?? '', '', '', '', perf.runs, 'rate'].map(esc).join(','))
    }
  } else if (view === 'reconciliation' || view === 'purchases') {
    const rec = m.reconciliation as ReconciliationResult | undefined
    for (const [k, v] of Object.entries(rec?.counts ?? {})) {
      lines.push([view, env.period.start, env.period.end, k, v, '', '', '', '', 'count (aggregate only; transaction-level rows are never exported)'].map(esc).join(','))
    }
  } else if (view === 'capture') {
    const cap = m.capture as CaptureResult | undefined
    for (const f of cap?.funnel ?? []) {
      lines.push([view, env.period.start, env.period.end, `funnel_runs:${f.stage}`, f.runs, '', '', '', f.runs, 'correlated runs by run_id'].map(esc).join(','))
    }
  }
  return lines.join('\n') + '\n'
}
export type { OverviewResult as Overview, ActivationResult as Activation, CaptureResult as Capture, PaywallResult as Paywall, ReconciliationResult as Reconciliation, OptimizePerfResult as OptimizePerformance }
