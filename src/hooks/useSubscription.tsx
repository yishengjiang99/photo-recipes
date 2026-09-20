import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import { track } from '../lib/analytics'

export type SubscriptionStatus = {
  pro: boolean
  /** Owner/device/admin allowlist — unlimited Ask without Pro badge */
  unlimited?: boolean
  status: string
  plan: 'monthly' | 'yearly' | null
  email: string | null
  asksUsedToday: number
  asksLimit: number | null
  asksRemaining: number | null
  freeDailyLimit?: number
  freePhoneTargetsEnabled?: boolean
  stripeConfigured: boolean
}

type SubscriptionContextValue = {
  status: SubscriptionStatus | null
  loading: boolean
  refresh: () => Promise<SubscriptionStatus | null>
  openPricing: () => void
  closePricing: () => void
  pricingOpen: boolean
  startCheckout: (plan: 'monthly' | 'yearly') => Promise<void>
  openBillingPortal: () => Promise<void>
  checkoutLoading: boolean
}

const defaultStatus: SubscriptionStatus = {
  pro: false,
  status: 'inactive',
  plan: null,
  email: null,
  asksUsedToday: 0,
  asksLimit: 5,
  asksRemaining: 5,
  stripeConfigured: false,
}

const SubscriptionContext = createContext<SubscriptionContextValue | null>(null)

async function fetchStatus(): Promise<SubscriptionStatus> {
  const res = await fetch('/api/subscription-status', { credentials: 'include' })
  if (!res.ok) return defaultStatus
  return (await res.json()) as SubscriptionStatus
}

export function SubscriptionProvider({ children }: { children: ReactNode }) {
  const [status, setStatus] = useState<SubscriptionStatus | null>(null)
  const [loading, setLoading] = useState(true)
  const [pricingOpen, setPricingOpen] = useState(false)
  const [checkoutLoading, setCheckoutLoading] = useState(false)

  const refresh = useCallback(async () => {
    try {
      const s = await fetchStatus()
      setStatus(s)
      return s
    } catch {
      setStatus(defaultStatus)
      return defaultStatus
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void refresh()
  }, [refresh])

  const startCheckout = useCallback(async (plan: 'monthly' | 'yearly') => {
    setCheckoutLoading(true)
    track('paywall_plan_select', { plan, source: 'web_pricing' })
    track('purchase_start', { plan, source: 'stripe' })
    try {
      const res = await fetch('/api/create-checkout-session', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ plan }),
      })
      const data = (await res.json().catch(() => ({}))) as { url?: string; error?: string }
      if (!res.ok || !data.url) {
        track('purchase_fail', {
          plan,
          source: 'stripe',
          error_code: String(res.status),
        })
        throw new Error(data.error || `Checkout failed (${res.status})`)
      }
      track('checkout_redirect', { plan, source: 'stripe' })
      window.location.href = data.url
    } catch (err) {
      track('purchase_fail', {
        plan,
        source: 'stripe',
        error_code: 'exception',
      })
      throw err
    } finally {
      setCheckoutLoading(false)
    }
  }, [])

  const openBillingPortal = useCallback(async () => {
    const res = await fetch('/api/billing-portal', {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json' },
      body: '{}',
    })
    const data = (await res.json().catch(() => ({}))) as { url?: string; error?: string }
    if (!res.ok || !data.url) {
      throw new Error(data.error || `Billing portal failed (${res.status})`)
    }
    window.location.href = data.url
  }, [])

  const value = useMemo<SubscriptionContextValue>(
    () => ({
      status,
      loading,
      refresh,
      openPricing: () => {
        track('paywall_view', { source: 'web_pricing' })
        setPricingOpen(true)
      },
      closePricing: () => setPricingOpen(false),
      pricingOpen,
      startCheckout,
      openBillingPortal,
      checkoutLoading,
    }),
    [
      status,
      loading,
      refresh,
      pricingOpen,
      startCheckout,
      openBillingPortal,
      checkoutLoading,
    ],
  )

  return (
    <SubscriptionContext.Provider value={value}>{children}</SubscriptionContext.Provider>
  )
}

export function useSubscription() {
  const ctx = useContext(SubscriptionContext)
  if (!ctx) {
    throw new Error('useSubscription must be used within SubscriptionProvider')
  }
  return ctx
}
