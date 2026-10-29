import { test } from 'node:test'
import assert from 'node:assert/strict'
import type { AddressInfo } from 'node:net'
import express from 'express'

// Fake primary MySQL target: pool is lazy; pool.query is replaced below.
process.env.MYSQL_URL = 'mysql://test@127.0.0.1:1/photo_recipes'
process.env.ADMIN_TOKEN = '<MASKED_SECRET_002>'
delete process.env.ADMIN_PASSWORD

const { getMysqlPool } = await import('./mysql.ts')
const A = await import('./adminAnalytics.ts')
const { mountAdminRoutes } = await import('./admin.ts')

type Row = A.AnalyticsRow
const H = 60 * 60 * 1000
const D = 24 * H
const NOW = Date.now()
const START = NOW - 7 * D
const PERIOD: A.Period = { startMs: START, endMs: NOW }
const PREV: A.Period = { startMs: START - 7 * D, endMs: START }

let seq = 0
function ev(
  ts: number,
  event: string,
  anon: string,
  props: Record<string, string | number | boolean> = {},
  extra: Partial<Row> = {},
): Row {
  seq++
  return {
    created_at: ts,
    event,
    anon_id: anon,
    session_id: extra.session_id ?? `s-${anon}`,
    app_version: extra.app_version ?? '1.5',
    platform: 'ios',
    props: { app_version: '1.5', ...props },
  }
}

// ---------------------------------------------------------------------------
// Deterministic healthy fixture (current period) + previous period
// ---------------------------------------------------------------------------

