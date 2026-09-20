/**
 * E2E: POST /api/push/register → GET /api/push/prefs tokenCount.
 * Required for server CI — keep green when changing push / devices / prefs.
 */
import assert from 'node:assert/strict'
import { after, before, describe, it } from 'node:test'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import type { Server } from 'node:http'
import express from 'express'
import cookieParser from 'cookie-parser'
import { mountPushRoutes } from './push.ts'
import { clearPushPrefsStoreForTests } from './pushPrefs.ts'

const TOKEN = 'a1'.repeat(32)

describe('push register e2e', () => {
  let server: Server
  let base = ''
  let cookie = ''

  before(async () => {
    process.env.PUSH_PREFS_PATH = join(
      tmpdir(),
      `push-prefs-e2e-${process.pid}.json`,
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
    delete process.env.PUSH_PREFS_PATH
    await new Promise<void>((resolve, reject) => {
      server.close((err) => (err ? reject(err) : resolve()))
    })
  })

  function collectSetCookie(res: Response) {
    const anyRes = res as Response & { headers: Headers & { getSetCookie?: () => string[] } }
    const list = anyRes.headers.getSetCookie?.() ?? []
    if (list.length) {
      cookie = list.map((c) => c.split(';')[0]!).join('; ')
      return
    }
    const single = res.headers.get('set-cookie')
    if (single) cookie = single.split(';')[0]!
  }

  async function api(path: string, init?: RequestInit) {
    const headers = new Headers(init?.headers)
    if (cookie) headers.set('cookie', cookie)
    if (init?.body && !headers.has('content-type')) {
      headers.set('content-type', 'application/json')
    }
    const res = await fetch(`${base}${path}`, { ...init, headers })
    collectSetCookie(res)
    return { status: res.status, json: (await res.json()) as Record<string, unknown> }
  }

  it('mints guest, register bumps tokenCount to 1, re-register stays 1', async () => {
    const prefs0 = await api('/api/push/prefs')
    assert.equal(prefs0.status, 200)
    assert.equal(prefs0.json.ok, true)
    const p0 = prefs0.json.prefs as { guestId: string; tokenCount: number }
    assert.ok(p0.guestId)
    assert.equal(p0.tokenCount, 0)
    assert.ok(cookie.includes('pr_guest'), `expected pr_guest cookie, got ${cookie}`)

    const reg = await api('/api/push/register', {
      method: 'POST',
      body: JSON.stringify({
        token: TOKEN,
        platform: 'ios',
        bundleId: 'com.ragnus.mvp',
        environment: 'sandbox',
        appVersion: 'ci-e2e',
      }),
    })
    assert.equal(reg.status, 200, JSON.stringify(reg.json))
    assert.equal(reg.json.ok, true)
    assert.equal(reg.json.guestId, p0.guestId)

    const prefs1 = await api('/api/push/prefs')
    const p1 = prefs1.json.prefs as { tokenCount: number; guestId: string }
    assert.equal(p1.guestId, p0.guestId)
    assert.equal(p1.tokenCount, 1)

    await api('/api/push/register', {
      method: 'POST',
      body: JSON.stringify({
        token: TOKEN,
        platform: 'ios',
        bundleId: 'com.ragnus.mvp',
        environment: 'sandbox',
        appVersion: 'ci-e2e',
      }),
    })
    const prefs2 = await api('/api/push/prefs')
    assert.equal((prefs2.json.prefs as { tokenCount: number }).tokenCount, 1)
  })

  it('rejects invalid token with 400', async () => {
    const bad = await api('/api/push/register', {
      method: 'POST',
      body: JSON.stringify({
        token: 'short',
        platform: 'ios',
        bundleId: 'com.ragnus.mvp',
        environment: 'sandbox',
      }),
    })
    assert.equal(bad.status, 400)
  })
})
