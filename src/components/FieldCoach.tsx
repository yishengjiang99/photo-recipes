import {
  Camera,
  ImagePlus,
  Loader2,
  Mic,
  Square,
  Sparkles,
  Wand2,
  X,
} from 'lucide-react'
import {
  useCallback,
  useEffect,
  useId,
  useRef,
  useState,
  type DragEvent,
  type FormEvent,
} from 'react'
import { useNavigate } from 'react-router-dom'
import { useFavorites } from '../hooks/useFavorites'
import { useVoiceInput, type VoiceInputApi } from '../hooks/useVoiceInput'
import { useSubscription } from '../hooks/useSubscription'
import { compressImageForUpload } from '../lib/compressImage'

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

type CoachMode = 'describe' | 'photo'

export function FieldCoach() {
  const [mode, setMode] = useState<CoachMode>('describe')
  const [message, setMessage] = useState('')
  const [note, setNote] = useState('')
  const [previewUrl, setPreviewUrl] = useState<string | null>(null)
  const [dataUrl, setDataUrl] = useState<string | null>(null)
  const [preparing, setPreparing] = useState(false)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [paywalled, setPaywalled] = useState(false)
  const [dragOver, setDragOver] = useState(false)
  const [captioning, setCaptioning] = useState(false)

  const fileInputId = useId()
  const cameraInputId = useId()
  const fileRef = useRef<HTMLInputElement>(null)
  const cameraRef = useRef<HTMLInputElement>(null)
  const describeAbortRef = useRef<AbortController | null>(null)
  const noteRef = useRef(note)

  const navigate = useNavigate()
  const { favorites } = useFavorites()
  const { status, refresh, openPricing } = useSubscription()

  const remaining = status?.pro ? null : (status?.asksRemaining ?? null)
  const busy = loading || preparing

  const describeVoice = useVoiceInput({
    value: message,
    onChange: setMessage,
    disabled: busy,
  })
  const noteVoice = useVoiceInput({
    value: note,
    onChange: setNote,
    disabled: busy,
  })

  const describeStopRef = useRef(describeVoice.stop)
  const noteStopRef = useRef(noteVoice.stop)
  describeStopRef.current = describeVoice.stop
  noteStopRef.current = noteVoice.stop

  // One session at a time
  useEffect(() => {
    if (describeVoice.listening) noteStopRef.current()
  }, [describeVoice.listening])

  useEffect(() => {
    if (noteVoice.listening) describeStopRef.current()
  }, [noteVoice.listening])

  useEffect(() => {
    if (mode === 'photo') describeStopRef.current()
    if (mode === 'describe') noteStopRef.current()
  }, [mode])

  useEffect(() => {
    noteRef.current = note
  }, [note])

  const voiceError =
    (mode === 'describe' ? describeVoice.error : noteVoice.error) || null


  const clearImage = useCallback(() => {
    describeAbortRef.current?.abort()
    describeAbortRef.current = null
    setCaptioning(false)
    setPreviewUrl(null)
    setDataUrl(null)
    if (fileRef.current) fileRef.current.value = ''
    if (cameraRef.current) cameraRef.current.value = ''
  }, [])

  /** Non-blocking caption prefill for optional note — failures stay quiet. */
  function prefillNoteFromScene(imageDataUrl: string) {
    describeAbortRef.current?.abort()
    const ac = new AbortController()
    describeAbortRef.current = ac
    setCaptioning(true)

    void (async () => {
      try {
        const res = await fetch('/api/describe-scene', {
          method: 'POST',
          credentials: 'include',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ image: imageDataUrl }),
          signal: ac.signal,
        })
        if (!res.ok) return
        const data = (await res.json().catch(() => ({}))) as {
          description?: string
          text?: string
        }
        const caption =
          (typeof data.description === 'string' && data.description.trim()) ||
          (typeof data.text === 'string' && data.text.trim()) ||
          ''
        if (!caption || ac.signal.aborted) return
        // Only fill empty note — never clobber typed/dictated text
        if (noteRef.current.trim()) return
        setNote(caption)
      } catch (err) {
        if (err instanceof DOMException && err.name === 'AbortError') return
        // Silent / calm — typing and Recommend from photo still work
      } finally {
        if (describeAbortRef.current === ac) {
          describeAbortRef.current = null
          setCaptioning(false)
        }
      }
    })()
  }

  async function ingestFile(file: File) {
    setError(null)
    setPaywalled(false)
    setPreparing(true)
    describeAbortRef.current?.abort()
    setCaptioning(false)
    try {
      const compressed = await compressImageForUpload(file)
      setDataUrl(compressed.dataUrl)
      setPreviewUrl(compressed.dataUrl)
      // Prefill optional note from a short vision caption (does not block recommend)
      prefillNoteFromScene(compressed.dataUrl)
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

  async function recommend(opts: { text?: string; image?: string }) {
    if (loading) return
    const trimmed = opts.text?.trim()

    setLoading(true)
    setError(null)
    setPaywalled(false)

    try {
      const res = await fetch('/api/recommend', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: trimmed || undefined,
          image: opts.image,
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
        reason:
          data.reason ||
          (opts.image
            ? 'Grok recommended this recipe from your photo.'
            : 'Grok recommended this recipe for your scene.'),
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

  function onDescribeSubmit(e: FormEvent) {
    e.preventDefault()
    void recommend({ text: message })
  }

  function onPhotoSubmit(e: FormEvent) {
    e.preventDefault()
    if (!dataUrl || preparing) return
    void recommend({ text: note, image: dataUrl })
  }

  const quotaBadge = status?.pro ? (
    <span className="rounded-full bg-success/15 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-success ring-1 ring-success/30">
      Unlimited
    </span>
  ) : remaining !== null ? (
    <span className="rounded-full bg-surface-2 px-2 py-0.5 text-[10px] font-medium text-ink-tertiary ring-1 ring-border">
      Free Peek · {remaining} left today
    </span>
  ) : null

  return (
    <section className="mb-6 overflow-hidden rounded-2xl border border-border bg-surface p-4 sm:p-5">
      <div className="mb-4 flex items-start gap-3">
        <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-surface-2 ring-1 ring-border">
          {mode === 'photo' ? (
            <Camera className="h-4 w-4 text-vision" strokeWidth={1.75} />
          ) : (
            <Wand2 className="h-4 w-4 text-ink-secondary" strokeWidth={1.75} />
          )}
        </span>
        <div className="min-w-0 flex-1 text-left">
          <div className="flex flex-wrap items-center gap-2">
            <h2 className="font-display text-xl text-ink sm:text-2xl">Field Coach</h2>
            {quotaBadge}
          </div>
        </div>
      </div>

      <div
        className="mb-4 grid grid-cols-2 gap-1 rounded-xl bg-surface-2 p-1 ring-1 ring-border"
        role="tablist"
        aria-label="Coach mode"
      >
        <button
          type="button"
          role="tab"
          aria-selected={mode === 'describe'}
          onClick={() => setMode('describe')}
          className={`inline-flex min-h-9 items-center justify-center gap-1.5 rounded-lg px-3 text-sm font-medium transition ${
            mode === 'describe'
              ? 'bg-surface text-ink shadow-sm ring-1 ring-border'
              : 'text-ink-secondary hover:text-ink'
          }`}
        >
          Describe scene
        </button>
        <button
          type="button"
          role="tab"
          aria-selected={mode === 'photo'}
          onClick={() => setMode('photo')}
          className={`inline-flex min-h-9 items-center justify-center gap-1.5 rounded-lg px-3 text-sm font-medium transition ${
            mode === 'photo'
              ? 'bg-surface text-ink shadow-sm ring-1 ring-border'
              : 'text-ink-secondary hover:text-ink'
          }`}
        >
          <span
            className={`h-1.5 w-1.5 rounded-full ${mode === 'photo' ? 'bg-vision' : 'bg-ink-tertiary/50'}`}
            aria-hidden
          />
          From photo
        </button>
      </div>

      {mode === 'describe' ? (
        <form onSubmit={onDescribeSubmit} className="space-y-3">
          <div className="flex flex-wrap gap-2">
            {EXAMPLES.map((ex) => (
              <button
                key={ex}
                type="button"
                disabled={busy}
                onClick={() => {
                  setMessage(ex)
                  void recommend({ text: ex })
                }}
                className="inline-flex min-h-9 items-center rounded-full border border-border bg-bg-elevated px-3 py-1.5 text-xs text-ink-secondary transition hover:border-border-strong hover:text-ink disabled:opacity-50"
              >
                {ex}
              </button>
            ))}
          </div>

          <label htmlFor="field-coach-scene" className="sr-only">
            Scene description
          </label>
          <div className="relative">
            <textarea
              id="field-coach-scene"
              rows={3}
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              disabled={busy}
              placeholder='e.g. "sunset canyon with dark foreground"'
              className="min-h-[88px] w-full resize-none rounded-xl border border-border bg-bg-elevated py-3 pl-4 pr-14 text-sm text-ink placeholder:text-ink-tertiary outline-none transition focus:border-border-strong focus:ring-2 focus:ring-accent/30 disabled:opacity-60"
            />
            <VoiceMicButton
              voice={describeVoice}
              disabled={busy}
              labelIdle="Dictate scene"
            />
          </div>
          {describeVoice.listening || describeVoice.transcribing ? (
            <p className="text-xs text-ink-secondary" aria-live="polite">
              {describeVoice.transcribing ? 'Transcribing…' : 'Listening…'}
            </p>
          ) : describeVoice.status === 'unsupported' ? (
            <p className="text-xs text-ink-tertiary">
              Voice input not supported in this browser
            </p>
          ) : null}

          <button
            type="submit"
            disabled={busy || !message.trim()}
            className="inline-flex w-full items-center justify-center gap-2 rounded-xl bg-accent px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-accent-soft disabled:cursor-not-allowed disabled:opacity-50 sm:w-auto"
          >
            {loading ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin" />
                Matching a recipe…
              </>
            ) : (
              <>
                <Sparkles className="h-4 w-4" />
                Recommend a recipe
              </>
            )}
          </button>
        </form>
      ) : (
        <form onSubmit={onPhotoSubmit} className="space-y-3">
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
              className={`flex flex-col items-center justify-center rounded-xl border border-dashed px-4 py-8 transition ${
                dragOver
                  ? 'border-vision/60 bg-vision/10'
                  : 'border-border-strong bg-bg-elevated'
              }`}
            >
              <ImagePlus
                className="mb-2 h-7 w-7 text-ink-tertiary"
                strokeWidth={1.5}
              />
              <p className="text-sm text-ink-secondary">Drag & drop a photo here</p>
              <p className="mt-1 text-xs text-ink-tertiary">
                JPEG, PNG, or WebP · compressed before upload
              </p>
              <div className="mt-3 flex flex-wrap items-center justify-center gap-2">
                <label
                  htmlFor={fileInputId}
                  className={`cursor-pointer rounded-full border border-border bg-surface px-3 py-1.5 text-xs font-medium text-ink-secondary transition hover:border-border-strong hover:text-ink ${
                    busy ? 'pointer-events-none opacity-50' : ''
                  }`}
                >
                  Choose photo
                </label>
                <label
                  htmlFor={cameraInputId}
                  className={`cursor-pointer rounded-full bg-vision/15 px-3 py-1.5 text-xs font-medium text-vision ring-1 ring-vision/30 transition hover:bg-vision/25 sm:hidden ${
                    busy ? 'pointer-events-none opacity-50' : ''
                  }`}
                >
                  Take photo
                </label>
              </div>
              {preparing ? (
                <p className="mt-3 inline-flex items-center gap-2 text-xs text-ink-tertiary">
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  Preparing image…
                </p>
              ) : null}
            </div>
          ) : (
            <div className="relative overflow-hidden rounded-xl border border-border bg-bg-elevated">
              <img
                src={previewUrl}
                alt="Scene preview"
                className="max-h-52 w-full object-contain"
              />
              <button
                type="button"
                onClick={clearImage}
                disabled={busy}
                className="absolute right-2 top-2 inline-flex h-8 w-8 items-center justify-center rounded-full bg-bg/80 text-ink-secondary ring-1 ring-border backdrop-blur hover:bg-surface disabled:opacity-50"
                aria-label="Remove photo"
              >
                <X className="h-4 w-4" />
              </button>
            </div>
          )}

          <label htmlFor="field-coach-note" className="sr-only">
            Optional note
          </label>
          <div className="relative">
            <input
              id="field-coach-note"
              type="text"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              disabled={busy}
              placeholder='Optional note — e.g. "want silky water"'
              className="w-full rounded-xl border border-border bg-bg-elevated py-2.5 pl-4 pr-14 text-sm text-ink placeholder:text-ink-tertiary outline-none transition focus:border-border-strong focus:ring-2 focus:ring-accent/30 disabled:opacity-60"
            />
            <VoiceMicButton
              voice={noteVoice}
              disabled={busy}
              labelIdle="Dictate note"
            />
          </div>
          {noteVoice.listening || noteVoice.transcribing ? (
            <p className="text-xs text-ink-secondary" aria-live="polite">
              {noteVoice.transcribing ? 'Transcribing…' : 'Listening…'}
            </p>
          ) : captioning ? (
            <p className="text-xs text-ink-tertiary" aria-live="polite">
              Captioning scene…
            </p>
          ) : null}

          <button
            type="submit"
            disabled={busy || !dataUrl}
            className="inline-flex w-full items-center justify-center gap-2 rounded-xl bg-accent px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-accent-soft disabled:cursor-not-allowed disabled:opacity-50 sm:w-auto"
          >
            {loading ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin" />
                Matching a recipe…
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
      )}

      {voiceError && !error ? (
        <p role="status" className="mt-3 text-sm text-ink-secondary">
          {voiceError}
        </p>
      ) : null}

      {error ? (
        <div
          role="alert"
          className={`mt-4 rounded-xl border px-3 py-2.5 text-sm ${
            paywalled
              ? 'border-border bg-surface-2 text-ink-secondary'
              : 'border-danger/30 bg-danger/10 text-danger'
          }`}
        >
          <p>{error}</p>
          {paywalled ? (
            <button
              type="button"
              onClick={openPricing}
              className="mt-3 inline-flex rounded-lg bg-accent px-3 py-1.5 text-xs font-semibold text-white hover:bg-accent-soft"
            >
              Upgrade to Pro — 7-day free trial
            </button>
          ) : null}
        </div>
      ) : null}
    </section>
  )
}


type VoiceMicButtonProps = {
  voice: VoiceInputApi
  disabled?: boolean
  labelIdle: string
}

function VoiceMicButton({ voice, disabled, labelIdle }: VoiceMicButtonProps) {
  const unsupported = voice.status === 'unsupported'
  const denied = voice.status === 'denied'
  const listening = voice.listening
  const transcribing = voice.transcribing
  const inactive = disabled || unsupported || denied || transcribing

  return (
    <button
      type="button"
      disabled={inactive && !denied}
      onClick={() => {
        if (denied || unsupported) return
        voice.toggle()
      }}
      title={
        unsupported
          ? 'Voice input not supported in this browser'
          : denied
            ? 'Microphone is off — type instead'
            : listening
              ? 'Stop'
              : transcribing
                ? 'Transcribing…'
                : labelIdle
      }
      aria-label={
        listening ? 'Stop dictation' : transcribing ? 'Transcribing' : labelIdle
      }
      aria-pressed={listening}
      className={`absolute bottom-2 right-2 inline-flex h-11 w-11 items-center justify-center rounded-full transition focus:outline-none focus-visible:ring-2 focus-visible:ring-accent/40 ${
        listening
          ? 'bg-accent-muted text-accent ring-1 ring-accent/40 voice-mic-pulse'
          : unsupported || denied
            ? 'bg-surface text-ink-tertiary ring-1 ring-border opacity-40'
            : 'bg-surface text-ink-secondary ring-1 ring-border hover:text-ink hover:ring-border-strong'
      } ${transcribing ? 'opacity-60' : ''}`}
    >
      {transcribing ? (
        <Loader2 className="h-4 w-4 animate-spin" aria-hidden />
      ) : listening ? (
        <Square className="h-3.5 w-3.5 fill-current" aria-hidden />
      ) : (
        <Mic className="h-4 w-4" strokeWidth={1.75} aria-hidden />
      )}
    </button>
  )
}
