import { test } from 'node:test'
import assert from 'node:assert/strict'
import type { AddressInfo } from 'node:net'
import express from 'express'

// Fake Temple MySQL target: the pool is lazy, we replace pool.query below so nothing connects.
process.env.TEMPLE_MYSQL_URL = 'mysql://test@127.0.0.1:1/temple'
process.env.ADMIN_TOKEN = '<MASKED_SECRET_001>'
delete process.env.ADMIN_PASSWORD

const { utcDayKeys } = await import('./finalcapUsage.ts')
const { fetchTempleTelemetry, TEMPLE_FUNNEL_STEPS } = await import(
  './templeUsage.ts'
)
const { getTempleMysqlPool, isTempleMysqlConfigured } = await import(
  './templeMysql.ts'
)
const { mountAdminRoutes } = await import('./admin.ts')

type Captured = { sql: string; params: unknown[] }
const captured: Captured[] = []

let failQueries = false

const b64url = (obj: unknown) =>
  Buffer.from(JSON.stringify(obj)).toString('base64url')
const fakeJws = (price: number, currency = 'USD') =>
  `eyJhbGciOiJFUzI1NiJ9.${b64url({ price, currency, transactionId: 'x' })}.sig`

// Rows keyed to the queries in fetchTempleTelemetry.
let installsByDayRows: Array<Record<string, unknown>> = []
let installsByVersionRows: Array<Record<string, unknown>> = []
let dauRows: Array<Record<string, unknown>> = []
let eventsByDayNameRows: Array<Record<string, unknown>> = []
let funnelRows: Array<Record<string, unknown>> = []
let entitlementRows: Array<Record<string, unknown>> = []
let perfRows: Array<Record<string, unknown>> = []
let diagnosticRows: Array<Record<string, unknown>> = []
let errorsByDayRows: Array<Record<string, unknown>> = []
let errorKindRows: Array<Record<string, unknown>> = []
let recentRows: Array<Record<string, unknown>> = []

const pool = getTempleMysqlPool()!
;(pool as unknown as { query: unknown }).query = async (
  sql: string,
  params: unknown[] = [],
) => {
  captured.push({ sql, params })
  if (failQueries) throw new Error('boom')
  // Most specific first: the bare COUNT(*) queries share table names with the grouped ones.
  if (/FROM devices/.test(sql) && /GROUP BY day/.test(sql)) return [installsByDayRows, []]
  if (/FROM devices/.test(sql) && /GROUP BY version/.test(sql)) return [installsByVersionRows, []]
  if (/FROM devices/.test(sql)) return [[{ n: 23 }], []]
  if (/FROM players/.test(sql)) return [[{ n: 23 }], []]
  if (/FROM saves/.test(sql)) return [[{ n: 1, players: 1 }], []]
  if (/name = 'session_start'/.test(sql) && /GROUP BY day/.test(sql)) return [dauRows, []]
  if (/name = 'session_start'/.test(sql)) return [[{ n: 3, players: 2 }], []]
  if (/name = 'perf_sample'/.test(sql)) return [perfRows, []]
  if (/name = 'diagnostic'/.test(sql)) return [diagnosticRows, []]
  if (/name = 'error'/.test(sql) && /GROUP BY day/.test(sql)) return [errorsByDayRows, []]
  if (/name = 'error'/.test(sql)) return [errorKindRows, []]
  if (/GROUP BY day, name/.test(sql)) return [eventsByDayNameRows, []]
  if (/GROUP BY name/.test(sql)) return [funnelRows, []]
  if (/FROM entitlements/.test(sql)) return [entitlementRows, []]
  if (/ORDER BY created_at DESC LIMIT 20/.test(sql)) return [recentRows, []]
  if (/FROM events/.test(sql)) return [[{ n: 13 }], []]
  return [[{}], []]
}

