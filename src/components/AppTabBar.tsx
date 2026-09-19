import { BookOpen, Camera, Crown, Sparkles, User } from 'lucide-react'
import { NavLink, useLocation, useNavigate } from 'react-router-dom'
import { useSubscription } from '../hooks/useSubscription'
import { track } from '../lib/analytics'

/** Dispatched when the center shutter is tapped while already on /app. */
export const SHUTTER_EVENT = 'photo-recipes:shutter'

/**
 * Instagram-inspired bottom tab bar (layout/IA only).
 * Library | Camera (center shutter) | Pro/Account
 */
export function AppTabBar() {
  const location = useLocation()
  const navigate = useNavigate()
  const { status, openPricing } = useSubscription()
  const pro = Boolean(status?.pro)
  const onCamera =
    location.pathname === '/app' || location.pathname === '/app/'

  function onShutter() {
    if (onCamera) {
      track('shutter_tap', { source: 'tab_bar' })
      window.dispatchEvent(new CustomEvent(SHUTTER_EVENT))
      return
    }
    track('tab_camera', { source: 'tab_bar' })
    navigate('/app')
  }

  return (
    <nav
      className="fixed inset-x-0 bottom-0 z-40 border-t border-border/70 bg-bg/95 backdrop-blur-md"
      style={{ paddingBottom: 'max(0.35rem, env(safe-area-inset-bottom))' }}
      aria-label="App"
    >
      <div className="mx-auto grid h-[4.25rem] max-w-[960px] grid-cols-3 items-end px-2 sm:px-4 xl:max-w-[1040px]">
        <NavLink
          to="/app/library"
          onClick={() => track('tab_library', { source: 'tab_bar' })}
          className={({ isActive }) =>
            `flex min-h-11 flex-col items-center justify-center gap-0.5 pb-2 text-[10px] font-medium transition ${
              isActive ? 'text-ink' : 'text-ink-tertiary hover:text-ink-secondary'
            }`
          }
        >
          <BookOpen className="h-5 w-5" strokeWidth={1.75} aria-hidden />
          Library
        </NavLink>

        <div className="relative flex flex-col items-center justify-end pb-1">
          <button
            type="button"
            onClick={onShutter}
            aria-label={onCamera ? 'Capture frame' : 'Open Camera'}
            className={`relative -mt-7 flex h-[4.25rem] w-[4.25rem] items-center justify-center rounded-full transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent ${
              onCamera
                ? 'bg-accent shadow-[0_10px_28px_-10px_rgba(244,63,94,0.7)] ring-[3px] ring-white/90'
                : 'bg-accent/90 shadow-[0_10px_28px_-12px_rgba(244,63,94,0.55)] ring-2 ring-white/70 hover:bg-accent'
            }`}
          >
            <span className="absolute inset-[5px] rounded-full border-2 border-white/35" aria-hidden />
            <Camera className="relative h-6 w-6 text-white" strokeWidth={2.25} aria-hidden />
          </button>
          <span
            className={`mt-1 text-[10px] font-semibold ${onCamera ? 'text-accent-soft' : 'text-ink-tertiary'}`}
          >
            Camera
          </span>
        </div>

        {pro ? (
          <NavLink
            to="/app/library"
            onClick={() => track('tab_pro', { source: 'tab_bar', pro: true })}
            className="flex min-h-11 flex-col items-center justify-center gap-0.5 pb-2 text-[10px] font-medium text-ink-tertiary hover:text-ink-secondary"
            aria-label="Pro account"
          >
            <Crown className="h-5 w-5 text-success" strokeWidth={1.75} aria-hidden />
            Pro
          </NavLink>
        ) : (
          <button
            type="button"
            onClick={() => {
              track('tab_pro', { source: 'tab_bar' })
              openPricing()
            }}
            className="flex min-h-11 flex-col items-center justify-center gap-0.5 pb-2 text-[10px] font-medium text-ink-tertiary transition hover:text-ink-secondary"
            aria-label="Upgrade to Pro"
          >
            <span className="relative">
              <User className="h-5 w-5" strokeWidth={1.75} aria-hidden />
              <Sparkles className="absolute -right-1.5 -top-1 h-3 w-3 text-accent-soft" aria-hidden />
            </span>
            Pro
          </button>
        )}
      </div>
    </nav>
  )
}
