import type { Express, Request, Response } from 'express'
import express from 'express'
import Stripe from 'stripe'
import {
  findByCustomer,
  findBySubscription,
  getEntitlementFromCookie,
  getGuestId,
  getSubscriptionStatus,
  isProStatus,
  setSubscriptionCookie,
  upsertEntitlement,
  type Plan,
} from './entitlements.ts'

const PRODUCT_NAME = 'Photo Recipes Pro'
const MONTHLY_CENTS = 799
const YEARLY_CENTS = 5999
const TRIAL_DAYS = 7

let stripe: Stripe | null = null
let priceMonthly: string | null = null
let priceYearly: string | null = null
let pricesReady: Promise<void> | null = null

function getBaseUrl(req: Request): string {
  const fromEnv = process.env.PUBLIC_BASE_URL?.trim().replace(/\/$/, '')
  if (fromEnv) return fromEnv
  const proto = (req.headers['x-forwarded-proto'] as string) || req.protocol || 'http'
  const host = req.headers['x-forwarded-host'] || req.headers.host
  return `${proto}://${host}`
}

export function getStripe(): Stripe | null {
  const key = process.env.STRIPE_SECRET_KEY?.trim()
  if (!key) return null
  if (!stripe) stripe = new Stripe(key)
  return stripe
}

async function findOrCreateProduct(s: Stripe): Promise<string> {
  const list = await s.products.list({ limit: 100, active: true })
  const existing = list.data.find((p) => p.name === PRODUCT_NAME)
  if (existing) return existing.id
  const created = await s.products.create({
    name: PRODUCT_NAME,
    description:
      'Unlimited Ask Grok + field checklists. Browse presets free; upgrade for Pro coaching.',
  })
  console.log(`[stripe] Created product ${created.id} (${PRODUCT_NAME})`)
  return created.id
}

async function findOrCreatePrice(
  s: Stripe,
  productId: string,
  unitAmount: number,
  interval: 'month' | 'year',
): Promise<string> {
  const list = await s.prices.list({ product: productId, active: true, limit: 100 })
  const match = list.data.find(
    (p) =>
      p.unit_amount === unitAmount &&
      p.currency === 'usd' &&
      p.recurring?.interval === interval &&
      p.type === 'recurring',
  )
  if (match) return match.id
  const created = await s.prices.create({
    product: productId,
    unit_amount: unitAmount,
    currency: 'usd',
    recurring: { interval },
    nickname: interval === 'month' ? 'Monthly' : 'Annual (Best value)',
  })
  console.log(`[stripe] Created ${interval} price ${created.id} @ ${unitAmount} cents`)
  return created.id
}

/** Resolve price IDs from env, or auto-create product/prices when secret key is present. */
export async function ensureStripePrices(): Promise<{
  monthly: string | null
  yearly: string | null
}> {
  const s = getStripe()
  if (!s) {
    priceMonthly = process.env.STRIPE_PRICE_MONTHLY?.trim() || null
    priceYearly = process.env.STRIPE_PRICE_YEARLY?.trim() || null
    return { monthly: priceMonthly, yearly: priceYearly }
  }

  priceMonthly = process.env.STRIPE_PRICE_MONTHLY?.trim() || null
  priceYearly = process.env.STRIPE_PRICE_YEARLY?.trim() || null

  if (priceMonthly && priceYearly) {
    return { monthly: priceMonthly, yearly: priceYearly }
  }

  try {
    const productId = await findOrCreateProduct(s)
    if (!priceMonthly) {
      priceMonthly = await findOrCreatePrice(s, productId, MONTHLY_CENTS, 'month')
    }
    if (!priceYearly) {
      priceYearly = await findOrCreatePrice(s, productId, YEARLY_CENTS, 'year')
    }
    console.log(
      `[stripe] Prices ready — monthly=${priceMonthly} yearly=${priceYearly}` +
        (process.env.STRIPE_PRICE_MONTHLY && process.env.STRIPE_PRICE_YEARLY
          ? ''
          : ' (auto-created; set STRIPE_PRICE_* in env to pin IDs)'),
    )
  } catch (err) {
    console.error('[stripe] Failed to ensure prices:', err)
  }

  return { monthly: priceMonthly, yearly: priceYearly }
}

