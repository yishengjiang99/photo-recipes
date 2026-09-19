import type { Express, Request, Response } from 'express'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const STORE = path.resolve(__dirname, 'data/waitlist.json')

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const SEGMENT_NAMES = ['waitlist', 'field-notes'] as const

type WaitlistEntry = { email: string; at: string; source?: string }

type ResendResult =
  | { ok: true; duplicate?: boolean }
  | { ok: false; detail?: string }

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

function authHeaders(key: string): HeadersInit {
  return {
    Authorization: `Bearer ${key}`,
    'Content-Type': 'application/json',
  }
}

/** Cache resolved segment id for process lifetime */
let cachedSegmentId: string | null | undefined

async function resolveSegmentId(key: string): Promise<string | null> {
  if (cachedSegmentId !== undefined) return cachedSegmentId

  const pinned = process.env.RESEND_SEGMENT_ID?.trim()
  if (pinned) {
    cachedSegmentId = pinned
    return pinned
  }

  try {
    const r = await fetch('https://api.resend.com/segments', {
      headers: authHeaders(key),
    })
    if (!r.ok) {
      console.warn('[waitlist] list segments', r.status)
      cachedSegmentId = null
      return null
    }
    const body = (await r.json()) as {
      data?: Array<{ id: string; name?: string }>
    }
    const list = Array.isArray(body.data) ? body.data : []
    const found = list.find((s) =>
      SEGMENT_NAMES.includes(
        (s.name || '').toLowerCase() as (typeof SEGMENT_NAMES)[number],
      ),
    )
    if (found?.id) {
      cachedSegmentId = found.id
      return found.id
    }

    // Create "waitlist" if missing
    const created = await fetch('https://api.resend.com/segments', {
      method: 'POST',
      headers: authHeaders(key),
      body: JSON.stringify({ name: 'waitlist' }),
    })
    if (created.ok) {
      const seg = (await created.json()) as { id?: string }
      if (seg.id) {
        cachedSegmentId = seg.id
        return seg.id
      }
    }
  } catch (err) {
    console.warn('[waitlist] resolve segment', (err as Error).message)
  }

  cachedSegmentId = null
  return null
}

async function addToSegment(
  key: string,
  email: string,
  segmentId: string,
): Promise<boolean> {
  const r = await fetch(
    `https://api.resend.com/contacts/${encodeURIComponent(email)}/segments/${segmentId}`,
    {
      method: 'POST',
      headers: authHeaders(key),
    },
  )
  // 409 / already in segment → fine
  return r.ok || r.status === 409
}

/**
 * Prefer Contacts + Segments API.
 * Falls back to legacy Audiences if RESEND_AUDIENCE_ID is set and no segment.
 * Never returns raw Resend error bodies to the caller.
 */
async function resendAddContact(email: string): Promise<ResendResult> {
  const key = process.env.RESEND_API_KEY?.trim()
  if (!key) return { ok: false, detail: 'RESEND_API_KEY missing' }

  const from =
    process.env.RESEND_FROM?.trim() || 'Photo Recipes <onboarding@resend.dev>'
  const notifyTo = process.env.WAITLIST_NOTIFY_TO?.trim()
  const audienceId = process.env.RESEND_AUDIENCE_ID?.trim()

  const segmentId = await resolveSegmentId(key)

  if (segmentId) {
    const create = await fetch('https://api.resend.com/contacts', {
      method: 'POST',
      headers: authHeaders(key),
      body: JSON.stringify({
        email,
        unsubscribed: false,
        segments: [{ id: segmentId }],
      }),
    })

    if (create.ok) {
      // optional notify
      if (notifyTo) {
        void fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: authHeaders(key),
          body: JSON.stringify({
            from,
            to: [notifyTo],
            subject: 'Photo Recipes waitlist signup',
            text: `New waitlist email: ${email}`,
          }),
        }).catch(() => undefined)
      }
      return { ok: true }
    }

    // Duplicate contact — ensure segment membership, treat as soft success
    if (create.status === 409) {
      await addToSegment(key, email, segmentId)
      return { ok: true, duplicate: true }
    }

    // Some Resend responses use 422 for existing email
    const text = await create.text().catch(() => '')
    const lower = text.toLowerCase()
    if (
      create.status === 422 &&
      (lower.includes('already') || lower.includes('exist'))
    ) {
      await addToSegment(key, email, segmentId)
      return { ok: true, duplicate: true }
    }

    console.warn('[waitlist] Resend contacts', create.status, text.slice(0, 120))
    return { ok: false, detail: `contacts ${create.status}` }
  }

  // Legacy Audiences path
  if (audienceId) {
    const r = await fetch(`https://api.resend.com/audiences/${audienceId}/contacts`, {
      method: 'POST',
      headers: authHeaders(key),
      body: JSON.stringify({ email, unsubscribed: false }),
    })
    if (r.ok) return { ok: true }
    if (r.status === 409) return { ok: true, duplicate: true }
    const text = await r.text().catch(() => '')
    console.warn('[waitlist] Resend audience', r.status, text.slice(0, 120))
    return { ok: false, detail: `audience ${r.status}` }
  }

  // Key present but no segment/audience — still accept locally
  if (notifyTo) {
    const r = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: authHeaders(key),
      body: JSON.stringify({
        from,
        to: [notifyTo],
        subject: 'Photo Recipes waitlist signup',
        text: `New waitlist email: ${email}`,
      }),
    })
    if (!r.ok) {
      console.warn('[waitlist] notify', r.status)
      return { ok: false, detail: `notify ${r.status}` }
    }
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

    const email =
      typeof req.body?.email === 'string' ? req.body.email.trim().toLowerCase() : ''

    if (!email || !EMAIL_RE.test(email) || email.length > 254) {
      res.status(400).json({ ok: false, error: 'Enter a valid email.' })
      return
    }

    if (!process.env.RESEND_API_KEY?.trim()) {
      res.status(503).json({
        ok: false,
        error: 'Couldn’t join right now. Try again.',
      })
      return
    }

    const entries = loadStore()
    const alreadyLocal = entries.some((e) => e.email === email)
    if (!alreadyLocal) {
      entries.push({
        email,
        at: new Date().toISOString(),
        source: 'landing',
      })
      saveStore(entries)
    }

    const remote = await resendAddContact(email)
    if (!remote.ok) {
      console.warn('[waitlist] Resend failed:', remote.detail)
      // Local ledger kept; still fail closed so client can retry when Resend is up
      res.status(502).json({
        ok: false,
        error: 'Couldn’t join right now. Try again.',
      })
      return
    }

    res.json({
      ok: true,
      ...(remote.duplicate || alreadyLocal ? { duplicate: true } : {}),
    })
  })
}
