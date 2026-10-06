/**
 * Come-shoot / D1 nudge scheduler — no shootWindow required.
 */
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { afterEach, beforeEach, describe, it } from 'node:test'
import {
  clearPushPrefsStoreForTests,
  registerApnsToken,
  updatePushPrefs,
  getPushPrefs,
} from './pushPrefs.ts'
import { runComeShootNudgeTick } from './pushScheduler.ts'

const ENV_KEYS = ['PUSH_EXP1_ENABLED', 'PUSH_PREFS_PATH', 'APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_BUNDLE_ID', 'APNS_P8_CONTENTS', 'APNS_P8_PATH']

describe('runComeShootNudgeTick', () => {
  let tmp: string
  const prior: Record<string, string | undefined> = {}

  beforeEach(() => {
    tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'come-shoot-'))
    for (const k of ENV_KEYS) prior[k] = process.env[k]
    process.env.PUSH_PREFS_PATH = path.join(tmp, 'prefs.json')
    process.env.PUSH_EXP1_ENABLED = 'true'
    // Leave APNS_* unset → stub send (ok:true) without hitting Apple.
    for (const k of ['APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_BUNDLE_ID', 'APNS_P8_CONTENTS', 'APNS_P8_PATH']) {
      delete process.env[k]
    }
    clearPushPrefsStoreForTests()
  })

  afterEach(() => {
    clearPushPrefsStoreForTests()
    for (const k of ENV_KEYS) {
      if (prior[k] === undefined) delete process.env[k]
      else process.env[k] = prior[k]
    }
    try {
      fs.rmSync(tmp, { recursive: true, force: true })
    } catch {
      /* ignore */
    }
  })

  it('sends come-shoot without shootWindow during evening window', async () => {
    const guestId = 'guest-come-shoot-1'
    registerApnsToken(guestId, {
      token: 'a'.repeat(64),
      platform: 'ios',
      bundleId: 'com.ragnus.mvp',
      environment: 'sandbox',
    })
    updatePushPrefs(guestId, {
      pushOptIn: true,
      timezone: 'America/Los_Angeles',
    })
    // 17:00 PT = 00:00 UTC next day (UTC-7 in Oct).
    const now = new Date('2026-10-07T00:00:00.000Z')
    const r = await runComeShootNudgeTick(now)
    assert.equal(r.enabled, true)
    assert.equal(r.sent, 1, JSON.stringify(r))
    const prefs = getPushPrefs(guestId)
    assert.ok(prefs.lastNudgeAt)
    assert.equal(prefs.shootWindow, null)
  })

  it('skips when outside evening window', async () => {
    const guestId = 'guest-come-shoot-2'
    registerApnsToken(guestId, {
      token: 'b'.repeat(64),
      platform: 'ios',
      bundleId: 'com.ragnus.mvp',
      environment: 'sandbox',
    })
    updatePushPrefs(guestId, {
      pushOptIn: true,
      timezone: 'America/Los_Angeles',
    })
    // 12:00 PT = 19:00 UTC
    const now = new Date('2026-10-06T19:00:00.000Z')
    const r = await runComeShootNudgeTick(now)
    assert.equal(r.sent, 0)
    assert.ok(r.skipped.some((s) => s.reason === 'outside_nudge_window'))
  })

  it('skips when no device token', async () => {
    const guestId = 'guest-no-token'
    updatePushPrefs(guestId, {
      pushOptIn: true,
      timezone: 'America/Los_Angeles',
    })
    const now = new Date('2026-10-07T00:00:00.000Z')
    const r = await runComeShootNudgeTick(now)
    assert.equal(r.sent, 0)
    assert.ok(r.skipped.some((s) => s.guestId === guestId))
  })
})
