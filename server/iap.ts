/**
 * App Store IAP verification for Photo Recipes iOS.
 *
 * iOS unlocks Pro ONLY via StoreKit 2 (not Stripe web checkout).
 * POST /api/iap/verify accepts a JWS transaction (or base64 jsonRepresentation
 * fallback) and upserts the same Pro entitlement used by Stripe.
 *
 * Production: set APPLE_IAP_BUNDLE_ID + App Store Server API credentials
 * (APPLE_IAP_ISSUER_ID, APPLE_IAP_KEY_ID, APPLE_IAP_PRIVATE_KEY) to verify
 * via Apple Get Transaction Info. Without those keys, DEV mode accepts
 * locally-shaped payloads only when NODE_ENV !== 'production'.
 */
import type { Express, Request, Response } from 'express'
import crypto from 'node:crypto'
import {
  APIError,
  APIException,
  AppStoreServerAPIClient,
  Environment,
  OfferDiscountType,
  OfferType,
  type JWSTransactionDecodedPayload,
  type TransactionInfoResponse,
} from '@apple/app-store-server-library'
import {
  getGuestId,
  setSubscriptionCookie,
  upsertEntitlement,
  isProStatus,
  type Plan,
} from './entitlements.ts'

const BUNDLE_ID =
  process.env.APPLE_IAP_BUNDLE_ID?.trim() || 'com.ragnus.mvp'

const PRODUCT_MONTHLY =
  process.env.APPLE_IAP_PRODUCT_MONTHLY?.trim() ||
  'com.ragnus.mvp.pro.monthly'
const PRODUCT_YEARLY =
  process.env.APPLE_IAP_PRODUCT_YEARLY?.trim() ||
  'com.ragnus.mvp.pro.yearly'

export type AppleVerifyOk = {
  ok: true
  productId: string
  status: 'active' | 'trialing'
}
export type AppleVerifyErr = { ok: false; error: string }
export type AppleVerifyResult = AppleVerifyOk | AppleVerifyErr

/** Injectable Apple Get Transaction Info for unit tests (no live network). */
export type AppleTransactionFetcher = (
  transactionId: string,
  environment: Environment,
) => Promise<TransactionInfoResponse>

export type VerifyAppleOptions = {
  fetchTransactionInfo?: AppleTransactionFetcher
  nowMs?: number
}

function planForProduct(productId: string): Plan {
  if (productId === PRODUCT_YEARLY) return 'yearly'
  if (productId === PRODUCT_MONTHLY) return 'monthly'
  return null
}

export function appleCredentialsConfigured(): boolean {
  return Boolean(
    process.env.APPLE_IAP_ISSUER_ID?.trim() &&
      process.env.APPLE_IAP_KEY_ID?.trim() &&
      process.env.APPLE_IAP_PRIVATE_KEY?.trim(),
  )
}

/** PEM may arrive as a single-line env value with literal \n escapes. */
export function normalizeApplePrivateKey(raw: string): string {
  let key = raw.trim()
  // Strip wrapping quotes some secret managers add
  if (
    (key.startsWith('"') && key.endsWith('"')) ||
    (key.startsWith("'") && key.endsWith("'"))
  ) {
    key = key.slice(1, -1)
  }
  return key.replace(/\\n/g, '\n')
}

function preferredAppleEnvironment(): Environment {
  const raw = process.env.APPLE_IAP_ENVIRONMENT?.trim().toLowerCase()
  if (raw === 'sandbox') return Environment.SANDBOX
  return Environment.PRODUCTION
}

function alternateEnvironment(env: Environment): Environment {
  return env === Environment.PRODUCTION
    ? Environment.SANDBOX
    : Environment.PRODUCTION
}

function createAppleClient(environment: Environment): AppStoreServerAPIClient {
  const issuerId = process.env.APPLE_IAP_ISSUER_ID!.trim()
  const keyId = process.env.APPLE_IAP_KEY_ID!.trim()
  const privateKey = normalizeApplePrivateKey(
    process.env.APPLE_IAP_PRIVATE_KEY!,
  )
  return new AppStoreServerAPIClient(
    privateKey,
    keyId,
    issuerId,
    BUNDLE_ID,
    environment,
  )
}

