import type { Express, Request, Response } from 'express'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const STORE = path.resolve(__dirname, 'data/waitlist.json')

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

type WaitlistEntry = { email: string; at: string; source?: string }

function loadStore(): WaitlistEntry[] {
  try {
    if (!fs.existsSync(STORE)) return []
    const raw = JSON.parse(fs.readFileSync(STORE, 'utf8'))
    return Array.isArray(raw) ? raw : []
  } catch {
    return []
  }
}

function saveStore(entries: WaitlistEntry[]) {
  fs.mkdirSync(path.dirname(STORE), { recursive: true })
  fs.writeFileSync(STORE, JSON.stringify(entries, null, 2))
}

/** Simple in-memory rate limit: 8 posts / IP / 10 min */
const hits = new Map<string, number[]>()
function rateLimited(ip: string): boolean {
  const now = Date.now()
  const windowMs = 10 * 60 * 1000
  const prev = (hits.get(ip) || []).filter((t) => now - t < windowMs)
  if (prev.length >= 8) {
    hits.set(ip, prev)
    return true
  }
  prev.push(now)
  hits.set(ip, prev)
  return false
}

async function resendAddContact(email: string): Promise<{ ok: boolean; detail?: string }> {
  const key = process.env.RESEND_API_KEY?.trim()
  if (!key) return { ok: false, detail: 'RESEND_API_KEY missing' }

  const audienceId = process.env.RESEND_AUDIENCE_ID?.trim()
  const from = process.env.RESEND_FROM?.trim() || 'Photo Recipes <onboarding@resend.dev>'
  const notifyTo = process.env.WAITLIST_NOTIFY_TO?.trim()

  // Prefer Audiences contacts when configured
  if (audienceId) {
    const r = await fetch(`https://api.resend.com/audiences/${audienceId}/contacts`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${key}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ email, unsubscribed: false }),
    })
    if (!r.ok) {
      const text = await r.text()
      // 409 conflict = already exists → treat as success
      if (r.status === 409) return { ok: true, detail: 'already_subscribed' }
      return { ok: false, detail: `audience ${r.status}: ${text.slice(0, 200)}` }
    }
  }

  // Optional notify email to operator
  if (notifyTo) {
    const r = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${key}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from,
        to: [notifyTo],
        subject: 'Photo Recipes waitlist signup',
        text: `New waitlist email: ${email}`,
      }),
    })
    if (!r.ok && !audienceId) {
      const text = await r.text()
      return { ok: false, detail: `notify ${r.status}: ${text.slice(0, 200)}` }
    }
  }

  // If neither audience nor notify configured, still ok if we have the key —
  // local JSON store is the fallback ledger.
  if (!audienceId && !notifyTo) {
    return { ok: true, detail: 'stored_local_only' }
  }
  return { ok: true }
}

export function mountWaitlistRoutes(app: Express) {
  app.post('/api/waitlist', async (req: Request, res: Response) => {
    const ip =
      (typeof req.headers['x-forwarded-for'] === 'string'
        ? req.headers['x-forwarded-for'].split(',')[0]
        : req.ip) || 'unknown'
    if (rateLimited(ip)) {
      res.status(429).json({ ok: false, error: 'Too many attempts. Try again later.' })
      return
    }

    const email = typeof req.body?.email === 'string' ? req.body.email.trim().toLowerCase() : ''
    const source = typeof req.body?.source === 'string' ? req.body.source.trim().slice(0, 64) : 'landing'

    if (!email || !EMAIL_RE.test(email) || email.length > 254) {
      res.status(400).json({ ok: false, error: 'Enter a valid email.' })
      return
    }

    const entries = loadStore()
    if (!entries.some((e) => e.email === email)) {
      entries.push({ email, at: new Date().toISOString(), source })
      saveStore(entries)
    }

    const remote = await resendAddContact(email)
    if (!remote.ok && process.env.RESEND_API_KEY?.trim()) {
      // Still accepted locally; surface soft failure for ops
      console.warn('[waitlist] Resend:', remote.detail)
    }

    if (!process.env.RESEND_API_KEY?.trim()) {
      res.status(503).json({
        ok: false,
        error: 'Email capture isn’t configured yet (missing RESEND_API_KEY).',
      })
      return
    }

    res.json({ ok: true })
  })
}
