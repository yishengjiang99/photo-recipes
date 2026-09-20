import assert from 'node:assert/strict'
import { describe, it, afterEach, beforeEach } from 'node:test'
import {
  clearOpsConfigOverridesForTests,
  getFreeDailyLimitFromOps,
  getFreePhoneTargetsEnabled,
  patchOpsConfig,
  resolveOpsConfig,
  DEFAULT_FREE_DAILY_LIMIT,
  DEFAULT_FREE_PHONE_TARGETS_ENABLED,
} from './opsConfig.ts'
import { getFreeDailyLimit, getQuotaConfigSnapshot } from './entitlements.ts'

describe('ops config resolution', () => {
  const prev = {
    FREE_DAILY_LIMIT: process.env.FREE_DAILY_LIMIT,
    FREE_PHONE_TARGETS_ENABLED: process.env.FREE_PHONE_TARGETS_ENABLED,
  }

  beforeEach(() => {
    clearOpsConfigOverridesForTests()
    delete process.env.FREE_DAILY_LIMIT
    delete process.env.FREE_PHONE_TARGETS_ENABLED
  })

  afterEach(() => {
    clearOpsConfigOverridesForTests()
    if (prev.FREE_DAILY_LIMIT === undefined) delete process.env.FREE_DAILY_LIMIT
    else process.env.FREE_DAILY_LIMIT = prev.FREE_DAILY_LIMIT
    if (prev.FREE_PHONE_TARGETS_ENABLED === undefined) {
      delete process.env.FREE_PHONE_TARGETS_ENABLED
    } else {
      process.env.FREE_PHONE_TARGETS_ENABLED = prev.FREE_PHONE_TARGETS_ENABLED
    }
  })

  it('defaults freeDailyLimit to 5 and dials on', () => {
    const cfg = resolveOpsConfig()
    assert.equal(cfg.freeDailyLimit, DEFAULT_FREE_DAILY_LIMIT)
    assert.equal(cfg.freePhoneTargetsEnabled, DEFAULT_FREE_PHONE_TARGETS_ENABLED)
    assert.equal(cfg.sources.freeDailyLimit, 'default')
    assert.equal(cfg.sources.freePhoneTargetsEnabled, 'default')
    assert.equal(getFreeDailyLimit(), 5)
    assert.equal(getFreePhoneTargetsEnabled(), true)
  })

  it('reads FREE_DAILY_LIMIT from env when no override', () => {
    process.env.FREE_DAILY_LIMIT = '12'
    assert.equal(getFreeDailyLimitFromOps(), 12)
    assert.equal(resolveOpsConfig().sources.freeDailyLimit, 'env')
  })

  it('reads FREE_PHONE_TARGETS_ENABLED from env', () => {
    process.env.FREE_PHONE_TARGETS_ENABLED = 'false'
    assert.equal(getFreePhoneTargetsEnabled(), false)
    assert.equal(resolveOpsConfig().sources.freePhoneTargetsEnabled, 'env')
  })

  it('override beats env for freeDailyLimit', () => {
    process.env.FREE_DAILY_LIMIT = '12'
    const r = patchOpsConfig({ freeDailyLimit: 3 })
    assert.equal(r.ok, true)
    assert.equal(getFreeDailyLimit(), 3)
    assert.equal(resolveOpsConfig().sources.freeDailyLimit, 'override')
  })

  it('override beats env for freePhoneTargetsEnabled', () => {
    process.env.FREE_PHONE_TARGETS_ENABLED = 'false'
    const r = patchOpsConfig({ freePhoneTargetsEnabled: true })
    assert.equal(r.ok, true)
    assert.equal(getFreePhoneTargetsEnabled(), true)
    assert.equal(resolveOpsConfig().sources.freePhoneTargetsEnabled, 'override')
  })

  it('allows freeDailyLimit 0 (no free peeks)', () => {
    const r = patchOpsConfig({ freeDailyLimit: 0 })
    assert.equal(r.ok, true)
    assert.equal(getFreeDailyLimit(), 0)
  })

  it('rejects negative freeDailyLimit', () => {
    const r = patchOpsConfig({ freeDailyLimit: -1 })
    assert.equal(r.ok, false)
    if (!r.ok) assert.equal(r.error, 'invalid_freeDailyLimit')
    assert.equal(getFreeDailyLimit(), 5)
  })

  it('rejects non-integer freeDailyLimit', () => {
    const r = patchOpsConfig({ freeDailyLimit: 2.5 })
    assert.equal(r.ok, false)
    if (!r.ok) assert.equal(r.error, 'invalid_freeDailyLimit')
  })

  it('rejects non-boolean freePhoneTargetsEnabled', () => {
    const r = patchOpsConfig({ freePhoneTargetsEnabled: 'maybe' })
    assert.equal(r.ok, false)
    if (!r.ok) assert.equal(r.error, 'invalid_freePhoneTargetsEnabled')
  })

  it('rejects non-object body', () => {
    const r = patchOpsConfig('nope')
    assert.equal(r.ok, false)
    if (!r.ok) assert.equal(r.error, 'invalid_body')
  })

  it('null clears override back to env/default', () => {
    assert.equal(patchOpsConfig({ freeDailyLimit: 9 }).ok, true)
    assert.equal(getFreeDailyLimit(), 9)
    process.env.FREE_DAILY_LIMIT = '4'
    assert.equal(patchOpsConfig({ freeDailyLimit: null }).ok, true)
    assert.equal(getFreeDailyLimit(), 4)
    assert.equal(resolveOpsConfig().sources.freeDailyLimit, 'env')
  })

  it('quota snapshot exposes effective + sources', () => {
    process.env.FREE_DAILY_LIMIT = '7'
    assert.equal(patchOpsConfig({ freePhoneTargetsEnabled: false }).ok, true)
    const snap = getQuotaConfigSnapshot()
    assert.equal(snap.freeDailyLimit, 7)
    assert.equal(snap.freePhoneTargetsEnabled, false)
    assert.equal(snap.sources?.freeDailyLimit, 'env')
    assert.equal(snap.sources?.freePhoneTargetsEnabled, 'override')
    assert.equal(snap.overrides?.freePhoneTargetsEnabled, false)
  })
})
