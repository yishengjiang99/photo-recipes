import { test } from 'node:test'
import assert from 'node:assert/strict'
import type { AddressInfo } from 'node:net'
import express from 'express'

// Fake MySQL target: the pool is lazy, we replace pool.query below so nothing connects.
process.env.MYSQL_URL = 'mysql://test@127.0.0.1:1/test'
process.env.ADMIN_TOKEN = 'test-admin-token'
delete process.env.ADMIN_PASSWORD
delete process.env.STRIPE_SECRET_KEY

const { ALL_APPS, REAL_APP, appAnd, iosOnlyScope, parseAppParam } = await import('./appFilter.ts')
const { getMysqlPool } = await import('./mysql.ts')
const { dailyActiveDefinition, dayBuckets, fetchDailyActiveUsers, fetchHourlyActiveUsers, fetchRecentApiErrors, ptOffsetSec } =
  await import('./telemetry.ts')
const { fetchDevicesSummary, fetchKnownApps } = await import('./installDevices.ts')
const { mountAdminRoutes } = await import('./admin.ts')

type Captured = { sql: string; params: unknown[] }
const captured: Captured[] = []
let knownAppRows: Array<{ app: string }> = []
const pool = getMysqlPool()!
;(pool as unknown as { query: unknown }).query = async (sql: string, params: unknown[] = []) => {
  captured.push({ sql, params })
  if (/SELECT app FROM install_devices\s+UNION/.test(sql)) return [knownAppRows, []]
  // single-row aggregate shape used by summary/devices; harmless for list queries
  return [[{}], []]
}

const placeholders = (sql: string) => (sql.match(/\?/g) ?? []).length

function assertBound(app: string | null) {
  assert.ok(captured.length > 0)
  for (const c of captured) {
    assert.equal(placeholders(c.sql), c.params.length, `placeholder/param mismatch in: ${c.sql}`)
    if (app) {
      assert.ok(!c.sql.includes(app), 'app name must never be interpolated into SQL')
    }
  }
}

test('parseAppParam: default, all, valid names, rejects unsafe input', () => {
  assert.deepEqual(parseAppParam(undefined), { ok: true, app: REAL_APP })
  assert.deepEqual(parseAppParam(''), { ok: true, app: REAL_APP })
  assert.deepEqual(parseAppParam('  '), { ok: true, app: REAL_APP })
  assert.deepEqual(parseAppParam(undefined, null), { ok: true, app: null })
  assert.deepEqual(parseAppParam('all'), { ok: true, app: null })
  assert.deepEqual(parseAppParam(' ALL '), { ok: true, app: null })
  assert.deepEqual(parseAppParam('finalcap'), { ok: true, app: 'finalcap' })
  assert.deepEqual(parseAppParam('music.radar_2-x'), { ok: true, app: 'music.radar_2-x' })
  for (const bad of [
    "x' OR '1'='1",
    'a b',
    'a;drop table t',
    '-lead',
    '.lead',
    'x'.repeat(65),
    ['a', 'b'],
    { a: 1 },
    'é',
    'a/b',
  ]) {
    assert.deepEqual(parseAppParam(bad as unknown), { ok: false }, JSON.stringify(bad))
  }
  assert.equal(ALL_APPS, 'all')
})

test('appAnd builds a parameterized fragment (or nothing for all apps)', () => {
  assert.deepEqual(appAnd('e.app', null), { and: '', params: [] })
  assert.deepEqual(appAnd('app', 'finalcap'), { and: ' AND app = ?', params: ['finalcap'] })
  assert.equal(iosOnlyScope(REAL_APP), true)
  assert.equal(iosOnlyScope('finalcap'), false)
  assert.equal(iosOnlyScope(null), false)
})

test('dailyActiveDefinition reflects the selected app', () => {
  assert.match(dailyActiveDefinition(REAL_APP), /iOS ProTune/)
  assert.match(dailyActiveDefinition('finalcap'), /app=finalcap/)
  assert.match(dailyActiveDefinition(null), /all apps/)
})

test('fetchDailyActiveUsers: photo-recipes keeps iOS-only; other apps drop it; all drops app filter', async () => {
  captured.length = 0
  await fetchDailyActiveUsers(7, REAL_APP)
  assert.match(captured[0]!.sql, /e\.platform = 'ios'/)
  assert.equal(captured[0]!.params.at(-1), REAL_APP)
  assertBound(REAL_APP)

  captured.length = 0
  await fetchDailyActiveUsers(7, 'finalcap')
  assert.doesNotMatch(captured[0]!.sql, /platform = 'ios'/)
  assert.equal(captured[0]!.params.at(-1), 'finalcap')
  assertBound('finalcap')

  captured.length = 0
  await fetchDailyActiveUsers(7, null)
  assert.doesNotMatch(captured[0]!.sql, /e\.app = \?/)
  assertBound(null)
})

