import assert from 'node:assert/strict'
import { describe, it, beforeEach, afterEach } from 'node:test'
import {
  APIError,
  APIException,
  Environment,
  OfferDiscountType,
  OfferType,
} from '@apple/app-store-server-library'
import {
  appleCredentialsConfigured,
  decodeJwsPayload,
  evaluateAppleTransaction,
  extractTransactionId,
  normalizeApplePrivateKey,
  statusFromAppleTransaction,
  verifyWithAppleServerAPI,
} from './iap.ts'

function b64url(obj: unknown): string {
  return Buffer.from(JSON.stringify(obj), 'utf8')
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '')
}

/** Unsigned fixture JWS (header.payload.sig) — signature unused by our decoder. */
function fixtureJws(payload: Record<string, unknown>): string {
  return `${b64url({ alg: 'ES256', typ: 'JWT' })}.${b64url(payload)}.fakesig`
}

describe('iap helpers', () => {
  it('normalizeApplePrivateKey expands escaped newlines', () => {
    const raw =
      '-----BEGIN PRIVATE KEY-----\\nABC\\n-----END PRIVATE KEY-----\\n'
    const pem = normalizeApplePrivateKey(raw)
    assert.ok(pem.includes('\nABC\n'))
    assert.ok(!pem.includes('\\n'))
  })

  it('normalizeApplePrivateKey strips wrapping quotes', () => {
    const pem = normalizeApplePrivateKey(
      '"-----BEGIN PRIVATE KEY-----\\nX\\n-----END PRIVATE KEY-----"',
    )
    assert.equal(pem.startsWith('-----BEGIN'), true)
    assert.ok(pem.includes('\nX\n'))
  })

  it('decodeJwsPayload reads middle segment', () => {
    const jws = fixtureJws({
      transactionId: 'tid-1',
      productId: 'com.ragnus.mvp.pro.monthly',
      bundleId: 'com.ragnus.mvp',
    })
    const p = decodeJwsPayload(jws)
    assert.equal(p?.transactionId, 'tid-1')
    assert.equal(p?.productId, 'com.ragnus.mvp.pro.monthly')
  })

  it('extractTransactionId prefers transactionId', () => {
    const jws = fixtureJws({
      transactionId: 't-new',
      originalTransactionId: 't-orig',
    })
    assert.equal(extractTransactionId(jws), 't-new')
  })

  it('extractTransactionId falls back to originalTransactionId', () => {
    const jws = fixtureJws({ originalTransactionId: 't-orig' })
    assert.equal(extractTransactionId(jws), 't-orig')
  })
})

describe('statusFromAppleTransaction / evaluateAppleTransaction', () => {
  const now = Date.parse('2026-06-15T12:00:00.000Z')

  it('active subscription within expiresDate', () => {
    const status = statusFromAppleTransaction(
      {
        productId: 'com.ragnus.mvp.pro.monthly',
        bundleId: 'com.ragnus.mvp',
        expiresDate: now + 86_400_000,
      },
      now,
    )
    assert.equal(status, 'active')
  })

  it('trialing for introductory free trial', () => {
    const status = statusFromAppleTransaction(
      {
        productId: 'com.ragnus.mvp.pro.yearly',
        bundleId: 'com.ragnus.mvp',
        expiresDate: now + 86_400_000,
        offerType: OfferType.INTRODUCTORY_OFFER,
        offerDiscountType: OfferDiscountType.FREE_TRIAL,
      },
      now,
    )
    assert.equal(status, 'trialing')
  })

  it('rejects revoked', () => {
    assert.equal(
      statusFromAppleTransaction(
        {
          productId: 'com.ragnus.mvp.pro.monthly',
          revocationDate: now - 1000,
          expiresDate: now + 86_400_000,
        },
        now,
      ),
      null,
    )
  })

  it('rejects expired', () => {
    assert.equal(
      statusFromAppleTransaction(
        {
          productId: 'com.ragnus.mvp.pro.monthly',
          expiresDate: now - 1000,
        },
        now,
      ),
      null,
    )
  })

  it('evaluate rejects bundle mismatch', () => {
    const r = evaluateAppleTransaction(
      {
        bundleId: 'com.other.app',
        productId: 'com.ragnus.mvp.pro.monthly',
        expiresDate: now + 1000,
      },
      now,
    )
    assert.equal(r.ok, false)
    if (!r.ok) assert.match(r.error, /bundleId mismatch/)
  })

  it('evaluate accepts known product', () => {
    const r = evaluateAppleTransaction(
      {
        bundleId: 'com.ragnus.mvp',
        productId: 'com.ragnus.mvp.pro.yearly',
        expiresDate: now + 1000,
      },
      now,
    )
    assert.equal(r.ok, true)
    if (r.ok) {
      assert.equal(r.productId, 'com.ragnus.mvp.pro.yearly')
      assert.equal(r.status, 'active')
    }
  })
})

