import { useCallback, useEffect, useRef, useState } from 'react'

type SpeechRecognitionLike = {
  continuous: boolean
  interimResults: boolean
  lang: string
  onresult: ((ev: SpeechRecognitionEventLike) => void) | null
  onerror: ((ev: { error?: string }) => void) | null
  onend: (() => void) | null
  start: () => void
  stop: () => void
  abort: () => void
}

type SpeechRecognitionEventLike = {
  resultIndex: number
  results: ArrayLike<{
    isFinal: boolean
    0: { transcript: string }
  }>
}

type SpeechRecognitionCtor = new () => SpeechRecognitionLike

export type VoiceInputStatus =
  | 'idle'
  | 'recording'
  | 'transcribing'
  | 'unsupported'
  | 'denied'

export type VoiceInputApi = {
  status: VoiceInputStatus
  supported: boolean
  error: string | null
  listening: boolean
  transcribing: boolean
  start: () => void
  stop: () => void
  toggle: () => void
  clearError: () => void
}

function getSpeechRecognitionCtor(): SpeechRecognitionCtor | null {
  if (typeof window === 'undefined') return null
  const w = window as Window & {
    SpeechRecognition?: SpeechRecognitionCtor
    webkitSpeechRecognition?: SpeechRecognitionCtor
  }
  return w.SpeechRecognition ?? w.webkitSpeechRecognition ?? null
}

function mediaRecorderSupported(): boolean {
  return (
    typeof window !== 'undefined' &&
    typeof navigator !== 'undefined' &&
    !!navigator.mediaDevices?.getUserMedia &&
    typeof MediaRecorder !== 'undefined'
  )
}

function pickRecorderMime(): string | undefined {
  if (typeof MediaRecorder === 'undefined') return undefined
  const candidates = [
    'audio/webm;codecs=opus',
    'audio/webm',
    'audio/ogg;codecs=opus',
    'audio/mp4',
  ]
  for (const mime of candidates) {
    if (MediaRecorder.isTypeSupported(mime)) return mime
  }
  return undefined
}

function appendTranscript(existing: string, addition: string): string {
  const next = addition.trim()
  if (!next) return existing
  const base = existing.trimEnd()
  if (!base) return next
  return `${base} ${next}`
}

async function uploadToStt(blob: Blob): Promise<string> {
  const form = new FormData()
  const ext = blob.type.includes('ogg')
    ? 'ogg'
    : blob.type.includes('mp4') || blob.type.includes('m4a')
      ? 'm4a'
      : 'webm'
  form.append('file', blob, `recording.${ext}`)

  const res = await fetch('/api/stt', {
    method: 'POST',
    credentials: 'include',
    body: form,
  })

  const data = (await res.json().catch(() => ({}))) as {
    text?: string
    error?: string
  }

  if (!res.ok) {
    throw new Error(data.error || `Voice unavailable (${res.status})`)
  }

  const text = typeof data.text === 'string' ? data.text.trim() : ''
  if (!text) {
    throw new Error('Didn’t catch that — try again')
  }
  return text
}

/**
 * Voice dictate for Field Coach.
 * Primary: MediaRecorder → POST /api/stt (Grok).
 * Fallback: Web Speech API if MediaRecorder unavailable or after STT failure (next tap).
 */
