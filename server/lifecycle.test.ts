/**
 * Push lifecycle: segments, copy guardrails, and engine safety (dry-run default,
 * kill switch, caps, quiet hours, consent, dead-token pruning).
 */
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { afterEach, beforeEach, describe, it } from 'node:test'
import { featuresFromEvents, matchSegments, SEGMENTS, type CopyFacts, type SegmentId, type TelemetryEventRow } from './lifecycleSegments.ts'
import { generateCopy, setCopyFetchForTests, templateCopy, validateCopy } from './lifecycleCopy.ts'
import { clearPushPrefsStoreForTests, getPushPrefs, registerApnsToken, updatePushPrefs } from './pushPrefs.ts'
import { autoGuard, effectiveMode, isKillSwitchOn, patchOps, readOps, runLifecycleTick, setLifecycleEventLoaderForTests, lifecycleReport } from './lifecycleEngine.ts'
import { clearApnsJwtCacheForTests, setApnsHttpPostForTests } from './apns.ts'

const H = 3600_000
const D = 24 * H
const NOW = new Date('2026-10-14T19:00:00Z') // 12:00 in America/Los_Angeles

function ev(event: string, agoMs: number, lookId?: string): TelemetryEventRow {
  return { event, at: new Date(NOW.getTime() - agoMs), lookId: lookId ?? null }
}

const FACTS: CopyFacts = { tier: 'free', capturesLastWeek: '1-3', usedAutoOptimize: true, favoriteLook: 'Warm Film', awayFor: 'about a week' }

describe('lifecycle segments', () => {
  it('onboarding d1 for a day-old install idle 12h+', () => {
    const f = featuresFromEvents([ev('session_start', 30 * H), ev('camera_open', 30 * H)], NOW, 'free')
    assert.equal(matchSegments(f, NOW)[0]?.segment.id, 'onboarding_d1')
  })
  it('unfinished edit outranks onboarding and clears after a capture', () => {
    const rows = [ev('session_start', 30 * H), ev('optimize_capture_abandoned', 5 * H)]
    const f = featuresFromEvents(rows, NOW, 'free')
    assert.equal(matchSegments(f, NOW)[0]?.segment.id, 'unfinished_edit')
    const f2 = featuresFromEvents([...rows, ev('capture_success', 4 * H)], NOW, 'free')
    assert.notEqual(matchSegments(f2, NOW)[0]?.segment.id, 'unfinished_edit')
  })
  it('paywall reminder only for free, never-purchased, 20–72h after view', () => {
    const rows = [ev('session_start', 20 * D), ev('paywall_view', 30 * H)]
    assert.ok(matchSegments(featuresFromEvents(rows, NOW, 'free'), NOW).some((m) => m.segment.id === 'paywall_not_converted'))
    assert.ok(!matchSegments(featuresFromEvents(rows, NOW, 'trial'), NOW).some((m) => m.segment.id === 'paywall_not_converted'))
    const bought = [...rows, ev('purchase_success', 29 * H)]
    assert.ok(!matchSegments(featuresFromEvents(bought, NOW, 'free'), NOW).some((m) => m.segment.id === 'paywall_not_converted'))
  })
  it('inactivity tiers + favorite look; push opens do not reset inactivity', () => {
    const rows = [ev('session_start', 40 * D), ev('look_applied', 9 * D, 'warm_film'), ev('look_applied', 9 * D, 'warm_film'), ev('push_opened', 1 * D)]
    const f = featuresFromEvents(rows, NOW, 'free')
    assert.equal(f.favoriteLook, 'warm_film')
    assert.equal(matchSegments(f, NOW)[0]?.segment.id, 'inactive_7')
    assert.equal(matchSegments(featuresFromEvents([ev('session_start', 35 * D)], NOW, 'free'), NOW)[0]?.segment.id, 'winback_30')
    assert.equal(matchSegments(featuresFromEvents([ev('session_start', 50 * D)], NOW, 'free'), NOW).length, 0)
  })
})