describe('verifyWithAppleServerAPI (mocked Apple client)', () => {
  const prev: Record<string, string | undefined> = {}

  beforeEach(() => {
    for (const k of [
      'APPLE_IAP_ISSUER_ID',
      'APPLE_IAP_KEY_ID',
      'APPLE_IAP_PRIVATE_KEY',
      'APPLE_IAP_ENVIRONMENT',
      'APPLE_IAP_BUNDLE_ID',
    ]) {
      prev[k] = process.env[k]
    }
    process.env.APPLE_IAP_ISSUER_ID = '00000000-0000-0000-0000-000000000001'
    process.env.APPLE_IAP_KEY_ID = 'ABC123DEFG'
    process.env.APPLE_IAP_PRIVATE_KEY =
      '-----BEGIN PRIVATE KEY-----\\nMIGH\\n-----END PRIVATE KEY-----\\n'
    process.env.APPLE_IAP_BUNDLE_ID = 'com.ragnus.mvp'
    delete process.env.APPLE_IAP_ENVIRONMENT
  })

  afterEach(() => {
    for (const [k, v] of Object.entries(prev)) {
      if (v === undefined) delete process.env[k]
      else process.env[k] = v
    }
  })

  it('appleCredentialsConfigured reflects env', () => {
    assert.equal(appleCredentialsConfigured(), true)
    delete process.env.APPLE_IAP_PRIVATE_KEY
    assert.equal(appleCredentialsConfigured(), false)
  })

  it('returns error when credentials missing', async () => {
    delete process.env.APPLE_IAP_ISSUER_ID
    const r = await verifyWithAppleServerAPI(fixtureJws({ transactionId: '1' }))
    assert.equal(r.ok, false)
    if (!r.ok) assert.match(r.error, /not configured/)
  })

  it('returns error when transactionId missing', async () => {
    const r = await verifyWithAppleServerAPI(
      fixtureJws({ productId: 'com.ragnus.mvp.pro.monthly' }),
    )
    assert.equal(r.ok, false)
    if (!r.ok) assert.match(r.error, /transactionId/)
  })

  it('unlocks Pro from mocked Get Transaction Info (Production)', async () => {
    const now = Date.parse('2026-06-15T12:00:00.000Z')
    const clientJws = fixtureJws({
      transactionId: '2000000123456789',
      productId: 'com.ragnus.mvp.pro.monthly',
      bundleId: 'com.ragnus.mvp',
    })
    const appleSigned = fixtureJws({
      transactionId: '2000000123456789',
      originalTransactionId: '2000000123456789',
      productId: 'com.ragnus.mvp.pro.monthly',
      bundleId: 'com.ragnus.mvp',
      expiresDate: now + 30 * 86_400_000,
      environment: 'Production',
    })

    const r = await verifyWithAppleServerAPI(clientJws, {
      nowMs: now,
      fetchTransactionInfo: async (tid, env) => {
        assert.equal(tid, '2000000123456789')
        assert.equal(env, Environment.PRODUCTION)
        return { signedTransactionInfo: appleSigned }
      },
    })
    assert.equal(r.ok, true)
    if (r.ok) {
      assert.equal(r.productId, 'com.ragnus.mvp.pro.monthly')
      assert.equal(r.status, 'active')
    }
  })

  it('falls back to Sandbox when Production returns TRANSACTION_ID_NOT_FOUND', async () => {
    const now = Date.parse('2026-06-15T12:00:00.000Z')
    const clientJws = fixtureJws({ transactionId: 'sandbox-tid-99' })
    const appleSigned = fixtureJws({
      transactionId: 'sandbox-tid-99',
      productId: 'com.ragnus.mvp.pro.yearly',
      bundleId: 'com.ragnus.mvp',
      expiresDate: now + 86_400_000,
      offerType: OfferType.INTRODUCTORY_OFFER,
      offerDiscountType: OfferDiscountType.FREE_TRIAL,
      environment: 'Sandbox',
    })
    const calls: Environment[] = []

    const r = await verifyWithAppleServerAPI(clientJws, {
      nowMs: now,
      fetchTransactionInfo: async (_tid, env) => {
        calls.push(env)
        if (env === Environment.PRODUCTION) {
          throw new APIException(
            404,
            APIError.TRANSACTION_ID_NOT_FOUND,
            'Transaction id not found.',
          )
        }
        return { signedTransactionInfo: appleSigned }
      },
    })
    assert.deepEqual(calls, [Environment.PRODUCTION, Environment.SANDBOX])
    assert.equal(r.ok, true)
    if (r.ok) {
      assert.equal(r.productId, 'com.ragnus.mvp.pro.yearly')
      assert.equal(r.status, 'trialing')
    }
  })

  it('honors APPLE_IAP_ENVIRONMENT=Sandbox as primary', async () => {
    process.env.APPLE_IAP_ENVIRONMENT = 'Sandbox'
    const now = Date.now()
    const clientJws = fixtureJws({ transactionId: 's1' })
    const appleSigned = fixtureJws({
      transactionId: 's1',
      productId: 'com.ragnus.mvp.pro.monthly',
      bundleId: 'com.ragnus.mvp',
      expiresDate: now + 1000,
    })
    const calls: Environment[] = []
    const r = await verifyWithAppleServerAPI(clientJws, {
      nowMs: now,
      fetchTransactionInfo: async (_tid, env) => {
        calls.push(env)
        return { signedTransactionInfo: appleSigned }
      },
    })
    assert.equal(calls[0], Environment.SANDBOX)
    assert.equal(r.ok, true)
  })

  it('rejects when Apple returns unknown productId', async () => {
    const now = Date.now()
    const r = await verifyWithAppleServerAPI(
      fixtureJws({ transactionId: 't1' }),
      {
        nowMs: now,
        fetchTransactionInfo: async () => ({
          signedTransactionInfo: fixtureJws({
            transactionId: 't1',
            productId: 'com.evil.product',
            bundleId: 'com.ragnus.mvp',
            expiresDate: now + 1000,
          }),
        }),
      },
    )
    assert.equal(r.ok, false)
    if (!r.ok) assert.match(r.error, /Unknown productId/)
  })
})
