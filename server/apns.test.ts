import assert from 'node:assert/strict'
import crypto from 'node:crypto'
import { describe, it, beforeEach, afterEach } from 'node:test'
import {
  clearApnsJwtCacheForTests,
  sendApns,
  setApnsHttpPostForTests,
  isApnsEnvPresent,
  type ApnsPayload,
} from './apns.ts'

/** Generate a throwaway EC P-256 PKCS8 PEM for JWT signing in unit tests. */
function generateTestP8(): string {
  const { privateKey } = crypto.generateKeyPairSync('ec', {
    namedCurve: 'P-256',
  })
  return privateKey.export({ type: 'pkcs8', format: 'pem' }).toString()
}

const SAMPLE_TOKEN = 'a'.repeat(64)

const samplePayload: ApnsPayload = {
  aps: { alert: { title: 'T', body: 'B' }, sound: 'default' },
  type: 'pre_alarm_shoot_brief',
  deepLink: 'photo-recipes://auto-optimize',
  recipeChips: [{ id: 'c1', title: 'Chip' }],
  entitlementTier: 'free',
  experiment: 'push_exp1',
}

describe('sendApns', () => {
  const prev: Record<string, string | undefined> = {}
  const keys = [
    'APNS_KEY_ID',
    'APNS_TEAM_ID',
    'APNS_BUNDLE_ID',
    'APNS_P8_PATH',
    'APNS_P8_CONTENTS',
    'APNS_ENVIRONMENT',
  ]

  beforeEach(() => {
    for (const k of keys) {
      prev[k] = process.env[k]
      delete process.env[k]
    }
    clearApnsJwtCacheForTests()
    setApnsHttpPostForTests(null)
  })

  afterEach(() => {
    for (const k of keys) {
      if (prev[k] === undefined) delete process.env[k]
      else process.env[k] = prev[k]
    }
    clearApnsJwtCacheForTests()
    setApnsHttpPostForTests(null)
  })

  it('stubs when APNS_* unset', async () => {
    assert.equal(isApnsEnvPresent(), false)
    const r = await sendApns(SAMPLE_TOKEN, samplePayload)
    assert.equal(r.ok, true)
    assert.equal('stub' in r && r.stub, true)
    if (r.ok && 'stub' in r && r.stub) {
      assert.match(r.reason, /not configured/)
    }
  })

  it('live path returns stub:false status on mocked 200', async () => {
    process.env.APNS_KEY_ID = 'KEYID123'
    process.env.APNS_TEAM_ID = 'TEAMID12'
    process.env.APNS_BUNDLE_ID = 'com.ragnus.mvp'
    process.env.APNS_P8_CONTENTS = generateTestP8()
    process.env.APNS_ENVIRONMENT = 'sandbox'

    let captured: {
      host: string
      path: string
      headers: Record<string, string>
      body: string
    } | null = null

    setApnsHttpPostForTests(async (args) => {
      captured = args
      return { status: 200, body: '' }
    })

    const r = await sendApns(SAMPLE_TOKEN, samplePayload, {
      environment: 'sandbox',
    })
    assert.equal(r.ok, true)
    assert.equal('stub' in r && r.stub === false, true)
    if (r.ok && 'stub' in r && !r.stub) {
      assert.equal(r.status, 200)
    }
    assert.ok(captured)
    assert.equal(captured!.host, 'api.sandbox.push.apple.com')
    assert.equal(captured!.path, `/3/device/${SAMPLE_TOKEN}`)
    assert.equal(captured!.headers['apns-topic'], 'com.ragnus.mvp')
    assert.equal(captured!.headers['apns-push-type'], 'alert')
    assert.ok(captured!.headers.authorization?.startsWith('bearer '))
    const parsed = JSON.parse(captured!.body) as ApnsPayload
    assert.equal(parsed.type, 'pre_alarm_shoot_brief')
    assert.equal(parsed.aps.alert.title, 'T')
  })

  it('uses production host when environment=production', async () => {
    process.env.APNS_KEY_ID = 'KEYID123'
    process.env.APNS_TEAM_ID = 'TEAMID12'
    process.env.APNS_P8_CONTENTS = generateTestP8()

    let host = ''
    setApnsHttpPostForTests(async (args) => {
      host = args.host
      return { status: 200, body: '' }
    })

    await sendApns(SAMPLE_TOKEN, samplePayload, { environment: 'production' })
    assert.equal(host, 'api.push.apple.com')
  })

  it('returns ok:false on Apple rejection (mocked)', async () => {
    process.env.APNS_KEY_ID = 'KEYID123'
    process.env.APNS_TEAM_ID = 'TEAMID12'
    process.env.APNS_P8_CONTENTS = generateTestP8()

    setApnsHttpPostForTests(async () => ({
      status: 400,
      body: JSON.stringify({ reason: 'BadDeviceToken' }),
    }))

    const r = await sendApns(SAMPLE_TOKEN, samplePayload)
    assert.equal(r.ok, false)
    if (!r.ok) {
      assert.equal(r.status, 400)
      assert.match(r.error, /BadDeviceToken/)
    }
  })

  it('rejects invalid device token hex', async () => {
    process.env.APNS_KEY_ID = 'KEYID123'
    process.env.APNS_TEAM_ID = 'TEAMID12'
    process.env.APNS_P8_CONTENTS = generateTestP8()

    let called = false
    setApnsHttpPostForTests(async () => {
      called = true
      return { status: 200, body: '' }
    })

    const r = await sendApns('not-a-token', samplePayload)
    assert.equal(r.ok, false)
    if (!r.ok) assert.equal(r.error, 'invalid_device_token')
    assert.equal(called, false)
  })
})
