import { Camera, CreditCard, Crown, Sparkles } from 'lucide-react'
import { useState } from 'react'
import { Link, Outlet } from 'react-router-dom'
import { useSubscription } from '../hooks/useSubscription'
import { PricingModal } from './PricingModal'

export function Layout() {
  const { status, loading, openPricing, openBillingPortal } = useSubscription()
  const [portalError, setPortalError] = useState<string | null>(null)
  const pro = Boolean(status?.pro)

  async function manageBilling() {
    setPortalError(null)
    try {
      await openBillingPortal()
    } catch (err) {
      setPortalError(err instanceof Error ? err.message : 'Could not open billing portal')
    }
  }

  return (
    <div className="mx-auto flex min-h-dvh max-w-3xl flex-col px-4 pb-10 pt-6 sm:px-6">
      <header className="mb-8 flex items-center justify-between gap-4">
        <Link to="/" className="group flex items-center gap-3">
          <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-rose-500/15 ring-1 ring-rose-500/30 transition group-hover:bg-rose-500/25">
            <Camera className="h-5 w-5 text-rose-400" strokeWidth={1.75} />
          </span>
          <div className="text-left">
            <p className="font-display text-2xl leading-none tracking-tight text-zinc-50">
              Photo Recipes
            </p>
            <p className="mt-0.5 text-xs text-zinc-500">Field presets · 30 Recipes book</p>
          </div>
        </Link>

        <div className="flex flex-col items-end gap-1.5">
          <div className="flex items-center gap-2">
            {!loading ? (
              <span
                className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[11px] font-semibold uppercase tracking-wide ring-1 ${
                  pro
                    ? 'bg-amber-500/15 text-amber-200 ring-amber-500/35'
                    : 'bg-zinc-900 text-zinc-400 ring-zinc-700'
                }`}
              >
                {pro ? <Crown className="h-3 w-3" /> : null}
                {pro ? 'Pro' : 'Free Peek'}
              </span>
            ) : null}

            {pro ? (
              <button
                type="button"
                onClick={() => void manageBilling()}
                className="inline-flex items-center gap-1.5 rounded-full bg-zinc-900 px-2.5 py-1 text-[11px] font-medium text-zinc-300 ring-1 ring-zinc-700 hover:bg-zinc-800"
              >
                <CreditCard className="h-3 w-3" />
                Manage billing
              </button>
            ) : (
              <button
                type="button"
                onClick={openPricing}
                className="inline-flex items-center gap-1.5 rounded-full bg-rose-500 px-2.5 py-1 text-[11px] font-semibold text-white hover:bg-rose-400"
              >
                <Sparkles className="h-3 w-3" />
                Upgrade
              </button>
            )}
          </div>
          {portalError ? (
            <p className="max-w-[14rem] text-right text-[10px] leading-snug text-amber-400/90">
              {portalError}
            </p>
          ) : null}
        </div>
      </header>
      <main className="flex-1">
        <Outlet />
      </main>
      <footer className="mt-12 border-t border-zinc-800/80 pt-6 text-center text-xs text-zinc-600">
        Educational presets from book pages · Not affiliated with the publisher
      </footer>
      <PricingModal />
    </div>
  )
}
