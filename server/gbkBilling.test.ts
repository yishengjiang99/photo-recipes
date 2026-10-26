import test from 'node:test'
import assert from 'node:assert/strict'
import { DatabaseSync } from 'node:sqlite'
import { mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fetchGbkBilling } from './gbkBilling.ts'

function fixtureDir(): string {
  const dir = mkdtempSync(join(tmpdir(), 'gbk-billing-'))
  const today = new Date().toISOString().slice(0, 10)
  const yesterday = new Date(Date.now() - 86_400_000).toISOString().slice(0, 10)
  const adb = new DatabaseSync(join(dir, 'analytics.sqlite'))
  adb.exec(
    'CREATE TABLE billing_daily (day TEXT NOT NULL, event TEXT NOT NULL, surface TEXT NOT NULL DEFAULT \'\', platform TEXT NOT NULL DEFAULT \'\', count INTEGER NOT NULL, PRIMARY KEY (day, event, surface, platform))',
  )
  const ins = adb.prepare('INSERT INTO billing_daily (day, event, surface, platform, count) VALUES (?, ?, ?, ?, ?)')
  ins.run(today, 'signup', '', '', 3)
  ins.run(today, 'paywall_view', 'studio', 'web', 2)
  ins.run(today, 'checkout_start', 'studio', 'web', 1)
  ins.run(today, 'purchase', 'studio', 'web', 1)
  ins.run(today, 'paywall_view', '', 'ios', 5)
  ins.run(yesterday, 'composition_created', 'mcp', 'server', 4)
  ins.run(yesterday, 'paywall_view', 'studio', 'web', 1)
  adb.close()
  const sdb = new DatabaseSync(join(dir, 'shares.sqlite'))
  sdb.exec(
    'CREATE TABLE billing_log (id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL, account TEXT NOT NULL, event TEXT NOT NULL, plan TEXT NOT NULL DEFAULT \'\', surface TEXT NOT NULL DEFAULT \'\', platform TEXT NOT NULL DEFAULT \'\', detail TEXT NOT NULL DEFAULT \'\')',
  )
  const lins = sdb.prepare('INSERT INTO billing_log (ts, account, event, plan, surface, platform, detail) VALUES (?, ?, ?, ?, ?, ?, ?)')
  lins.run(1_000, 'acct-a', 'signup', '', '', '', '')
  lins.run(3_000, 'acct-b', 'paywall_view', '', 'studio', 'web', 'reason=landing')
  lins.run(2_000, 'acct-b', 'composition_created', '', 'studio', 'web', '')
  sdb.close()
  return dir
}

test('fetchGbkBilling aggregates billing_daily and reads the recent log', () => {
  const rep = fetchGbkBilling(30, fixtureDir())
  assert.equal(rep.available, true)
  assert.equal(rep.totals.signup, 3)
  assert.equal(rep.totals.paywall_view, 8)
  assert.equal(rep.totals.composition_created, 4)
  assert.equal(rep.totals.purchase, 1)
  assert.deepEqual(rep.steps.overall, { paywall_view: 8, checkout_start: 1, purchase: 1 })
  const studioWeb = rep.steps.bySurface.find((r) => r.surface === 'studio' && r.platform === 'web')
  assert.deepEqual(studioWeb, { surface: 'studio', platform: 'web', paywall_view: 3, checkout_start: 1, purchase: 1 })
  const today = rep.byDay[rep.byDay.length - 1]
  assert.equal(today.counts.signup, 3)
  assert.equal(today.counts.paywall_view, 7)
  assert.equal(rep.recent.length, 3)
  assert.equal(rep.recent[0].event, 'paywall_view') // ts DESC
  assert.match(rep.recent[0].detail, /reason=landing/)
})

test('fetchGbkBilling soft-zeros when the GBK data dir is absent', () => {
  const rep = fetchGbkBilling(7, join(tmpdir(), 'gbk-billing-definitely-missing'))
  assert.equal(rep.available, false)
  assert.equal(rep.totals.signup, 0)
  assert.equal(rep.byDay.length, 7)
  assert.deepEqual(rep.recent, [])
})
