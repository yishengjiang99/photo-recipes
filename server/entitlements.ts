import crypto from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import type { Request, Response, NextFunction } from 'express'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const DATA_DIR = path.resolve(__dirname, 'data')
const STORE_PATH = path.join(DATA_DIR, 'entitlements.json')

const GUEST_COOKIE = 'pr_guest'
const SUB_COOKIE = 'pr_sub'
/** Free Ask / Photo Vision / AO Pass-2 refine per day. Override with FREE_ASKS_PER_DAY env. */
const FREE_ASKS_PER_DAY = (() => {
  const n = Number(process.env.FREE_ASKS_PER_DAY ?? 5)
  return Number.isFinite(n) && n >= 0 ? Math.floor(n) : 5
})()
/** Combined daily free-tier cap for STT + describe-scene (short FieldCoach clips / captions). */
const FREE_ASSIST_PER_DAY = 20
/** Comma-separated emails with unlimited Ask (Pass 2 / Recommend). */
const UNLIMITED_ASK_EMAILS = new Set(
  (process.env.UNLIMITED_ASK_EMAILS ?? 'yisheng.jiang@gmail.com')
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean),
)

export type Plan = 'monthly' | 'yearly' | null

export type Entitlement = {
  id: string
  email: string | null
  status: 'active' | 'trialing' | 'canceled' | 'inactive'
  plan: Plan
  stripeCustomerId: string | null
  stripeSubscriptionId: string | null
  guestId: string | null
  updatedAt: string
}

type QuotaEntry = { date: string; count: number }

type Store = {
  entitlements: Record<string, Entitlement>
  /** guestId or entitlement id → daily Ask Grok usage */
  askQuota: Record<string, QuotaEntry>
  /** guestId → daily STT + describe-scene (FieldCoach assist) usage */
  assistQuota: Record<string, QuotaEntry>
  /** stripe customer id → entitlement id */
  byCustomer: Record<string, string>
  /** stripe subscription id → entitlement id */
  bySubscription: Record<string, string>
}

function sessionSecret(): string {
  const s = process.env.SESSION_SECRET?.trim()
  if (s) return s
  // Dev fallback — not for production
  return 'photo-recipes-dev-session-secret-change-me'
}

function todayUtc(): string {
  return new Date().toISOString().slice(0, 10)
}

function ensureDataDir() {
  if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true })
}

function emptyStore(): Store {
  return { entitlements: {}, askQuota: {}, assistQuota: {}, byCustomer: {}, bySubscription: {} }
}

function readStore(): Store {
  ensureDataDir()
  try {
    if (!fs.existsSync(STORE_PATH)) return emptyStore()
    const raw = fs.readFileSync(STORE_PATH, 'utf8')
    const parsed = JSON.parse(raw) as Partial<Store>
    return {
      entitlements: parsed.entitlements ?? {},
      askQuota: parsed.askQuota ?? {},
      assistQuota: parsed.assistQuota ?? {},
      byCustomer: parsed.byCustomer ?? {},
      bySubscription: parsed.bySubscription ?? {},
    }
  } catch {
    return emptyStore()
  }
}

function writeStore(store: Store) {
  ensureDataDir()
  const tmp = `${STORE_PATH}.${process.pid}.tmp`
  fs.writeFileSync(tmp, JSON.stringify(store, null, 2), 'utf8')
  fs.renameSync(tmp, STORE_PATH)
}

function sign(value: string): string {
  const sig = crypto.createHmac('sha256', sessionSecret()).update(value).digest('base64url')
  return `${value}.${sig}`
}

function unsign(signed: string): string | null {
  const i = signed.lastIndexOf('.')
  if (i <= 0) return null
  const value = signed.slice(0, i)
  const sig = signed.slice(i + 1)
  const expected = crypto.createHmac('sha256', sessionSecret()).update(value).digest('base64url')
  try {
    const a = Buffer.from(sig)
    const b = Buffer.from(expected)
    if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null
    return value
  } catch {
    return null
  }
}

function cookieOpts(maxAgeMs: number) {
  return {
    httpOnly: true,
    sameSite: 'lax' as const,
    secure: process.env.NODE_ENV === 'production',
    maxAge: maxAgeMs,
    path: '/',
    signed: false,
  }
}

export function isProStatus(status: Entitlement['status'] | undefined): boolean {
  return status === 'active' || status === 'trialing'
}

export function getGuestId(req: Request, res: Response): string {
  const raw = req.cookies?.[GUEST_COOKIE] as string | undefined
  if (raw) {
    const id = unsign(raw)
    if (id) return id
  }
  const id = crypto.randomUUID()
  res.cookie(GUEST_COOKIE, sign(id), cookieOpts(365 * 24 * 60 * 60 * 1000))
  return id
}

