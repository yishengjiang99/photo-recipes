import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { INSTALL_DEVICES_DDL, isTestInstall } from './installDevices.ts'

const here = path.dirname(fileURLToPath(import.meta.url))
const norm = (s: string) => s.replace(/--[^\n]*\n/g, '').replace(/\s+/g, ' ').replace(/;\s*$/, '').trim()

test('inlined install_devices DDL matches migrations/004', () => {
  const sql = fs.readFileSync(path.join(here, 'migrations', '004_install_devices.sql'), 'utf8')
  assert.equal(norm(sql), norm(INSTALL_DEVICES_DDL))
})

test('isTestInstall flags server ids and 1.2(50) dev builds only', () => {
  assert.equal(isTestInstall({ anonId: 'server-api-error', platform: 'ios' }), true)
  assert.equal(isTestInstall({ anonId: 'ABCDEFGH-1', platform: 'ios', appVersion: '1.2', build: '50' }), true)
  assert.equal(isTestInstall({ anonId: 'ABCDEFGH-1', platform: 'ios', appVersion: '1.4', build: '72' }), false)
  assert.equal(isTestInstall({ anonId: 'ABCDEFGH-1', platform: 'web' }), false)
})
