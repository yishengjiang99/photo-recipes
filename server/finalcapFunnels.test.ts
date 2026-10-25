import { test } from 'node:test'
import assert from 'node:assert/strict'
import type { AddressInfo } from 'node:net'
import express from 'express'

// Fake primary MySQL target: the pool is lazy, we replace pool.query below so nothing connects.
process.env.MYSQL_URL = 'mysql://test@127.0.0.1:1/photo_recipes'
process.env.ADMIN_TOKEN = '<MASKED_SECRET_001>'
delete process.env.ADMIN_PASSWORD

const { getMysqlPool } = await import('./mysql.ts')
const {
  CANONICAL_FUNNEL_DEFINITION,
  CANONICAL_FUNNEL_STAGES,
  fetchCanonicalFunnel,
} = await import('./telemetry.ts')
const {
  FINALCAP_APP,
  FINALCAP_FUNNEL_CORE_STAGES,
  FINALCAP_FUNNEL_EXPORT_STAGES,
  FINALCAP_FUNNEL_REVENUE_STAGES,
  fetchFinalcapFunnels,
} = await import('./finalcapFunnels.ts')
const { mountAdminRoutes } = await import('./admin.ts')

type Captured = { sql: string; params: unknown[] }
const captured: Captured[] = []

/** Row the next funnel query returns: { sessions, s0..sN } in stage order. */
let funnelRow: Record<string, number> = { sessions: 0 }
let failQueries = false

const pool = getMysqlPool()!
;(pool as unknown as { query: unknown }).query = async (
  sql: string,
  params: unknown[] = [],
) => {
  captured.push({ sql, params })
  if (failQueries) throw new Error('boom')
  if (/FROM telemetry_events/.test(sql)) return [[funnelRow], []]
  return [[{}], []]
}

test('FinalCap funnel stage contract is exactly as fixed', () => {
  assert.equal(FINALCAP_APP, 'finalcap')
  assert.deepEqual([...FINALCAP_FUNNEL_CORE_STAGES], [
    'app_open',
    'editor_open',
    'edit_start',
    'edit_success',
  ])
  assert.deepEqual([...FINALCAP_FUNNEL_EXPORT_STAGES], ['export_start', 'export_success'])
  assert.deepEqual([...FINALCAP_FUNNEL_REVENUE_STAGES], [
    'paywall_view',
    'trial_start',
    'purchase_success',
  ])
})

test('fetchFinalcapFunnels: counts map to stages, conversions are within-group, scope is app=finalcap', async () => {
  // Stage order: app_open, editor_open, edit_start, edit_success,
  // export_start, export_success, paywall_view, trial_start, purchase_success.
  funnelRow = {
    sessions: 130,
    s0: 100,
    s1: 80,
    s2: 50,
    s3: 40,
    s4: 30,
    s5: 25,
    s6: 20,
    s7: 2,
    s8: 5,
  }
  captured.length = 0
  const f = await fetchFinalcapFunnels(30)
  assert.equal(f.error, undefined)
  assert.equal(f.app, 'finalcap')
  assert.equal(f.unit, 'distinct session_id')
  assert.equal(f.days, 30)
  assert.equal(f.timezone, 'America/Los_Angeles')
  assert.deepEqual(f.core.counts, {
    app_open: 100,
    editor_open: 80,
    edit_start: 50,
    edit_success: 40,
  })
  assert.deepEqual(f.export.counts, { export_start: 30, export_success: 25 })
  assert.deepEqual(f.revenue.counts, {
    paywall_view: 20,
    trial_start: 2,
    purchase_success: 5,
  })
  // Conversions: adjacent within the group, plus vs the group's first stage.
  assert.equal(f.core.steps[0]!.conversionFromPrev, null)
  assert.equal(f.core.steps[1]!.conversionFromPrev, 0.8)
  assert.equal(f.core.steps[3]!.conversionFromPrev, 0.8)
  assert.equal(f.core.steps[3]!.conversionFromFirst, 0.4)
  assert.equal(f.export.steps[1]!.conversionFromPrev, 25 / 30)
  // paywall_view's "previous" is paywall_view itself (group start), never export_success.
  assert.equal(f.revenue.steps[0]!.conversionFromPrev, null)
  assert.equal(f.revenue.steps[2]!.conversionFromPrev, 5 / 2)
  assert.equal(f.revenue.steps[2]!.conversionFromFirst, 0.25)

  // Exactly one query, fully parameterized, app bound as the LAST param.
  assert.equal(captured.length, 1)
  const q = captured[0]!
  assert.match(q.sql, /session_id IS NOT NULL AND session_id <> ''/)
  assert.match(q.sql, /AND app = \?/)
  assert.equal((q.sql.match(/\?/g) ?? []).length, q.params.length, q.sql)
  assert.deepEqual(q.params.slice(0, 9), [
    'app_open',
    'editor_open',
    'edit_start',
    'edit_success',
    'export_start',
    'export_success',
    'paywall_view',
    'trial_start',
    'purchase_success',
  ])
  assert.equal(q.params.at(-1), 'finalcap')
})