export function getEntitlementFromCookie(req: Request): Entitlement | null {
  const raw = req.cookies?.[SUB_COOKIE] as string | undefined
  if (!raw) return null
  const id = unsign(raw)
  if (!id) return null
  const store = readStore()
  return store.entitlements[id] ?? null
}

export function setSubscriptionCookie(res: Response, entitlementId: string) {
  res.cookie(SUB_COOKIE, sign(entitlementId), cookieOpts(400 * 24 * 60 * 60 * 1000))
}

export function clearSubscriptionCookie(res: Response) {
  res.clearCookie(SUB_COOKIE, { path: '/' })
}

export function upsertEntitlement(input: {
  id?: string
  email?: string | null
  status: Entitlement['status']
  plan?: Plan
  stripeCustomerId?: string | null
  stripeSubscriptionId?: string | null
  guestId?: string | null
}): Entitlement {
  const store = readStore()
  let id = input.id
  if (!id && input.stripeCustomerId && store.byCustomer[input.stripeCustomerId]) {
    id = store.byCustomer[input.stripeCustomerId]
  }
  if (!id && input.stripeSubscriptionId && store.bySubscription[input.stripeSubscriptionId]) {
    id = store.bySubscription[input.stripeSubscriptionId]
  }
  if (!id && input.guestId) {
    const existing = Object.values(store.entitlements).find(
      (e) => e.guestId === input.guestId && isProStatus(e.status),
    )
    if (existing) id = existing.id
  }
  if (!id) id = crypto.randomUUID()

  const prev = store.entitlements[id]
  const ent: Entitlement = {
    id,
    email: input.email !== undefined ? input.email : (prev?.email ?? null),
    status: input.status,
    plan: input.plan !== undefined ? input.plan : (prev?.plan ?? null),
    stripeCustomerId:
      input.stripeCustomerId !== undefined
        ? input.stripeCustomerId
        : (prev?.stripeCustomerId ?? null),
    stripeSubscriptionId:
      input.stripeSubscriptionId !== undefined
        ? input.stripeSubscriptionId
        : (prev?.stripeSubscriptionId ?? null),
    guestId: input.guestId !== undefined ? input.guestId : (prev?.guestId ?? null),
    updatedAt: new Date().toISOString(),
  }
  store.entitlements[id] = ent
  if (ent.stripeCustomerId) store.byCustomer[ent.stripeCustomerId] = id
  if (ent.stripeSubscriptionId) store.bySubscription[ent.stripeSubscriptionId] = id
  writeStore(store)
  return ent
}

export function findByCustomer(customerId: string): Entitlement | null {
  const store = readStore()
  const id = store.byCustomer[customerId]
  return id ? (store.entitlements[id] ?? null) : null
}

export function findBySubscription(subscriptionId: string): Entitlement | null {
  const store = readStore()
  const id = store.bySubscription[subscriptionId]
  return id ? (store.entitlements[id] ?? null) : null
}

export function getSubscriptionStatus(req: Request, res: Response) {
  const guestId = getGuestId(req, res)
  const ent = getEntitlementFromCookie(req)
  const pro = ent ? isProStatus(ent.status) : false
  const quotaKey = pro && ent ? ent.id : guestId
  const store = readStore()
  const day = todayUtc()
  const q = store.askQuota[quotaKey]
  const used = q && q.date === day ? q.count : 0
  const email = ent?.email ?? null
  const unlimitedAsk = Boolean(email && UNLIMITED_ASK_EMAILS.has(email.trim().toLowerCase()))
  const limit = pro || unlimitedAsk ? null : FREE_ASKS_PER_DAY
  // Assist quota is always keyed by guestId (free-tier voice/scene combined)
  const aq = store.assistQuota[guestId]
  const assistUsed = aq && aq.date === day ? aq.count : 0
  return {
    pro,
    status: ent?.status ?? 'inactive',
    plan: ent?.plan ?? null,
    email,
    asksUsedToday: used,
    asksLimit: limit,
    asksRemaining: pro || unlimitedAsk ? null : Math.max(0, FREE_ASKS_PER_DAY - used),
    assistUsedToday: assistUsed,
    assistLimit: pro ? null : FREE_ASSIST_PER_DAY,
    assistRemaining: pro ? null : Math.max(0, FREE_ASSIST_PER_DAY - assistUsed),
    stripeConfigured: Boolean(process.env.STRIPE_SECRET_KEY?.trim()),
  }
}