function ensurePricesOnce(): Promise<void> {
  if (!pricesReady) {
    pricesReady = ensureStripePrices().then(() => undefined)
  }
  return pricesReady
}

function planFromPriceId(priceId: string | null | undefined): Plan {
  if (!priceId) return null
  if (priceId === priceYearly) return 'yearly'
  if (priceId === priceMonthly) return 'monthly'
  return null
}

function statusFromSubscription(
  sub: Stripe.Subscription,
): 'active' | 'trialing' | 'canceled' | 'inactive' {
  if (sub.status === 'active') return 'active'
  if (sub.status === 'trialing') return 'trialing'
  if (sub.status === 'canceled') return 'canceled'
  return 'inactive'
}

async function unlockFromSession(
  s: Stripe,
  session: Stripe.Checkout.Session,
  guestId: string | null,
) {
  const customerId =
    typeof session.customer === 'string'
      ? session.customer
      : session.customer?.id ?? null
  const subscriptionId =
    typeof session.subscription === 'string'
      ? session.subscription
      : session.subscription?.id ?? null

  let plan: Plan = null
  let subStatus: 'active' | 'trialing' | 'canceled' | 'inactive' = 'active'

  if (subscriptionId) {
    const sub = await s.subscriptions.retrieve(subscriptionId)
    subStatus = statusFromSubscription(sub)
    const priceId = sub.items.data[0]?.price?.id
    plan = planFromPriceId(priceId)
  }

  // Checkout complete with trial often has payment_status=no_payment_required
  const paidOk =
    session.status === 'complete' &&
    (session.payment_status === 'paid' ||
      session.payment_status === 'no_payment_required' ||
      subStatus === 'trialing' ||
      subStatus === 'active')

  if (!paidOk) return null

  return upsertEntitlement({
    email: session.customer_details?.email || session.customer_email || null,
    status: subStatus === 'inactive' ? 'active' : subStatus,
    plan,
    stripeCustomerId: customerId,
    stripeSubscriptionId: subscriptionId,
    guestId,
  })
}

export function mountStripeWebhook(app: Express) {
  // Must use raw body for signature verification — mount BEFORE express.json()
  app.post(
    '/api/stripe-webhook',
    express.raw({ type: 'application/json' }),
    async (req: Request, res: Response) => {
      const s = getStripe()
      const secret = process.env.STRIPE_WEBHOOK_SECRET?.trim()
      if (!s) {
        res.status(503).json({ error: 'Stripe is not configured' })
        return
      }
      if (!secret) {
        res.status(400).json({ error: 'STRIPE_WEBHOOK_SECRET is not configured' })
        return
      }

      const sig = req.headers['stripe-signature']
      if (!sig || typeof sig !== 'string') {
        res.status(400).json({ error: 'Missing stripe-signature header' })
        return
      }

      let event: Stripe.Event
      try {
        event = s.webhooks.constructEvent(req.body, sig, secret)
      } catch (err) {
        const msg = err instanceof Error ? err.message : 'invalid signature'
        console.error('[stripe-webhook] signature failed:', msg)
        res.status(400).json({ error: `Webhook Error: ${msg}` })
        return
      }

      try {
        await ensurePricesOnce()
        switch (event.type) {
          case 'checkout.session.completed': {
            const session = event.data.object as Stripe.Checkout.Session
            const guestId =
              typeof session.client_reference_id === 'string'
                ? session.client_reference_id
                : null
            const ent = await unlockFromSession(s, session, guestId)
            if (ent) {
              console.log(`[stripe-webhook] unlocked ${ent.id} (${ent.email ?? 'no-email'})`)
            }
            break
          }
          case 'customer.subscription.updated':
          case 'customer.subscription.created': {
            const sub = event.data.object as Stripe.Subscription
            const customerId = typeof sub.customer === 'string' ? sub.customer : sub.customer.id
            const priceId = sub.items.data[0]?.price?.id
            upsertEntitlement({
              status: statusFromSubscription(sub),
              plan: planFromPriceId(priceId),
              stripeCustomerId: customerId,
              stripeSubscriptionId: sub.id,
            })
            break
          }
          case 'customer.subscription.deleted': {
            const sub = event.data.object as Stripe.Subscription
            const customerId = typeof sub.customer === 'string' ? sub.customer : sub.customer.id
            const existing = findBySubscription(sub.id) || findByCustomer(customerId)
            upsertEntitlement({
              id: existing?.id,
              status: 'canceled',
              plan: existing?.plan ?? null,
              stripeCustomerId: customerId,
              stripeSubscriptionId: sub.id,
              guestId: existing?.guestId ?? null,
              email: existing?.email ?? null,
            })
            console.log(`[stripe-webhook] subscription canceled ${sub.id}`)
            break
          }
          default:
            break
        }
        res.json({ received: true })
      } catch (err) {
        console.error('[stripe-webhook] handler error:', err)
        res.status(500).json({ error: 'Webhook handler failed' })
      }
    },
  )
}

