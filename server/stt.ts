/**
 * Grok speech-to-text proxy.
 * Client uploads audio → we forward to xAI with XAI_API_KEY (never on device).
 * Batch REST for v1; live WSS (interim_results / smart_turn) is a v1.1 follow-up.
 */
import type { Express, Request, Response, NextFunction } from 'express'
import multer from 'multer'

const XAI_STT_URL = 'https://api.x.ai/v1/stt'
/** Current xAI batch model — https://docs.x.ai/docs/guides/voice/speech-to-text */
const STT_MODEL = 'grok-voice-transcribe-2.0'

/** Photography vocabulary bias (repeat `keyterm`; max 100, ≤50 chars each). */
export const PHOTO_STT_KEYTERMS = [
  'ISO',
  'aperture',
  'shutter',
  'shutter speed',
  'f-stop',
  'depth of field',
  'HDR',
  'panning',
  'bokeh',
  'golden hour',
  'blue hour',
  'tripod',
  'exposure',
  'white balance',
  'ND filter',
  'long exposure',
  'motion blur',
  'silky water',
  'backlighting',
  'low light',
  'focal length',
  'wide angle',
  'telephoto',
  'manual mode',
  'metering',
  'rule of thirds',
  'composition',
  'foreground',
  'landscape',
  'cyclist',
] as const

export const ALLOWED_AUDIO_MIMES = new Set([
  'audio/webm',
  'audio/ogg',
  'audio/mpeg',
  'audio/mp3',
  'audio/mp4',
  'audio/m4a',
  'audio/x-m4a',
  'audio/wav',
  'audio/x-wav',
  'audio/wave',
  'audio/flac',
  'audio/aac',
  'audio/opus',
  'audio/caf',
  'video/webm',
])

export const MAX_AUDIO_BYTES = 25 * 1024 * 1024

const EXT_FROM_MIME: Record<string, string> = {
  'audio/webm': 'webm',
  'video/webm': 'webm',
  'audio/ogg': 'ogg',
  'audio/mpeg': 'mp3',
  'audio/mp3': 'mp3',
  'audio/mp4': 'm4a',
  'audio/m4a': 'm4a',
  'audio/x-m4a': 'm4a',
  'audio/wav': 'wav',
  'audio/x-wav': 'wav',
  'audio/wave': 'wav',
  'audio/flac': 'flac',
  'audio/aac': 'aac',
  'audio/opus': 'opus',
  'audio/caf': 'caf',
}

const MIME_FROM_EXT: Record<string, string> = {
  webm: 'audio/webm',
  ogg: 'audio/ogg',
  mp3: 'audio/mpeg',
  m4a: 'audio/mp4',
  mp4: 'audio/mp4',
  wav: 'audio/wav',
  flac: 'audio/flac',
  aac: 'audio/aac',
  opus: 'audio/opus',
  caf: 'audio/caf',
}

export function normalizeAudioMime(raw: string | undefined | null): string | null {
  if (!raw) return null
  const mime = raw.split(';')[0]!.trim().toLowerCase()
  return ALLOWED_AUDIO_MIMES.has(mime) ? mime : null
}

export function mimeFromAudioFilename(name: string | undefined): string | null {
  if (!name) return null
  const ext = name.split('.').pop()?.toLowerCase()
  if (!ext) return null
  const mime = MIME_FROM_EXT[ext]
  return mime && ALLOWED_AUDIO_MIMES.has(mime) ? mime : null
}

export function audioExtFromMime(mime: string): string {
  return EXT_FROM_MIME[mime] ?? 'm4a'
}

export type SttResult = {
  text: string
  language?: string
  duration?: number
}

