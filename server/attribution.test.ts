import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { after, before, test } from 'node:test'
import type { AddressInfo } from 'node:net'
import type { Server } from 'node:http'
import express from 'express'
import { mountAttributionRoutes, summarizePostback } from './attribution.ts'

const SKAN4 = {
  'version': '4.0',
  'ad-network-id': '9yg77x724h.skadnetwork',
  'source-identifier': '5239',
  'app-id': 6813991381,
  'transaction-id': '6aafb7a5-0170-41b5-bbe4-fe71dedf1e30',
  'redownload': false,
  'source-domain': 'example.com',
  'fidelity-type': 1,
  'did-win': true,
  'postback-sequence-index': 0,
  'coarse-conversion-value': 'low',
  'attribution-signature': 'MEUCIQD4rX6eh38qEhuUKHdap345UbmlzA7KEZ1bhWZuYM8MJwIgMnyiiZe6heabDkGwOaKBYrUXQhKtF3P/ERHqkR/XpuA=',
}

function b64url(o: unknown) {
  return Buffer.from(JSON.stringify(o)).toString('base64url')
}
const AAK_JWS = [
  b64url({ alg: 'ES256', kid: 'apple-cas-identifier' }),
  b64url({
    'impression-type': 'app-impression',
    'ad-network-identifier': 'example123.adattributionkit',
    'source-identifier': '3120',
    'advertised-item-identifier': 6813991381,
    'conversion-type': 'download',
    'postback-identifier': '2fa7e0e6-0000-4000-8000-000000000000',
    'did-win': true,
    'postback-sequence-index': 0,
    'conversion-value': 0,
  }),
  'c2lnbmF0dXJl',
].join('.')

let server: Server
let base = ''
let dir = ''

before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'attr-'))
  process.env.ATTRIBUTION_LOG_DIR = dir
  const app = express()
  mountAttributionRoutes(app)
  app.use(express.json())
  server = app.listen(0)
  await new Promise<void>((r) => server.once('listening', () => r()))
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`
})

after(() => {
  server?.close()
  delete process.env.ATTRIBUTION_LOG_DIR
})

test('summarizePostback reads SKAN 4 JSON', () => {
  const s = summarizePostback('skan', JSON.stringify(SKAN4))
  assert.ok(s)
  assert.equal(s.format, 'json')
  assert.equal(s.hasSignature, true)
  assert.equal(s.fields['ad-network-id'], '9yg77x724h.skadnetwork')
  assert.equal(s.fields['coarse-conversion-value'], 'low')
  assert.equal(s.fields['app-id'], 6813991381)
  assert.equal('attribution-signature' in s.fields, false)
})

test('summarizePostback decodes an AdAttributionKit JWS (bare or wrapped)', () => {
  const bare = summarizePostback('aak', AAK_JWS)
  assert.ok(bare)
  assert.equal(bare.format, 'jws')
  assert.equal(bare.fields['conversion-type'], 'download')
  const wrapped = summarizePostback('aak', JSON.stringify({ 'jws-string': AAK_JWS }))
  assert.ok(wrapped)
  assert.equal(wrapped.format, 'jws')
  assert.equal(wrapped.fields['advertised-item-identifier'], 6813991381)
})

test('summarizePostback rejects garbage', () => {
  assert.equal(summarizePostback('skan', ''), null)
  assert.equal(summarizePostback('skan', 'hello'), null)
  assert.equal(summarizePostback('skan', '[1,2]'), null)
})

test('POST SKAN postback copy (with and without trailing slash) → 200 + raw log', async () => {
  for (const p of [
    '/.well-known/skadnetwork/report-attribution/',
    '/.well-known/skadnetwork/report-attribution',
  ]) {
    const r = await fetch(base + p, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(SKAN4),
    })
    assert.equal(r.status, 200, p)
    assert.deepEqual(await r.json(), { ok: true })
  }
  const lines = fs.readFileSync(path.join(dir, 'attribution-postbacks.jsonl'), 'utf8').trim().split('\n')
  assert.ok(lines.length >= 2)
  const first = JSON.parse(lines[0]!)
  assert.equal(first.kind, 'skan')
  assert.equal(JSON.parse(first.body)['transaction-id'], SKAN4['transaction-id'])
})

test('POST AdAttributionKit postback copy → 200', async () => {
  const r = await fetch(base + '/.well-known/appattribution/report-attribution/', {
    method: 'POST',
    headers: { 'Content-Type': 'text/plain' },
    body: AAK_JWS,
  })
  assert.equal(r.status, 200)
})

test('bad body → 400, GET → 200 liveness', async () => {
  const bad = await fetch(base + '/.well-known/skadnetwork/report-attribution/', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: 'not json',
  })
  assert.equal(bad.status, 400)
  const get = await fetch(base + '/.well-known/appattribution/report-attribution/')
  assert.equal(get.status, 200)
})