/** Returns null if allowed; otherwise a 402 payload. */
export function checkAskGrokQuota(
  req: Request,
  res: Response,
): { allowed: true; consume: () => void } | { allowed: false; body: Record<string, unknown> } {
  const status = getSubscriptionStatus(req, res)
  if (status.pro) {
    return { allowed: true, consume: () => {} }
  }
  const email = (status.email ?? '').trim().toLowerCase()
  if (email && UNLIMITED_ASK_EMAILS.has(email)) {
    return { allowed: true, consume: () => {} }
  }
  if ((status.asksRemaining ?? 0) > 0) {
    const guestId = getGuestId(req, res)
    return {
      allowed: true,
      consume: () => {
        const store = readStore()
        const day = todayUtc()
        const prev = store.askQuota[guestId]
        const count = prev && prev.date === day ? prev.count + 1 : 1
        store.askQuota[guestId] = { date: day, count }
        writeStore(store)
      },
    }
  }
  return {
    allowed: false,
    body: {
      error: 'Free Peek limit reached (Ask / Photo Vision / AO cloud refine for today). Upgrade to Photo Recipes Pro for unlimited Ask Grok & Photo Vision.',
      code: 'paywall',
      asksUsedToday: status.asksUsedToday,
      asksLimit: FREE_ASKS_PER_DAY,
      upgrade: {
        product: 'Photo Recipes Pro',
        monthlyCents: 799,
        yearlyCents: 5999,
        trialDays: 7,
      },
    },
  }
}


/** Returns null-style gate for STT + describe-scene combined daily quota. */
export function checkAssistQuota(
  req: Request,
  res: Response,
): { allowed: true; consume: () => void } | { allowed: false; body: Record<string, unknown> } {
  const status = getSubscriptionStatus(req, res)
  if (status.pro) {
    return { allowed: true, consume: () => {} }
  }
  if ((status.assistRemaining ?? 0) > 0) {
    const guestId = getGuestId(req, res)
    return {
      allowed: true,
      consume: () => {
        const store = readStore()
        const day = todayUtc()
        const prev = store.assistQuota[guestId]
        const count = prev && prev.date === day ? prev.count + 1 : 1
        store.assistQuota[guestId] = { date: day, count }
        writeStore(store)
      },
    }
  }
  return {
    allowed: false,
    body: {
      error:
        'Free assist limit reached (voice + scene captions for today). Upgrade to Photo Recipes Pro for unlimited FieldCoach assist.',
      code: 'paywall',
      assistUsedToday: status.assistUsedToday,
      assistLimit: FREE_ASSIST_PER_DAY,
      upgrade: {
        product: 'Photo Recipes Pro',
        monthlyCents: 799,
        yearlyCents: 5999,
        trialDays: 7,
      },
    },
  }
}

/** Soft identity middleware — always ensure guest cookie exists. */
export function identityMiddleware(req: Request, res: Response, next: NextFunction) {
  getGuestId(req, res)
  next()
}


/** Lookup Pro/trial entitlement linked to a guest id (scheduler / offline). */
export function findEntitlementByGuestId(guestId: string): Entitlement | null {
  if (!guestId) return null
  const store = readStore()
  const matches = Object.values(store.entitlements).filter((e) => e.guestId === guestId)
  const pro = matches.find((e) => isProStatus(e.status))
  if (pro) return pro
  return matches.sort((a, b) => (a.updatedAt < b.updatedAt ? 1 : -1))[0] ?? null
}

export { GUEST_COOKIE, SUB_COOKIE, FREE_ASKS_PER_DAY, FREE_ASSIST_PER_DAY }

/** Admin income snapshot from local entitlement store (not ASC payouts). */
export function getEntitlementIncomeSnapshot() {
  const store = readStore()
  const all = Object.values(store.entitlements)
  let proActive = 0
  let proTrialing = 0
  let stripePro = 0
  let iapPro = 0
  let monthly = 0
  let yearly = 0
  let unknownPlan = 0

  for (const e of all) {
    if (!isProStatus(e.status)) continue
    if (e.status === 'active') proActive++
    if (e.status === 'trialing') proTrialing++

    // IAP verify stamps id as iap_<guest>_<product>; Stripe uses UUID + customer ids.
    const isIap = e.id.startsWith('iap_')
    if (isIap) iapPro++
    else stripePro++

    if (e.plan === 'monthly') monthly++
    else if (e.plan === 'yearly') yearly++
    else unknownPlan++
  }

  return {
    proTotal: proActive + proTrialing,
    proActive,
    proTrialing,
    /** Local Pro unlocks via Stripe web checkout (has Stripe customer/sub ids). */
    stripePro,
    /**
     * Local Pro unlocks via App Store IAP verify (id iap_* or no Stripe ids).
     * These are entitlement counts — NOT App Store Connect payout amounts.
     */
    iapPro,
    iapNote:
      'IAP counts are local Pro entitlements from StoreKit verify — not ASC payouts or proceeds.',
    byPlan: { monthly, yearly, unknown: unknownPlan },
    totalRecords: all.length,
  }
}