export async function transcribeWithGrok(
  apiKey: string,
  file: { buffer: Buffer; mime: string; filename?: string },
): Promise<SttResult> {
  const mime =
    normalizeAudioMime(file.mime) ??
    (file.mime.split(';')[0]?.trim() || 'audio/mp4')
  const filename = file.filename || `recording.${audioExtFromMime(mime)}`

  // Options MUST precede `file` in multipart (xAI streamable-upload rule).
  const form = new FormData()
  form.append('model', STT_MODEL)
  form.append('format', 'true')
  form.append('language', 'en')
  for (const term of PHOTO_STT_KEYTERMS) {
    form.append('keyterm', term)
  }
  form.append(
    'file',
    new Blob([new Uint8Array(file.buffer)], { type: mime }),
    filename,
  )

  const res = await fetch(XAI_STT_URL, {
    method: 'POST',
    headers: { Authorization: `Bearer ${apiKey}` },
    body: form,
  })

  if (!res.ok) {
    let details = ''
    try {
      const body = (await res.json()) as {
        error?: string | { message?: string }
      }
      if (typeof body.error === 'string') details = body.error
      else if (body.error && typeof body.error === 'object' && body.error.message) {
        details = body.error.message
      }
    } catch {
      details = await res.text().catch(() => '')
    }
    const err = new Error(
      details || `Speech-to-text failed (${res.status})`,
    ) as Error & { status?: number }
    err.status = res.status >= 400 && res.status < 600 ? res.status : 502
    throw err
  }

  const data = (await res.json()) as {
    text?: string
    language?: string
    duration?: number
  }

  const text = typeof data.text === 'string' ? data.text.trim() : ''
  if (!text) {
    const err = new Error('Didn’t catch that — try again') as Error & {
      status?: number
    }
    err.status = 422
    throw err
  }

  return {
    text,
    language: typeof data.language === 'string' ? data.language : undefined,
    duration: typeof data.duration === 'number' ? data.duration : undefined,
  }
}

const audioUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_AUDIO_BYTES, files: 1 },
  fileFilter: (_req, file, cb) => {
    const mime =
      normalizeAudioMime(file.mimetype) || mimeFromAudioFilename(file.originalname)
    if (!mime) {
      const name = (file.originalname || '').toLowerCase()
      const okExt = /\.(webm|ogg|mp3|mp4|m4a|wav|flac|aac|opus|caf)$/.test(name)
      if (
        !okExt &&
        !(file.mimetype || '').startsWith('audio/') &&
        file.mimetype !== 'video/webm'
      ) {
        cb(new Error('Unsupported audio type. Use m4a, wav, mp3, webm, or aac.'))
        return
      }
    }
    cb(null, true)
  },
})

/**
 * Mount POST /api/stt — multipart field `audio` (or `file`).
 * Returns `{ text }` on success. Does not consume Ask/Optimize quota.
 */
export function mountSttRoutes(app: Express) {
  app.post(
    '/api/stt',
    (req: Request, res: Response, next: NextFunction) => {
      audioUpload.any()(req, res, (err: unknown) => {
        if (err) {
          const msg = err instanceof Error ? err.message : 'Invalid audio upload'
          const isSize =
            typeof err === 'object' &&
            err !== null &&
            'code' in err &&
            (err as { code?: string }).code === 'LIMIT_FILE_SIZE'
          res.status(400).json({
            error: isSize
              ? `Audio too large (max ${MAX_AUDIO_BYTES / (1024 * 1024)}MB)`
              : msg,
          })
          return
        }
        next()
      })
    },
    (req: Request, res: Response) => {
      const apiKey = process.env.XAI_API_KEY?.trim()
      if (!apiKey) {
        res.status(503).json({
          error:
            'XAI_API_KEY is not set. Add it to .env (see .env.example) and restart the API server.',
        })
        return
      }

      const files = (req.files as Express.Multer.File[] | undefined) ?? []
      const uploaded =
        files.find((f) => f.fieldname === 'audio') ||
        files.find((f) => f.fieldname === 'file') ||
        files[0]

      if (!uploaded) {
        res.status(400).json({
          error:
            'Multipart body must include an audio file (field "audio" or "file").',
        })
        return
      }

      const mime =
        normalizeAudioMime(uploaded.mimetype) ||
        mimeFromAudioFilename(uploaded.originalname) ||
        'audio/mp4'

      void (async () => {
        try {
          const result = await transcribeWithGrok(apiKey, {
            buffer: uploaded.buffer,
            mime,
            filename:
              uploaded.originalname || `recording.${audioExtFromMime(mime)}`,
          })
          res.json({ text: result.text })
        } catch (e) {
          const ex = e as Error & { status?: number }
          const status =
            ex.status && ex.status >= 400 && ex.status < 600 ? ex.status : 502
          console.error('[stt]', ex.message)
          res.status(status).json({
            error: ex.message || 'Voice unavailable — type your scene',
          })
        }
      })()
    },
  )
}
