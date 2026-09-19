import { CheckCircle2, Loader2, XCircle } from 'lucide-react'
import { useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { useSubscription } from '../hooks/useSubscription'

export function Success() {
  const [params] = useSearchParams()
  const sessionId = params.get('session_id')
  const { refresh } = useSubscription()
  const [state, setState] = useState<'loading' | 'ok' | 'fail'>('loading')
  const [detail, setDetail] = useState<string>('')

  useEffect(() => {
    let cancelled = false
    async function run() {
      if (!sessionId) {
        setState('fail')
        setDetail('Missing session_id in the URL.')
        return
      }
      try {
        const res = await fetch('/api/verify-checkout-session', {
          method: 'POST',
          credentials: 'include',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ sessionId }),
        })
        const data = (await res.json().catch(() => ({}))) as {
          verified?: boolean
          error?: string
          status?: string
          plan?: string
        }
        if (cancelled) return
        if (!res.ok) {
          setState('fail')
          setDetail(data.error || `Verify failed (${res.status})`)
          return
        }
        if (data.verified) {
          await refresh()
          setState('ok')
          setDetail(
            data.status === 'trialing'
              ? 'Your 7-day free trial is active. Enjoy unlimited Ask Grok and field checklists.'
              : `Pro is unlocked${data.plan ? ` (${data.plan})` : ''}.`,
          )
        } else {
          setState('fail')
          setDetail('Checkout was not completed yet. If you paid, wait a moment and refresh.')
        }
      } catch (err) {
        if (cancelled) return
        setState('fail')
        setDetail(err instanceof Error ? err.message : 'Verification failed')
      }
    }
    void run()
    return () => {
      cancelled = true
    }
  }, [sessionId, refresh])

  return (
    <div className="mx-auto max-w-md py-16 text-center">
      {state === 'loading' ? (
        <>
          <Loader2 className="mx-auto h-10 w-10 animate-spin text-rose-400" />
          <h1 className="mt-4 font-display text-2xl text-zinc-50">Confirming Pro…</h1>
          <p className="mt-2 text-sm text-zinc-400">Verifying your Stripe checkout session.</p>
        </>
      ) : null}

      {state === 'ok' ? (
        <>
          <CheckCircle2 className="mx-auto h-10 w-10 text-emerald-400" />
          <h1 className="mt-4 font-display text-2xl text-zinc-50">Welcome to Pro</h1>
          <p className="mt-2 text-sm text-zinc-400">{detail}</p>
          <Link
            to="/"
            className="mt-6 inline-flex rounded-xl bg-rose-500 px-4 py-2.5 text-sm font-semibold text-white hover:bg-rose-400"
          >
            Back to library
          </Link>
        </>
      ) : null}

      {state === 'fail' ? (
        <>
          <XCircle className="mx-auto h-10 w-10 text-amber-400" />
          <h1 className="mt-4 font-display text-2xl text-zinc-50">Couldn’t verify yet</h1>
          <p className="mt-2 text-sm text-zinc-400">{detail}</p>
          <Link
            to="/"
            className="mt-6 inline-flex rounded-xl bg-zinc-800 px-4 py-2.5 text-sm font-semibold text-zinc-200 ring-1 ring-zinc-700 hover:bg-zinc-700"
          >
            Back to library
          </Link>
        </>
      ) : null}
    </div>
  )
}