const defaultFetchTransactionInfo: AppleTransactionFetcher = async (
  transactionId,
  environment,
) => {
  const client = createAppleClient(environment)
  return client.getTransactionInfo(transactionId)
}

/**
 * Minimal JWS payload decode (middle segment). Does NOT verify signature —
 * production path confirms via App Store Server API Get Transaction Info.
 */
export function decodeJwsPayload(jws: string): Record<string, unknown> | null {
  const parts = jws.split('.')
  if (parts.length < 2) return null
  try {
    const json = Buffer.from(
      parts[1]!.replace(/-/g, '+').replace(/_/g, '/'),
      'base64',
    ).toString('utf8')
    return JSON.parse(json) as Record<string, unknown>
  } catch {
    return null
  }
}

export function decodeFallbackJson(
  signed: string,
): Record<string, unknown> | null {
  // Client may send base64(jsonRepresentation) when jws unavailable
  try {
    const raw = Buffer.from(signed.replace(/\s+/g, ''), 'base64').toString(
      'utf8',
    )
    if (raw.startsWith('{')) return JSON.parse(raw) as Record<string, unknown>
  } catch {
    /* ignore */
  }
  return decodeJwsPayload(signed)
}

export function extractTransactionId(signed: string): string | null {
  const payload = decodeFallbackJson(signed)
  if (!payload) return null
  const tid =
    (typeof payload.transactionId === 'string' && payload.transactionId) ||
    (typeof payload.originalTransactionId === 'string' &&
      payload.originalTransactionId) ||
    ''
  return tid || null
}

function isTransactionNotFound(err: unknown): boolean {
  if (!(err instanceof APIException)) return false
  if (err.httpStatusCode === 404) return true
  return (
    err.apiError === APIError.TRANSACTION_ID_NOT_FOUND ||
    err.apiError === APIError.INVALID_TRANSACTION_ID
  )
}

/**
 * Map a verified Apple transaction payload to Pro unlock status.
 * Active or introductory free-trial → unlock; revoked/expired → reject.
 */
export function statusFromAppleTransaction(
  tx: JWSTransactionDecodedPayload,
  nowMs: number = Date.now(),
): 'active' | 'trialing' | null {
  if (tx.revocationDate != null) return null
  if (typeof tx.expiresDate === 'number' && tx.expiresDate < nowMs) return null

  const offerType = tx.offerType
  const discount = tx.offerDiscountType
  const isIntro =
    offerType === OfferType.INTRODUCTORY_OFFER || offerType === 1
  const isFreeTrial =
    discount === OfferDiscountType.FREE_TRIAL || discount === 'FREE_TRIAL'
  if (isIntro && isFreeTrial) return 'trialing'
  // Introductory offer without explicit FREE_TRIAL still counts as Pro access
  if (isIntro) return 'trialing'
  return 'active'
}

export function evaluateAppleTransaction(
  tx: JWSTransactionDecodedPayload,
  nowMs: number = Date.now(),
): AppleVerifyResult {
  if (tx.bundleId && tx.bundleId !== BUNDLE_ID) {
    return {
      ok: false,
      error: `bundleId mismatch (expected ${BUNDLE_ID}, got ${tx.bundleId})`,
    }
  }
  const productId = typeof tx.productId === 'string' ? tx.productId : ''
  if (!productId) {
    return { ok: false, error: 'Apple transaction missing productId' }
  }
  if (productId !== PRODUCT_MONTHLY && productId !== PRODUCT_YEARLY) {
    return {
      ok: false,
      error: `Unknown productId from Apple. Expected ${PRODUCT_MONTHLY} or ${PRODUCT_YEARLY}`,
    }
  }
  const status = statusFromAppleTransaction(tx, nowMs)
  if (!status) {
    return {
      ok: false,
      error: 'Apple transaction is revoked or expired',
    }
  }
  return { ok: true, productId, status }
}