function healthyCurrent(): Row[] {
  const rows: Row[] = []
  const t0 = START + H
  // Activation experiment: 60 control + 60 treatment assigned.
  for (let i = 0; i < 60; i++) {
    const c = `c${i}`
    rows.push(ev(t0, 'first_photo_experiment_assigned', c, { arm: 'control', bucket: i, exp_version: 'v1' }))
    rows.push(ev(t0, 'session_start', c))
    rows.push(ev(t0 + 1000, 'camera_open', c))
    if (i < 30) rows.push(ev(t0 + 200_000, 'first_photo_activation_complete', c, { arm: 'control', elapsed_sec: 200, within_window: true }))
    else if (i < 36) rows.push(ev(t0 + 400_000, 'first_photo_activation_complete', c, { arm: 'control', elapsed_sec: 400, within_window: false }))
  }
  for (let i = 0; i < 60; i++) {
    const t = `t${i}`
    rows.push(ev(t0, 'first_photo_experiment_assigned', t, { arm: 'treatment', bucket: 50 + (i % 50), exp_version: 'v1' }))
    rows.push(ev(t0, 'session_start', t))
    rows.push(ev(t0 + 1000, 'camera_open', t))
    if (i < 55) rows.push(ev(t0 + 2000, 'first_photo_guidance_view', t, { arm: 'treatment' }))
    if (i >= 50) rows.push(ev(t0 + 3000, 'first_photo_guidance_skip', t, { arm: 'treatment', reason: 'skipped' }))
    if (i < 45) rows.push(ev(t0 + 4000, 'first_photo_preoptimize_start', t, { arm: 'treatment', run_id: `gr${i}` }))
    if (i < 40) rows.push(ev(t0 + 5000, 'first_photo_preoptimize_complete', t, { arm: 'treatment', run_id: `gr${i}`, outcome: 'success' }))
    if (i < 42) rows.push(ev(t0 + 180_000, 'first_photo_activation_complete', t, { arm: 'treatment', elapsed_sec: 180, within_window: true }))
    else if (i < 45) rows.push(ev(t0 + 500_000, 'first_photo_activation_complete', t, { arm: 'treatment', elapsed_sec: 500, within_window: false }))
  }
  // Optimize latency summaries + correlated captures: 120 runs.
  for (let i = 0; i < 120; i++) {
    const anon = `u${i % 60}`
    const ts = START + 2 * D + i * 60_000
    const outcome = i < 108 ? 'success' : i < 116 ? 'failure' : 'cancelled'
    rows.push(
      ev(ts, 'optimize_latency_summary', anon, {
        run_id: `r${i}`,
        trigger: i % 2 ? 'manual' : 'auto',
        lens: i % 3 ? 'rear' : 'front',
        outcome,
        total_ms: 900 + (i % 10) * 50,
        stage_aeConvergence_ms: 300,
        stage_inference_ms: 400,
        stage_apply_ms: 100,
      }),
    )
    if (i < 80 && outcome === 'success') {
      rows.push(ev(ts + 1000, 'capture_ready_view', anon, { run_id: `r${i}` }))
      if (i < 70) rows.push(ev(ts + 2000, 'capture_ready_shutter_tap', anon, { run_id: `r${i}` }))
      if (i < 60) rows.push(ev(ts + 3000, 'capture_after_optimize', anon, { run_id: `r${i}`, classification: 'afterComplete', seconds_after_ready: 3 }))
    }
  }
  for (let i = 0; i < 6; i++) rows.push(ev(START + 3 * D + i * 1000, 'ae_converge_timeout', `u${i}`, { lens: 'front' }))
  for (let i = 0; i < 4; i++) rows.push(ev(START + 3 * D + i * 1000, 'ao_metering_missing', `u${i}`, { reason: 'missingInput' }))
  rows.push(ev(START + 3 * D, 'ao_exposure_reverted', 'u0'))
  rows.push(ev(START + 3 * D, 'camera_reset', 'u1'))
  // Paywall funnel: 50 viewers in distinct sessions.
  for (let i = 0; i < 50; i++) {
    const p = `p${i}`
    const sess = `sess-${p}`
    const ts = START + 4 * D + i * 60_000
    rows.push(ev(ts, 'paywall_view', p, { experiment_arm: i % 2 ? 'treatment' : 'control', paywall_id: 'main', is_new_user: i < 25 }, { session_id: sess }))
    if (i < 30) rows.push(ev(ts + 1000, 'paywall_plan_select', p, { product_id: 'pro_monthly', paywall_id: 'main' }, { session_id: sess }))
    if (i < 25) rows.push(ev(ts + 2000, 'purchase_start', p, { product_id: 'pro_monthly', paywall_id: 'main', purchase_attempt_id: `a${i}` }, { session_id: sess }))
    if (i < 20) {
      rows.push(ev(ts + 3000, 'purchase_verified', p, { purchase_attempt_id: `a${i}`, transaction_id: `TX${i}`, product_id: 'pro_monthly' }, { session_id: sess }))
      rows.push(ev(ts + 3500, 'purchase_success', p, { purchase_attempt_id: `a${i}`, transaction_id: `TX${i}`, product_id: 'pro_monthly', telemetry_v: 2 }, { session_id: sess }))
    }
    if (i < 19) rows.push(ev(ts + 4000, 'entitlement_activated', p, { transaction_id: `TX${i}`, product_id: 'pro_monthly' }, { session_id: sess }))
  }
  // Duplicate purchase_success for TX0 (retry/bug — reconciliation must flag).
  rows.push(ev(START + 4 * D + 9000, 'purchase_success', 'p0', { transaction_id: 'TX0', product_id: 'pro_monthly', telemetry_v: 2 }, { session_id: 'sess-p0' }))
  // Entitlement without verified (and p48 has no restore).
  rows.push(ev(START + 4 * D + 5000, 'entitlement_activated', 'p48', { transaction_id: 'TXORPHAN', product_id: 'pro_monthly' }, { session_id: 'sess-p48' }))
  // Starts without terminal outcome.
  for (let i = 0; i < 5; i++) {
    rows.push(ev(START + 5 * D + i * 1000, 'purchase_start', `q${i}`, { purchase_attempt_id: `orphan${i}`, product_id: 'pro_monthly' }, { session_id: `sess-q${i}` }))
  }
  rows.push(ev(START + 5 * D, 'purchase_cancelled', 'p30', { purchase_attempt_id: 'ac1' }))
  rows.push(ev(START + 5 * D, 'purchase_pending', 'p31', { purchase_attempt_id: 'ap1', product_id: 'pro_monthly' }))
  rows.push(ev(START + 5 * D, 'purchase_failed', 'p32', { purchase_attempt_id: 'af1', error_category: 'verification' }))
  rows.push(ev(START + 5 * D, 'purchase_restore', 'p33', { result: 'success', telemetry_v: 2 }))
  // Legacy aggregates.
  for (let i = 0; i < 10; i++) rows.push(ev(START + 6 * D + i, 'auto_optimize_success', `u${i}`))
  for (let i = 0; i < 3; i++) rows.push(ev(START + 6 * D + i, 'optimize_capture_abandoned', `u${i}`))
  return A.dedupeRows(rows)
}

