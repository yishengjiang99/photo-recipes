import { test } from 'node:test'
import assert from 'node:assert/strict'
import { fillHourBuckets, hourBuckets } from './telemetry.ts'

test('hourBuckets: epoch-second grid ending at current hour, step 3600', () => {
  const now = Date.parse('2026-10-07T05:12:34Z')
  const b = hourBuckets(3, now)
  const end = Date.parse('2026-10-07T05:00:00Z') / 1000
  assert.deepEqual(b, [end - 7200, end - 3600, end])
  assert.equal(hourBuckets(168, now).length, 168)
})

test('fillHourBuckets keys by number; string/BigInt-ish SQL values still match', () => {
  const end = Date.parse('2026-10-07T05:00:00Z') / 1000
  const grid = [end - 7200, end - 3600, end]
  const series = fillHourBuckets(
    [
      { bucket: String(end - 7200), users: '4' }, // mysql2 string numerics
      { bucket: end, users: 2 },
      { bucket: end - 86400, users: 9 }, // outside grid → dropped
    ],
    grid,
  )
  assert.deepEqual(series, [
    { bucket: end - 7200, users: 4 },
    { bucket: end - 3600, users: 0 },
    { bucket: end, users: 2 },
  ])
})

import { dayBuckets, fillDayBuckets, ptDayBucket, ptOffsetRegime, ptOffsetSec } from './telemetry.ts'

const sec = (iso: string) => Date.parse(iso) / 1000

test('ptOffsetSec: PDT -7h, PST -8h', () => {
  assert.equal(ptOffsetSec(sec('2026-10-07T05:00:00Z')), -25200)
  assert.equal(ptOffsetSec(sec('2026-12-01T12:00:00Z')), -28800)
})

test('ptDayBucket = PT date key (00:00 UTC of PT date)', () => {
  // 2026-10-07 05:12 UTC = 2026-10-06 22:12 PDT
  assert.equal(ptDayBucket(sec('2026-10-07T05:12:00Z')), sec('2026-10-06T00:00:00Z'))
  assert.equal(ptDayBucket(sec('2026-10-07T07:00:00Z')), sec('2026-10-07T00:00:00Z'))
})

test('ptOffsetRegime finds DST end instant (2026-11-01 09:00 UTC)', () => {
  const r = ptOffsetRegime(sec('2026-10-20T00:00:00Z'), sec('2026-11-10T00:00:00Z'))
  assert.deepEqual(r, { switchAt: sec('2026-11-01T09:00:00Z'), before: -25200, after: -28800 })
  assert.equal(ptOffsetRegime(sec('2026-09-01T00:00:00Z'), sec('2026-10-07T00:00:00Z')).switchAt, 0)
})

test('dayBuckets / fillDayBuckets step 86400 and key by number', () => {
  const grid = dayBuckets(3, Date.parse('2026-10-07T05:12:00Z'))
  assert.deepEqual(grid, [sec('2026-10-04T00:00:00Z'), sec('2026-10-05T00:00:00Z'), sec('2026-10-06T00:00:00Z')])
  const s = fillDayBuckets([{ bucket: String(grid[1]), users: '7' }], grid)
  assert.deepEqual(s.map((d) => [d.day, d.users]), [['2026-10-04', 0], ['2026-10-05', 7], ['2026-10-06', 0]])
})
