import { Camera } from 'lucide-react'
import { Link, Outlet, useLocation } from 'react-router-dom'
import { AppTabBar } from './AppTabBar'

export function Layout() {
  const location = useLocation()
  const onCamera =
    location.pathname === '/app' || location.pathname === '/app/'

  return (
    <div
      className={`flex min-h-dvh w-full flex-col ${
        onCamera ? 'bg-black' : 'bg-bg'
      }`}
    >
      {!onCamera ? (
        <header className="sticky top-0 z-20 flex items-center justify-between gap-3 border-b border-border/50 bg-bg/90 px-4 py-2.5 backdrop-blur-md sm:px-6">
          <Link to="/app" className="group flex items-center gap-2.5" aria-label="Open Camera">
            <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-accent-muted ring-1 ring-accent/30">
              <Camera className="h-4 w-4 text-accent-soft" strokeWidth={1.75} />
            </span>
            <span className="font-display text-base tracking-tight text-ink">Photo Recipes</span>
          </Link>
        </header>
      ) : null}

      <main
        className={
          onCamera
            ? 'relative flex min-h-0 flex-1 flex-col'
            : 'mx-auto w-full max-w-[960px] flex-1 px-4 pb-[calc(5.75rem+env(safe-area-inset-bottom))] pt-5 sm:px-6 xl:max-w-[1040px]'
        }
        style={
          onCamera
            ? { paddingBottom: 'calc(5.75rem + env(safe-area-inset-bottom))' }
            : undefined
        }
      >
        <Outlet />
      </main>

      <AppTabBar />
    </div>
  )
}