function healthyPrevious(): Row[] {
  const rows: Row[] = []
  const t0 = PREV.startMs + H
  for (let i = 0; i < 100; i++) {
    rows.push(
      ev(t0 + i * 60_000, 'optimize_latency_summary', `v${i % 50}`, {
        run_id: `pr${i}`,
        trigger: 'manual',
        lens: 'rear',
        outcome: i < 90 ? 'success' : 'failure',
        total_ms: 2000,
        stage_aeConvergence_ms: 800,
        stage_inference_ms: 700,
      }),
    )
  }
  for (let i = 0; i < 40; i++) {
    rows.push(ev(t0, 'first_photo_experiment_assigned', `pc${i}`, { arm: 'control' }))
    if (i < 16) rows.push(ev(t0 + 100_000, 'first_photo_activation_complete', `pc${i}`, { arm: 'control', elapsed_sec: 100, within_window: true }))
  }
  return rows
}

const CUR = healthyCurrent()
const PREVROWS = healthyPrevious()

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------

test('percentileNearestRank: known arrays', () => {
  assert.equal(A.percentileNearestRank([10, 20, 30, 40], 50), 20)
  assert.equal(A.percentileNearestRank([10, 20, 30, 40], 95), 40)
  assert.equal(A.percentileNearestRank([], 95), null)
  const oneTo100 = Array.from({ length: 100 }, (_, i) => i + 1)
  const p = A.percentiles(oneTo100)
  assert.equal(p.p50, 50)
  assert.equal(p.p95, 95)
  assert.equal(p.p99, 99)
  assert.equal(p.n, 100)
  assert.equal(p.method, 'nearest-rank')
})

test('twoProportionZTest: gated below n=30/arm, significant on large split', () => {
  assert.equal(A.twoProportionZTest(20, 29, 10, 29), null)
  const r = A.twoProportionZTest(420, 600, 300, 600)
  assert.ok(r)
  assert.equal(r.significantAt95, true)
  const flat = A.twoProportionZTest(300, 600, 300, 600)
  assert.equal(flat?.significantAt95, false)
})

test('dedupeRows collapses exact retries but keeps distinct events', () => {
  const r = ev(1000, 'purchase_verified', 'a', { transaction_id: 'TX1' })
  const retry = { ...r }
  const other = ev(2000, 'purchase_verified', 'a', { transaction_id: 'TX1' })
  const out = A.dedupeRows([r, retry, other])
  assert.equal(out.length, 2)
})

test('parseAnalyticsQuery: presets, custom, invalid + excessive ranges', () => {
  const ok = A.parseAnalyticsQuery({ range: '7d' }, NOW)
  assert.equal(ok.ok, true)
  if (ok.ok) assert.equal(ok.value.endMs - ok.value.startMs, 7 * D)
  assert.equal(A.parseAnalyticsQuery({ range: 'bogus' }, NOW).ok, false)
  assert.equal(A.parseAnalyticsQuery({ start: 'not-a-date', end: new Date(NOW).toISOString() }, NOW).ok, false)
  assert.equal(
    A.parseAnalyticsQuery({ start: new Date(NOW - 100 * D).toISOString(), end: new Date(NOW).toISOString() }, NOW).ok,
    false,
    'ranges over 92 days are rejected',
  )
  assert.equal(
    A.parseAnalyticsQuery({ start: new Date(NOW).toISOString(), end: new Date(NOW - D).toISOString() }, NOW).ok,
    false,
  )
  assert.equal(A.parseAnalyticsQuery({ range: ['7d', '30d'] }, NOW).ok, false)
})

// ---------------------------------------------------------------------------
// Overview / activation on the healthy fixture
// ---------------------------------------------------------------------------

test('computeOverview: correlated optimize-to-capture, verified tx distinct, legacy kept separate', () => {
  const o = A.computeOverview(CUR, PREVROWS, null, null, null, PERIOD, NOW)
  assert.equal(o.optimizeToCapture.denominator, 108)
  assert.equal(o.optimizeToCapture.numerator, 60)
  assert.equal(o.optimizeToCapture.value, 60 / 108)
  assert.equal(o.verifiedPurchases.value, 20)
  assert.equal(o.aoLatency.n, 120)
  assert.ok(o.aoLatency.p95 !== null && o.aoLatency.p95 <= 1400)
  assert.equal(o.firstOptimizedWithin5Min.numerator, 72) // 30 control + 42 treatment
  assert.equal(o.firstOptimizedWithin5Min.denominator, 120)
  assert.equal(o.firstOptimizedWithin5Min.value, 0.6)
  assert.equal(o.legacy.optimizeCaptureAbandonedEvents, 3)
  // No capture-failure event exists in the fixture (true to the client):
  // the KPI must be uninstrumented-null, not 0.
  assert.equal(o.captureFailureRate.value, null)
  assert.equal(o.captureFailureRate.instrumented, false)
  assert.equal(o.newInstalls.value, null)
  assert.equal(o.newInstalls.instrumented, false)
  assert.equal(o.retentionD1.rate, null)
})

