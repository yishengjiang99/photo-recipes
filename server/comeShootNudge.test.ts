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
import { runComeShootNudgeTick, nudgeFallbackCopy, nudgeFallbackPool } from './pushScheduler.ts'
import { BRIEF_RECIPE_CHIPS, pickRecipeChips } from './pushCatalog.ts'
import { prettyLook } from './lifecycleSegments.ts'
import { validateCopy } from './lifecycleCopy.ts'

const ENV_KEYS = ['PUSH_EXP1_ENABLED', 'PUSH_PREFS_PATH', 'APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_BUNDLE_ID', 'APNS_P8_CONTENTS', 'APNS_P8_PATH', 'PUSH_COPY_GROK', 'PUSH_COPY_CACHE_PATH', 'XAI_API_KEY']

describe('runComeShootNudgeTick', () => {
  let tmp: string
  const prior: Record<string, string | undefined> = {}

  beforeEach(() => {
    tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'come-shoot-'))
    for (const k of ENV_KEYS) prior[k] = process.env[k]
    process.env.PUSH_PREFS_PATH = path.join(tmp, 'prefs.json')
    process.env.PUSH_EXP1_ENABLED = 'true'
    // Deterministic copy: no Grok in tests, isolated copy cache.
    process.env.PUSH_COPY_GROK = 'false'
    process.env.PUSH_COPY_CACHE_PATH = path.join(tmp, 'copy-cache.json')
    delete process.env.XAI_API_KEY
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

  it('rotates copy across days: never repeats the last text, and the rotation names the recipe chips', async () => {
    const guestId = 'guest-rotate-1'
    registerApnsToken(guestId, {
      token: 'c'.repeat(64),
      platform: 'ios',
      bundleId: 'com.ragnus.mvp',
      environment: 'sandbox',
    })
    updatePushPrefs(guestId, { pushOptIn: true, timezone: 'America/Los_Angeles' })

    // Day 1, 17:00 PT.
    const day1 = await runComeShootNudgeTick(new Date('2026-10-07T00:00:00.000Z'))
    assert.equal(day1.sent, 1, JSON.stringify(day1))
    const copy1 = getPushPrefs(guestId).lastNudgeCopy
    assert.ok(copy1, 'the sent copy is persisted for rotation')
    // Not the old hardcoded string.
    assert.notEqual(copy1.body, 'Light is soft right now — open the camera and Auto Optimize a frame.')

    // Day 2, 17:30 PT (past the daily dedupe: new UTC day and > 18 h later).
    const day2 = await runComeShootNudgeTick(new Date('2026-10-08T00:30:00.000Z'))
    assert.equal(day2.sent, 1, JSON.stringify(day2))
    const copy2 = getPushPrefs(guestId).lastNudgeCopy
    assert.ok(copy2)
    assert.ok(
      copy2.title !== copy1.title || copy2.body !== copy1.body,
      `copy must rotate; got the same text twice: ${JSON.stringify(copy2)}`,
    )
    // With Grok off, day 2's anti-repeat lands on the pool variant, which names a chip.
    const chipNames = pickRecipeChips(guestId, 3).map((c) => prettyLook(c.id))
    assert.ok(
      chipNames.some((n) => n && copy2.body.includes(n)),
      `rotated copy should name one of the user's chips ${JSON.stringify(chipNames)}: ${copy2.body}`,
    )
    // Both days' copy passes the guardrails for the weekly_tip segment.
    const facts = {
      tier: 'free' as const,
      capturesLastWeek: '0' as const,
      usedAutoOptimize: false,
      favoriteLook: chipNames[0] ?? null,
      awayFor: null,
    }
    assert.deepEqual(validateCopy(copy1, 'weekly_tip', facts), [])
    assert.deepEqual(validateCopy(copy2, 'weekly_tip', facts), [])
  })

  it('fallback pool: every variant passes validateCopy for every catalog chip, both kinds and tiers', () => {
    for (const kind of ['come_shoot_nudge', 'd1_return'] as const) {
      const segment = kind === 'd1_return' ? 'onboarding_d1' : 'weekly_tip'
      for (let i = 0; i < BRIEF_RECIPE_CHIPS.length; i++) {
        const chips = [0, 1, 2].map((k) => BRIEF_RECIPE_CHIPS[(i + k) % BRIEF_RECIPE_CHIPS.length]!)
        const pool = nudgeFallbackPool(kind, chips)
        assert.ok(pool.length >= 3, `${kind} pool should hold at least 3 variants, got ${pool.length}`)
        for (const v of pool) {
          for (const tier of ['free', 'pro'] as const) {
            const facts = {
              tier,
              capturesLastWeek: '0' as const,
              usedAutoOptimize: false,
              favoriteLook: prettyLook(chips[0]!.id),
              awayFor: null,
            }
            assert.deepEqual(
              validateCopy(v, segment, facts),
              [],
              `${kind}/${tier} variant must pass guardrails (chip ${chips[0]!.id}): ${JSON.stringify(v)}`,
            )
          }
          // The picker never returns the avoided (last-sent) variant.
          const picked = nudgeFallbackCopy(kind, chips, v)
          assert.ok(picked.title !== v.title || picked.body !== v.body)
        }
      }
    }
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
