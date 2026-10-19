import { test } from 'node:test'
import assert from 'node:assert/strict'

const { sanitizeProps } = await import('./telemetry.ts')

test('sanitizeProps keeps the full auto_optimize_success prop set', () => {
  // AOTelemetrySerializer.readyProps alone sends 23 keys; merged with the
  // caller's base props the success event carries 34+. The old 24-key cap
  // silently dropped an arbitrary tail of these (dictionary order is not
  // stable), losing planner/verify/GPU props. 40 keys must survive intact.
  const raw: Record<string, unknown> = {}
  for (let i = 0; i < 40; i++) raw[`k${i}`] = i
  const out = sanitizeProps(raw)
  assert.ok(out)
  assert.equal(Object.keys(out).length, 40)
  assert.equal(out.k39, 39)
})

test('sanitizeProps still drops blocked PII keys without counting them', () => {
  const out = sanitizeProps({ email: 'a@b.c', phone: '555', keep: 'yes', n: 3 })
  assert.deepEqual(out, { keep: 'yes', n: 3 })
})

test('sanitizeProps still drops payload-like strings and truncates long ones', () => {
  const out = sanitizeProps({
    img: `data:image/png;base64,${'A'.repeat(50)}`,
    huge: 'x'.repeat(4001),
    long: 'word '.repeat(60),
    ok: true,
  })
  assert.ok(out)
  assert.equal('img' in out, false)
  assert.equal('huge' in out, false)
  assert.equal(String(out.long).length, 200)
  assert.equal(out.ok, true)
})

test('sanitizeProps rejects non-objects and empty results', () => {
  assert.equal(sanitizeProps(null), null)
  assert.equal(sanitizeProps([1, 2]), null)
  assert.equal(sanitizeProps({}), null)
})