export function mountStripeRoutes(app: Express) {
  app.get('/api/subscription-status', async (req, res) => {
    await ensurePricesOnce()
    res.json(getSubscriptionStatus(req, res))
  })

  app.post('/api/create-checkout-session', async (req, res) => {
    const s = getStripe()
    if (!s) {
      res.status(503).json({ error: 'Stripe is not configured on this server' })
      return
    }
    await ensurePricesOnce()

    const plan = (req.body?.plan as string) === 'monthly' ? 'monthly' : 'yearly'
    const priceId = plan === 'monthly' ? priceMonthly : priceYearly
    if (!priceId) {
      res.status(503).json({
        error:
          'Stripe prices are not ready. Set STRIPE_PRICE_MONTHLY / STRIPE_PRICE_YEARLY or ensure the secret key can create products.',
      })
      return
    }

    const guestId = getGuestId(req, res)
    const base = getBaseUrl(req)

    try {
      const session = await s.checkout.sessions.create({
        mode: 'subscription',
        payment_method_types: ['card'],
        line_items: [{ price: priceId, quantity: 1 }],
        subscription_data: { trial_period_days: TRIAL_DAYS },
        success_url: `${base}/success?session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: `${base}/?checkout=canceled`,
        client_reference_id: guestId,
        allow_promotion_codes: true,
      })
      res.json({ sessionId: session.id, url: session.url, plan })
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Failed to create checkout session'
      console.error('[stripe] create-checkout-session:', msg)
      res.status(500).json({ error: msg })
    }
  })

  app.post('/api/verify-checkout-session', async (req, res) => {
    const s = getStripe()
    if (!s) {
      res.status(503).json({ error: 'Stripe is not configured on this server' })
      return
    }
    await ensurePricesOnce()

    const sessionId = typeof req.body?.sessionId === 'string' ? req.body.sessionId.trim() : ''
    if (!sessionId) {
      res.status(400).json({ error: 'Missing required field: sessionId' })
      return
    }

    try {
      const session = await s.checkout.sessions.retrieve(sessionId)
      const guestId = getGuestId(req, res)
      const ent = await unlockFromSession(s, session, guestId)
      if (ent && isProStatus(ent.status)) {
        setSubscriptionCookie(res, ent.id)
        res.json({
          verified: true,
          paymentStatus: session.payment_status,
          status: ent.status,
          plan: ent.plan,
          customerEmail: ent.email,
        })
        return
      }
      res.json({
        verified: false,
        paymentStatus: session.payment_status ?? 'unknown',
        sessionStatus: session.status,
      })
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Failed to verify checkout session'
      console.error('[stripe] verify-checkout-session:', msg)
      res.status(500).json({ error: msg })
    }
  })

  app.post('/api/billing-portal', async (req, res) => {
    const s = getStripe()
    if (!s) {
      res.status(503).json({ error: 'Stripe is not configured on this server' })
      return
    }

    const status = getSubscriptionStatus(req, res)
    const ent = getEntitlementFromCookie(req)
    if (!ent?.stripeCustomerId) {
      res.status(400).json({
        error: 'No Stripe customer on this browser session. Complete checkout first, or open Manage billing from the device you subscribed on.',
        pro: status.pro,
      })
      return
    }

    try {
      const base = getBaseUrl(req)
      const portal = await s.billingPortal.sessions.create({
        customer: ent.stripeCustomerId,
        return_url: `${base}/`,
      })
      res.json({ url: portal.url })
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Failed to open billing portal'
      console.error('[stripe] billing-portal:', msg)
      res.status(500).json({ error: msg })
    }
  })
}

export { PRODUCT_NAME, MONTHLY_CENTS, YEARLY_CENTS, TRIAL_DAYS }
