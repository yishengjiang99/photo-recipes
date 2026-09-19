import { Camera } from 'lucide-react'
import { Link, Outlet } from 'react-router-dom'

export function Layout() {
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
      </header>
      <main className="flex-1">
        <Outlet />
      </main>
      <footer className="mt-12 border-t border-zinc-800/80 pt-6 text-center text-xs text-zinc-600">
        Educational presets from book pages · Not affiliated with the publisher
      </footer>
    </div>
  )
}
