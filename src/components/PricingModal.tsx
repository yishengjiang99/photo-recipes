import { Check, Loader2, Sparkles, X, Zap } from 'lucide-react'
import { useState } from 'react'
import { useSubscription } from '../hooks/useSubscription'

const FEATURES_FREE = [
  'Browse all recipe presets',
  'Favorites & filters',
  'Ask Grok 1× per day (Free Peek)',
]

const FEATURES_PRO = [
  'Unlimited Ask Grok recommendations',
  'Interactive field checklists',
  '7-day free trial, cancel anytime',
  'Support ongoing recipe updates',
]

export function PricingModal() {
  const { pricingOpen, closePricing, startCheckout, checkoutLoading, status } =
    useSubscription()
  const [error, setError] = useState<string | null>(null)
  const [pending, setPending] = useState<'monthly' | 'yearly' | null>(null)

  if (!pricingOpen) return null

  async function checkout(plan: 'monthly' | 'yearly') {
    setError(null)
    setPending(plan)
    try {
      await startCheckout(plan)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Checkout failed')
      setPending(null)
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-black/70 p-4 sm:items-center"
      role="dialog"
      aria-modal="true"
      aria-labelledby="pricing-title"
      onClick={(e) => {
        if (e.target === e.currentTarget) closePricing()
      }}
    >
      <div className="relative max-h-[92dvh] w-full max-w-lg overflow-y-auto rounded-2xl border border-zinc-700 bg-zinc-950 p-5 shadow-2xl sm:p-6">
        <button
          type="button"
          onClick={closePricing}
          className="absolute right-3 top-3 rounded-lg p-1.5 text-zinc-500 hover:bg-zinc-800 hover:text-zinc-200"
          aria-label="Close"
        >
          <X className="h-5 w-5" />
        </button>

        <div className="mb-5 pr-8 text-left">
          <p className="mb-1 inline-flex items-center gap-1.5 rounded-full bg-rose-500/15 px-2.5 py-0.5 text-[11px] font-semibold uppercase tracking-wider text-rose-300 ring-1 ring-rose-500/30">
            <Sparkles className="h-3 w-3" />
            Soft upgrade · browse stays free
          </p>
          <h2 id="pricing-title" className="font-display text-2xl text-zinc-50">
            Photo Recipes Pro
          </h2>
          <p className="mt-1.5 text-sm text-zinc-400">
            Free Peek lets you explore presets. Pro unlocks unlimited Ask Grok and
            field checklists.
          </p>
        </div>

        <div className="mb-4 grid gap-3">
          {/* Yearly — primary */}
          <button
            type="button"
            disabled={checkoutLoading || !status?.stripeConfigured}
            onClick={() => void checkout('yearly')}
            className="relative rounded-2xl border-2 border-rose-500/60 bg-gradient-to-br from-rose-500/20 via-zinc-900 to-zinc-950 p-4 text-left transition hover:border-rose-400 disabled:opacity-60"
          >
            <span className="absolute -top-2.5 right-4 rounded-full bg-rose-500 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-white">
              Best value
            </span>
            <div className="flex items-start justify-between gap-3">
              <div>
                <p className="text-sm font-semibold text-zinc-100">Annual</p>
                <p className="mt-1 flex items-baseline gap-1">
                  <span className="font-display text-3xl text-white">$59.99</span>
                  <span className="text-sm text-zinc-400">/year</span>
                </p>
                <p className="mt-1 text-xs text-rose-300/90">≈ $5/mo · save vs monthly</p>
              </div>
              <span className="inline-flex items-center gap-1 rounded-full bg-emerald-500/15 px-2 py-1 text-[11px] font-semibold text-emerald-300 ring-1 ring-emerald-500/30">
                <Zap className="h-3 w-3" />
                7-day free trial
              </span>
            </div>
            <p className="mt-3 inline-flex items-center gap-2 text-sm font-semibold text-rose-200">
              {pending === 'yearly' ? (
                <>
                  <Loader2 className="h-4 w-4 animate-spin" /> Redirecting…
                </>
              ) : (
                'Start free trial →'
              )}
            </p>
          </button>

          {/* Monthly */}
          <button
            type="button"
            disabled={checkoutLoading || !status?.stripeConfigured}
            onClick={() => void checkout('monthly')}
            className="rounded-2xl border border-zinc-700 bg-zinc-900/60 p-4 text-left transition hover:border-zinc-500 disabled:opacity-60"
          >
            <div className="flex items-start justify-between gap-3">
              <div>
                <p className="text-sm font-semibold text-zinc-200">Monthly</p>
                <p className="mt-1 flex items-baseline gap-1">
                  <span className="font-display text-2xl text-zinc-50">$7.99</span>
                  <span className="text-sm text-zinc-500">/month</span>
                </p>
              </div>
              <span className="rounded-full bg-zinc-800 px-2 py-1 text-[11px] font-semibold text-zinc-400 ring-1 ring-zinc-700">
                7-day free trial
              </span>
            </div>
            <p className="mt-3 text-sm font-medium text-zinc-400">
              {pending === 'monthly' ? (
                <span className="inline-flex items-center gap-2">
                  <Loader2 className="h-4 w-4 animate-spin" /> Redirecting…
                </span>
              ) : (
                'Start free trial'
              )}
            </p>
          </button>
        </div>

        {!status?.stripeConfigured ? (
          <p className="mb-3 rounded-xl border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-xs text-amber-200">
            Stripe is not configured on this server yet (missing STRIPE_SECRET_KEY).
          </p>
        ) : null}

        {error ? (
          <p role="alert" className="mb-3 rounded-xl border border-rose-500/30 bg-rose-500/10 px-3 py-2 text-sm text-rose-200">
            {error}
          </p>
        ) : null}

        <div className="grid gap-4 sm:grid-cols-2">
          <div>
            <p className="mb-2 text-[11px] font-semibold uppercase tracking-wider text-zinc-500">
              Free Peek
            </p>
            <ul className="space-y-1.5">
              {FEATURES_FREE.map((f) => (
                <li key={f} className="flex gap-2 text-xs text-zinc-400">
                  <Check className="mt-0.5 h-3.5 w-3.5 shrink-0 text-zinc-600" />
                  {f}
                </li>
              ))}
            </ul>
          </div>
          <div>
            <p className="mb-2 text-[11px] font-semibold uppercase tracking-wider text-rose-400">
              Pro
            </p>
            <ul className="space-y-1.5">
              {FEATURES_PRO.map((f) => (
                <li key={f} className="flex gap-2 text-xs text-zinc-300">
                  <Check className="mt-0.5 h-3.5 w-3.5 shrink-0 text-rose-400" />
                  {f}
                </li>
              ))}
            </ul>
          </div>
        </div>
      </div>
    </div>
  )
}
