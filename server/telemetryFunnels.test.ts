import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, it } from 'node:test'
import {
  CANONICAL_FUNNEL_DAYS,
  CANONICAL_FUNNEL_STAGES,
  CANONICAL_FUNNEL_TIMEZONE,
  FUNNEL_MONETIZATION,
  canonicalFunnelWindow,
} from './telemetry.ts'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const NEW_STEPS = ['paywall_dismiss', 'purchase_cancelled', 'purchase_pending', 'purchase_failed']

describe('monetization funnel steps', () => {
  it('endpoint includes paywall dismiss + purchase outcome steps', () => {
    for (const e of NEW_STEPS) assert.ok((FUNNEL_MONETIZATION as readonly string[]).includes(e), e)
    assert.equal(FUNNEL_MONETIZATION[0], 'paywall_view')
    assert.equal(FUNNEL_MONETIZATION.at(-1), 'purchase_success')
  })
  it('docs and SQL report stay in sync with the endpoint', () => {
    const sql = fs.readFileSync(path.join(root, 'scripts/funnel-report.sql'), 'utf8')
    const doc = fs.readFileSync(path.join(root, 'docs/telemetry-funnels.md'), 'utf8')
    for (const e of NEW_STEPS) {
      assert.match(sql, new RegExp(`'${e}'`), `sql missing ${e}`)
      assert.match(doc, new RegExp(e), `doc missing ${e}`)
    }
  })
})

describe('canonical funnel definition', () => {
  it('is session-based with the exact canonical stages, timezone and default window', () => {
    assert.deepEqual([...CANONICAL_FUNNEL_STAGES], [
      'sessions',
      'camera_open',
      'auto_optimize_start',
      'auto_optimize_success',
    ])
    assert.equal(CANONICAL_FUNNEL_TIMEZONE, 'America/Los_Angeles')
    assert.equal(CANONICAL_FUNNEL_DAYS, 7)
  })
  it('window is trailing complete PT days (today excluded, PT midnights)', () => {
    // 2026-10-18T19:00:00Z = Sun 2026-10-18 12:00 PDT.
    const w = canonicalFunnelWindow(7, Date.UTC(2026, 9, 18, 19, 0, 0))
    assert.equal(w.startDay, '2026-10-11')
    assert.equal(w.endDayExclusive, '2026-10-18')
    // PDT is UTC-7, so PT midnight = 07:00 UTC.
    assert.equal(new Date(w.startSec * 1000).toISOString(), '2026-10-11T07:00:00.000Z')
    assert.equal(new Date(w.endSec * 1000).toISOString(), '2026-10-18T07:00:00.000Z')
    assert.equal(w.endSec - w.startSec, 7 * 86400)
  })
  it('window handles the PT fall-back DST transition', () => {
    // 2026-11-04T20:00:00Z = Wed 2026-11-04 12:00 PST; trailing 7 complete
    // days = Oct 28..Nov 3 PT, spanning the Nov 1 PDT->PST transition.
    const w = canonicalFunnelWindow(7, Date.UTC(2026, 10, 4, 20, 0, 0))
    assert.equal(w.startDay, '2026-10-28')
    assert.equal(w.endDayExclusive, '2026-11-04')
    assert.equal(new Date(w.startSec * 1000).toISOString(), '2026-10-28T07:00:00.000Z')
    assert.equal(new Date(w.endSec * 1000).toISOString(), '2026-11-04T08:00:00.000Z')
    assert.equal(w.endSec - w.startSec, 7 * 86400 + 3600)
  })
  it('docs state the canonical definition and label the other cuts alternate', () => {
    const doc = fs.readFileSync(path.join(root, 'docs/telemetry-funnels.md'), 'utf8')
    assert.match(doc, /Canonical ProTune funnel/)
    assert.match(doc, /distinct `session_id`/)
    assert.match(doc, /America\/Los_Angeles/)
    assert.match(doc, /Alternate cuts — NOT the canonical funnel/)
    const sql = fs.readFileSync(path.join(root, 'scripts/funnel-report.sql'), 'utf8')
    assert.match(sql, /COUNT\(DISTINCT session_id\) AS sessions/)
  })
})