describe('lifecycle copy guardrails', () => {
  it('every template passes its own guardrails for every tier', () => {
    for (const seg of Object.keys(SEGMENTS) as SegmentId[]) {
      for (const tier of ['free', 'trial', 'pro'] as const) {
        for (const look of [null, 'Warm Film']) {
          const facts = { ...FACTS, tier, favoriteLook: look, announcement: 'Selfie looks for the front camera.' }
          const c = templateCopy(seg, facts)
          assert.deepEqual(validateCopy(c, seg, facts), [], `${seg}/${tier}: ${JSON.stringify(c)}`)
        }
      }
    }
  })
  it('rejects urgency, prices, links, wrong trial length, upsell outside paywall, too long', () => {
    const bad: Array<[string, SegmentId]> = [
      ['Hurry, last chance to shoot!', 'inactive_7'],
      ['Pro is only $7.99 a month', 'paywall_not_converted'],
      ['50% off Pro this week', 'paywall_not_converted'],
      ['See photo.grepawk.com', 'onboarding_d1'],
      ['Start your 3-day free trial if eligible', 'paywall_not_converted'],
      ['Upgrade to Pro for more looks', 'inactive_14'],
      ['We miss you', 'winback_30'],
      ["It's been a month since you last opened ProTune", 'winback_30'],
      ['x'.repeat(141), 'onboarding_d3'],
      ['Try the new look', 'onboarding_d3'],
      ['Get it FREE today', 'paywall_not_converted'],
      ['Pro adds all looks and recipes. Eligible new subscribers get a 7-day free trial.', 'paywall_not_converted'],
    ]
    for (const [body, seg] of bad) {
      assert.notDeepEqual(validateCopy({ title: 'Hi', body }, seg, FACTS), [], body)
    }
    assert.deepEqual(
      validateCopy({ title: 'Still deciding?', body: 'Pro unlocks unlimited Auto Optimize. Eligible new subscribers get a 7-day free trial.' }, 'paywall_not_converted', FACTS),
      [],
    )
  })
  it('falls back to template when Grok output fails guardrails, caches good output', async () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'copy-'))
    process.env.PUSH_COPY_CACHE_PATH = path.join(tmp, 'cache.json')
    const priorKey = process.env.XAI_API_KEY
    process.env.XAI_API_KEY = 'test-key'
    let calls = 0
    const reply = (content: string) => ({ ok: true, status: 200, json: async () => ({ choices: [{ message: { content } }] }) })
    try {
      setCopyFetchForTests((async () => {
        calls++
        return reply('{"title":"HURRY!!","body":"Last chance: 50% off"}')
      }) as unknown as typeof fetch)
      const r1 = await generateCopy('inactive_7', SEGMENTS.inactive_7.goal, FACTS, { now: NOW })
      assert.equal(r1.source, 'template')
      assert.ok(r1.rejected?.length)

      setCopyFetchForTests((async () => {
        calls++
        return reply('{"title":"Soft light this week","body":"Your Warm Film look suits window light. Open the camera and give it a try."}')
      }) as unknown as typeof fetch)
      const r2 = await generateCopy('inactive_7', SEGMENTS.inactive_7.goal, FACTS, { now: NOW })
      assert.equal(r2.source, 'grok')
      const before = calls
      const r3 = await generateCopy('inactive_7', SEGMENTS.inactive_7.goal, FACTS, { now: NOW })
      assert.equal(r3.source, 'cache')
      assert.equal(calls, before)

      setCopyFetchForTests((async () => {
        throw new Error('network down')
      }) as unknown as typeof fetch)
      const r4 = await generateCopy('onboarding_d1', SEGMENTS.onboarding_d1.goal, FACTS, { now: NOW })
      assert.equal(r4.source, 'template')
    } finally {
      setCopyFetchForTests(null)
      if (priorKey === undefined) delete process.env.XAI_API_KEY
      else process.env.XAI_API_KEY = priorKey
      delete process.env.PUSH_COPY_CACHE_PATH
      fs.rmSync(tmp, { recursive: true, force: true })
    }
  })
})

const ENV_KEYS = [
  'PUSH_PREFS_PATH', 'PUSH_LIFECYCLE_MODE', 'PUSH_KILL_SWITCH', 'PUSH_LIFECYCLE_ALLOWLIST', 'PUSH_LIFECYCLE_STATE_PATH',
  'PUSH_LIFECYCLE_DRY_STATE_PATH', 'PUSH_LIFECYCLE_LOG_PATH', 'PUSH_LIFECYCLE_OPS_PATH', 'PUSH_LIFECYCLE_LAST_TICK_PATH',
  'PUSH_COPY_CACHE_PATH', 'PUSH_COPY_GROK', 'PUSH_EVENTS_LOG_PATH',
  'APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_BUNDLE_ID', 'APNS_P8_CONTENTS', 'APNS_P8_PATH', 'MYSQL_URL', 'MYSQL_HOST',
]
const TOKEN = 'a'.repeat(64)

