/**
 * APNs HTTP/2 JWT provider for Push Experiment 1.
 * Fail-soft stub when APNS_* env is missing; live send when configured.
 * Never commit .p8 key material — path or contents via env only.
 */
import crypto from 'node:crypto'
import fs from 'node:fs'
import http2 from 'node:http2'

export type ApnsPayload = {
  aps: {
    alert: { title: string; body: string }
    sound?: string
    'mutable-content'?: number
  }
  type: 'pre_alarm_shoot_brief'
  deepLink: string
  recipeChips: Array<{ id: string; title: string }>
  entitlementTier: 'free' | 'trial' | 'pro'
  experiment: 'push_exp1'
}

export type ApnsSendResult =
  | { ok: true; stub: true; reason: string }
  | { ok: true; stub: false; status: number }
  | { ok: false; error: string; status?: number }

export type ApnsEnvironment = 'sandbox' | 'production'

type ApnsHttpPostResult = { status: number; body: string }

export type ApnsHttpPost = (args: {
  host: string
  path: string
  headers: Record<string, string>
  body: string
}) => Promise<ApnsHttpPostResult>

/** Test seam — when set, skips real Apple HTTP/2. */
let httpPostOverride: ApnsHttpPost | null = null

export function setApnsHttpPostForTests(fn: ApnsHttpPost | null): void {
  httpPostOverride = fn
}

function apnsConfigured(): boolean {
  const keyId = process.env.APNS_KEY_ID?.trim()
  const teamId = process.env.APNS_TEAM_ID?.trim()
  const bundleId =
    process.env.APNS_BUNDLE_ID?.trim() || 'com.ragnus.mvp'
  const p8Path = process.env.APNS_P8_PATH?.trim()
  const p8Contents = process.env.APNS_P8_CONTENTS?.trim()
  return Boolean(keyId && teamId && bundleId && (p8Path || p8Contents))
}

function readP8(): string | null {
  const contents = process.env.APNS_P8_CONTENTS?.trim()
  if (contents) return contents.replace(/\\n/g, '\n')
  const p = process.env.APNS_P8_PATH?.trim()
  if (!p) return null
  try {
    return fs.readFileSync(p, 'utf8')
  } catch (err) {
    console.error('[apns] failed to read APNS_P8_PATH', (err as Error).message)
    return null
  }
}

function b64urlJson(obj: unknown): string {
  return Buffer.from(JSON.stringify(obj), 'utf8')
    .toString('base64url')
}

function b64urlBuf(buf: Buffer): string {
  return buf.toString('base64url')
}

/**
 * Apple APNs provider token (JWT ES256). Cached ~50 min (Apple allows ≤60).
 */
let cachedJwt: { token: string; expMs: number } | null = null

export function clearApnsJwtCacheForTests(): void {
  cachedJwt = null
}

function buildApnsJwt(p8Pem: string, keyId: string, teamId: string): string {
  const now = Math.floor(Date.now() / 1000)
  if (cachedJwt && cachedJwt.expMs > Date.now() + 60_000) {
    return cachedJwt.token
  }

  const header = b64urlJson({ alg: 'ES256', kid: keyId })
  const payload = b64urlJson({ iss: teamId, iat: now })
  const signingInput = `${header}.${payload}`

  const key = crypto.createPrivateKey(p8Pem)
  const sig = crypto.sign('sha256', Buffer.from(signingInput, 'utf8'), {
    key,
    dsaEncoding: 'ieee-p1363',
  })
  const token = `${signingInput}.${b64urlBuf(sig)}`
  // Refresh before Apple's 60m max
  cachedJwt = { token, expMs: Date.now() + 50 * 60 * 1000 }
  return token
}

function resolveEnvironment(
  optsEnv?: ApnsEnvironment,
): ApnsEnvironment {
  if (optsEnv === 'sandbox' || optsEnv === 'production') return optsEnv
  const fromEnv = process.env.APNS_ENVIRONMENT?.trim().toLowerCase()
  if (fromEnv === 'production') return 'production'
  return 'sandbox'
}

/** APNs HTTP/2 host (no scheme) for the given environment. */
export function apnsHost(env: ApnsEnvironment): string {
  return env === 'production'
    ? 'api.push.apple.com'
    : 'api.sandbox.push.apple.com'
}

/** Bounded wait for a single APNs HTTP/2 request (hung sockets must not stall the process). */
export const APNS_HTTP2_TIMEOUT_MS = 12_000

/**
 * Race a promise against a timeout; calls onTimeout then rejects.
 * Exported for unit tests (short ms) — production path uses APNS_HTTP2_TIMEOUT_MS.
 */
export function raceWithTimeout<T>(
  promise: Promise<T>,
  ms: number,
  onTimeout?: () => void,
): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    let settled = false
    const timer = setTimeout(() => {
      if (settled) return
      settled = true
      try {
        onTimeout?.()
      } catch {
        /* ignore */
      }
      reject(new Error(`apns_http2_timeout_${ms}ms`))
    }, ms)
    promise.then(
      (v) => {
        if (settled) return
        settled = true
        clearTimeout(timer)
        resolve(v)
      },
      (err: unknown) => {
        if (settled) return
        settled = true
        clearTimeout(timer)
        reject(err)
      },
    )
  })
}