test('computeActivation: per-arm funnels, primary metric, pp diff + lift, eligibility denominators', () => {
  const a = A.computeActivation(CUR, PERIOD)
  assert.equal(a.instrumented, true)
  const [control, treatment] = a.arms
  assert.equal(control!.arm, 'post_capture_v1')
  assert.equal(control!.primary.rate, 0.5)
  assert.equal(treatment!.arm, 'pre_capture_guided_v1')
  assert.equal(treatment!.primary.rate, 0.7)
  assert.equal(treatment!.primary.denominator, 60)
  assert.ok(Math.abs(a.difference.absolutePp! - 0.2) < 1e-9)
  assert.ok(Math.abs(a.difference.relativeLift! - 0.4) < 1e-9)
  // n=60/arm ≥ 30: z-test offered and labeled; 0.5 vs 0.7 at n=60/arm gives
  // z ≈ 2.24, p ≈ 0.025 — significant at 95%.
  assert.ok(a.difference.significance)
  assert.equal(a.difference.significance.significantAt95, true)
  const guidance = treatment!.steps.find((s) => s.stage === 'guidance_view')
  assert.equal(guidance?.users, 55)
  const controlGuidance = control!.steps.find((s) => s.stage === 'guidance_view')
  assert.equal(controlGuidance?.applicable, false)
  assert.equal(controlGuidance?.users, null)
  assert.equal(treatment!.medianTimeToFirstOptimizedSec, 180)
})

test('computeActivation: unassigned users never enter denominators; 5-min boundary follows within_window', () => {
  const rows: Row[] = [
    ev(START + H, 'first_photo_experiment_assigned', 'x1', { arm: 'treatment' }),
    ev(START + H + 1000, 'first_photo_activation_complete', 'x1', { arm: 'treatment', elapsed_sec: 299, within_window: true }),
    ev(START + H, 'first_photo_experiment_assigned', 'x2', { arm: 'treatment' }),
    ev(START + H + 1000, 'first_photo_activation_complete', 'x2', { arm: 'treatment', elapsed_sec: 300, within_window: false }),
    ev(START + H, 'first_photo_experiment_assigned', 'x3', { arm: 'treatment' }),
    ev(START + H + 1000, 'first_photo_activation_complete', 'x3', { arm: 'treatment', elapsed_sec: 301, within_window: false }),
    // Unassigned activation must be excluded entirely.
    ev(START + H + 1000, 'first_photo_activation_complete', 'stray', { arm: 'treatment', elapsed_sec: 10, within_window: true }),
  ]
  const a = A.computeActivation(rows, PERIOD)
  const treatment = a.arms[1]!
  assert.equal(treatment.primary.denominator, 3)
  assert.equal(treatment.primary.numerator, 1)
  assert.equal(a.difference.significance, null, 'no significance under 30/arm')
  assert.match(a.difference.significanceNote, /insufficient data/)
})

test('computeActivation: empty dataset -> not instrumented, no fake zeros-as-rates', () => {
  const a = A.computeActivation([], PERIOD)
  assert.equal(a.instrumented, false)
  assert.equal(a.arms[0]!.primary.rate, null)
  assert.equal(a.difference.absolutePp, null)
})

// ---------------------------------------------------------------------------
// Capture-ready correlation
// ---------------------------------------------------------------------------

test('computeCapture: run_id-correlated ordered funnel; out-of-order and wrong classification excluded', () => {
  const c = A.computeCapture(CUR)
  assert.equal(c.instrumented, true)
  assert.equal(c.successRuns, 108)
  assert.equal(c.readyRuns, 80)
  assert.equal(c.shutterTapRuns, 70)
  assert.equal(c.capturedRuns, 60)
  assert.equal(c.medianSecondsOptimizeCompleteToShutter, 3)
  // Noise: capture before the run summary, and a during-classification capture.
  const noisy: Row[] = [
    ev(START + 10_000, 'optimize_latency_summary', 'n1', { run_id: 'nr1', outcome: 'success', total_ms: 500 }),
    ev(START + 5_000, 'capture_ready_view', 'n1', { run_id: 'nr1' }), // before summary
    ev(START + 11_000, 'capture_after_optimize', 'n1', { run_id: 'nr1', classification: 'during', seconds_after_ready: 1 }),
  ]
  const cn = A.computeCapture(noisy)
  assert.equal(cn.readyRuns, 0)
  assert.equal(cn.capturedRuns, 0)
})