test('fetchHourlyActiveUsers / fetchRecentApiErrors scope by app', async () => {
  captured.length = 0
  await fetchHourlyActiveUsers(24, 'omr')
  assert.match(captured[0]!.sql, /AND app = \?/)
  assert.equal(captured[0]!.params.at(-1), 'omr')
  assertBound('omr')

  captured.length = 0
  await fetchHourlyActiveUsers(24, null)
  assert.doesNotMatch(captured[0]!.sql, /app = \?/)
  assertBound(null)

  captured.length = 0
  await fetchRecentApiErrors(10, 'omr')
  assert.deepEqual(captured[0]!.params, ['omr', 10])
  assertBound('omr')
})

test('fetchDevicesSummary: scoped queries are parameterized for app / all', async () => {
  const opts = { dayBuckets: (n: number) => dayBuckets(n), ptOffsetSec, days: 2 }
  captured.length = 0
  const d = await fetchDevicesSummary({ ...opts, app: 'music-radar' })
  assert.match(d.definition, /app music-radar/)
  assert.ok(captured.some((c) => c.params.includes('music-radar')))
  assert.ok(!captured.some((c) => /platform = 'ios'/.test(c.sql.replace(/SUM\([^)]*\)/g, ''))))
  assertBound('music-radar')

  captured.length = 0
  const r = await fetchDevicesSummary({ ...opts, app: REAL_APP })
  assert.match(r.definition, /iOS only/)
  assert.ok(captured.some((c) => /platform = 'ios'/.test(c.sql)))
  assertBound(REAL_APP)

  captured.length = 0
  const a = await fetchDevicesSummary({ ...opts, app: null })
  assert.match(a.definition, /all apps/)
  assert.equal(a.totals.otherApps, 0)
  assertBound(null)
})

test('fetchKnownApps: always lists photo-recipes first, drops unsafe values', async () => {
  knownAppRows = [{ app: 'finalcap' }, { app: 'omr' }, { app: "bad'app" }, { app: REAL_APP }, { app: 'music radar' }]
  assert.deepEqual(await fetchKnownApps(pool), [REAL_APP, 'finalcap', 'omr'])
  knownAppRows = []
  assert.deepEqual(await fetchKnownApps(pool), [REAL_APP])
})

test('GET /api/admin/summary?app=: auth, validation, echoes scope, global sections unchanged', async () => {
  const app = express()
  app.use(express.json())
  mountAdminRoutes(app)
  const server = app.listen(0)
  try {
    const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`
    const auth = { Authorization: 'Bearer test-admin-token' }
    knownAppRows = [{ app: 'finalcap' }]

    assert.equal((await fetch(`${base}/api/admin/summary?app=finalcap`)).status, 401)

    const bad = await fetch(`${base}/api/admin/summary?app=${encodeURIComponent("x' OR 1=1 --")}`, { headers: auth })
    assert.equal(bad.status, 400)
    assert.equal(((await bad.json()) as { error: string }).error, 'invalid_app')
    assert.equal((await fetch(`${base}/api/admin/summary?app=a&app=b`, { headers: auth })).status, 400)

    for (const [q, expected] of [
      ['', REAL_APP],
      ['?app=all', 'all'],
      ['?app=finalcap', 'finalcap'],
    ] as const) {
      captured.length = 0
      const res = await fetch(`${base}/api/admin/summary${q}`, { headers: auth })
      assert.equal(res.status, 200, q)
      const body = (await res.json()) as {
        app: string
        apps: string[]
        telemetry: { app: string }
        stripe: unknown
        entitlements: unknown
      }
      assert.equal(body.app, expected)
      assert.equal(body.telemetry.app, expected)
      assert.deepEqual(body.apps, [REAL_APP, 'finalcap'])
      assert.ok(body.stripe && body.entitlements)
      for (const c of captured) {
        assert.equal(placeholders(c.sql), c.params.length, c.sql)
        if (expected !== 'all') assert.ok(!c.sql.includes(expected))
      }
      if (expected !== 'all') {
        assert.ok(captured.some((c) => c.params.includes(expected)))
      }
    }
  } finally {
    server.close()
  }
})
