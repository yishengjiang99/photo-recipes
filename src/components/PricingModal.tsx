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
  const { pricingOpen, closePricing, startCheckout, checkoutLoading } =
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
      className="fixed inset-0 z-50 flex items-end justify-center bg-black/72 p-4 sm:items-center"
      role="dialog"
      aria-modal="true"
      aria-labelledby="pricing-title"
      onClick={(e) => {
        if (e.target === e.currentTarget) closePricing()
      }}
    >
      <div className="relative max-h-[92dvh] w-full max-w-[440px] overflow-y-auto rounded-2xl border border-border bg-surface p-5 shadow-2xl sm:max-w-[480px] sm:p-6">
        <button
          type="button"
          onClick={closePricing}
          className="absolute right-3 top-3 rounded-lg p-1.5 text-ink-tertiary hover:bg-surface-2 hover:text-ink"
          aria-label="Close"
        >
          <X className="h-5 w-5" />
        </button>

        <div className="mb-5 pr-8 text-left">
          <p className="mb-1 inline-flex items-center gap-1.5 rounded-full bg-accent-muted px-2.5 py-0.5 text-[11px] font-semibold uppercase tracking-wider text-accent-soft ring-1 ring-accent/30">
            <Sparkles className="h-3 w-3" />
            Soft upgrade · browse stays free
          </p>
          <h2 id="pricing-title" className="font-display text-2xl text-ink">
            Photo Recipes Pro
          </h2>
          <p className="mt-1.5 text-sm text-ink-secondary">
            Free Peek lets you explore presets. Pro unlocks unlimited Ask Grok and
            field checklists.
          </p>
        </div>

        <div className="mb-4 grid gap-3">
          <div className="relative rounded-2xl border-2 border-accent/50 bg-surface-2 p-4 text-left">
            <span className="absolute -top-2.5 right-4 rounded-full bg-accent px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-white">
              Best value
            </span>
            <div className="flex items-start justify-between gap-3">
              <div>
                <p className="text-sm font-semibold text-ink">Annual</p>
                <p className="mt-1 flex items-baseline gap-1">
                  <span className="font-display text-3xl text-ink">$59.99</span>
                  <span className="text-sm text-ink-secondary">/year</span>
                </p>
                <p className="mt-1 text-xs text-ink-secondary">
                  ≈ $5/mo · save vs monthly
                </p>
              </div>
              <span className="inline-flex items-center gap-1 rounded-full bg-success/15 px-2 py-1 text-[11px] font-semibold text-success ring-1 ring-success/30">
                <Zap className="h-3 w-3" />
                7-day free trial
              </span>
            </div>
            <button
              type="button"
              disabled={checkoutLoading}
              onClick={() => void checkout('yearly')}
              className="mt-4 inline-flex w-full items-center justify-center gap-2 rounded-xl bg-accent px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-accent-soft disabled:opacity-60"
            >
              {pending === 'yearly' ? (
                <>
                  <Loader2 className="h-4 w-4 animate-spin" /> Redirecting…
                </>
              ) : (
                'Start free trial'
              )}
            </button>
          </div>

          <div className="rounded-2xl border border-border bg-bg-elevated p-4 text-left">
            <div className="flex items-start justify-between gap-3">
              <div>
                <p className="text-sm font-semibold text-ink">Monthly</p>
                <p className="mt-1 flex items-baseline gap-1">
                  <span className="font-display text-2xl text-ink">$7.99</span>
                  <span className="text-sm text-ink-tertiary">/month</span>
                </p>
              </div>
              <span className="rounded-full bg-surface-2 px-2 py-1 text-[11px] font-semibold text-ink-tertiary ring-1 ring-border">
                7-day free trial
              </span>
            </div>
            <button
              type="button"
              disabled={checkoutLoading}
              onClick={() => void checkout('monthly')}
              className="mt-4 inline-flex w-full items-center justify-center gap-2 rounded-xl border border-border-strong bg-transparent px-4 py-2.5 text-sm font-semibold text-ink-secondary transition hover:border-ink-tertiary hover:text-ink disabled:opacity-60"
            >
              {pending === 'monthly' ? (
                <>
                  <Loader2 className="h-4 w-4 animate-spin" /> Redirecting…
                </>
              ) : (
                'Start free trial'
              )}
            </button>
          </div>
        </div>

        {error ? (
          <p
            role="alert"
            className="mb-4 rounded-xl border border-danger/30 bg-danger/10 px-3 py-2 text-sm text-danger"
          >
            {error}
          </p>
        ) : null}

        <div className="grid gap-4 sm:grid-cols-2">
          <div>
            <p className="mb-2 text-[11px] font-semibold uppercase tracking-wider text-ink-tertiary">
              Free Peek
            </p>
            <ul className="space-y-1.5">
              {FEATURES_FREE.map((f) => (
                <li key={f} className="flex gap-2 text-xs text-ink-secondary">
                  <Check className="mt-0.5 h-3.5 w-3.5 shrink-0 text-ink-tertiary" />
                  {f}
                </li>
              ))}
            </ul>
          </div>
          <div>
            <p className="mb-2 text-[11px] font-semibold uppercase tracking-wider text-accent-soft">
              Pro
            </p>
            <ul className="space-y-1.5">
              {FEATURES_PRO.map((f) => (
                <li key={f} className="flex gap-2 text-xs text-ink-secondary">
                  <Check className="mt-0.5 h-3.5 w-3.5 shrink-0 text-accent" />
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