test('computeCapture: zero run_id coverage -> instrumented:false, not a zero funnel', () => {
  const rows: Row[] = [ev(START + 1000, 'optimize_photo_captured', 'a'), ev(START + 2000, 'optimize_capture_abandoned', 'a')]
  const c = A.computeCapture(rows)
  assert.equal(c.instrumented, false)
  assert.equal(c.successRuns, 0)
  assert.equal(c.abandonedLegacyEvents, 1)
})

test('computeCapture: small-cohort breakdown cells are suppressed', () => {
  const rows: Row[] = []
  for (let i = 0; i < 3; i++) {
    rows.push(ev(START + i * 1000, 'optimize_latency_summary', `solo${i}`, { run_id: `sr${i}`, outcome: 'success', total_ms: 100, lens: 'front' }))
    rows.push(ev(START + i * 1000 + 500, 'capture_ready_view', `solo${i}`, { run_id: `sr${i}` }))
  }
  const c = A.computeCapture(rows)
  const front = c.breakdowns.byLens.find((b) => b.key === 'front')
  assert.ok(front)
  assert.equal(front.suppressed, true)
  assert.equal(front.conversion, null)
})

// ---------------------------------------------------------------------------
// Paywall funnel: sequence + same-session enforcement
// ---------------------------------------------------------------------------

test('computePaywall: ordered same-session funnel on healthy fixture', () => {
  const p = A.computePaywall(CUR)
  assert.equal(p.uniqueViewers, 50)
  const byStage = Object.fromEntries(p.funnel.map((f) => [f.stage, f.users]))
  assert.equal(byStage.paywall_view, 50)
  assert.equal(byStage.paywall_plan_select, 30)
  assert.equal(byStage.purchase_start, 25)
  assert.equal(byStage.purchase_verified, 20)
  assert.equal(byStage.entitlement_activated, 19)
  assert.equal(p.cancellations, 1)
  assert.equal(p.pending, 1)
  assert.equal(p.failed, 1)
  assert.equal(p.restores, 1)
  assert.equal(p.verifiedTrialStarts, null, 'no trial signal in props -> null, not 0')
})

test('computePaywall: cross-session and out-of-order progression is rejected', () => {
  const rows: Row[] = [
    ev(START + 1000, 'paywall_view', 'z1', {}, { session_id: 'A' }),
    ev(START + 2000, 'purchase_verified', 'z1', { transaction_id: 'TXZ' }, { session_id: 'B' }), // other session
    ev(START + 3000, 'paywall_view', 'z2', {}, { session_id: 'C' }),
    ev(START + 2500, 'purchase_start', 'z2', { purchase_attempt_id: 'az2' }, { session_id: 'C' }), // before its view? no: after view ts 3000? out of order below
  ]
  // Fix z2 ordering explicitly: start BEFORE view must not count.
  rows[3] = ev(START + 2000, 'purchase_start', 'z2', { purchase_attempt_id: 'az2' }, { session_id: 'C' })
  const reached = A.orderedPaywallFunnel(rows)
  assert.equal(reached.paywall_view!.size, 2)
  assert.equal(reached.purchase_verified!.size, 0)
  assert.equal(reached.purchase_start!.size, 0)
})

// ---------------------------------------------------------------------------
// Reconciliation
// ---------------------------------------------------------------------------

test('computeReconciliation: all four discrepancy classes on healthy fixture', () => {
  const r = A.computeReconciliation(CUR)
  assert.equal(r.instrumented, true)
  assert.equal(r.counts.verifiedTransactions, 20)
  assert.equal(r.counts.verifiedWithoutEntitlement, 1) // TX19
  assert.equal(r.counts.entitlementWithoutVerifiedOrRestore, 1) // TXORPHAN
  assert.equal(r.counts.duplicateSuccessTransactions, 1) // TX0 twice
  assert.equal(r.counts.purchaseSuccessV2Transactions, 20)
  // 5 paywall starts (a20–a24) never reached a terminal event + 5 orphan starts.
  assert.equal(r.counts.startsWithoutTerminalOutcome, 10)
  const issues = new Set(r.rows.map((x) => x.issue))
  assert.ok(issues.has('verified_without_entitlement'))
  assert.ok(issues.has('entitlement_without_verified'))
  assert.ok(issues.has('duplicate_purchase_success'))
  // Rows carry only tx id + product + timestamps.
  for (const row of r.rows) {
    assert.deepEqual(Object.keys(row).sort(), ['entitlement_at', 'issue', 'product_id', 'transaction_id', 'verified_at'])
  }
})

