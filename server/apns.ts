/**
 * APNs send stub for Push Experiment 1.
 * No-ops with structured log unless APNS_* env is present.
 * Never commit .p8 key material — path or contents via env only.
 */
import fs from 'node:fs'

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
  | { ok: false; error: string }

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

/**
 * Send (or stub) an APNs notification.
 * Real HTTP/2 JWT path is intentionally deferred — when APNS_* is set we log
 * intent and return stub:false only after a future provider is wired.
 * Today: always safe no-op with log if unconfigured; if configured, still
 * no-op with a clear log (provider not yet linked) so Ubuntu cron stays safe.
 */
export async function sendApns(
  token: string,
  payload: ApnsPayload,
  opts?: { environment?: 'sandbox' | 'production' },
): Promise<ApnsSendResult> {
  const env = opts?.environment ?? 'sandbox'
  const tokenHint = token.slice(0, 8)

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

  // Credentials present — still no live provider in Exp1 server surface.
  // Log structured intent; do not attempt raw HTTP/2 without a reviewed client.
  const p8 = readP8()
  console.info(
    JSON.stringify({
      event: 'apns_deferred',
      reason: p8
        ? 'APNS credentials present; live provider not wired in Exp1 (safe no-op)'
        : 'APNS_* set but .p8 unreadable',
      tokenHint,
      environment: env,
      keyId: process.env.APNS_KEY_ID?.trim()?.slice(0, 4) + '…',
      teamIdPresent: Boolean(process.env.APNS_TEAM_ID?.trim()),
      bundleId:
        process.env.APNS_BUNDLE_ID?.trim() || 'com.ragnus.mvp',
      type: payload.type,
      deepLink: payload.deepLink,
      chips: payload.recipeChips.map((c) => c.id),
      tier: payload.entitlementTier,
    }),
  )
  return {
    ok: true,
    stub: true,
    reason: 'APNS credentials present; live send deferred (Exp1 stub)',
  }
}

export function isApnsEnvPresent(): boolean {
  return apnsConfigured()
}
