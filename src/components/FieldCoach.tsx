import {
  Camera,
  ImagePlus,
  Loader2,
  MessageSquareText,
  Mic,
  RotateCcw,
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
} from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { useFavorites } from '../hooks/useFavorites'
import { useVoiceInput, type VoiceInputApi } from '../hooks/useVoiceInput'
import { useSubscription } from '../hooks/useSubscription'
import { compressImageForUpload } from '../lib/compressImage'
import { track } from '../lib/analytics'
import { SHUTTER_EVENT } from './AppTabBar'

const EXAMPLES = [
  'Sunset canyon with a dark foreground',
  'Kid running through the woods',
  'Waterfall with silky motion blur',
  'Landscape sharp from rocks to skyline',
  'Fresh low-angle street scene',
]

const EMPTY_CTA_ERROR = 'Enable the camera or add a scene note'
const HONESTY_LINE = 'Recommends dials — does not write them in the browser'
const LOADING_LABEL = 'Matching a recipe…'

export type AiRecommendState = {
  reason: string
  tips: string[]
  fromAsk: true
}

type FieldCoachProps = {
  /** Start live viewfinder once on mount (camera page default). */
  autoStartCamera?: boolean
}

export function FieldCoach({ autoStartCamera = false }: FieldCoachProps = {}) {
  const [searchParams, setSearchParams] = useSearchParams()
  const cameraQuery = searchParams.get('camera') === '1'
  const autoStartDoneRef = useRef(false)
  const [message, setMessage] = useState('')
  const [previewUrl, setPreviewUrl] = useState<string | null>(null)
  const [dataUrl, setDataUrl] = useState<string | null>(null)
  const [preparing, setPreparing] = useState(false)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [inlineEmptyError, setInlineEmptyError] = useState<string | null>(null)
  const [paywalled, setPaywalled] = useState(false)
  const [cameraActive, setCameraActive] = useState(false)
  const [cameraStarting, setCameraStarting] = useState(false)
  const [cameraError, setCameraError] = useState<string | null>(null)
  const [describeOpen, setDescribeOpen] = useState(false)

  const fileInputId = useId()
  const fileRef = useRef<HTMLInputElement>(null)
  const videoRef = useRef<HTMLVideoElement>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const describeAbortRef = useRef<AbortController | null>(null)
  const oneshotLockRef = useRef(false)

  const navigate = useNavigate()
  const { favorites } = useFavorites()
  const { status, refresh, openPricing } = useSubscription()

  const remaining = status?.pro ? null : (status?.asksRemaining ?? null)
  const busy = loading || preparing || cameraStarting

  const describeVoice = useVoiceInput({
    value: message,
    onChange: setMessage,
    disabled: busy,
  })

  const describeStopRef = useRef(describeVoice.stop)
  describeStopRef.current = describeVoice.stop

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
    if (cameraStarting || streamRef.current) return
    setCameraError(null)
    setError(null)
    setInlineEmptyError(null)
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
  }, [cameraStarting, stopCamera])

  useEffect(() => {
    if (!describeOpen) describeStopRef.current()
  }, [describeOpen])

  useEffect(() => {
    const want = autoStartCamera || cameraQuery
    if (!want || autoStartDoneRef.current) return
    autoStartDoneRef.current = true
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
    return () => {
      stopCamera()
    }
  }, [stopCamera])

  const clearImage = useCallback(() => {
    describeAbortRef.current?.abort()
    describeAbortRef.current = null
    setPreviewUrl(null)
    setDataUrl(null)
    setInlineEmptyError(null)
    if (fileRef.current) fileRef.current.value = ''
  }, [])

  const retake = useCallback(() => {
    clearImage()
    if (!streamRef.current) void startCamera()
  }, [clearImage, startCamera])

  function waitForVideoReady(timeoutMs = 4500): Promise<boolean> {
    const start = Date.now()
    return new Promise((resolve) => {
      const tick = () => {
        const video = videoRef.current
        if (video && video.videoWidth > 0 && video.videoHeight > 0) {
          resolve(true)
          return
        }
        if (Date.now() - start >= timeoutMs) {
          resolve(false)
          return
        }
        requestAnimationFrame(tick)
      }
      tick()
    })
  }

  async function captureLiveFrame(): Promise<string | null> {
    const video = videoRef.current
    if (!video || !streamRef.current) return null
    if (!video.videoWidth || !video.videoHeight) {
      setCameraError('Camera is still warming up — try again in a moment.')
      return null
    }
    setCameraError(null)
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
    const compressed = await compressImageForUpload(file)
    return compressed.dataUrl
  }

  const recommend = useCallback(
    async (opts: { text?: string; image?: string; oneshot?: boolean }) => {
      if (loading) return
      const trimmed = opts.text?.trim()

      setLoading(true)
      setError(null)
      setPaywalled(false)
      setInlineEmptyError(null)
      track('auto_optimize_start', {
        source: 'field_coach',
        has_image: Boolean(opts.image),
        oneshot: Boolean(opts.oneshot),
      })

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
          track('auto_optimize_fail', { source: 'field_coach', error_code: 'paywall' })
          track('paywall_view', { source: 'auto_optimize_limit' })
          openPricing()
          void refresh()
          return
        }

        if (!res.ok) {
          track('auto_optimize_fail', {
            source: 'field_coach',
            error_code: String(res.status),
          })
          throw new Error(data.error || `Request failed (${res.status})`)
        }

        if (!data.presetId) {
          track('auto_optimize_fail', { source: 'field_coach', error_code: 'no_preset' })
          throw new Error('No preset returned from Grok')
        }

        const state: AiRecommendState = {
          reason:
            data.reason ||
            (opts.image
              ? 'Grok recommended this recipe from your photo (coach — not applied on web).'
              : 'Grok recommended this recipe for your scene (coach — not applied on web).'),
          tips: Array.isArray(data.tips) ? data.tips : [],
          fromAsk: true,
        }

        track('auto_optimize_success', {
          source: 'field_coach',
          recipe_id: data.presetId,
        })
        void refresh()
        stopCamera()
        navigate(`/app/preset/${data.presetId}`, { state })
      } catch (err) {
        track('auto_optimize_fail', {
          source: 'field_coach',
          error_code: 'exception',
        })
        setError(err instanceof Error ? err.message : 'Something went wrong')
      } finally {
        setLoading(false)
      }
    },
    [favorites, loading, navigate, openPricing, refresh, stopCamera],
  )

  const onRecommendPrimary = useCallback(async () => {
    if (busy || oneshotLockRef.current) return
    oneshotLockRef.current = true

    const hadHeldFrame = Boolean(dataUrl)
    track('recommend_cta_tap', {
      surface: 'web_camera',
      had_held_frame: hadHeldFrame,
    })
    track('shutter_tap', { source: 'field_coach', oneshot: true })

    setError(null)
    setInlineEmptyError(null)
    setPaywalled(false)

    const textPayload = message.trim() || undefined

    try {
      let image = dataUrl

      if (!image) {
        if (!streamRef.current) {
          await startCamera()
        }
        const ready = await waitForVideoReady(4500)
        if (!ready || !streamRef.current) {
          if (textPayload) {
            await recommend({ text: textPayload, oneshot: true })
            return
          }
          setInlineEmptyError(EMPTY_CTA_ERROR)
          return
        }

        setPreparing(true)
        try {
          const captured = await captureLiveFrame()
          if (!captured) {
            if (textPayload) {
              await recommend({ text: textPayload, oneshot: true })
              return
            }
            setInlineEmptyError(EMPTY_CTA_ERROR)
            return
          }
          image = captured
          setDataUrl(captured)
          setPreviewUrl(captured)
          track('capture_success', { source: 'field_coach', oneshot: true })
        } finally {
          setPreparing(false)
        }
      }

      await recommend({
        text: textPayload,
        image: image || undefined,
        oneshot: true,
      })
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not capture frame')
    } finally {
      oneshotLockRef.current = false
    }
  }, [busy, dataUrl, message, recommend, startCamera])

  async function ingestFile(file: File) {
    setError(null)
    setPaywalled(false)
    setInlineEmptyError(null)
    setPreparing(true)
    describeAbortRef.current?.abort()
    setDescribeOpen(false)
    try {
      const compressed = await compressImageForUpload(file)
      setDataUrl(compressed.dataUrl)
      setPreviewUrl(compressed.dataUrl)
      track('capture_success', { source: 'field_coach_upload' })
      track('recommend_cta_tap', {
        surface: 'web_camera',
        had_held_frame: true,
        source: 'upload_auto',
      })
      // Prefer auto-recommend after upload (confirmed web pattern).
      setPreparing(false)
      await recommend({ image: compressed.dataUrl, oneshot: true })
    } catch (err) {
      clearImage()
      setError(err instanceof Error ? err.message : 'Could not prepare image')
      setPreparing(false)
    }
  }

  function onFileChange(files: FileList | null) {
    const file = files?.[0]
    if (file) void ingestFile(file)
  }

  useEffect(() => {
    function onShutterEvent() {
      void onRecommendPrimary()
    }
    window.addEventListener(SHUTTER_EVENT, onShutterEvent)
    return () => window.removeEventListener(SHUTTER_EVENT, onShutterEvent)
  }, [onRecommendPrimary])

  const voiceError = describeOpen ? describeVoice.error : null

  const quotaLabel = status?.pro
    ? 'Unlimited'
    : remaining !== null
      ? `${remaining} left today`
      : null

  const heldFrame = Boolean(previewUrl)

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
              {cameraStarting
                ? 'Starting camera…'
                : 'Tap Recommend recipe to capture and match'}
            </p>
            <p className="mt-1 max-w-xs text-xs text-white/40">{HONESTY_LINE}</p>
            {cameraStarting ? (
              <Loader2 className="mt-4 h-6 w-6 animate-spin text-white/60" />
            ) : null}
          </div>
        ) : null}

        {/* Top chrome — honesty + quota */}
        <div className="pointer-events-none absolute inset-x-0 top-0 z-10 flex items-start justify-between gap-2 bg-gradient-to-b from-black/70 to-transparent px-3 pb-10 pt-[max(0.75rem,env(safe-area-inset-top))]">
          <span className="pointer-events-auto rounded-full bg-black/50 px-2.5 py-1 text-[10px] font-semibold uppercase tracking-wide text-white/80 ring-1 ring-white/15 backdrop-blur">
            Coach — not applied on web
          </span>
          {quotaLabel ? (
            <span className="pointer-events-auto rounded-full bg-black/50 px-2.5 py-1 text-[10px] font-medium text-white/70 ring-1 ring-white/15 backdrop-blur">
              {quotaLabel}
            </span>
          ) : null}
        </div>

        {/* Bottom chrome — primary Recommend always on; secondaries below */}
        <div className="absolute inset-x-0 bottom-0 z-10 bg-gradient-to-t from-black/90 via-black/65 to-transparent px-4 pb-4 pt-16">
          {describeOpen ? (
            <div className="mb-3">
              <div className="mb-2 flex flex-wrap gap-1.5">
                {EXAMPLES.slice(0, 3).map((ex) => (
                  <button
                    key={ex}
                    type="button"
                    disabled={busy}
                    onClick={() => setMessage(ex)}
                    className="rounded-full bg-white/8 px-2.5 py-1 text-[11px] text-white/60 ring-1 ring-white/10 hover:text-white disabled:opacity-50"
                  >
                    {ex}
                  </button>
                ))}
              </div>
              <div className="relative">
                <textarea
                  rows={3}
                  value={message}
                  onChange={(e) => {
                    setMessage(e.target.value)
                    setInlineEmptyError(null)
                  }}
                  disabled={busy}
                  placeholder='e.g. "sunset canyon with dark foreground"'
                  className="min-h-[88px] w-full resize-none rounded-xl border border-white/15 bg-black/50 py-3 pl-4 pr-14 text-sm text-white placeholder:text-white/35 outline-none backdrop-blur focus:border-white/30 disabled:opacity-60"
                  aria-label="Scene description"
                />
                <VoiceMicButton
                  voice={describeVoice}
                  disabled={busy}
                  labelIdle="Dictate scene"
                  light
                />
              </div>
            </div>
          ) : null}

          <button
            type="button"
            onClick={() => void onRecommendPrimary()}
            disabled={busy}
            aria-label="Recommend recipe from viewfinder"
            className="inline-flex min-h-12 w-full items-center justify-center gap-2 rounded-full bg-accent px-4 text-sm font-semibold text-white shadow-[0_8px_24px_-12px_rgba(244,63,94,0.55)] hover:bg-accent-soft disabled:opacity-50"
          >
            {loading || preparing ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin" />
                {LOADING_LABEL}
              </>
            ) : (
              <>
                <Sparkles className="h-4 w-4" />
                Recommend recipe
              </>
            )}
          </button>

          {inlineEmptyError ? (
            <p
              role="alert"
              className="mt-2 text-center text-xs text-danger"
            >
              {inlineEmptyError}
            </p>
          ) : null}

          <div className="mt-3 flex items-center justify-center gap-6">
            <button
              type="button"
              disabled={busy || !heldFrame}
              onClick={retake}
              className="flex min-h-11 min-w-11 flex-col items-center justify-center gap-1 text-white/70 transition hover:text-white disabled:opacity-35"
              aria-label="Retake"
            >
              <span className="flex h-11 w-11 items-center justify-center rounded-full bg-white/10 ring-1 ring-white/20">
                <RotateCcw className="h-5 w-5" strokeWidth={1.75} />
              </span>
              <span className="text-[10px] font-medium">Retake</span>
            </button>

            <button
              type="button"
              disabled={busy}
              onClick={() => fileRef.current?.click()}
              className="flex min-h-11 min-w-11 flex-col items-center justify-center gap-1 text-white/70 transition hover:text-white disabled:opacity-50"
              aria-label="Upload photo"
            >
              <span className="flex h-11 w-11 items-center justify-center rounded-full bg-white/10 ring-1 ring-white/20">
                <ImagePlus className="h-5 w-5" strokeWidth={1.75} />
              </span>
              <span className="text-[10px] font-medium">Upload</span>
            </button>

            <button
              type="button"
              disabled={busy}
              onClick={() => setDescribeOpen((open) => !open)}
              aria-pressed={describeOpen}
              className={`flex min-h-11 min-w-11 flex-col items-center justify-center gap-1 transition disabled:opacity-50 ${
                describeOpen ? 'text-white' : 'text-white/70 hover:text-white'
              }`}
              aria-label="Describe scene"
            >
              <span
                className={`flex h-11 w-11 items-center justify-center rounded-full ring-1 ${
                  describeOpen
                    ? 'bg-white/20 ring-white/35'
                    : 'bg-white/10 ring-white/20'
                }`}
              >
                <MessageSquareText className="h-5 w-5" strokeWidth={1.75} />
              </span>
              <span className="text-[10px] font-medium">Describe</span>
            </button>
          </div>

          <p className="mt-3 text-center text-[10px] text-white/35">{HONESTY_LINE}</p>
        </div>
      </div>

      {(cameraError || error || voiceError) && !inlineEmptyError ? (
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
          {error || cameraError ? (
            <button
              type="button"
              onClick={() => {
                setError(null)
                setCameraError(null)
              }}
              className="absolute right-2 top-2 inline-flex h-8 w-8 items-center justify-center rounded-full text-white/50 hover:bg-white/10 hover:text-white"
              aria-label="Dismiss"
            >
              <X className="h-3.5 w-3.5" />
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
