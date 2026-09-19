import {
  Camera,
  ImagePlus,
  Loader2,
  Sparkles,
  X,
} from 'lucide-react'
import { useCallback, useId, useRef, useState, type DragEvent, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { useFavorites } from '../hooks/useFavorites'
import { useSubscription } from '../hooks/useSubscription'
import { compressImageForUpload } from '../lib/compressImage'
import type { AiRecommendState } from './AskGrok'

export function PhotoVision() {
  const fileInputId = useId()
  const cameraInputId = useId()
  const fileRef = useRef<HTMLInputElement>(null)
  const cameraRef = useRef<HTMLInputElement>(null)

  const [previewUrl, setPreviewUrl] = useState<string | null>(null)
  const [dataUrl, setDataUrl] = useState<string | null>(null)
  const [note, setNote] = useState('')
  const [preparing, setPreparing] = useState(false)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [paywalled, setPaywalled] = useState(false)
  const [dragOver, setDragOver] = useState(false)

  const navigate = useNavigate()
  const { favorites } = useFavorites()
  const { status, refresh, openPricing } = useSubscription()

  const clearImage = useCallback(() => {
    setPreviewUrl(null)
    setDataUrl(null)
    if (fileRef.current) fileRef.current.value = ''
    if (cameraRef.current) cameraRef.current.value = ''
  }, [])

  async function ingestFile(file: File) {
    setError(null)
    setPaywalled(false)
    setPreparing(true)
    try {
      const compressed = await compressImageForUpload(file)
      setDataUrl(compressed.dataUrl)
      setPreviewUrl(compressed.dataUrl)
    } catch (err) {
      clearImage()
      setError(err instanceof Error ? err.message : 'Could not prepare image')
    } finally {
      setPreparing(false)
    }
  }

  function onFileChange(files: FileList | null) {
    const file = files?.[0]
    if (file) void ingestFile(file)
  }

  function onDrop(e: DragEvent) {
    e.preventDefault()
    setDragOver(false)
    const file = e.dataTransfer.files?.[0]
    if (file) void ingestFile(file)
  }

  async function submit(e?: FormEvent) {
    e?.preventDefault()
    if (!dataUrl || loading || preparing) return

    setLoading(true)
    setError(null)
    setPaywalled(false)

    try {
      const res = await fetch('/api/recommend', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: note.trim() || undefined,
          image: dataUrl,
          favorites: favorites.length ? favorites : undefined,
        }),
      })

      const data = (await res.json().catch(() => ({}))) as {
        error?: string
        code?: string
        presetId?: string
        reason?: string
        tips?: string[]
      }

      if (res.status === 402 || data.code === 'paywall') {
        setPaywalled(true)
        setError(
          data.error ||
            'Free Peek limit reached (1 Ask / Photo Vision per day). Upgrade for unlimited.',
        )
        void refresh()
        return
      }

      if (!res.ok) {
        throw new Error(data.error || `Request failed (${res.status})`)
      }

      if (!data.presetId) {
        throw new Error('No preset returned from Grok')
      }

      const state: AiRecommendState = {
        reason: data.reason || 'Grok recommended this recipe from your photo.',
        tips: Array.isArray(data.tips) ? data.tips : [],
        fromAsk: true,
      }

      void refresh()
      navigate(`/preset/${data.presetId}`, { state })
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Something went wrong')
    } finally {
      setLoading(false)
    }
  }

  const remaining = status?.pro ? null : (status?.asksRemaining ?? null)
  const busy = loading || preparing

  return (
    <section className="mb-8 overflow-hidden rounded-2xl border border-violet-500/25 bg-gradient-to-br from-violet-500/10 via-zinc-900/80 to-zinc-950 p-5 shadow-[0_0_40px_-20px_rgba(139,92,246,0.45)] sm:p-6">
      <div className="mb-4 flex items-start gap-3">
        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-violet-500/20 ring-1 ring-violet-500/35">
          <Camera className="h-5 w-5 text-violet-300" strokeWidth={1.75} />
        </span>
        <div className="min-w-0 flex-1 text-left">
          <div className="flex flex-wrap items-center gap-2">
            <h2 className="font-display text-2xl text-zinc-50">Photo Vision</h2>
            {status?.pro ? (
              <span className="rounded-full bg-amber-500/15 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-amber-200 ring-1 ring-amber-500/30">
                Unlimited
              </span>
            ) : remaining !== null ? (
              <span className="rounded-full bg-zinc-800 px-2 py-0.5 text-[10px] font-medium text-zinc-400 ring-1 ring-zinc-700">
                Free Peek · shared with Ask · {remaining} left today
              </span>
            ) : null}
          </div>
          <p className="mt-1 text-sm leading-relaxed text-zinc-400">
            Drop or capture a scene photo — Grok vision picks the best catalog
            recipe and coaches you on why.
          </p>
        </div>
      </div>

      <form onSubmit={(e) => void submit(e)} className="space-y-3">
        <input
          ref={fileRef}
          id={fileInputId}
          type="file"
          accept="image/jpeg,image/png,image/webp"
          className="sr-only"
          disabled={busy}
          onChange={(e) => onFileChange(e.target.files)}
        />
        <input
          ref={cameraRef}
          id={cameraInputId}
          type="file"
          accept="image/*"
          capture="environment"
          className="sr-only"
          disabled={busy}
          onChange={(e) => onFileChange(e.target.files)}
        />

        {!previewUrl ? (
          <div
            onDragOver={(e) => {
              e.preventDefault()
              setDragOver(true)
            }}
            onDragLeave={() => setDragOver(false)}
            onDrop={onDrop}
            className={`flex flex-col items-center justify-center rounded-xl border border-dashed px-4 py-10 transition ${
              dragOver
                ? 'border-violet-400/60 bg-violet-500/10'
                : 'border-zinc-700/80 bg-zinc-950/50'
            }`}
          >
            <ImagePlus className="mb-3 h-8 w-8 text-violet-300/80" strokeWidth={1.5} />
            <p className="text-sm text-zinc-300">Drag & drop a photo here</p>
            <p className="mt-1 text-xs text-zinc-500">
              JPEG, PNG, or WebP · compressed to ~1280px before upload
            </p>
            <div className="mt-4 flex flex-wrap items-center justify-center gap-2">
              <label
                htmlFor={fileInputId}
                className={`cursor-pointer rounded-full bg-zinc-900 px-3 py-1.5 text-xs font-medium text-zinc-200 ring-1 ring-zinc-700 transition hover:bg-zinc-800 ${
                  busy ? 'pointer-events-none opacity-50' : ''
                }`}
              >
                Choose file
              </label>
              <label
                htmlFor={cameraInputId}
                className={`cursor-pointer rounded-full bg-violet-500/20 px-3 py-1.5 text-xs font-medium text-violet-200 ring-1 ring-violet-500/35 transition hover:bg-violet-500/30 sm:hidden ${
                  busy ? 'pointer-events-none opacity-50' : ''
                }`}
              >
                Take photo
              </label>
            </div>
            {preparing ? (
              <p className="mt-3 inline-flex items-center gap-2 text-xs text-zinc-400">
                <Loader2 className="h-3.5 w-3.5 animate-spin" />
                Preparing image…
              </p>
            ) : null}
          </div>
        ) : (
          <div className="relative overflow-hidden rounded-xl border border-zinc-700/80 bg-zinc-950/70">
            <img
              src={previewUrl}
              alt="Scene preview"
              className="max-h-64 w-full object-contain"
            />
            <button
              type="button"
              onClick={clearImage}
              disabled={busy}
              className="absolute right-2 top-2 inline-flex h-8 w-8 items-center justify-center rounded-full bg-zinc-950/80 text-zinc-300 ring-1 ring-zinc-700 backdrop-blur hover:bg-zinc-900 disabled:opacity-50"
              aria-label="Remove photo"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        )}

        <label htmlFor="photo-vision-note" className="sr-only">
          Optional note
        </label>
        <textarea
          id="photo-vision-note"
          rows={2}
          value={note}
          onChange={(e) => setNote(e.target.value)}
          disabled={busy}
          placeholder='Optional note — e.g. "want silky water" or "keep the kid sharp"'
          className="w-full resize-none rounded-xl border border-zinc-700/80 bg-zinc-950/70 px-4 py-3 text-sm text-zinc-100 placeholder:text-zinc-600 outline-none ring-violet-500/40 transition focus:border-violet-500/50 focus:ring-2 disabled:opacity-60"
        />

        <button
          type="submit"
          disabled={busy || !dataUrl}
          className="inline-flex w-full items-center justify-center gap-2 rounded-xl bg-violet-500 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-violet-400 disabled:cursor-not-allowed disabled:opacity-50 sm:w-auto"
        >
          {loading ? (
            <>
              <Loader2 className="h-4 w-4 animate-spin" />
              Grok is looking…
            </>
          ) : preparing ? (
            <>
              <Loader2 className="h-4 w-4 animate-spin" />
              Preparing…
            </>
          ) : (
            <>
              <Sparkles className="h-4 w-4" />
              Recommend from photo
            </>
          )}
        </button>
      </form>

      {error ? (
        <div
          role="alert"
          className={`mt-4 rounded-xl border px-3 py-2.5 text-sm ${
            paywalled
              ? 'border-violet-500/35 bg-violet-500/10 text-violet-100'
              : 'border-amber-500/30 bg-amber-500/10 text-amber-200'
          }`}
        >
          <p>{error}</p>
          {paywalled ? (
            <button
              type="button"
              onClick={openPricing}
              className="mt-3 inline-flex rounded-lg bg-violet-500 px-3 py-1.5 text-xs font-semibold text-white hover:bg-violet-400"
            >
              Upgrade to Pro — 7-day free trial
            </button>
          ) : null}
        </div>
      ) : null}
    </section>
  )
}