/**
 * Verify StoreKit 2 JWS by calling App Store Server API Get Transaction Info.
 * Prefers APPLE_IAP_ENVIRONMENT (default Production); on not-found retries
 * the other environment (TestFlight / Sandbox).
 */
export async function verifyWithAppleServerAPI(
  signedTransaction: string,
  options: VerifyAppleOptions = {},
): Promise<AppleVerifyResult> {
  if (!appleCredentialsConfigured()) {
    return { ok: false, error: 'Apple Server API not configured' }
  }

  const transactionId = extractTransactionId(signedTransaction)
  if (!transactionId) {
    return {
      ok: false,
      error:
        'Could not extract transactionId from signedTransaction (need StoreKit 2 JWS)',
    }
  }

  const fetchInfo =
    options.fetchTransactionInfo ?? defaultFetchTransactionInfo
  const nowMs = options.nowMs ?? Date.now()
  const primary = preferredAppleEnvironment()
  const order: Environment[] = [primary, alternateEnvironment(primary)]

  let lastError = 'Apple Get Transaction Info failed'
  for (let i = 0; i < order.length; i++) {
    const env = order[i]!
    try {
      const response = await fetchInfo(transactionId, env)
      const signedInfo = response.signedTransactionInfo
      if (!signedInfo) {
        lastError = 'Apple response missing signedTransactionInfo'
        continue
      }
      const payload = decodeJwsPayload(signedInfo) as
        | JWSTransactionDecodedPayload
        | null
      if (!payload) {
        lastError = 'Could not decode Apple signedTransactionInfo'
        continue
      }
      return evaluateAppleTransaction(payload, nowMs)
    } catch (err) {
      if (i === 0 && isTransactionNotFound(err)) {
        // TestFlight / Sandbox receipts often miss on Production — try other env
        console.warn(
          `[iap] transaction ${transactionId} not found in ${env}; trying ${order[1]}`,
        )
        continue
      }
      if (err instanceof APIException) {
        lastError = `Apple API ${err.httpStatusCode}: ${err.errorMessage || err.apiError || 'error'}`
      } else if (err instanceof Error) {
        lastError = err.message
      } else {
        lastError = String(err)
      }
      // Non-404 on primary: still try alternate once (misconfigured env)
      if (i === 0) continue
    }
  }

  return { ok: false, error: lastError }
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
      body.plan === 'monthly' || body.plan === 'yearly'
        ? (body.plan as Plan)
        : null

    if (!signed) {
      res
        .status(400)
        .json({ error: 'signedTransaction (JWS or base64 JSON) is required' })
      return
    }

    const guestId = getGuestId(req, res)

    void (async () => {
      let productId = productIdHint
      let status: 'active' | 'trialing' = 'active'

      if (appleCredentialsConfigured()) {
        const verified = await verifyWithAppleServerAPI(signed)
        if (!verified.ok) {
          res.status(502).json({ error: verified.error })
          return
        }
        productId = verified.productId
        status = verified.status
      } else {
        // Dev soft-decode only when credentials missing AND not production.
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
        const bid =
          (typeof payload?.bundleId === 'string' && payload.bundleId) ||
          (typeof payload?.bid === 'string' && payload.bid) ||
          ''
        if (bid && bid !== BUNDLE_ID) {
          res
            .status(400)
            .json({ error: `bundleId mismatch (expected ${BUNDLE_ID})` })
          return
        }
        console.warn(
          '[iap] DEV verify — signature not checked. Configure App Store Server API for production.',
        )
      }

      if (
        !productId ||
        (productId !== PRODUCT_MONTHLY && productId !== PRODUCT_YEARLY)
      ) {
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

      // Read from the entitlement just written — the request's pr_sub cookie
      // predates this verify, so getSubscriptionStatus(req) reports free here.
      res.json({
        ok: true,
        pro: isProStatus(ent.status),
        status: ent.status,
        plan: ent.plan,
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
