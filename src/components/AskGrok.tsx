import { Loader2, Sparkles, Wand2 } from 'lucide-react'
import { useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { useFavorites } from '../hooks/useFavorites'

const EXAMPLES = [
  'Sunset canyon with a dark foreground',
  'Kid running through the woods',
  'Waterfall with silky motion blur',
  'Landscape sharp from rocks to skyline',
  'Fresh low-angle street scene',
]

export type AiRecommendState = {
  reason: string
  tips: string[]
  fromAsk: true
}

export function AskGrok() {
  const [message, setMessage] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const navigate = useNavigate()
  const { favorites } = useFavorites()

  async function submit(text: string) {
    const trimmed = text.trim()
    if (!trimmed || loading) return

    setLoading(true)
    setError(null)

    try {
      const res = await fetch('/api/recommend', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: trimmed,
          favorites: favorites.length ? favorites : undefined,
        }),
      })

      const data = (await res.json().catch(() => ({}))) as {
        error?: string
        presetId?: string
        reason?: string
        tips?: string[]
      }

      if (!res.ok) {
        throw new Error(data.error || `Request failed (${res.status})`)
      }

      if (!data.presetId) {
        throw new Error('No preset returned from Grok')
      }

      const state: AiRecommendState = {
        reason: data.reason || 'Grok recommended this recipe for your scene.',
        tips: Array.isArray(data.tips) ? data.tips : [],
        fromAsk: true,
      }

      navigate(`/preset/${data.presetId}`, { state })
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Something went wrong')
    } finally {
      setLoading(false)
    }
  }

  function onSubmit(e: FormEvent) {
    e.preventDefault()
    void submit(message)
  }

  return (
    <section className="mb-8 overflow-hidden rounded-2xl border border-rose-500/25 bg-gradient-to-br from-rose-500/10 via-zinc-900/80 to-zinc-950 p-5 shadow-[0_0_40px_-20px_rgba(244,63,94,0.5)] sm:p-6">
      <div className="mb-4 flex items-start gap-3">
        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-rose-500/20 ring-1 ring-rose-500/35">
          <Wand2 className="h-5 w-5 text-rose-300" strokeWidth={1.75} />
        </span>
        <div className="text-left">
          <h2 className="font-display text-2xl text-zinc-50">Ask Grok</h2>
          <p className="mt-1 text-sm leading-relaxed text-zinc-400">
            Describe the scene — Grok picks a recipe from this catalog and
            coaches you on why.
          </p>
        </div>
      </div>

      <form onSubmit={onSubmit} className="space-y-3">
        <label htmlFor="ask-grok" className="sr-only">
          Scene description
        </label>
        <textarea
          id="ask-grok"
          rows={3}
          value={message}
          onChange={(e) => setMessage(e.target.value)}
          disabled={loading}
          placeholder='e.g. "sunset canyon with dark foreground"'
          className="w-full resize-none rounded-xl border border-zinc-700/80 bg-zinc-950/70 px-4 py-3 text-sm text-zinc-100 placeholder:text-zinc-600 outline-none ring-rose-500/40 transition focus:border-rose-500/50 focus:ring-2 disabled:opacity-60"
        />

        <div className="flex flex-wrap gap-2">
          {EXAMPLES.map((ex) => (
            <button
              key={ex}
              type="button"
              disabled={loading}
              onClick={() => {
                setMessage(ex)
                void submit(ex)
              }}
              className="rounded-full bg-zinc-900/80 px-3 py-1 text-xs text-zinc-400 ring-1 ring-zinc-700/80 transition hover:bg-zinc-800 hover:text-zinc-200 disabled:opacity-50"
            >
              {ex}
            </button>
          ))}
        </div>

        <button
          type="submit"
          disabled={loading || !message.trim()}
          className="inline-flex w-full items-center justify-center gap-2 rounded-xl bg-rose-500 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-rose-400 disabled:cursor-not-allowed disabled:opacity-50 sm:w-auto"
        >
          {loading ? (
            <>
              <Loader2 className="h-4 w-4 animate-spin" />
              Grok is choosing…
            </>
          ) : (
            <>
              <Sparkles className="h-4 w-4" />
              Recommend a recipe
            </>
          )}
        </button>
      </form>

      {error ? (
        <p
          role="alert"
          className="mt-4 rounded-xl border border-amber-500/30 bg-amber-500/10 px-3 py-2.5 text-sm text-amber-200"
        >
          {error}
        </p>
      ) : null}
    </section>
  )
}