export function useVoiceInput(opts: {
  value: string
  onChange: (next: string) => void
  disabled?: boolean
}): VoiceInputApi {
  const { value, onChange, disabled } = opts
  const valueRef = useRef(value)
  valueRef.current = value
  const onChangeRef = useRef(onChange)
  onChangeRef.current = onChange

  const grokCapable = mediaRecorderSupported()
  const speechCtor = getSpeechRecognitionCtor()
  const supported = grokCapable || !!speechCtor

  const [status, setStatus] = useState<VoiceInputStatus>(() =>
    supported ? 'idle' : 'unsupported',
  )
  const [error, setError] = useState<string | null>(null)

  const mediaRecorderRef = useRef<MediaRecorder | null>(null)
  const chunksRef = useRef<Blob[]>([])
  const streamRef = useRef<MediaStream | null>(null)
  const recognitionRef = useRef<SpeechRecognitionLike | null>(null)
  const usingFallbackRef = useRef(false)
  const preferWebSpeechRef = useRef(false)
  const baseTextRef = useRef('')
  const mountedRef = useRef(true)

  const cleanupStream = useCallback(() => {
    streamRef.current?.getTracks().forEach((t) => t.stop())
    streamRef.current = null
  }, [])

  const stopRecognition = useCallback(() => {
    const rec = recognitionRef.current
    recognitionRef.current = null
    if (rec) {
      try {
        rec.onresult = null
        rec.onerror = null
        rec.onend = null
        rec.abort()
      } catch {
        /* ignore */
      }
    }
  }, [])

  const stopRecorder = useCallback(() => {
    const mr = mediaRecorderRef.current
    mediaRecorderRef.current = null
    if (mr && mr.state !== 'inactive') {
      try {
        mr.stop()
      } catch {
        /* ignore */
      }
    } else {
      cleanupStream()
    }
  }, [cleanupStream])

  useEffect(() => {
    mountedRef.current = true
    return () => {
      mountedRef.current = false
      stopRecorder()
      stopRecognition()
      cleanupStream()
    }
  }, [cleanupStream, stopRecognition, stopRecorder])

  const startWebSpeechFallback = useCallback(() => {
    const Ctor = getSpeechRecognitionCtor()
    if (!Ctor) {
      setError('Voice unavailable — type your scene')
      setStatus('idle')
      return
    }

    usingFallbackRef.current = true
    baseTextRef.current = valueRef.current
    stopRecognition()

    const rec = new Ctor()
    recognitionRef.current = rec
    rec.continuous = true
    rec.interimResults = true
    rec.lang = 'en-US'

    rec.onresult = (ev) => {
      let interim = ''
      let finalChunk = ''
      for (let i = ev.resultIndex; i < ev.results.length; i++) {
        const result = ev.results[i]
        if (!result) continue
        const piece = result[0]?.transcript ?? ''
        if (result.isFinal) finalChunk += piece
        else interim += piece
      }
      if (finalChunk) {
        baseTextRef.current = appendTranscript(baseTextRef.current, finalChunk)
        onChangeRef.current(baseTextRef.current)
      } else if (interim) {
        onChangeRef.current(appendTranscript(baseTextRef.current, interim))
      }
    }

    rec.onerror = (ev) => {
      if (!mountedRef.current) return
      const code = ev.error
      if (code === 'not-allowed' || code === 'service-not-allowed') {
        setStatus('denied')
        setError('Microphone is off — type your scene instead')
      } else if (code === 'no-speech') {
        setError('Didn’t catch that — try again')
        setStatus('idle')
      } else if (code !== 'aborted') {
        setError('Voice unavailable — type your scene')
        setStatus('idle')
      } else {
        setStatus('idle')
      }
      stopRecognition()
    }

    rec.onend = () => {
      if (!mountedRef.current) return
      recognitionRef.current = null
      usingFallbackRef.current = false
      setStatus((s) => (s === 'recording' ? 'idle' : s))
    }

    try {
      rec.start()
      setStatus('recording')
      setError(null)
    } catch {
      setError('Voice unavailable — type your scene')
      setStatus('idle')
      stopRecognition()
    }
  }, [stopRecognition])

  const finishGrokRecording = useCallback(
    async (blob: Blob) => {
      if (!mountedRef.current) return
      if (!blob.size) {
        setError('Didn’t catch that — try again')
        setStatus('idle')
        return
      }

      setStatus('transcribing')
      try {
        const text = await uploadToStt(blob)
        if (!mountedRef.current) return
        onChangeRef.current(appendTranscript(valueRef.current, text))
        setError(null)
        setStatus('idle')
      } catch (err) {
        if (!mountedRef.current) return
        const msg = err instanceof Error ? err.message : 'Voice unavailable'
        if (getSpeechRecognitionCtor()) {
          preferWebSpeechRef.current = true
        }
        setError(
          msg.includes('catch')
            ? msg
            : 'Voice unavailable — type your scene',
        )
        setStatus('idle')
      }
    },
    [],
  )

  const startGrokRecording = useCallback(async () => {
    usingFallbackRef.current = false
    baseTextRef.current = valueRef.current
    chunksRef.current = []

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      if (!mountedRef.current) {
        stream.getTracks().forEach((t) => t.stop())
        return
      }
      streamRef.current = stream
      const mime = pickRecorderMime()
      const mr = mime
        ? new MediaRecorder(stream, { mimeType: mime })
        : new MediaRecorder(stream)
      mediaRecorderRef.current = mr

      mr.ondataavailable = (e) => {
        if (e.data.size > 0) chunksRef.current.push(e.data)
      }

      mr.onstop = () => {
        const type = mr.mimeType || mime || 'audio/webm'
        const blob = new Blob(chunksRef.current, { type })
        chunksRef.current = []
        cleanupStream()
        void finishGrokRecording(blob)
      }

      mr.start(250)
      setStatus('recording')
      setError(null)
    } catch (err) {
      cleanupStream()
      const name = err instanceof DOMException ? err.name : ''
      if (name === 'NotAllowedError' || name === 'PermissionDeniedError') {
        setStatus('denied')
        setError('Microphone is off — type your scene instead')
        return
      }
      if (getSpeechRecognitionCtor()) {
        startWebSpeechFallback()
        return
      }
      setError('Voice unavailable — type your scene')
      setStatus('idle')
    }
  }, [cleanupStream, finishGrokRecording, startWebSpeechFallback])

  const start = useCallback(() => {
    if (disabled || !supported) return
    if (status === 'recording' || status === 'transcribing') return
    setError(null)
    if (preferWebSpeechRef.current && getSpeechRecognitionCtor()) {
      preferWebSpeechRef.current = false
      startWebSpeechFallback()
    } else if (grokCapable) {
      void startGrokRecording()
    } else {
      startWebSpeechFallback()
    }
  }, [
    disabled,
    grokCapable,
    startGrokRecording,
    startWebSpeechFallback,
    status,
    supported,
  ])

  const stop = useCallback(() => {
    if (usingFallbackRef.current || recognitionRef.current) {
      try {
        recognitionRef.current?.stop()
      } catch {
        stopRecognition()
      }
      setStatus('idle')
      return
    }
    if (mediaRecorderRef.current) {
      stopRecorder()
      return
    }
    setStatus('idle')
  }, [stopRecognition, stopRecorder])

  const toggle = useCallback(() => {
    if (status === 'recording') stop()
    else if (status === 'idle' || status === 'denied') start()
  }, [start, status, stop])

  useEffect(() => {
    if (status !== 'recording') return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault()
        stop()
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [status, stop])

  return {
    status: supported ? status : 'unsupported',
    supported,
    error,
    listening: status === 'recording',
    transcribing: status === 'transcribing',
    start,
    stop,
    toggle,
    clearError: () => setError(null),
  }
}
