import { Camera } from 'lucide-react'
import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { Seo } from './Seo'

type LegalShellProps = {
  title: string
  description: string
  path: '/privacy' | '/terms' | '/support'
  children: ReactNode
}

const NAV = [
  { to: '/privacy', label: 'Privacy' },
  { to: '/terms', label: 'Terms' },
  { to: '/support', label: 'Support' },
] as const

export function LegalShell({ title, description, path, children }: LegalShellProps) {
  return (
    <div className="min-h-dvh">
      <Seo title={`${title} — ProTune AI Camera`} description={description} path={path} />
      <header className="border-b border-border">
        <div className="mx-auto flex max-w-[720px] items-center justify-between gap-4 px-4 py-4 sm:px-6">
          <Link to="/" className="flex items-center gap-2 text-ink hover:opacity-90">
            <Camera className="h-4 w-4 text-accent-soft" />
            <span className="font-display text-lg">ProTune AI Camera</span>
          </Link>
          <nav className="flex flex-wrap gap-3 text-sm text-ink-tertiary">
            {NAV.map((item) => (
              <Link
                key={item.to}
                to={item.to}
                className={item.to === path ? 'text-ink' : 'hover:text-ink'}
              >
                {item.label}
              </Link>
            ))}
          </nav>
        </div>
      </header>

      <main className="mx-auto max-w-[720px] px-4 py-10 sm:px-6 sm:py-14">
        <h1 className="font-display text-3xl text-ink sm:text-4xl">{title}</h1>
        <p className="mt-2 text-sm text-ink-tertiary">{description}</p>
        <div className="mt-8 space-y-6 text-[15px] leading-relaxed text-ink-secondary">
          {children}
        </div>
      </main>

      <footer className="border-t border-border py-8">
        <div className="mx-auto flex max-w-[720px] flex-col gap-3 px-4 text-sm text-ink-tertiary sm:flex-row sm:items-center sm:justify-between sm:px-6">
          <Link to="/" className="hover:text-ink">
            ← Back to home
          </Link>
          <p>© {new Date().getFullYear()} ProTune AI Camera · Grepawk Photos</p>
        </div>
      </footer>
    </div>
  )
}