test('computeReconciliation: legacy-only data is not instrumented; renewals/refunds never counted from client events', () => {
  const rows: Row[] = [
    ev(START + 1000, 'purchase_success', 'a', { product_id: 'pro_monthly' }), // legacy, no tx id
    ev(START + 2000, 'subscription_renewed', 'a', { transaction_id: 'TXR' }),
    ev(START + 3000, 'refund', 'a', { transaction_id: 'TXR' }),
  ]
  const r = A.computeReconciliation(rows)
  assert.equal(r.instrumented, false)
  assert.equal(r.counts.verifiedTransactions, 0)
  assert.match(r.notes.join(' '), /Renewals and refunds\/revocations are NOT visible/)
})

test('computeReconciliation: entitlement matched by a restore is not a discrepancy', () => {
  const rows: Row[] = [
    ev(START + 1000, 'purchase_restore', 'a', { result: 'success', telemetry_v: 2 }),
    ev(START + 2000, 'entitlement_activated', 'a', { transaction_id: 'TXRESTORE' }),
  ]
  const r = A.computeReconciliation(rows)
  assert.equal(r.counts.entitlementWithoutVerifiedOrRestore, 0)
})

// ---------------------------------------------------------------------------
// Optimize performance
// ---------------------------------------------------------------------------

test('computeOptimizePerformance: outcomes, stage percentiles, >10s share, per-version split', () => {
  const perf = A.computeOptimizePerformance(CUR, PREVROWS, PERIOD)
  assert.equal(perf.instrumented, true)
  assert.equal(perf.runs, 120)
  assert.equal(perf.outcomes.success, 108)
  assert.equal(perf.outcomes.failure, 8)
  assert.equal(perf.outcomes.cancelled, 4)
  assert.equal(perf.aeTimeoutRate, 6 / 120)
  assert.equal(perf.meteringMissingRate, 4 / 120)
  assert.equal(perf.over10sShare, 0)
  assert.equal(perf.slowestStage, 'inference')
  assert.equal(perf.reliabilityCounts.exposureReverts, 1)
  assert.equal(perf.reliabilityCounts.cameraResets, 1)
  assert.equal(perf.reliabilityCounts.captureFailuresAfterOptimize, null)

  const rows: Row[] = []
  for (let i = 0; i < 10; i++) {
    rows.push(ev(START + i * 1000, 'optimize_latency_summary', `w${i}`, {
      run_id: `wr${i}`, outcome: 'success', total_ms: i < 3 ? 12_000 : 1000, lens: 'rear', trigger: 'manual',
    }, { app_version: i < 5 ? '1.4' : '1.5', props: undefined }))
  }
  // app_version must ride on the row, not just props:
  const perf2 = A.computeOptimizePerformance(rows, [], PERIOD)
  assert.equal(perf2.over10sShare, 0.3)
  const versions = perf2.breakdowns.byAppVersion.map((b) => b.key).sort()
  assert.deepEqual(versions, ['1.4', '1.5'])
})

test('computeOptimizePerformance: regression flags need n>=30 and fire on a real p95 blowout', () => {
  const mk = (total: number, n: number, base: number): Row[] =>
    Array.from({ length: n }, (_, i) =>
      ev(base + i * 1000, 'optimize_latency_summary', `g${i % 40}`, { run_id: `g${base}-${i}`, outcome: 'success', total_ms: total }),
    )
  const regressed = A.computeOptimizePerformance(mk(9000, 60, START), mk(2000, 60, PREV.startMs), PERIOD)
  const p95Row = regressed.regressions.find((r) => r.metric === 'p95_total_ms')
  assert.equal(p95Row?.regression, true)
  const healthy = A.computeOptimizePerformance(mk(1000, 60, START), mk(2000, 60, PREV.startMs), PERIOD)
  assert.equal(healthy.regressions.find((r) => r.metric === 'p95_total_ms')?.regression, false)
  const tiny = A.computeOptimizePerformance(mk(9000, 10, START), mk(2000, 10, PREV.startMs), PERIOD)
  assert.equal(tiny.regressions.find((r) => r.metric === 'p95_total_ms')?.regression, false)
})

