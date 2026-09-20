/**
 * Unit/e2e: POST /api/push/test-send production hard-refuse + allow header.
 * Does not hit Apple — APNS_* unset → stub path when authorized.
 */
import assert from 'node:assert/strict'
import { after, before, beforeEach, afterEach, describe, it } from 'node:test'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import type { Server } from 'node:http'
import express from 'express'
import cookieParser from 'cookie-parser'
import { mountPushRoutes } from './push.ts'
import { clearPushPrefsStoreForTests } from './pushPrefs.ts'

const TOKEN = 'ab'.repeat(32)
const SECRET = 'test-cron-secret-push-test-send'

describe('POST /api/push/test-send production hard-refuse', () => {
  let server: Server
  let base = ''
  const prev: Record<string, string | undefined> = {}
  const envKeys = ['PUSH_CRON_SECRET', 'PUSH_PREFS_PATH', 'PUSH_EXP1_ENABLED']

  before(async () => {
    for (const k of envKeys) prev[k] = process.env[k]
    process.env.PUSH_CRON_SECRET = SECRET
    process.env.PUSH_EXP1_ENABLED = 'false'
    process.env.PUSH_PREFS_PATH = join(
      tmpdir(),
      `push-prefs-test-send-${process.pid}.json`,
    )
    clearPushPrefsStoreForTests()

    const app = express()
    app.use(express.json())
    app.use(cookieParser())
    mountPushRoutes(app)

    await new Promise<void>((resolve) => {
      server = app.listen(0, '127.0.0.1', () => resolve())
    })
    const addr = server.address()
    if (!addr || typeof addr === 'string') throw new Error('no port')
    base = `http://127.0.0.1:${addr.port}`
  })

  after(async () => {
    clearPushPrefsStoreForTests()
    for (const k of envKeys) {
      if (prev[k] === undefined) delete process.env[k]
      else process.env[k] = prev[k]
    }
    await new Promise<void>((resolve, reject) => {
      server.close((err) => (err ? reject(err) : resolve()))
    })
  })

  async function testSend(
    body: Record<string, unknown>,
    headers: Record<string, string> = {},
  ) {
    const res = await fetch(`${base}/api/push/test-send`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        ...headers,
      },
      body: JSON.stringify(body),
    })
    return {
      status: res.status,
      json: (await res.json()) as Record<string, unknown>,
    }
  }

  it('refuses production without allow header (secret alone → 403)', async () => {
    const r = await testSend(
      { token: TOKEN, environment: 'production', title: 'prod refuse' },
      { 'X-Push-Cron-Secret': SECRET },
    )
    assert.equal(r.status, 403)
    assert.equal(r.json.error, 'production_test_send_refused')
    assert.match(String(r.json.message ?? ''), /X-Push-Test-Allow-Production/)
  })

  it('authorizes production with secret + allow header (stub, no Apple)', async () => {
    const r = await testSend(
      { token: TOKEN, environment: 'production', title: 'prod allow' },
      {
        'X-Push-Cron-Secret': SECRET,
        'X-Push-Test-Allow-Production': '1',
      },
    )
    assert.equal(r.status, 200)
    assert.equal(r.json.ok, true)
    assert.equal(r.json.deepLink, 'photo-recipes://auto-optimize')
    const results = r.json.results as Array<Record<string, unknown>>
    assert.ok(Array.isArray(results) && results.length >= 1)
    assert.equal(results[0]!.environment, 'production')
    assert.equal(results[0]!.stub, true)
  })

  it('sandbox remains secret-gated only (no allow header needed)', async () => {
    const r = await testSend(
      { token: TOKEN, environment: 'sandbox', title: 'sandbox ok' },
      { 'X-Push-Cron-Secret': SECRET },
    )
    assert.equal(r.status, 200)
    assert.equal(r.json.ok, true)
    const results = r.json.results as Array<Record<string, unknown>>
    assert.equal(results[0]!.environment, 'sandbox')
  })

  it('unauthorized without cron secret', async () => {
    const r = await testSend(
      { token: TOKEN, environment: 'sandbox' },
      {},
    )
    assert.equal(r.status, 401)
    assert.equal(r.json.error, 'unauthorized')
  })
})
