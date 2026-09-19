import { Check, Loader2 } from 'lucide-react'
import { useEffect, useId, useRef, useState, type FormEvent } from 'react'
import { CameraCta } from './CameraCta'
import { track } from '../lib/analytics'

type FormState =
  | 'idle'
  | 'loading'
  | 'success'
  | 'duplicate'
  | 'error_validation'
  | 'error_server'

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

type ApiOk = { ok: true; duplicate?: boolean }
type ApiErr = { ok?: false; error?: string }

export function LandingEmailCapture({ className = '' }: { className?: string }) {
  const inputId = useId()
  const errorId = useId()
  const successRef = useRef<HTMLHeadingElement>(null)
  const [email, setEmail] = useState('')
  const [state, setState] = useState<FormState>('idle')

  useEffect(() => {
    if (state === 'success' || state === 'duplicate') {
      successRef.current?.focus()
    }
  }, [state])

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    const trimmed = email.trim().toLowerCase()
    if (!trimmed || !EMAIL_RE.test(trimmed) || trimmed.length > 254) {
      setState('error_validation')
      return
    }

    setState('loading')
    track('waitlist_submit', { source: 'landing_notes' })
    try {
      const res = await fetch('/api/waitlist', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: trimmed }),
      })
      const data = (await res.json().catch(() => ({}))) as ApiOk | ApiErr

      if (res.status === 400) {
        setState('error_validation')
        track('waitlist_fail', { source: 'landing_notes', error_code: 'validation' })
        return
      }

      if (!res.ok || !('ok' in data) || !data.ok) {
        setState('error_server')
        track('waitlist_fail', { source: 'landing_notes', error_code: 'server' })
        return
      }

      setState(data.duplicate ? 'duplicate' : 'success')
      track('waitlist_success', {
        source: 'landing_notes',
        duplicate: Boolean(data.duplicate),
      })
    } catch {
      setState('error_server')
      track('waitlist_fail', { source: 'landing_notes', error_code: 'network' })
    }
  }

  if (state === 'success' || state === 'duplicate') {
    return (
      <div className={`rounded-2xl border border-border bg-surface p-6 sm:p-7 ${className}`}>
        <div className="flex items-start gap-3">
          <span className="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-accent-muted text-accent-soft ring-1 ring-accent/30">
            <Check className="h-4 w-4" strokeWidth={2.25} />
          </span>
          <div>
            <h3
              ref={successRef}
              tabIndex={-1}
              className="text-base font-semibold text-ink outline-none"
            >
              {state === 'duplicate' ? 'You’re already on the list.' : 'You’re on the list.'}
            </h3>
            <p className="mt-1 text-sm text-ink-secondary">We’ll write when it matters.</p>
            <div className="mt-4">
              <CameraCta label="Open Camera" />
            </div>
          </div>
        </div>
      </div>
    )
  }

  const showValidation = state === 'error_validation'
  const showServer = state === 'error_server'
  const busy = state === 'loading'

  return (
    <div className={`rounded-2xl border border-border bg-surface p-6 sm:p-7 ${className}`}>
      <form onSubmit={onSubmit} noValidate>
        <label htmlFor={inputId} className="sr-only">
          Email for field notes
        </label>
        <div className="flex flex-col gap-2.5 sm:flex-row sm:items-stretch">
          <input
            id={inputId}
            type="email"
            name="email"
            autoComplete="email"
            inputMode="email"
            value={email}
            onChange={(e) => {
              setEmail(e.target.value)
              if (state === 'error_validation' || state === 'error_server') setState('idle')
            }}
            placeholder="you@studio.email"
            readOnly={busy}
            aria-invalid={showValidation || undefined}
            aria-describedby={showValidation || showServer ? errorId : undefined}
            className="min-h-11 flex-1 rounded-full border border-border bg-bg px-4 text-sm text-ink placeholder:text-ink-tertiary focus:border-accent focus:outline-none focus:ring-1 focus:ring-accent-soft disabled:opacity-60 aria-[invalid=true]:border-danger"
          />
          <button
            type="submit"
            disabled={busy}
            className="inline-flex min-h-11 shrink-0 items-center justify-center gap-2 rounded-full bg-accent px-5 text-sm font-semibold text-white hover:bg-accent-soft disabled:opacity-60"
          >
            {busy ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin" aria-hidden />
                Sending…
              </>
            ) : (
              'Join the list'
            )}
          </button>
        </div>

        {showValidation ? (
          <p id={errorId} className="mt-2.5 text-xs text-danger" role="alert">
            Enter a valid email.
          </p>
        ) : showServer ? (
          <p id={errorId} className="mt-2.5 rounded-lg bg-danger/10 px-3 py-2 text-xs text-danger" role="alert">
            Couldn’t join right now. Try again.
          </p>
        ) : (
          <p className="mt-2.5 text-xs text-ink-tertiary">
            We’ll only use this for Photo Recipes field notes.
          </p>
        )}
      </form>
    </div>
  )
}