// ---------------------------------------------------------------------------
// Experiments + alerts gating
// ---------------------------------------------------------------------------

test('computeExperiments: flags listed, config honestly unknown, alerts gated by n and freshness', () => {
  const overview = A.computeOverview(CUR, PREVROWS, null, null, null, PERIOD, NOW)
  const prevOverview = A.computeOverview(PREVROWS, [], null, null, null, PREV, NOW)
  const activation = A.computeActivation(CUR, PERIOD)
  const perf = A.computeOptimizePerformance(CUR, PREVROWS, PERIOD)
  const prevPerf = A.computeOptimizePerformance(PREVROWS, [], PREV)
  const rec = A.computeReconciliation(CUR)
  const exp = A.computeExperiments(CUR, activation, overview, perf, prevPerf, rec, prevOverview, 0, NOW, PERIOD, NOW)
  assert.equal(exp.experiments.length, 6)
  assert.ok(exp.experiments.every((e) => e.configStatus === 'unknown_client_side'))
  const fp = exp.experiments.find((e) => e.flag === 'first_photo_preoptimize_enabled')
  assert.equal(fp?.sampleSize, 120)
  assert.equal(fp?.observedStatus, 'events_observed')
  const p95Alert = exp.alerts.find((a) => a.id === 'ao_p95_over_5s')
  assert.equal(p95Alert?.status, 'ok') // p95 ~1350ms, n=120
  const empty = A.computeExperiments([], A.computeActivation([], PERIOD), A.computeOverview([], [], null, null, null, PERIOD, NOW), A.computeOptimizePerformance([], [], PERIOD), A.computeOptimizePerformance([], [], PREV), A.computeReconciliation([]), null, null, null, PERIOD, NOW)
  assert.ok(empty.alerts.every((a) => a.status === 'unknown'), 'no data -> every alert unknown, never a false alarm')
  assert.ok(empty.experiments.every((e) => e.observedStatus === 'no_data'))
})

// ---------------------------------------------------------------------------
// CSV: aggregates only
// ---------------------------------------------------------------------------

test('buildAggregateCsv: overview + reconciliation contain aggregates and no transaction ids', () => {
  const overview = A.computeOverview(CUR, PREVROWS, null, null, null, PERIOD, NOW)
  const rec = A.computeReconciliation(CUR)
  const dataset: A.AnalyticsDataset = { rows: CUR, installs: null, partial: false, configured: true, warnings: [], dataFreshness: null }
  const envO = A.envelope({ period: PERIOD, rangeLabel: '7d', filters: A.NO_FILTERS, dataset, metrics: { overview }, sampleSizes: { rows: CUR.length } })
  const csv = A.buildAggregateCsv('overview', envO)
  assert.match(csv, /firstOptimizedWithin5Min/)
  const envR = A.envelope({ period: PERIOD, rangeLabel: '7d', filters: A.NO_FILTERS, dataset, metrics: { reconciliation: rec }, sampleSizes: {} })
  const csvR = A.buildAggregateCsv('reconciliation', envR)
  assert.match(csvR, /verifiedWithoutEntitlement/)
  assert.ok(!csvR.includes('TX0'), 'transaction ids must never appear in CSV exports')
  assert.ok(!csv.includes('TX0'))
})

// ---------------------------------------------------------------------------
// HTTP layer: auth, validation, shapes — pool stubbed like finalcapFunnels
// ---------------------------------------------------------------------------

let stubRows: Row[] = CUR
let stubInstalls: Array<{ anon_id: string; first_seen_at: Date }> = []
const capturedSql: Array<{ sql: string; params: unknown[] }> = []
const pool = getMysqlPool()!
;(pool as unknown as { query: unknown }).query = async (sql: string, params: unknown[] = []) => {
  capturedSql.push({ sql, params })
  if (/FROM telemetry_events/.test(sql)) {
    return [
      stubRows.map((r) => ({
        created_at: new Date(r.created_at),
        event: r.event,
        anon_id: r.anon_id,
        session_id: r.session_id,
        app_version: r.app_version,
        platform: r.platform,
        props_json: r.props,
      })),
      [],
    ]
  }
  if (/FROM install_devices/.test(sql)) return [stubInstalls, []]
  return [[{}], []]
}

