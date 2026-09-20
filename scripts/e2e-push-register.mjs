#!/usr/bin/env node
/**
 * HTTP smoke: register mock APNs token → read prefs.tokenCount.
 * Usage: BASE_URL=https://photo.grepawk.com node scripts/e2e-push-register.mjs
 * Default BASE_URL=http://127.0.0.1:8787
 */
const BASE = (process.env.BASE_URL || 'http://127.0.0.1:8787').replace(/\/$/, '')
const TOKEN = 'b2'.repeat(32)

function parseSetCookie(res) {
  const raw = typeof res.headers.getSetCookie === 'function' ? res.headers.getSetCookie() : []
  if (raw.length) return raw.map((c) => c.split(';')[0]).join('; ')
  const s = res.headers.get('set-cookie')
  return s ? s.split(';')[0] : ''
}

async function main() {
  let cookie = ''
  const api = async (path, init = {}) => {
    const headers = { ...(init.headers || {}) }
    if (cookie) headers.cookie = cookie
    if (init.body && !headers['content-type']) headers['content-type'] = 'application/json'
    const res = await fetch(`${BASE}${path}`, { ...init, headers })
    const set = parseSetCookie(res)
    if (set) cookie = cookie ? `${cookie}; ${set}` : set
    // de-dupe cookie pairs by name
    const map = new Map()
    for (const part of cookie.split(';').map((s) => s.trim()).filter(Boolean)) {
      const i = part.indexOf('=')
      if (i > 0) map.set(part.slice(0, i), part)
    }
    cookie = [...map.values()].join('; ')
    const json = await res.json().catch(() => ({}))
    return { status: res.status, json }
  }

  const p0 = await api('/api/push/prefs')
  if (p0.status !== 200 || !p0.json?.ok) {
    console.error('FAIL prefs', p0)
    process.exit(1)
  }
  const guestId = p0.json.prefs?.guestId
  const before = p0.json.prefs?.tokenCount ?? -1

  const reg = await api('/api/push/register', {
    method: 'POST',
    body: JSON.stringify({
      token: TOKEN,
      platform: 'ios',
      bundleId: 'com.ragnus.mvp',
      environment: 'sandbox',
      appVersion: 'smoke-e2e',
    }),
  })
  if (reg.status !== 200 || !reg.json?.ok) {
    console.error('FAIL register', reg)
    process.exit(1)
  }

  const p1 = await api('/api/push/prefs')
  const after = p1.json.prefs?.tokenCount
  if (p1.status !== 200 || after < 1) {
    console.error('FAIL readback', { before, after, p1 })
    process.exit(1)
  }

  console.log(
    JSON.stringify({
      ok: true,
      base: BASE,
      guestId,
      tokenCountBefore: before,
      tokenCountAfter: after,
    }),
  )
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
