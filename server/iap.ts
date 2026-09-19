/**
 * App Store IAP verification for Photo Recipes iOS.
 *
 * iOS unlocks Pro ONLY via StoreKit 2 (not Stripe web checkout).
 * POST /api/iap/verify accepts a JWS transaction (or base64 jsonRepresentation
 * fallback) and upserts the same Pro entitlement used by Stripe.
 *
 * Production: set APPLE_IAP_BUNDLE_ID + App Store Server API credentials
 * (APPLE_IAP_ISSUER_ID, APPLE_IAP_KEY_ID, APPLE_IAP_PRIVATE_KEY) to verify
 * via Apple. Without those keys, DEV mode accepts locally-shaped payloads
 * only when NODE_ENV !== 'production' — never enable that in prod.
 */
import type { Express, Request, Response } from 'express'
import crypto from 'node:crypto'
import {
  getGuestId,
  setSubscriptionCookie,
  upsertEntitlement,
  getSubscriptionStatus,
  type Plan,
} from './entitlements.ts'

const BUNDLE_ID =
  process.env.APPLE_IAP_BUNDLE_ID?.trim() || 'com.yishengjiang.photorecipes'

const PRODUCT_MONTHLY =
  process.env.APPLE_IAP_PRODUCT_MONTHLY?.trim() ||
  'com.yishengjiang.photorecipes.pro.monthly'
const PRODUCT_YEARLY =
  process.env.APPLE_IAP_PRODUCT_YEARLY?.trim() ||
  'com.yishengjiang.photorecipes.pro.yearly'

function planForProduct(productId: string): Plan {
  if (productId === PRODUCT_YEARLY) return 'yearly'
  if (productId === PRODUCT_MONTHLY) return 'monthly'
  return null
}

function appleCredentialsConfigured(): boolean {
  return Boolean(
    process.env.APPLE_IAP_ISSUER_ID?.trim() &&
      process.env.APPLE_IAP_KEY_ID?.trim() &&
      process.env.APPLE_IAP_PRIVATE_KEY?.trim(),
  )
}

/**
 * Minimal JWS payload decode (middle segment). Does NOT verify signature —
 * production path should call App Store Server API instead.
 */
function decodeJwsPayload(jws: string): Record<string, unknown> | null {
  const parts = jws.split('.')
  if (parts.length < 2) return null
  try {
    const json = Buffer.from(parts[1]!.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString(
      'utf8',
    )
    return JSON.parse(json) as Record<string, unknown>
  } catch {
    return null
  }
}

function decodeFallbackJson(signed: string): Record<string, unknown> | null {
  // Client may send base64(jsonRepresentation) when jws unavailable
  try {
    const raw = Buffer.from(signed.replace(/\s+/g, ''), 'base64').toString('utf8')
    if (raw.startsWith('{')) return JSON.parse(raw) as Record<string, unknown>
  } catch {
    /* ignore */
  }
  return decodeJwsPayload(signed)
}

async function verifyWithAppleServerAPI(
  _signedTransaction: string,
): Promise<{ ok: true; productId: string; status: 'active' | 'trialing' } | { ok: false; error: string }> {
  // Placeholder for App Store Server API (Get Transaction Info).
  // Wire with apple-signin / app-store-server-api library using:
  //   APPLE_IAP_ISSUER_ID, APPLE_IAP_KEY_ID, APPLE_IAP_PRIVATE_KEY (PEM)
  // When credentials exist but client not implemented yet, reject in production.
  if (process.env.NODE_ENV === 'production' && appleCredentialsConfigured()) {
    return {
      ok: false,
      error:
        'APPLE_IAP_* credentials are set but App Store Server API client is not wired yet. Complete server/iap.ts verifyWithAppleServerAPI before production IAP.',
    }
  }
  return { ok: false, error: 'Apple Server API not configured' }
}

export function mountIapRoutes(app: Express) {
  app.post('/api/iap/verify', (req: Request, res: Response) => {
    const body = (req.body ?? {}) as Record<string, unknown>
    const signed =
      typeof body.signedTransaction === 'string'
        ? body.signedTransaction.trim()
        : typeof body.jws === 'string'
          ? body.jws.trim()
          : ''
    const productIdHint =
      typeof body.productId === 'string' ? body.productId.trim() : ''
    const planHint =
      body.plan === 'monthly' || body.plan === 'yearly' ? (body.plan as Plan) : null

    if (!signed) {
      res.status(400).json({ error: 'signedTransaction (JWS or base64 JSON) is required' })
      return
    }

    const guestId = getGuestId(req, res)

    void (async () => {
      let productId = productIdHint
      let status: 'active' | 'trialing' = 'active'

      if (appleCredentialsConfigured() && process.env.NODE_ENV === 'production') {
        const verified = await verifyWithAppleServerAPI(signed)
        if (!verified.ok) {
          res.status(502).json({ error: verified.error })
          return
        }
        productId = verified.productId
        status = verified.status
      } else {
        // Dev / soft TestFlight without Apple API keys: decode payload shape only.
        if (process.env.NODE_ENV === 'production') {
          res.status(503).json({
            error:
              'IAP verification requires APPLE_IAP_ISSUER_ID, APPLE_IAP_KEY_ID, and APPLE_IAP_PRIVATE_KEY in production.',
          })
          return
        }
        const payload = decodeFallbackJson(signed)
        const fromPayload =
          (typeof payload?.productId === 'string' && payload.productId) ||
          (typeof payload?.productID === 'string' && payload.productID) ||
          ''
        productId = productId || fromPayload
        // Optional bundle check when present
        const bid =
          (typeof payload?.bundleId === 'string' && payload.bundleId) ||
          (typeof payload?.bid === 'string' && payload.bid) ||
          ''
        if (bid && bid !== BUNDLE_ID) {
          res.status(400).json({ error: `bundleId mismatch (expected ${BUNDLE_ID})` })
          return
        }
        console.warn(
          '[iap] DEV verify — signature not checked. Configure App Store Server API for production.',
        )
      }

      if (!productId || (productId !== PRODUCT_MONTHLY && productId !== PRODUCT_YEARLY)) {
        res.status(400).json({
          error: `Unknown productId. Expected ${PRODUCT_MONTHLY} or ${PRODUCT_YEARLY}`,
          productId,
        })
        return
      }

      const plan = planForProduct(productId) ?? planHint
      const ent = upsertEntitlement({
        status,
        plan,
        guestId,
        // Synthetic id stable per guest+product for IAP (no Stripe customer)
        id: `iap_${guestId}_${productId}`,
      })
      setSubscriptionCookie(res, ent.id)

      const sub = getSubscriptionStatus(req, res)
      res.json({
        ok: true,
        pro: sub.pro,
        status: sub.status,
        plan: sub.plan,
        productId,
        source: 'iap',
      })
    })().catch((err: Error) => {
      console.error('[iap]', err.message)
      res.status(500).json({ error: err.message || 'IAP verify failed' })
    })
  })

  app.get('/api/iap/products', (_req, res) => {
    res.json({
      bundleId: BUNDLE_ID,
      monthly: PRODUCT_MONTHLY,
      yearly: PRODUCT_YEARLY,
      appleApiConfigured: appleCredentialsConfigured(),
    })
  })
}

/** Stable hash helper (unused export for future receipt dedupe). */
export function hashTransaction(signed: string): string {
  return crypto.createHash('sha256').update(signed).digest('hex')
}
