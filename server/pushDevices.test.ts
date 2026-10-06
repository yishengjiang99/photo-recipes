/**
 * devices/push_tokens DDL must ship inside the esbuild bundle (no fs read of
 * migrations/ at runtime) and stay in sync with the checked-in .sql file.
 */
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, it } from 'node:test'
import { PUSH_DEVICES_DDL, splitSqlStatements } from './pushDevices.ts'
import { isUnregisteredApnsError } from './pushScheduler.ts'

const here = path.dirname(fileURLToPath(import.meta.url))
const norm = (s: string) => s.replace(/\s+/g, ' ').trim()

describe('pushDevices schema', () => {
  it('inlined DDL matches migrations/002_devices_push_tokens.sql', () => {
    const sql = fs.readFileSync(
      path.join(here, 'migrations', '002_devices_push_tokens.sql'),
      'utf8',
    )
    const fromFile = splitSqlStatements(sql).map(norm)
    assert.equal(fromFile.length, 2, 'devices + push_tokens')
    assert.deepEqual(PUSH_DEVICES_DDL.map(norm), fromFile)
  })

  it('splitSqlStatements keeps a statement that follows a leading comment', () => {
    const stmts = splitSqlStatements('-- header\n-- more\n\nCREATE TABLE a (x INT);\n\nCREATE TABLE b (y INT);\n')
    assert.deepEqual(stmts, ['CREATE TABLE a (x INT)', 'CREATE TABLE b (y INT)'])
  })

  it('devices is created before push_tokens (FK order)', () => {
    assert.match(PUSH_DEVICES_DDL[0]!, /CREATE TABLE IF NOT EXISTS devices/)
    assert.match(PUSH_DEVICES_DDL[1]!, /CREATE TABLE IF NOT EXISTS push_tokens/)
  })
})

describe('isUnregisteredApnsError', () => {
  it('410 / Unregistered are dead; BadDeviceToken is not auto-pruned', () => {
    assert.equal(isUnregisteredApnsError({ ok: false, status: 410, error: '{"reason":"Unregistered"}' }), true)
    assert.equal(isUnregisteredApnsError({ ok: false, error: '{"reason":"Unregistered"}' }), true)
    assert.equal(isUnregisteredApnsError({ ok: false, status: 400, error: '{"reason":"BadDeviceToken"}' }), false)
    assert.equal(isUnregisteredApnsError({ ok: true }), false)
  })
})