test('fetchFinalcapFunnels: zero rows -> clean zero state, null conversions, no error', async () => {
  funnelRow = { sessions: 0, s0: 0, s1: 0, s2: 0, s3: 0, s4: 0, s5: 0, s6: 0, s7: 0, s8: 0 }
  const f = await fetchFinalcapFunnels(30)
  assert.equal(f.error, undefined)
  assert.equal(f.core.counts.app_open, 0)
  assert.equal(f.revenue.counts.purchase_success, 0)
  assert.equal(f.core.steps[1]!.conversionFromPrev, null)
  assert.equal(f.revenue.steps[2]!.conversionFromFirst, null)
})

test('fetchFinalcapFunnels: query failure -> error flag with zeros, not a throw', async () => {
  failQueries = true
  const f = await fetchFinalcapFunnels(30)
  failQueries = false
  assert.equal(f.error, 'query_failed')
  assert.equal(f.core.counts.app_open, 0)
})

test('fetchCanonicalFunnel: parameterization changed nothing (stages, counts, conversions, scope)', async () => {
  // Canonical event-stage order: camera_open, auto_optimize_start, auto_optimize_success.
  funnelRow = { sessions: 200, s0: 150, s1: 60, s2: 45 }
  captured.length = 0
  const f = await fetchCanonicalFunnel(7)
  assert.equal(f.error, undefined)
  assert.deepEqual([...f.stages], [...CANONICAL_FUNNEL_STAGES])
  assert.equal(f.definition, CANONICAL_FUNNEL_DEFINITION)
  assert.deepEqual(f.counts, {
    sessions: 200,
    camera_open: 150,
    auto_optimize_start: 60,
    auto_optimize_success: 45,
  })
  assert.deepEqual(f.conversions, {
    sessionsToCamera: 0.75,
    cameraToOptimizeStart: 0.4,
    optimizeStartToSuccess: 0.75,
  })
  const q = captured[0]!
  assert.deepEqual(q.params.slice(0, 3), [
    'camera_open',
    'auto_optimize_start',
    'auto_optimize_success',
  ])
  assert.equal(q.params.at(-1), 'photo-recipes')
})

test('GET /api/admin/finalcap-funnels: auth, validation, payload shape, zero state', async () => {
  funnelRow = { sessions: 0, s0: 0, s1: 0, s2: 0, s3: 0, s4: 0, s5: 0, s6: 0, s7: 0, s8: 0 }
  const app = express()
  app.use(express.json())
  mountAdminRoutes(app)
  const server = app.listen(0)
  try {
    const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`
    const auth = { Authorization: `Bearer ${process.env.ADMIN_TOKEN}` }

    assert.equal((await fetch(`${base}/api/admin/finalcap-funnels`)).status, 401)

    const bad = await fetch(`${base}/api/admin/finalcap-funnels?days=abc`, { headers: auth })
    assert.equal(bad.status, 400)
    assert.equal(((await bad.json()) as { error: string }).error, 'invalid_days')

    const res = await fetch(`${base}/api/admin/finalcap-funnels`, { headers: auth })
    assert.equal(res.status, 200)
    const body = (await res.json()) as {
      ok: boolean
      funnels: {
        app: string
        days: number
        core: { stages: string[]; counts: Record<string, number> }
        revenue: { counts: Record<string, number> }
        error?: string
      }
    }
    assert.equal(body.ok, true)
    assert.equal(body.funnels.app, 'finalcap')
    assert.equal(body.funnels.days, 30)
    assert.equal(body.funnels.error, undefined)
    assert.deepEqual(body.funnels.core.stages, [
      'app_open',
      'editor_open',
      'edit_start',
      'edit_success',
    ])
    assert.equal(body.funnels.core.counts.app_open, 0)
    assert.equal(body.funnels.revenue.counts.purchase_success, 0)

    const week = await fetch(`${base}/api/admin/finalcap-funnels?days=7`, { headers: auth })
    assert.equal(week.status, 200)
    assert.equal(((await week.json()) as { funnels: { days: number } }).funnels.days, 7)
  } finally {
    server.close()
  }
})
