import { Camera, CreditCard, Crown, Sparkles } from 'lucide-react'
import { useState } from 'react'
import { Link, Outlet } from 'react-router-dom'
import { useSubscription } from '../hooks/useSubscription'

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
    <div className="mx-auto flex min-h-dvh w-full max-w-[960px] flex-col px-4 pb-10 pt-6 sm:px-6 lg:max-w-[960px] xl:max-w-[1040px] xl:px-8">
      <header className="sticky top-0 z-20 -mx-4 mb-8 flex items-center justify-between gap-4 bg-bg/90 px-4 py-3 backdrop-blur-md sm:-mx-6 sm:px-6 xl:-mx-8 xl:px-8">
        <Link to="/app" className="group flex items-center gap-3">
          <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-accent-muted ring-1 ring-accent/30 transition group-hover:bg-accent/20">
            <Camera className="h-5 w-5 text-accent-soft" strokeWidth={1.75} />
          </span>
          <div className="text-left">
            <p className="font-display text-lg leading-none tracking-tight text-ink sm:text-xl">
              Photo Recipes
            </p>
            <p className="mt-0.5 text-xs text-ink-tertiary">
              Field presets · 30 Recipes book
            </p>
          </div>
        </Link>

        <div className="flex flex-col items-end gap-1.5">
          <div className="flex items-center gap-2">
            {!loading ? (
              <span
                className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[11px] font-semibold uppercase tracking-wide ring-1 ${
                  pro
                    ? 'bg-success/15 text-success ring-success/35'
                    : 'bg-surface text-ink-secondary ring-border'
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
                className="inline-flex min-h-9 items-center gap-1.5 rounded-full bg-surface px-2.5 py-1 text-[11px] font-medium text-ink-secondary ring-1 ring-border hover:bg-surface-2"
              >
                <CreditCard className="h-3 w-3" />
                Manage billing
              </button>
            ) : (
              <button
                type="button"
                onClick={openPricing}
                className="inline-flex min-h-9 items-center gap-1.5 rounded-full bg-accent px-2.5 py-1 text-[11px] font-semibold text-white hover:bg-accent-soft"
              >
                <Sparkles className="h-3 w-3" />
                Upgrade
              </button>
            )}
          </div>
          {portalError ? (
            <p className="max-w-[14rem] text-right text-[10px] leading-snug text-danger">
              {portalError}
            </p>
          ) : null}
        </div>
      </header>
      <main className="flex-1">
        <Outlet />
      </main>
      <footer className="mt-12 border-t border-border pt-6 text-center text-xs text-ink-tertiary">
        <p>
          <Link to="/" className="text-ink-secondary underline-offset-2 hover:text-ink hover:underline">
            Photo Recipes home
          </Link>
          {' · '}
          Educational presets from book pages · Not affiliated with the publisher
        </p>
      </footer>
    </div>
  )
}