async function withServer(fn: (base: string, auth: Record<string, string>) => Promise<void>) {
  const app = express()
  app.use(express.json())
  mountAdminRoutes(app)
  const server = app.listen(0)
  try {
    const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`
    await fn(base, { Authorization: `Bearer ${process.env.ADMIN_TOKEN}` })
  } finally {
    server.close()
  }
}

test('HTTP: analytics endpoints require auth (401), admin unconfigured -> 503', async () => {
  await withServer(async (base, auth) => {
    for (const view of ['overview', 'activation', 'capture', 'paywall', 'purchases', 'reconciliation', 'optimize-performance', 'experiments']) {
      assert.equal((await fetch(`${base}/api/admin/analytics/${view}`)).status, 401, view)
    }
    assert.equal((await fetch(`${base}/api/admin/analytics/export?view=overview`)).status, 401)
    const okRes = await fetch(`${base}/api/admin/analytics/overview`, { headers: auth })
    assert.equal(okRes.status, 200)
    // Unconfigured: remove both env credentials -> 503.
    const saved = process.env.ADMIN_TOKEN
    delete process.env.ADMIN_TOKEN
    try {
      assert.equal((await fetch(`${base}/api/admin/analytics/overview`)).status, 503)
    } finally {
      process.env.ADMIN_TOKEN = saved
    }
  })
})

test('HTTP: invalid and excessive ranges -> 400; valid custom range -> 200 with envelope', async () => {
  await withServer(async (base, auth) => {
    const bad1 = await fetch(`${base}/api/admin/analytics/overview?range=bogus`, { headers: auth })
    assert.equal(bad1.status, 400)
    const bad2 = await fetch(
      `${base}/api/admin/analytics/overview?start=${new Date(NOW - 100 * D).toISOString()}&end=${new Date(NOW).toISOString()}`,
      { headers: auth },
    )
    assert.equal(bad2.status, 400)
    assert.equal(((await bad2.json()) as { error: string }).error, 'range_too_large')
    const good = await fetch(
      `${base}/api/admin/analytics/activation?start=${new Date(START).toISOString()}&end=${new Date(NOW).toISOString()}`,
      { headers: auth },
    )
    assert.equal(good.status, 200)
    const body = (await good.json()) as {
      ok: boolean
      timezone: string
      period: { start: string; end: string }
      metrics: { activation: { arms: Array<{ arm: string; primary: { rate: number | null } }> } }
      sample_sizes: { rows: number }
    }
    assert.equal(body.ok, true)
    assert.equal(body.timezone, 'UTC')
    assert.equal(body.metrics.activation.arms[1]?.primary.rate, 0.7)
    assert.ok(body.sample_sizes.rows > 0)
    // The dataset query is scoped to the shared table's photo-recipes rows only.
    const q = capturedSql.find((c) => /FROM telemetry_events/.test(c.sql) && /ORDER BY created_at/.test(c.sql))
    assert.ok(q)
    assert.equal(q.params[0], 'photo-recipes')
  })
})

test('HTTP: empty dataset -> 200 with not-instrumented states, not errors', async () => {
  stubRows = []
  try {
    await withServer(async (base, auth) => {
      const res = await fetch(`${base}/api/admin/analytics/overview`, { headers: auth })
      assert.equal(res.status, 200)
      const body = (await res.json()) as {
        warnings: string[]
        metrics: { overview: { firstOptimizedWithin5Min: { instrumented: boolean }; aoLatency: { p95: number | null } } }
      }
      assert.ok(body.warnings.some((w) => w.includes('no_data')))
      assert.equal(body.metrics.overview.firstOptimizedWithin5Min.instrumented, false)
      assert.equal(body.metrics.overview.aoLatency.p95, null)
    })
  } finally {
    stubRows = CUR
  }
})

test('HTTP: CSV export requires auth, is aggregate-only, and reconciliation JSON stays admin-only', async () => {
  await withServer(async (base, auth) => {
    const res = await fetch(`${base}/api/admin/analytics/export?view=reconciliation&range=7d`, { headers: auth })
    assert.equal(res.status, 200)
    assert.match(res.headers.get('content-type') ?? '', /text\/csv/)
    const csv = await res.text()
    assert.ok(!csv.includes('TX0'))
    assert.ok(!csv.includes('TXORPHAN'))
    const bad = await fetch(`${base}/api/admin/analytics/export?view=raw-events`, { headers: auth })
    assert.equal(bad.status, 400)
    const rec = await fetch(`${base}/api/admin/analytics/reconciliation?range=7d`, { headers: auth })
    const recBody = (await rec.json()) as { metrics: { reconciliation: { counts: { verifiedWithoutEntitlement: number } } } }
    assert.equal(recBody.metrics.reconciliation.counts.verifiedWithoutEntitlement, 1)
  })
})