function seed(keys: string[]) {
  installsByDayRows = [
    { day: '2026-10-07', n: 8 },
    { day: keys[29], n: 1 },
  ]
  installsByVersionRows = [
    { version: '1.0 (1)', n: 17 },
    { version: '1.0 (5)', n: 6 },
  ]
  dauRows = [
    { day: keys[28], sessions: 2, dau: 1 },
    { day: keys[29], sessions: 1, dau: 1 },
  ]
  eventsByDayNameRows = [
    { day: keys[29], name: 'session_start', n: 1 },
    { day: keys[29], name: 'paywall_shown', n: 2 },
    { day: keys[28], name: 'session_start', n: 2 },
  ]
  funnelRows = [
    { name: 'session_start', n: 3, players: 2 },
    { name: 'paywall_shown', n: 3, players: 2 },
    { name: 'purchase_started', n: 2, players: 2 },
    { name: 'purchase', n: 1, players: 1 },
    { name: 'purchase_cancelled', n: 1, players: 1 },
    { name: 'paywall_dismissed', n: 1, players: 1 },
  ]
  entitlementRows = [
    { product_id: 'com.ragnus.weather.fullgame.b', environment: 'Sandbox', revoked_at: null, signed_transaction: fakeJws(6990) },
    { product_id: 'com.ragnus.weather.fullgame', environment: 'Production', revoked_at: null, signed_transaction: fakeJws(4990) },
    { product_id: 'com.ragnus.weather.fullgame', environment: 'Production', revoked_at: '2026-11-01 00:00:00', signed_transaction: fakeJws(4990) },
  ]
  perfRows = [
    { props: JSON.stringify({ fps: 29.7, med: 33, p95: 34, map: 'forest' }) },
    { props: JSON.stringify({ fps: 41.9, med: 17, p95: 41, map: 'temple' }) },
    { props: JSON.stringify({ fps: 29.6, med: 33, p95: 38, map: 'temple' }) },
  ]
  diagnosticRows = [{ kind: 'crash', n: 2 }]
  errorsByDayRows = [{ day: keys[29], n: 1 }]
  errorKindRows = [{ kind: 'save', n: 1 }]
  recentRows = [
    { name: 'session_start', app_version: '1.0 (5)', props: '{"returning":true}', created_at: new Date('2026-11-10T12:00:00Z') },
    { name: 'purchase', app_version: '1.0 (5)', props: '{"product":"com.ragnus.weather.fullgame.b"}', created_at: new Date('2026-11-09T03:00:00Z') },
  ]
}

test('isTempleMysqlConfigured follows TEMPLE_MYSQL_URL', () => {
  assert.equal(isTempleMysqlConfigured(), true)
  assert.ok(pool)
})

test('fetchTempleTelemetry: totals, funnel, purchases split by verified environment', async () => {
  const keys = utcDayKeys(30)
  seed(keys)
  captured.length = 0
  const t = await fetchTempleTelemetry(30)
  assert.equal(t.configured, true)
  assert.equal(t.error, undefined)
  assert.equal(t.days, 30)
  assert.equal(t.timezone, 'UTC')
  assert.deepEqual(t.totals, {
    installs: 23,
    players: 23,
    eventsAllTime: 13,
    eventsInWindow: 13,
    sessionsInWindow: 3,
    dauInWindow: 2,
    purchasesProduction: 1,
    purchasesSandbox: 1,
    revenueUsd: 4.99,
    sandboxRevenueUsd: 6.99,
    cloudSavePlayers: 1,
    cloudSaveSlots: 1,
  })
  // The revoked production row is counted but contributes no revenue.
  const prod = t.purchases.find(
    (p) => p.product === 'com.ragnus.weather.fullgame' && p.environment === 'Production',
  )!
  assert.equal(prod.count, 2)
  assert.equal(prod.revoked, 1)
  assert.equal(prod.revenueUsd, 4.99)
  const sandbox = t.purchases.find((p) => p.environment === 'Sandbox')!
  assert.equal(sandbox.count, 1)
  assert.equal(sandbox.revenueUsd, 0)
  // Funnel follows the temple-api step order; purchase converts 1/2 from purchase_started.
  assert.deepEqual(
    t.funnel.map((s) => s.name),
    [...TEMPLE_FUNNEL_STEPS],
  )
  const purchase = t.funnel.find((s) => s.name === 'purchase')!
  assert.equal(purchase.events, 1)
  assert.equal(purchase.players, 1)
  assert.equal(purchase.conversionFromPrev, 0.5)
  assert.equal(t.funnel.find((s) => s.name === 'session_start')!.conversionFromPrev, null)
  assert.equal(t.funnel.find((s) => s.name === 'region_complete')!.events, 0)
  assert.equal(t.funnel.find((s) => s.name === 'purchase_failed')!.events, 0)
  assert.deepEqual(t.installsByDay, [
    { day: '2026-10-07', installs: 8 },
    { day: keys[29], installs: 1 },
  ])
  assert.deepEqual(t.installsByVersion, [
    { version: '1.0 (1)', devices: 17 },
    { version: '1.0 (5)', devices: 6 },
  ])
  assert.equal(t.dauByDay.length, 30)
  assert.deepEqual(t.dauByDay[29], { day: keys[29], sessions: 1, dau: 1 })
  assert.deepEqual(t.eventsByName, [
    { name: 'session_start', count: 3 },
    { name: 'paywall_shown', count: 2 },
  ])
  // Every query is parameterized; the window is bound, never interpolated.
  for (const c of captured) {
    assert.equal((c.sql.match(/\?/g) ?? []).length, c.params.length, c.sql)
    assert.ok(!c.sql.includes('temple'), 'no db name interpolated into SQL')
  }
  // No player-identifying data anywhere in the payload.
  const blob = JSON.stringify(t)
  for (const banned of ['player_id', 'install_id', 'secret_hash', 'signed_transaction', 'public_id']) {
    assert.ok(!blob.includes(banned), `payload must not contain ${banned}`)
  }
})

