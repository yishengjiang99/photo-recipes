import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, it } from 'node:test'
import { FUNNEL_MONETIZATION } from './telemetry.ts'

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
