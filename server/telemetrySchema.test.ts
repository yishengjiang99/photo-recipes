import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, it } from 'node:test'
import { splitSqlStatements } from './pushDevices.ts'
import {
  TELEMETRY_CREATED_INDEX_DDL,
  TELEMETRY_TABLE_DDL,
  ensureTelemetrySchemaWith,
} from './telemetrySchema.ts'

const here = path.dirname(fileURLToPath(import.meta.url))
const norm = (s: string) => s.replace(/\s+/g, ' ').trim()
const read = (f: string) => fs.readFileSync(path.join(here, 'migrations', f), 'utf8')

describe('telemetry schema parity', () => {
  it('inlined table DDL matches 001_telemetry_events.sql', () => {
    assert.deepEqual([norm(TELEMETRY_TABLE_DDL)], splitSqlStatements(read('001_telemetry_events.sql')).map(norm))
  })
  it('003 migration carries the same online ADD INDEX and is guarded', () => {
    const sql = read('003_telemetry_created_index.sql')
    assert.ok(norm(sql).includes(norm(TELEMETRY_CREATED_INDEX_DDL)))
    assert.match(sql, /information_schema\.statistics/)
    assert.match(sql, /'DO 0'/)
  })
})

type Call = { sql: string; params?: unknown[] }
function fakePool(opts: { hasIndex: boolean; alterErrno?: number }) {
  const calls: Call[] = []
  const pool = {
    query: async (sql: string, params?: unknown[]) => {
      calls.push({ sql, params })
      if (/information_schema/.test(sql)) return [[{ n: opts.hasIndex ? 1 : 0 }], []]
      if (/^ALTER TABLE/.test(sql) && opts.alterErrno) {
        throw Object.assign(new Error('alter failed'), { errno: opts.alterErrno })
      }
      return [{}, []]
    },
  }
  return { pool: pool as never, calls }
}

describe('ensureTelemetrySchemaWith', () => {
  it('adds the index when missing', async () => {
    const { pool, calls } = fakePool({ hasIndex: false })
    assert.deepEqual(await ensureTelemetrySchemaWith(pool), { ok: true, indexAdded: true })
    assert.equal(calls.filter((c) => /^ALTER TABLE/.test(c.sql)).length, 1)
  })
  it('re-run is a no-op when the index exists (never ALTERs, never drops)', async () => {
    const { pool, calls } = fakePool({ hasIndex: true })
    assert.deepEqual(await ensureTelemetrySchemaWith(pool), { ok: true, indexAdded: false })
    assert.equal(calls.some((c) => /ALTER|DROP|TRUNCATE/i.test(c.sql)), false)
  })
  it('treats ER_DUP_KEYNAME race as success', async () => {
    const { pool } = fakePool({ hasIndex: false, alterErrno: 1061 })
    assert.deepEqual(await ensureTelemetrySchemaWith(pool), { ok: true, indexAdded: false })
  })
  it('other errors → ok:false without throwing', async () => {
    const { pool } = fakePool({ hasIndex: false, alterErrno: 1205 })
    assert.deepEqual(await ensureTelemetrySchemaWith(pool), { ok: false, indexAdded: false })
  })
})
