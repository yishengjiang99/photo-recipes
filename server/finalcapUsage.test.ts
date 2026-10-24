import { test } from 'node:test'
import assert from 'node:assert/strict'
import type { AddressInfo } from 'node:net'
import express from 'express'

// Fake FinalCap MySQL target: the pool is lazy, we replace pool.query below so nothing connects.
process.env.FINALCUT_MYSQL_URL = 'mysql://test@127.0.0.1:1/finalcut'
process.env.ADMIN_TOKEN = '<MASKED_SECRET_001>'
delete process.env.ADMIN_PASSWORD

const { parseDaysParam, utcDayKeys, fetchFinalcapUsage } = await import('./finalcapUsage.ts')
const { getFinalcutMysqlPool, isFinalcutMysqlConfigured } = await import(
  './finalcapMysql.ts'
)
const { mountAdminRoutes } = await import('./admin.ts')

type Captured = { sql: string; params: unknown[] }
const captured: Captured[] = []

let usageRows: Array<Record<string, unknown>> = []
let chatRows: Array<Record<string, unknown>> = []
let failQueries = false

const pool = getFinalcutMysqlPool()!
;(pool as unknown as { query: unknown }).query = async (
  sql: string,
  params: unknown[] = [],
) => {
  captured.push({ sql, params })
  if (failQueries) throw new Error('boom')
  if (/FROM daily_inference_usage/.test(sql) && /GROUP BY/.test(sql)) return [usageRows, []]
  if (/FROM chat_interactions/.test(sql)) return [chatRows, []]
  if (/FROM apple_transactions/.test(sql)) return [[{ n: 2 }], []]
  if (/has_subscription/.test(sql)) return [[{ n: 3 }], []]
  if (/FROM users/.test(sql)) return [[{ n: 339 }], []]
  if (/FROM daily_inference_usage/.test(sql)) return [[{ n: 7 }], []]
  return [[{}], []]
}

test('parseDaysParam: default 30, clamps 1..90, rejects junk', () => {
  assert.deepEqual(parseDaysParam(undefined), { ok: true, days: 30 })
  assert.deepEqual(parseDaysParam(''), { ok: true, days: 30 })
  assert.deepEqual(parseDaysParam('7'), { ok: true, days: 7 })
  assert.deepEqual(parseDaysParam(' 14 '), { ok: true, days: 14 })
  assert.deepEqual(parseDaysParam('0'), { ok: true, days: 1 })
  assert.deepEqual(parseDaysParam('365'), { ok: true, days: 90 })
  for (const bad of ['abc', '1.5', '-3', '1e3', ['7'], { days: 7 }, '٣']) {
    assert.deepEqual(parseDaysParam(bad as unknown), { ok: false }, JSON.stringify(bad))
  }
})

test('utcDayKeys: ascending UTC dates ending today', () => {
  const now = Date.parse('2026-10-24T08:15:00Z')
  assert.deepEqual(utcDayKeys(3, now), ['2026-10-22', '2026-10-23', '2026-10-24'])
  assert.equal(utcDayKeys(30, now).length, 30)
  assert.equal(utcDayKeys(1, now)[0], '2026-10-24')
})

test('isFinalcutMysqlConfigured follows FINALCUT_MYSQL_URL', () => {
  assert.equal(isFinalcutMysqlConfigured(), true)
  assert.ok(pool)
})

