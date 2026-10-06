/**
 * Apple ad-attribution postback copies (SKAdNetwork + AdAttributionKit).
 *
 * The iOS app (1.2+) sets NSAdvertisingAttributionReportEndpoint and
 * AdAttributionKit.AttributionCopyEndpoint to https://photo.grepawk.com. Apple
 * uses the registrable domain only, so devices POST copies of winning
 * postbacks to:
 *   https://grepawk.com/.well-known/skadnetwork/report-attribution/
 *   https://grepawk.com/.well-known/appattribution/report-attribution/
 * nginx proxies those paths (on grepawk.com and photo.grepawk.com) to this API.
 *
 * We only log: one JSON line to stdout (journald), the raw body to
 * $STATE_DIRECTORY/attribution-postbacks.jsonl (systemd StateDirectory), and a
 * summary row in telemetry_events (event skan_postback / aak_postback) when MySQL
 * is configured. Postbacks carry no user identifiers (Apple's privacy design).
 * Signatures are kept raw for later verification; we do not verify them here.
 */
import fs from 'node:fs'
import path from 'node:path'
import express from 'express'
import type { Express, Request, Response } from 'express'
import { insertTelemetry } from './telemetry.ts'

export const SKAN_PATHS = [
  '/.well-known/skadnetwork/report-attribution',
  '/.well-known/skadnetwork/report-attribution/',
]
export const AAK_PATHS = [
  '/.well-known/appattribution/report-attribution',
  '/.well-known/appattribution/report-attribution/',
]

const MAX_BODY = '64kb'

/** Fields worth summarising from SKAN 2–4 JSON postbacks or AAK JWS payloads. */
const SUMMARY_FIELDS = [
  'version',
  'ad-network-id',
  'ad-network-identifier',
  'app-id',
  'advertised-item-identifier',
  'source-app-id',
  'source-domain',
  'source-identifier',
  'campaign-id',
  'publisher-item-identifier',
  'marketplace-identifier',
  'transaction-id',
  'postback-identifier',
  'redownload',
  'fidelity-type',
  'impression-type',
  'conversion-type',
  'did-win',
  'postback-sequence-index',
  'conversion-value',
  'coarse-conversion-value',
] as const

export type PostbackKind = 'skan' | 'aak'

export type PostbackSummary = {
  kind: PostbackKind
  format: 'json' | 'jws' | 'unknown'
  fields: Record<string, string | number | boolean>
  hasSignature: boolean
}

function decodeJwsPayload(jws: string): Record<string, unknown> | null {
  const parts = jws.trim().split('.')
  if (parts.length !== 3) return null
  try {
    const json = Buffer.from(parts[1]!, 'base64url').toString('utf8')
    const obj = JSON.parse(json)
    return obj && typeof obj === 'object' && !Array.isArray(obj) ? obj : null
  } catch {
    return null
  }
}

function pickFields(obj: Record<string, unknown>): Record<string, string | number | boolean> {
  const out: Record<string, string | number | boolean> = {}
  for (const key of SUMMARY_FIELDS) {
    const v = obj[key]
    if (typeof v === 'string') out[key] = v.slice(0, 120)
    else if (typeof v === 'number' && Number.isFinite(v)) out[key] = v
    else if (typeof v === 'boolean') out[key] = v
  }
  return out
}

/** Parse a raw postback body (JSON object, JSON wrapping a JWS, or a bare JWS). */
export function summarizePostback(kind: PostbackKind, raw: string): PostbackSummary | null {
  const text = raw.trim()
  if (!text) return null
  let parsed: unknown = null
  try {
    parsed = JSON.parse(text)
  } catch {
    parsed = null
  }
  if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
    const obj = parsed as Record<string, unknown>
    // Some senders wrap the JWS in a JSON field.
    const jwsField = Object.values(obj).find(
      (v) => typeof v === 'string' && /^[\w-]+\.[\w-]+\.[\w-]+$/.test(v) && v.length > 40,
    ) as string | undefined
    const inner = jwsField ? decodeJwsPayload(jwsField) : null
    if (inner && !('ad-network-id' in obj)) {
      return { kind, format: 'jws', fields: pickFields(inner), hasSignature: true }
    }
    return {
      kind,
      format: 'json',
      fields: pickFields(obj),
      hasSignature: typeof obj['attribution-signature'] === 'string',
    }
  }
  const payload = decodeJwsPayload(text)
  if (payload) return { kind, format: 'jws', fields: pickFields(payload), hasSignature: true }
  return null
}

function stateFile(): string | null {
  const dir =
    process.env.ATTRIBUTION_LOG_DIR?.trim() ||
    process.env.STATE_DIRECTORY?.split(':')[0]?.trim() ||
    ''
  return dir ? path.join(dir, 'attribution-postbacks.jsonl') : null
}

function appendRaw(kind: PostbackKind, raw: string, receivedAt: string) {
  const file = stateFile()
  if (!file) return
  try {
    fs.mkdirSync(path.dirname(file), { recursive: true })
    fs.appendFileSync(file, JSON.stringify({ receivedAt, kind, body: raw }) + '\n')
  } catch (err) {
    console.warn('[attribution] could not append raw postback:', err instanceof Error ? err.message : err)
  }
}

function handler(kind: PostbackKind) {
  return (req: Request, res: Response) => {
    const raw = typeof req.body === 'string' ? req.body : ''
    const summary = summarizePostback(kind, raw)
    if (!summary) {
      res.status(400).json({ ok: false, error: 'expected a JSON or JWS postback body' })
      return
    }
    const receivedAt = new Date().toISOString()
    console.log(
      '[attribution] postback',
      JSON.stringify({ receivedAt, kind, format: summary.format, signed: summary.hasSignature, ...summary.fields }),
    )
    appendRaw(kind, raw, receivedAt)
    const anon =
      String(summary.fields['transaction-id'] ?? summary.fields['postback-identifier'] ?? 'postback').slice(0, 64)
    void insertTelemetry({
      app: 'grepawk-photos',
      platform: 'ios',
      event: kind === 'skan' ? 'skan_postback' : 'aak_postback',
      anon_id: anon,
      session_id: null,
      props: { format: summary.format, signed: summary.hasSignature, ...summary.fields },
      ip_hash: null,
    })
    res.status(200).json({ ok: true })
  }
}

/** Mount before the global express.json() so any content type is read as text. */
export function mountAttributionRoutes(app: Express) {
  const textBody = express.text({ type: () => true, limit: MAX_BODY })
  for (const p of SKAN_PATHS) app.post(p, textBody, handler('skan'))
  for (const p of AAK_PATHS) app.post(p, textBody, handler('aak'))
  // Simple liveness check for ops (Apple only POSTs).
  app.get([...SKAN_PATHS, ...AAK_PATHS], (_req, res) => {
    res.status(200).json({ ok: true, accepts: 'POST' })
  })
}