async function defaultHttp2Post(args: {
  host: string
  path: string
  headers: Record<string, string>
  body: string
  timeoutMs?: number
}): Promise<ApnsHttpPostResult> {
  const authority = `https://${args.host}`
  const timeoutMs = args.timeoutMs ?? APNS_HTTP2_TIMEOUT_MS
  return new Promise((resolve, reject) => {
    const client = http2.connect(authority)
    let settled = false

    const cleanup = () => {
      try {
        client.close()
      } catch {
        /* ignore */
      }
      try {
        client.destroy()
      } catch {
        /* ignore */
      }
    }

    const fail = (err: Error) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      cleanup()
      reject(err)
    }

    const timer = setTimeout(() => {
      fail(new Error(`apns_http2_timeout_${timeoutMs}ms`))
    }, timeoutMs)

    client.on('error', (err) => fail(err instanceof Error ? err : new Error(String(err))))

    const req = client.request({
      ':method': 'POST',
      ':path': args.path,
      ...args.headers,
    })

    let status = 0
    const chunks: Buffer[] = []

    req.on('response', (headers) => {
      const s = headers[':status']
      status = typeof s === 'number' ? s : Number(s) || 0
    })
    req.on('data', (chunk: Buffer) => chunks.push(chunk))
    req.on('error', (err) => fail(err instanceof Error ? err : new Error(String(err))))
    req.on('end', () => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      cleanup()
      resolve({
        status,
        body: Buffer.concat(chunks).toString('utf8'),
      })
    })

    req.end(args.body)
  })
}

/**
 * Send (or stub) an APNs notification.
 * When APNS_* is unset → stub. When set → real HTTP/2 JWT POST.
 */
export async function sendApns(
  token: string,
  payload: ApnsPayload,
  opts?: { environment?: ApnsEnvironment },
): Promise<ApnsSendResult> {
  const env = resolveEnvironment(opts?.environment)
  const tokenHint = token.slice(0, 8)
  const deviceToken = token.trim().toLowerCase().replace(/\s+/g, '')

  if (!apnsConfigured()) {
    console.info(
      JSON.stringify({
        event: 'apns_stub',
        reason: 'APNS_* env not configured',
        tokenHint,
        environment: env,
        type: payload.type,
        deepLink: payload.deepLink,
        chips: payload.recipeChips.map((c) => c.id),
        tier: payload.entitlementTier,
      }),
    )
    return { ok: true, stub: true, reason: 'APNS_* env not configured' }
  }

  const keyId = process.env.APNS_KEY_ID!.trim()
  const teamId = process.env.APNS_TEAM_ID!.trim()
  const bundleId =
    process.env.APNS_BUNDLE_ID?.trim() || 'com.ragnus.mvp'
  const p8 = readP8()
  if (!p8) {
    console.error(
      JSON.stringify({
        event: 'apns_error',
        reason: 'APNS_* set but .p8 unreadable',
        tokenHint,
        environment: env,
      }),
    )
    return { ok: false, error: 'APNS_* set but .p8 unreadable' }
  }

  if (!/^[0-9a-f]{64}$/.test(deviceToken)) {
    return { ok: false, error: 'invalid_device_token' }
  }

  let jwt: string
  try {
    jwt = buildApnsJwt(p8, keyId, teamId)
  } catch (err) {
    const msg = err instanceof Error ? err.message : 'jwt_sign_failed'
    console.error(JSON.stringify({ event: 'apns_error', reason: msg, tokenHint }))
    return { ok: false, error: `jwt_sign_failed: ${msg}` }
  }

  const host = apnsHost(env)
  const path = `/3/device/${deviceToken}`
  const body = JSON.stringify(payload)
  const headers: Record<string, string> = {
    authorization: `bearer ${jwt}`,
    'apns-topic': bundleId,
    'apns-push-type': 'alert',
    'apns-priority': '10',
    'content-type': 'application/json',
  }

  const post = httpPostOverride ?? defaultHttp2Post

  try {
    const res = await post({ host, path, headers, body })
    const ok = res.status === 200
    console.info(
      JSON.stringify({
        event: ok ? 'apns_sent' : 'apns_rejected',
        status: res.status,
        tokenHint,
        environment: env,
        host,
        type: payload.type,
        deepLink: payload.deepLink,
        chips: payload.recipeChips.map((c) => c.id),
        tier: payload.entitlementTier,
        ...(ok ? {} : { body: res.body.slice(0, 200) }),
      }),
    )
    if (ok) return { ok: true, stub: false, status: res.status }
    return {
      ok: false,
      error: res.body || `apns_http_${res.status}`,
      status: res.status,
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : 'apns_http_error'
    console.error(
      JSON.stringify({
        event: 'apns_error',
        reason: msg,
        tokenHint,
        environment: env,
      }),
    )
    return { ok: false, error: msg }
  }
}

export function isApnsEnvPresent(): boolean {
  return apnsConfigured()
}

export function getDefaultApnsEnvironment(): ApnsEnvironment {
  return resolveEnvironment()
}
