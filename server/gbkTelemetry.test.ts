import test from 'node:test'
import assert from 'node:assert/strict'
import { fetchGbkTelemetry } from './gbkTelemetry.ts'

test('gbk telemetry: no token = not configured, no fetch', async () => {
  let called = false
  const r = await fetchGbkTelemetry(30, { token: '', fetchImpl: (async () => { called = true; return new Response('{}') }) as typeof fetch })
  assert.equal(r.ok, false); assert.equal(r.configured, false); assert.equal(called, false)
})

test('gbk telemetry: sends the token header, returns data; HTTP errors and throws are soft', async () => {
  let hdr = ''
  const ok = await fetchGbkTelemetry(30, { token: 't0k', origin: 'http://gbk.test', fetchImpl: (async (_u: string, init: RequestInit) => {
    hdr = (init.headers as Record<string, string>)['x-gbk-admin-read']; return new Response(JSON.stringify({ days: 30 }))
  }) as typeof fetch })
  assert.equal(hdr, 't0k'); assert.deepEqual(ok, { ok: true, configured: true, data: { days: 30 } })
  const bad = await fetchGbkTelemetry(30, { token: 't', fetchImpl: (async () => new Response('', { status: 401 })) as typeof fetch })
  assert.equal(bad.ok, false); assert.equal((bad as { status?: number }).status, 401)
  const boom = await fetchGbkTelemetry(30, { token: 't', fetchImpl: (async () => { throw new Error('ECONNREFUSED') }) as typeof fetch })
  assert.deepEqual(boom, { ok: false, configured: true, error: 'ECONNREFUSED' })
})
