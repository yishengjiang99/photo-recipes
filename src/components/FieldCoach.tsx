import {
  Camera,
  ImagePlus,
  Loader2,
  MessageSquareText,
  Mic,
  Square,
  Sparkles,
  X,
} from 'lucide-react'
import {
  useCallback,
  useEffect,
  useId,
  useRef,
  useState,
  type FormEvent,
} from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { useFavorites } from '../hooks/useFavorites'
import { useVoiceInput, type VoiceInputApi } from '../hooks/useVoiceInput'
import { useSubscription } from '../hooks/useSubscription'
import { compressImageForUpload } from '../lib/compressImage'
import { track } from '../lib/analytics'

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

type FieldCoachProps = {
  /** Start live viewfinder once on mount (camera page default). */
  autoStartCamera?: boolean
}

export function FieldCoach({ autoStartCamera = false }: FieldCoachProps = {}) {
  const [searchParams, setSearchParams] = useSearchParams()
  const cameraQuery = searchParams.get('camera') === '1'
  const [mode, setMode] = useState<CoachMode>('photo')
  const autoStartDoneRef = useRef(false)
  const [message, setMessage] = useState('')
  const [note, setNote] = useState('')
  const [previewUrl, setPreviewUrl] = useState<string | null>(null)
  const [dataUrl, setDataUrl] = useState<string | null>(null)
  const [preparing, setPreparing] = useState(false)
  const [loading, setLoading] = useState(false)
  const [streamStatus, setStreamStatus] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [paywalled, setPaywalled] = useState(false)
  const [captioning, setCaptioning] = useState(false)
  const [cameraActive, setCameraActive] = useState(false)
  const [cameraStarting, setCameraStarting] = useState(false)
  const [cameraError, setCameraError] = useState<string | null>(null)
  const [describeOpen, setDescribeOpen] = useState(false)

  const fileInputId = useId()
  const fileRef = useRef<HTMLInputElement>(null)
  const videoRef = useRef<HTMLVideoElement>(null)
  const streamRef = useRef<MediaStream | null>(null)
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

  const stopCamera = useCallback(() => {
    const stream = streamRef.current
    if (stream) {
      for (const track of stream.getTracks()) {
        track.stop()
      }
      streamRef.current = null
    }
    const video = videoRef.current
    if (video) {
      video.srcObject = null
    }
    setCameraActive(false)
    setCameraStarting(false)
  }, [])

  const startCamera = useCallback(async () => {
    if (cameraStarting || cameraActive) return
    setCameraError(null)
    setError(null)
    setCameraStarting(true)
    try {
      if (!navigator.mediaDevices?.getUserMedia) {
        throw new Error(
          'Live camera is not supported in this browser. Use upload instead.',
        )
      }
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: { ideal: 'environment' } },
        audio: false,
      })
      streamRef.current = stream
      const video = videoRef.current
      if (video) {
        video.srcObject = stream
        await video.play().catch(() => {})
      }
      setCameraActive(true)
      track('camera_permission_granted', { source: 'field_coach' })
      track('camera_start_ok', { source: 'field_coach' })
    } catch (err) {
      stopCamera()
      const name = err instanceof DOMException ? err.name : ''
      if (name === 'NotAllowedError' || name === 'PermissionDeniedError') {
        track('camera_permission_denied', { source: 'field_coach', error_code: name })
        track('camera_start_fail', { source: 'field_coach', error_code: name })
        setCameraError(
          'Camera permission denied. Allow camera access, or upload a photo.',
        )
      } else if (name === 'NotFoundError' || name === 'DevicesNotFoundError') {
        track('camera_start_fail', { source: 'field_coach', error_code: name })
        setCameraError('No camera found. Upload a photo instead.')
      } else {
        track('camera_start_fail', {
          source: 'field_coach',
          error_code: name || 'unknown',
        })
        setCameraError(
          err instanceof Error
            ? err.message
            : 'Could not start camera. Upload a photo instead.',
        )
      }
    } finally {
      setCameraStarting(false)
    }
  }, [cameraActive, cameraStarting, stopCamera])

  useEffect(() => {
    if (describeVoice.listening) noteStopRef.current()
  }, [describeVoice.listening])

  useEffect(() => {
    if (noteVoice.listening) describeStopRef.current()
  }, [noteVoice.listening])

  useEffect(() => {
    if (mode === 'photo') describeStopRef.current()
    if (mode === 'describe') {
      noteStopRef.current()
      stopCamera()
    }
  }, [mode, stopCamera])

  useEffect(() => {
    const want = autoStartCamera || cameraQuery
    if (!want || autoStartDoneRef.current) return
    autoStartDoneRef.current = true
    setMode('photo')
    setDescribeOpen(false)
    void startCamera()
    if (cameraQuery) {
      const next = new URLSearchParams(searchParams)
      next.delete('camera')
      setSearchParams(next, { replace: true })
    }
  }, [autoStartCamera, cameraQuery, searchParams, setSearchParams, startCamera])

  useEffect(() => {
    if (!cameraActive) return
    const video = videoRef.current
    const stream = streamRef.current
    if (!video || !stream) return
    if (video.srcObject !== stream) {
      video.srcObject = stream
    }
    void video.play().catch(() => {})
  }, [cameraActive])

  useEffect(() => {
    noteRef.current = note
  }, [note])

  useEffect(() => {
    return () => {
      stopCamera()
    }
  }, [stopCamera])

  const clearImage = useCallback(() => {
    describeAbortRef.current?.abort()
    describeAbortRef.current = null
    setCaptioning(false)
    setPreviewUrl(null)
    setDataUrl(null)
    if (fileRef.current) fileRef.current.value = ''
  }, [])

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
        if (noteRef.current.trim()) return
        setNote(caption)
      } catch (err) {
        if (err instanceof DOMException && err.name === 'AbortError') return
      } finally {
        if (describeAbortRef.current === ac) {
          describeAbortRef.current = null
          setCaptioning(false)
        }
      }
    })()
  }

  async function ingestFile(file: File): Promise<string | null> {
    setError(null)
    setPaywalled(false)
    setPreparing(true)
    describeAbortRef.current?.abort()
    setCaptioning(false)
    setMode('photo')
    setDescribeOpen(false)
    try {
      const compressed = await compressImageForUpload(file)
      setDataUrl(compressed.dataUrl)
      setPreviewUrl(compressed.dataUrl)
      prefillNoteFromScene(compressed.dataUrl)
      return compressed.dataUrl
    } catch (err) {
      clearImage()
      setError(err instanceof Error ? err.message : 'Could not prepare image')
      return null
    } finally {
      setPreparing(false)
    }
  }

  function onFileChange(files: FileList | null) {
    const file = files?.[0]
    if (file) void ingestFile(file)
  }

  const captureFrame = useCallback(async (): Promise<string | null> => {
    const video = videoRef.current
    if (!video || !cameraActive || busy) return null
    if (!video.videoWidth || !video.videoHeight) {
      setCameraError('Camera is still warming up — try again in a moment.')
      return null
    }
    setCameraError(null)
    setError(null)
    try {
      const canvas = document.createElement('canvas')
      canvas.width = video.videoWidth
      canvas.height = video.videoHeight
      const ctx = canvas.getContext('2d')
      if (!ctx) throw new Error('Canvas not available')
      ctx.drawImage(video, 0, 0)
      const blob = await new Promise<Blob | null>((resolve) =>
        canvas.toBlob(resolve, 'image/jpeg', 0.92),
      )
      if (!blob) throw new Error('Could not capture frame')
      const file = new File([blob], 'viewfinder.jpg', { type: 'image/jpeg' })
      const image = await ingestFile(file)
      if (image) track('capture_success', { source: 'field_coach' })
      return image
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not capture frame')
      return null
    }
  }, [busy, cameraActive])

  function onRetake() {
    if (busy) return
    clearImage()
    setDescribeOpen(false)
    setMode('photo')
    if (!cameraActive) void startCamera()
  }

  /** One gesture: capture live frame then recommend (or start camera if not live). */
  async function autoOptimizeFromViewfinder() {
    if (busy || cameraStarting) return
    track('shutter_tap', { source: 'field_coach' })
    setDescribeOpen(false)
    setMode('photo')
    if (!cameraActive) {
      void startCamera()
      return
    }
    const image = await captureFrame()
    if (!image) return
    await recommend({ text: noteRef.current, image })
  }

  async function recommend(opts: { text?: string; image?: string }) {
    if (loading) return
    const trimmed = opts.text?.trim()

    setLoading(true)
    setStreamStatus('Starting…')
    setError(null)
    setPaywalled(false)
    track('auto_optimize_start', {
      source: 'field_coach',
      has_image: Boolean(opts.image),
      stream: true,
    })

    const body = {
      message: trimmed || undefined,
      image: opts.image,
      favorites: favorites.length ? favorites : undefined,
    }

    const finishWithResult = (data: {
      presetId?: string
      reason?: string
      tips?: string[]
    }) => {
      if (!data.presetId) {
        track('auto_optimize_fail', { source: 'field_coach', error_code: 'no_preset' })
        throw new Error('No preset returned from Grok')
      }
      const state: AiRecommendState = {
        reason:
          data.reason ||
          (opts.image
            ? 'Grok picked this recipe from your photo. On web this is coaching only — dials apply in the iOS app.'
            : 'Grok picked this recipe for your scene. On web this is coaching only — dials apply in the iOS app.'),
        tips: Array.isArray(data.tips) ? data.tips : [],
        fromAsk: true,
      }
      track('auto_optimize_success', {
        source: 'field_coach',
        recipe_id: data.presetId,
        stream: true,
      })
      void refresh()
      stopCamera()
      navigate(`/app/preset/${data.presetId}`, { state })
    }

    try {
      const res = await fetch('/api/recommend/stream', {
        method: 'POST',
        credentials: 'include',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'text/event-stream',
        },
        body: JSON.stringify(body),
      })

      if (res.status === 402) {
        const data = (await res.json().catch(() => ({}))) as {
          error?: string
          code?: string
        }
        setPaywalled(true)
        setError(
          data.error ||
            'Free Peek limit reached. Upgrade for unlimited Ask Grok & Photo Vision.',
        )
        track('auto_optimize_fail', { source: 'field_coach', error_code: 'paywall' })
        track('paywall_view', { source: 'auto_optimize_limit' })
        openPricing()
        void refresh()
        return
      }

      // Non-SSE fallback (proxy/old server)
      const ct = res.headers.get('content-type') || ''
      if (!res.ok || !ct.includes('text/event-stream') || !res.body) {
        if (!res.ok) {
          const data = (await res.json().catch(() => ({}))) as { error?: string }
          track('auto_optimize_fail', {
            source: 'field_coach',
            error_code: String(res.status),
          })
          throw new Error(data.error || `Request failed (${res.status})`)
        }
        // ok but not stream — try JSON
        const data = (await res.json().catch(() => ({}))) as {
          presetId?: string
          reason?: string
          tips?: string[]
          error?: string
        }
        if (data.error) throw new Error(data.error)
        finishWithResult(data)
        return
      }

      const reader = res.body.getReader()
      const decoder = new TextDecoder()
      let buf = ''
      let sawResult = false

      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        buf += decoder.decode(value, { stream: true })
        const parts = buf.split('\n\n')
        buf = parts.pop() ?? ''
        for (const part of parts) {
          const lines = part.split('\n')
          let event = 'message'
          const dataLines: string[] = []
          for (const line of lines) {
            if (line.startsWith('event:')) event = line.slice(6).trim()
            else if (line.startsWith('data:')) dataLines.push(line.slice(5).trim())
          }
          if (!dataLines.length) continue
          let payload: Record<string, unknown> = {}
          try {
            payload = JSON.parse(dataLines.join('\n')) as Record<string, unknown>
          } catch {
            continue
          }
          if (event === 'status' && typeof payload.message === 'string') {
            setStreamStatus(payload.message)
          } else if (event === 'phase' && typeof payload.phase === 'string') {
            if (payload.phase === 'thinking') setStreamStatus('Grok is thinking…')
            if (payload.phase === 'writing') setStreamStatus('Writing tips…')
            if (payload.phase === 'sensing') setStreamStatus('Reading the scene…')
          } else if (event === 'result') {
            sawResult = true
            finishWithResult(payload as { presetId?: string; reason?: string; tips?: string[] })
          } else if (event === 'error') {
            const err =
              typeof payload.error === 'string'
                ? payload.error
                : 'Recommend failed'
            throw new Error(err)
          }
        }
      }

      if (!sawResult) {
        throw new Error('Stream ended without a recipe')
      }
    } catch (err) {
      track('auto_optimize_fail', {
        source: 'field_coach',
        error_code: 'exception',
      })
      setError(err instanceof Error ? err.message : 'Something went wrong')
    } finally {
      setLoading(false)
      setStreamStatus(null)
    }
  }

  function onDescribeSubmit(e: FormEvent) {
    e.preventDefault()
    void recommend({ text: message })
  }

  function onPhotoRecommend() {
    if (!dataUrl || preparing) return
    void recommend({ text: note, image: dataUrl })
  }

  const voiceError =
    (describeOpen || mode === 'describe' ? describeVoice.error : noteVoice.error) ||
    null

  const quotaLabel =
    status && status.asksLimit === null
      ? 'Unlimited'
      : remaining !== null
        ? `${remaining} left today`
        : null

  return (
    <section
      className="relative flex min-h-[calc(100dvh-5.75rem-env(safe-area-inset-bottom))] flex-1 flex-col overflow-hidden bg-black"
      aria-label="Field Coach camera"
    >
      <input
        ref={fileRef}
        id={fileInputId}
        type="file"
        accept="image/jpeg,image/png,image/webp"
        className="sr-only"
        disabled={busy}
        onChange={(e) => onFileChange(e.target.files)}
      />

      {/* Full-bleed viewfinder / preview */}
      <div className="relative min-h-0 flex-1 bg-black">
        <video
          ref={videoRef}
          playsInline
          muted
          autoPlay
          className={`absolute inset-0 h-full w-full object-cover ${
            cameraActive && !previewUrl ? '' : 'hidden'
          }`}
          aria-label="Live camera preview"
        />

        {previewUrl ? (
          <img
            src={previewUrl}
            alt="Captured scene"
            className="absolute inset-0 h-full w-full object-contain bg-black"
          />
        ) : null}

        {!cameraActive && !previewUrl ? (
          <div className="absolute inset-0 flex flex-col items-center justify-center px-6 text-center">
            <Camera className="mb-3 h-10 w-10 text-white/40" strokeWidth={1.5} />
            <p className="text-sm text-white/70">
              {cameraStarting ? 'Starting camera…' : 'Open the viewfinder, then Auto Optimize'}
            </p>
            <p className="mt-1 max-w-xs text-xs text-white/40">
              Recommends dials — does not write them in the browser
            </p>
            {cameraStarting ? (
              <Loader2 className="mt-4 h-6 w-6 animate-spin text-white/60" />
            ) : (
              <button
                type="button"
                disabled={busy}
                onClick={() => void startCamera()}
                className="mt-5 inline-flex min-h-11 items-center gap-2 rounded-full bg-accent px-5 py-2.5 text-sm font-semibold text-white hover:bg-accent-soft disabled:opacity-50"
              >
                <Camera className="h-4 w-4" />
                Open Camera
              </button>
            )}
          </div>
        ) : null}

        {/* Top chrome — minimal honesty + quota */}
        <div className="pointer-events-none absolute inset-x-0 top-0 z-10 flex items-start justify-between gap-2 bg-gradient-to-b from-black/70 to-transparent px-3 pb-10 pt-[max(0.75rem,env(safe-area-inset-top))]">
          <span className="pointer-events-auto rounded-full bg-black/50 px-2.5 py-1 text-[10px] font-semibold uppercase tracking-wide text-white/80 ring-1 ring-white/15 backdrop-blur">
            Coach · tips only on web
          </span>
          {quotaLabel ? (
            <span className="pointer-events-auto rounded-full bg-black/50 px-2.5 py-1 text-[10px] font-medium text-white/70 ring-1 ring-white/15 backdrop-blur">
              {quotaLabel}
            </span>
          ) : null}
        </div>

        {/* Captured frame actions */}
        {previewUrl ? (
          <div className="absolute inset-x-0 bottom-0 z-10 bg-gradient-to-t from-black/90 via-black/60 to-transparent px-4 pb-4 pt-16">
            <div className="relative mb-3">
              <input
                type="text"
                value={note}
                onChange={(e) => setNote(e.target.value)}
                disabled={busy}
                placeholder='Optional note — e.g. "want silky water"'
                className="w-full rounded-full border border-white/15 bg-black/50 py-2.5 pl-4 pr-14 text-sm text-white placeholder:text-white/40 outline-none backdrop-blur focus:border-white/30 disabled:opacity-60"
                aria-label="Optional note"
              />
              <VoiceMicButton
                voice={noteVoice}
                disabled={busy}
                labelIdle="Dictate note"
                light
              />
            </div>
            {captioning ? (
              <p className="mb-2 text-center text-xs text-white/50" aria-live="polite">
                Captioning scene…
              </p>
            ) : null}
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={onRetake}
                disabled={busy}
                className="inline-flex min-h-11 items-center justify-center gap-1.5 rounded-full bg-white/10 px-4 text-sm font-medium text-white ring-1 ring-white/20 hover:bg-white/15 disabled:opacity-50"
                aria-label="Retake"
              >
                <Camera className="h-4 w-4" strokeWidth={1.75} />
                Retake
              </button>
              <button
                type="button"
                onClick={onPhotoRecommend}
                disabled={busy || !dataUrl}
                className="inline-flex min-h-11 flex-1 items-center justify-center gap-2 rounded-full bg-accent px-4 text-sm font-semibold text-white hover:bg-accent-soft disabled:opacity-50"
              >
                {loading ? (
                  <>
                    <Loader2 className="h-4 w-4 animate-spin" />
                    Matching…
                  </>
                ) : preparing ? (
                  <>
                    <Loader2 className="h-4 w-4 animate-spin" />
                    Preparing…
                  </>
                ) : (
                  <>
                    <Sparkles className="h-4 w-4" />
                    Auto Optimize
                  </>
                )}
              </button>
            </div>
          </div>
        ) : null}

        {/* Overlay controls when live / idle (no preview) */}
        {!previewUrl ? (
          <div className="absolute inset-x-0 bottom-0 z-10 bg-gradient-to-t from-black/80 to-transparent px-6 pb-5 pt-14">
            <div className="flex items-end justify-center gap-6 sm:gap-8">
              <button
                type="button"
                disabled={busy}
                onClick={() => fileRef.current?.click()}
                className="flex min-h-11 min-w-11 flex-col items-center justify-center gap-1 text-white/55 transition hover:text-white/85 disabled:opacity-50"
                aria-label="Upload photo"
              >
                <span className="flex h-11 w-11 items-center justify-center rounded-full bg-white/10 ring-1 ring-white/15">
                  <ImagePlus className="h-5 w-5" strokeWidth={1.75} />
                </span>
                <span className="text-[10px] font-medium">Upload</span>
              </button>

              <button
                type="button"
                disabled={busy || cameraStarting}
                onClick={() => void autoOptimizeFromViewfinder()}
                aria-label={
                  cameraStarting
                    ? 'Starting camera'
                    : cameraActive
                      ? 'Auto Optimize'
                      : 'Open Camera'
                }
                className="inline-flex min-h-[4.5rem] min-w-[9.5rem] flex-col items-center justify-center gap-1 rounded-full bg-accent px-5 py-3 text-white shadow-[0_12px_32px_-12px_rgba(244,63,94,0.75)] transition active:scale-[0.98] hover:bg-accent-soft disabled:opacity-50"
              >
                {cameraStarting || loading || preparing ? (
                  <Loader2 className="h-6 w-6 animate-spin" aria-hidden />
                ) : (
                  <Sparkles className="h-6 w-6" strokeWidth={2} aria-hidden />
                )}
                <span className="text-xs font-semibold tracking-wide">
                  {cameraStarting
                    ? 'Starting…'
                    : loading
                    // streamStatus shown below
                      ? 'Matching…'
                      : preparing
                        ? 'Capturing…'
                        : cameraActive
                          ? 'Auto Optimize'
                          : 'Open Camera'}
                </span>
              </button>

              <button
                type="button"
                disabled={busy}
                onClick={() => {
                  setDescribeOpen(true)
                  setMode('describe')
                }}
                className="flex min-h-11 min-w-11 flex-col items-center justify-center gap-1 text-white/55 transition hover:text-white/85 disabled:opacity-50"
                aria-label="Describe scene"
              >
                <span className="flex h-11 w-11 items-center justify-center rounded-full bg-white/10 ring-1 ring-white/15">
                  <MessageSquareText className="h-5 w-5" strokeWidth={1.75} />
                </span>
                <span className="text-[10px] font-medium">Describe</span>
              </button>
            </div>
            <p className="mt-3 text-center text-[10px] text-white/35">
              iOS writes dials · web recommends
            </p>
          </div>
        ) : null}
      </div>

      {/* Describe sheet — secondary, not equal peer */}
      {describeOpen ? (
        <div
          className="absolute inset-0 z-20 flex flex-col justify-end bg-black/60 backdrop-blur-sm"
          role="dialog"
          aria-modal="true"
          aria-label="Describe scene"
        >
          <button
            type="button"
            className="flex-1"
            aria-label="Close describe"
            onClick={() => {
              setDescribeOpen(false)
              setMode('photo')
              if (!cameraActive && !previewUrl) void startCamera()
            }}
          />
          <form
            onSubmit={onDescribeSubmit}
            className="rounded-t-2xl border-t border-white/10 bg-[#121212] px-4 pb-[max(1rem,env(safe-area-inset-bottom))] pt-3"
          >
            <div className="mb-3 flex items-center justify-between">
              <h2 className="text-sm font-semibold text-white">Describe scene</h2>
              <button
                type="button"
                onClick={() => {
                  setDescribeOpen(false)
                  setMode('photo')
                  if (!cameraActive && !previewUrl) void startCamera()
                }}
                className="inline-flex h-9 w-9 items-center justify-center rounded-full text-white/60 hover:bg-white/10 hover:text-white"
                aria-label="Close"
              >
                <X className="h-4 w-4" />
              </button>
            </div>
            <div className="mb-2 flex flex-wrap gap-1.5">
              {EXAMPLES.slice(0, 3).map((ex) => (
                <button
                  key={ex}
                  type="button"
                  disabled={busy}
                  onClick={() => {
                    setMessage(ex)
                    void recommend({ text: ex })
                  }}
                  className="rounded-full bg-white/8 px-2.5 py-1 text-[11px] text-white/60 ring-1 ring-white/10 hover:text-white disabled:opacity-50"
                >
                  {ex}
                </button>
              ))}
            </div>
            <div className="relative mb-3">
              <textarea
                rows={3}
                value={message}
                onChange={(e) => setMessage(e.target.value)}
                disabled={busy}
                placeholder='e.g. "sunset canyon with dark foreground"'
                className="min-h-[88px] w-full resize-none rounded-xl border border-white/15 bg-black/40 py-3 pl-4 pr-14 text-sm text-white placeholder:text-white/35 outline-none focus:border-white/30 disabled:opacity-60"
                aria-label="Scene description"
              />
              <VoiceMicButton
                voice={describeVoice}
                disabled={busy}
                labelIdle="Dictate scene"
                light
              />
            </div>
            <button
              type="submit"
              disabled={busy || !message.trim()}
              className="inline-flex min-h-11 w-full items-center justify-center gap-2 rounded-full bg-accent text-sm font-semibold text-white hover:bg-accent-soft disabled:opacity-50"
            >
              {loading ? (
                <>
                  <Loader2 className="h-4 w-4 animate-spin" />
                  Matching…
                </>
              ) : (
                <>
                  <Sparkles className="h-4 w-4" />
                  Auto Optimize
                </>
              )}
            </button>
          </form>
        </div>
      ) : null}

      {loading && streamStatus ? (
        <p
          className="absolute inset-x-3 top-14 z-30 px-1 text-center text-xs text-white/70"
          role="status"
          aria-live="polite"
        >
          {streamStatus}
        </p>
      ) : null}

      {(cameraError || error || voiceError) && !describeOpen ? (
        <div
          role={error ? 'alert' : 'status'}
          className={`absolute inset-x-3 top-14 z-30 rounded-xl px-3 py-2.5 text-sm backdrop-blur ${
            paywalled
              ? 'border border-white/15 bg-black/80 text-white/80'
              : error
                ? 'border border-danger/40 bg-black/85 text-danger'
                : 'border border-white/15 bg-black/80 text-white/70'
          }`}
        >
          <p>{error || cameraError || voiceError}</p>
          {paywalled ? (
            <button
              type="button"
              onClick={openPricing}
              className="mt-2 inline-flex rounded-lg bg-accent px-3 py-1.5 text-xs font-semibold text-white hover:bg-accent-soft"
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
  light?: boolean
}

function VoiceMicButton({ voice, disabled, labelIdle, light }: VoiceMicButtonProps) {
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
      className={`absolute bottom-1.5 right-1.5 inline-flex h-11 w-11 items-center justify-center rounded-full transition focus:outline-none focus-visible:ring-2 focus-visible:ring-accent/40 ${
        listening
          ? 'bg-accent-muted text-accent ring-1 ring-accent/40 voice-mic-pulse'
          : unsupported || denied
            ? light
              ? 'bg-white/10 text-white/30 ring-1 ring-white/15 opacity-40'
              : 'bg-surface text-ink-tertiary ring-1 ring-border opacity-40'
            : light
              ? 'bg-white/10 text-white/70 ring-1 ring-white/20 hover:text-white'
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
