import { useState, type FormEvent } from 'react'

type Status = 'idle' | 'loading' | 'done' | 'error'

export function LandingEmailCapture({ className = '' }: { className?: string }) {
  const [email, setEmail] = useState('')
  const [status, setStatus] = useState<Status>('idle')
  const [error, setError] = useState<string | null>(null)

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setError(null)
    setStatus('loading')
    try {
      const res = await fetch('/api/waitlist', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, source: 'landing' }),
      })
      const data = (await res.json().catch(() => ({}))) as { ok?: boolean; error?: string }
      if (!res.ok || !data.ok) {
        setStatus('error')
        setError(data.error || 'Something went wrong. Try again.')
        return
      }
      setStatus('done')
      setEmail('')
    } catch {
      setStatus('error')
      setError('Network error. Try again.')
    }
  }

  if (status === 'done') {
    return (
      <p className={`text-sm text-ink-secondary ${className}`} role="status">
        You’re on the list — we’ll send field notes when there’s news.
      </p>
    )
  }

  return (
    <form onSubmit={onSubmit} className={`w-full max-w-md ${className}`}>
      <label htmlFor="waitlist-email" className="sr-only">
        Email for field notes
      </label>
      <div className="flex flex-col gap-2 sm:flex-row sm:items-stretch">
        <input
          id="waitlist-email"
          type="email"
          name="email"
          autoComplete="email"
          required
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="you@studio.com"
          disabled={status === 'loading'}
          className="min-h-11 flex-1 rounded-full border border-border bg-surface px-4 text-sm text-ink placeholder:text-ink-tertiary focus:border-accent focus:outline-none focus:ring-1 focus:ring-accent disabled:opacity-60"
        />
        <button
          type="submit"
          disabled={status === 'loading'}
          className="inline-flex min-h-11 shrink-0 items-center justify-center rounded-full bg-accent px-5 text-sm font-semibold text-white hover:bg-accent-soft disabled:opacity-60"
        >
          {status === 'loading' ? 'Joining…' : 'Get field notes'}
        </button>
      </div>
      {error ? (
        <p className="mt-2 text-left text-xs text-red-400" role="alert">
          {error}
        </p>
      ) : (
        <p className="mt-2 text-left text-xs text-ink-tertiary">
          Occasional updates on Auto Optimize & TestFlight — no spam.
        </p>
      )}
    </form>
  )
}