test('fetchTempleTelemetry: perf medians + diagnostics + recent events', async () => {
  const keys = utcDayKeys(30)
  seed(keys)
  const t = await fetchTempleTelemetry(30)
  assert.equal(t.perf.samples, 3)
  assert.equal(t.perf.medianFps, 29.7)
  assert.equal(t.perf.medianMedMs, 33)
  assert.equal(t.perf.medianP95Ms, 38)
  assert.deepEqual(t.perf.byMap, [
    { map: 'temple', samples: 2, medianFps: 35.8, medianMedMs: 25, medianP95Ms: 39.5 },
    { map: 'forest', samples: 1, medianFps: 29.7, medianMedMs: 33, medianP95Ms: 34 },
  ])
  assert.deepEqual(t.diagnostics, [{ kind: 'crash', count: 2 }])
  assert.deepEqual(t.errorKinds, [{ kind: 'save', count: 1 }])
  assert.equal(t.errorsByDay[29]?.count, 1)
  assert.equal(t.recentEvents.length, 2)
  assert.equal(t.recentEvents[0]?.name, 'session_start')
  assert.equal(t.recentEvents[0]?.appVersion, '1.0 (5)')
})

test('fetchTempleTelemetry: pool null → soft-empty; query failure → error flag, not a throw', async () => {
  const none = await fetchTempleTelemetry(30, null)
  assert.equal(none.configured, true) // env is set in this test process
  assert.equal(none.totals.installs, 0)
  assert.equal(none.dauByDay.length, 30)
  assert.equal(none.funnel.length, TEMPLE_FUNNEL_STEPS.length)

  failQueries = true
  const failed = await fetchTempleTelemetry(30)
  failQueries = false
  assert.equal(failed.configured, true)
  assert.equal(failed.error, 'query_failed')
  assert.equal(failed.totals.installs, 0)
})

test('GET /api/admin/temple: auth, validation, payload shape', async () => {
  const keys = utcDayKeys(30)
  seed(keys)

  const app = express()
  app.use(express.json())
  mountAdminRoutes(app)
  const server = app.listen(0)
  try {
    const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`
    const auth = { Authorization: `Bearer ${process.env.ADMIN_TOKEN}` }

    assert.equal((await fetch(`${base}/api/admin/temple`)).status, 401)

    const bad = await fetch(`${base}/api/admin/temple?days=abc`, { headers: auth })
    assert.equal(bad.status, 400)
    assert.equal(((await bad.json()) as { error: string }).error, 'invalid_days')

    const res = await fetch(`${base}/api/admin/temple`, { headers: auth })
    assert.equal(res.status, 200)
    const body = (await res.json()) as {
      ok: boolean
      temple: {
        configured: boolean
        days: number
        totals: { installs: number; revenueUsd: number; purchasesSandbox: number }
        funnel: Array<{ name: string; events: number }>
      }
    }
    assert.equal(body.ok, true)
    assert.equal(body.temple.configured, true)
    assert.equal(body.temple.days, 30)
    assert.equal(body.temple.totals.installs, 23)
    assert.equal(body.temple.totals.revenueUsd, 4.99)
    assert.equal(body.temple.totals.purchasesSandbox, 1)
    assert.equal(body.temple.funnel.find((s) => s.name === 'purchase')?.events, 1)

    const week = await fetch(`${base}/api/admin/temple?days=7`, { headers: auth })
    assert.equal(week.status, 200)
    const weekBody = (await week.json()) as { temple: { days: number; dauByDay: unknown[] } }
    assert.equal(weekBody.temple.days, 7)
    assert.equal(weekBody.temple.dauByDay.length, 7)
  } finally {
    server.close()
  }
})