describe('lifecycle engine safety', () => {
  let tmp: string
  const prior: Record<string, string | undefined> = {}
  let apnsCalls = 0

  beforeEach(() => {
    tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'lifecycle-'))
    for (const k of ENV_KEYS) prior[k] = process.env[k]
    for (const k of ENV_KEYS) delete process.env[k]
    process.env.PUSH_PREFS_PATH = path.join(tmp, 'prefs.json')
    for (const [k, f] of [
      ['PUSH_LIFECYCLE_STATE_PATH', 'state.json'], ['PUSH_LIFECYCLE_DRY_STATE_PATH', 'dry.json'], ['PUSH_LIFECYCLE_LOG_PATH', 'log.jsonl'],
      ['PUSH_LIFECYCLE_OPS_PATH', 'ops.json'], ['PUSH_LIFECYCLE_LAST_TICK_PATH', 'last.json'], ['PUSH_COPY_CACHE_PATH', 'cache.json'],
      ['PUSH_EVENTS_LOG_PATH', 'events.jsonl'],
    ]) process.env[k!] = path.join(tmp, f!)
    process.env.PUSH_COPY_GROK = 'false'
    clearPushPrefsStoreForTests()
    apnsCalls = 0
    setApnsHttpPostForTests(async () => {
      apnsCalls++
      return { status: 200, body: '' }
    })
    // Day-old install idle 30h → onboarding_d1 (feature class).
    setLifecycleEventLoaderForTests(async () => ({ rows: [ev('session_start', 30 * H)], firstSeen: null }))
    registerApnsToken('g1', { token: TOKEN, platform: 'ios', bundleId: 'com.ragnus.mvp', environment: 'production', timezone: 'America/Los_Angeles', anonId: 'anon-0001-abcd' })
  })

  afterEach(() => {
    setApnsHttpPostForTests(null)
    setLifecycleEventLoaderForTests(null)
    clearApnsJwtCacheForTests()
    for (const k of ENV_KEYS) {
      if (prior[k] === undefined) delete process.env[k]
      else process.env[k] = prior[k]
    }
    fs.rmSync(tmp, { recursive: true, force: true })
  })

  function liveApnsEnv() {
    // Throwaway EC key so sendApns signs a JWT (HTTP is stubbed — Apple is never contacted).
    const { privateKey } = require_crypto().generateKeyPairSync('ec', { namedCurve: 'prime256v1' })
    process.env.APNS_KEY_ID = 'TESTKEY123'
    process.env.APNS_TEAM_ID = 'TEAM123456'
    process.env.APNS_BUNDLE_ID = 'com.ragnus.mvp'
    process.env.APNS_P8_CONTENTS = privateKey.export({ type: 'pkcs8', format: 'pem' }).toString()
  }

  it('defaults to dry_run and never calls APNs, even with APNs configured', async () => {
    liveApnsEnv()
    assert.equal(effectiveMode(), 'dry_run')
    const s = await runLifecycleTick(NOW)
    assert.equal(s.wouldSend, 1)
    assert.equal(s.sent, 0)
    assert.equal(apnsCalls, 0)
    // dedupe: second tick does not re-generate the same message
    const s2 = await runLifecycleTick(new Date(NOW.getTime() + 25 * H))
    assert.equal(s2.wouldSend, 0)
    assert.equal(lifecycleReport().kpis.wouldSend, 1)
  })

  it('auto guard: opt-outs above 2% (distinct installs, since go-live) flip the kill switch', () => {
    const start = new Date(NOW.getTime() - 2 * D)
    fs.writeFileSync(process.env.PUSH_LIFECYCLE_OPS_PATH!, JSON.stringify({ liveSince: start.toISOString() }))
    const line = (guestId: string, agoMs: number, event = 'push_opt_out') => JSON.stringify({ at: new Date(NOW.getTime() - agoMs).toISOString(), guestId, event }) + '\n'
    // before go-live: ignored; same install twice: counted once
    fs.writeFileSync(process.env.PUSH_EVENTS_LOG_PATH!, line('old', 3 * D) + line('a', H) + line('a', H, 'push_marketing_opt_out'))
    let g = autoGuard(NOW)
    assert.equal(g.optOuts, 1)
    assert.equal(g.tripped, false) // below the 2-install minimum
    fs.appendFileSync(process.env.PUSH_EVENTS_LOG_PATH!, line('b', H))
    g = autoGuard(NOW)
    assert.equal(g.optOuts, 2)
    assert.equal(g.tripped, true)
    assert.ok(isKillSwitchOn())
    assert.match(String(readOps().autoKill?.reason), /opt_out_rate/)
    assert.equal(effectiveMode(), 'off')
  })

  it('auto guard: APNs error rate above 20% over 10+ attempts flips the kill switch; uninstalls do not count', () => {
    const rows: string[] = []
    for (let i = 0; i < 12; i++) {
      const results = i < 6 ? [{ ok: false, status: 410, error: 'Unregistered' }] : i < 9 ? [{ ok: true }] : [{ ok: false, status: 403, error: 'InvalidProviderToken' }]
      rows.push(JSON.stringify({ at: new Date(NOW.getTime() - H).toISOString(), event: i < 6 || i >= 9 ? 'lifecycle_send_failed' : 'lifecycle_sent', results }))
    }
    fs.writeFileSync(process.env.PUSH_LIFECYCLE_LOG_PATH!, rows.join('\n') + '\n')
    const dry = autoGuard(NOW, { dryRun: true })
    assert.equal(dry.apnsAttempts24h, 12)
    assert.equal(dry.apnsErrors24h, 3)
    assert.equal(dry.tripped, false)
    assert.ok(!isKillSwitchOn())
    const g = autoGuard(NOW)
    assert.equal(g.tripped, true) // 3/12 = 25% > 20%
    assert.ok(isKillSwitchOn())
  })

  it('kill switch (runtime) stops everything; ops can only downgrade the env mode', async () => {
    process.env.PUSH_LIFECYCLE_MODE = 'live'
    liveApnsEnv()
    patchOps({ killSwitch: true })
    assert.equal(effectiveMode(), 'off')
    const s = await runLifecycleTick(NOW)
    assert.equal(s.scanned, 0)
    assert.equal(apnsCalls, 0)
    patchOps({ killSwitch: false, mode: 'dry_run' })
    assert.equal(effectiveMode(), 'dry_run')
    process.env.PUSH_LIFECYCLE_MODE = 'dry_run'
    patchOps({ mode: 'live' })
    assert.equal(effectiveMode(), 'dry_run')
  })

  it('live: sends once, then daily cap blocks; quiet hours and consent respected', async () => {
    process.env.PUSH_LIFECYCLE_MODE = 'live'
    liveApnsEnv()
    const s = await runLifecycleTick(NOW)
    assert.equal(s.sent, 1)
    assert.equal(apnsCalls, 1)
    assert.ok(getPushPrefs('g1').lastNudgeAt, 'shares cap with legacy nudges')
    // Different segment the next morning would still hit the daily cap within 24h.
    setLifecycleEventLoaderForTests(async () => ({ rows: [ev('session_start', 3.5 * D)], firstSeen: null }))
    const s2 = await runLifecycleTick(new Date(NOW.getTime() + 2 * H))
    assert.equal(s2.sent, 0)
    assert.equal(s2.skipped.cap_daily, 1)
    // 23:00 local → quiet hours
    const late = new Date('2026-10-18T06:00:00Z')
    const s3 = await runLifecycleTick(late)
    assert.equal(s3.sent, 0)
    // promotional segment without marketing consent → skipped
    setLifecycleEventLoaderForTests(async () => ({ rows: [ev('session_start', 20 * D), ev('camera_open', 8 * D)], firstSeen: null }))
    const s4 = await runLifecycleTick(new Date(NOW.getTime() + 3 * D))
    assert.equal(s4.skipped.no_marketing_consent, 1)
    updatePushPrefs('g1', { marketingOptIn: true })
    const s5 = await runLifecycleTick(new Date(NOW.getTime() + 3 * D))
    assert.equal(s5.sent, 1)
    assert.equal(s5.decisions[0]?.segment, 'inactive_7')
  })

  it('allowlist mode only really sends to listed installs', async () => {
    process.env.PUSH_LIFECYCLE_MODE = 'allowlist'
    liveApnsEnv()
    const s = await runLifecycleTick(NOW)
    assert.equal(s.sent, 0)
    assert.equal(s.wouldSend, 1)
    process.env.PUSH_LIFECYCLE_ALLOWLIST = 'g1'
    registerApnsToken('g2', { token: 'b'.repeat(64), platform: 'ios', bundleId: 'com.ragnus.mvp', environment: 'production', anonId: 'anon-0002-abcd', timezone: 'America/Los_Angeles' })
    const s2 = await runLifecycleTick(new Date(NOW.getTime() + 1000))
    // g1 (allowlisted) really sends — dry-run history is separate from real history;
    // g2 (not listed) stays a would_send.
    assert.equal(s2.sent, 1)
    assert.equal(s2.wouldSend, 1)
    assert.equal(apnsCalls, 1)
  })

  it('prunes tokens on 410 / BadDeviceToken', async () => {
    process.env.PUSH_LIFECYCLE_MODE = 'live'
    liveApnsEnv()
    setApnsHttpPostForTests(async () => {
      apnsCalls++
      return { status: 400, body: '{"reason":"BadDeviceToken"}' }
    })
    const s = await runLifecycleTick(NOW)
    assert.equal(s.sent, 0)
    assert.equal(getPushPrefs('g1').apnsDeviceTokens.length, 0)
  })
})

import { createRequire } from 'node:module'
function require_crypto() {
  return createRequire(import.meta.url)('node:crypto') as typeof import('node:crypto')
}