test('fetchFinalcapUsage: zero-fills days, splits chat types, totals from the right tables', async () => {
  const keys = utcDayKeys(30)
  usageRows = [
    { day: keys[28], users: 2, inferences: 6 },
    { day: keys[29], users: '1', inferences: '3' }, // mysql2 string numerics
  ]
  chatRows = [
    { day: keys[29], type: 'human2ai', n: 5 },
    { day: keys[29], type: 'ai2human', n: 4 },
    { day: keys[29], type: 'error', n: 1 },
    { day: keys[20], type: 'human2ai', n: 2 },
  ]
  captured.length = 0
  const u = await fetchFinalcapUsage(30)
  assert.equal(u.configured, true)
  assert.equal(u.error, undefined)
  assert.equal(u.dailyUsage.length, 30)
  assert.deepEqual(u.dailyUsage[0], { day: keys[0], activeUsers: 0, inferences: 0 })
  assert.deepEqual(u.dailyUsage[28], { day: keys[28], activeUsers: 2, inferences: 6 })
  assert.deepEqual(u.dailyUsage[29], { day: keys[29], activeUsers: 1, inferences: 3 })
  assert.deepEqual(u.chatByDay[29], {
    day: keys[29],
    human2ai: 5,
    ai2human: 4,
    error: 1,
    total: 10,
  })
  assert.deepEqual(u.chatByDay[20], {
    day: keys[20],
    human2ai: 2,
    ai2human: 0,
    error: 0,
    total: 2,
  })
  assert.deepEqual(u.totals, {
    registeredUsers: 339,
    activeSubscribers: 2,
    subscribersByUserFlag: 3,
    activeUsersInWindow: 7,
    inferencesInWindow: 9,
    chatInWindow: 12,
  })
  // Every query is parameterized; the day window is bound, never interpolated.
  for (const c of captured) {
    assert.equal((c.sql.match(/\?/g) ?? []).length, c.params.length, c.sql)
    assert.ok(!c.sql.includes(keys[0]!), 'day keys must be bound params')
  }
  const usageQuery = captured.find((c) => /GROUP BY/.test(c.sql))!
  assert.deepEqual(usageQuery.params, [keys[0], keys[29]])
})

test('fetchFinalcapUsage: pool null → soft-empty; query failure → error flag, not a throw', async () => {
  const none = await fetchFinalcapUsage(30, null)
  assert.equal(none.configured, true) // env is set in this test process
  assert.equal(none.dailyUsage.length, 30)
  assert.equal(none.totals.registeredUsers, 0)

  usageRows = []
  chatRows = []
  failQueries = true
  const failed = await fetchFinalcapUsage(30)
  failQueries = false
  assert.equal(failed.configured, true)
  assert.equal(failed.error, 'query_failed')
  assert.equal(failed.totals.chatInWindow, 0)
})

test('GET /api/admin/finalcap-usage: auth, validation, payload shape', async () => {
  const keys = utcDayKeys(30)
  usageRows = [{ day: keys[29], users: 4, inferences: 11 }]
  chatRows = [{ day: keys[29], type: 'human2ai', n: 9 }]

  const app = express()
  app.use(express.json())
  mountAdminRoutes(app)
  const server = app.listen(0)
  try {
    const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`
    const auth = { Authorization: `Bearer ${process.env.ADMIN_TOKEN}` }

    assert.equal((await fetch(`${base}/api/admin/finalcap-usage`)).status, 401)

    const bad = await fetch(`${base}/api/admin/finalcap-usage?days=abc`, { headers: auth })
    assert.equal(bad.status, 400)
    assert.equal(((await bad.json()) as { error: string }).error, 'invalid_days')

    const res = await fetch(`${base}/api/admin/finalcap-usage`, { headers: auth })
    assert.equal(res.status, 200)
    const body = (await res.json()) as {
      ok: boolean
      finalcap: {
        configured: boolean
        days: number
        dailyUsage: Array<{ day: string; activeUsers: number; inferences: number }>
        totals: { registeredUsers: number; activeSubscribers: number }
      }
    }
    assert.equal(body.ok, true)
    assert.equal(body.finalcap.configured, true)
    assert.equal(body.finalcap.days, 30)
    assert.deepEqual(body.finalcap.dailyUsage.at(-1), {
      day: keys[29],
      activeUsers: 4,
      inferences: 11,
    })
    assert.equal(body.finalcap.totals.registeredUsers, 339)
    assert.equal(body.finalcap.totals.activeSubscribers, 2)

    const week = await fetch(`${base}/api/admin/finalcap-usage?days=7`, { headers: auth })
    assert.equal(week.status, 200)
    const weekBody = (await week.json()) as { finalcap: { days: number; dailyUsage: unknown[] } }
    assert.equal(weekBody.finalcap.days, 7)
    assert.equal(weekBody.finalcap.dailyUsage.length, 7)
  } finally {
    server.close()
  }
})
