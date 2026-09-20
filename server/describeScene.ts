/**
 * Lightweight Grok vision caption for iOS scene prefill.
 * Single chat completion — no catalog tools / no recommendWithGrok.
 */
import type { Express, Request, Response, NextFunction } from 'express'
import multer from 'multer'
import {
  MAX_IMAGE_BYTES,
  mimeFromFilename,
  normalizeMime,
} from './image.ts'
import { logApiError } from './telemetry.ts'
import { checkAssistQuota } from './entitlements.ts'
import { fetchWithTimeout } from './fetchTimeout.ts'
import {
  dataUrlFromMultipartFile,
  parseImageFromJsonBody,
  releaseMultipartImageBuffer,
  scrubImageFieldsFromBody,
} from './visionPassthrough.ts'

const XAI_BASE = 'https://api.x.ai/v1'
const VISION_MODELS = ['grok-4.6', 'grok-4'] as const

const SYSTEM_PROMPT = `You are a concise field photography coach. Look at the photo and write a short scene description a photographer would type into a recipe ask box.

Include: subject, lighting, motion (if any), and one composition or exposure hint.
Keep it to 1–2 sentences, under 40 words. Plain text only — no bullet lists, no recipe names, no camera dial numbers unless clearly readable in the scene.`

type ContentPart =
  | { type: 'text'; text: string }
  | { type: 'image_url'; image_url: { url: string; detail?: 'auto' | 'low' | 'high' } }

function isModelMissing(status: number, body: string): boolean {
  if (status === 404) return true
  const lower = body.toLowerCase()
  return (
    status === 400 &&
    (lower.includes('model') ||
      lower.includes('not found') ||
      lower.includes('does not exist'))
  )
}

export async function describeSceneWithGrok(
  apiKey: string,
  imageDataUrl: string,
): Promise<{ description: string; model: string }> {
  const messages = [
    { role: 'system' as const, content: SYSTEM_PROMPT },
    {
      role: 'user' as const,
      content: [
        {
          type: 'text' as const,
          text: 'Describe this photography scene briefly for recipe matching.',
        },
        {
          type: 'image_url' as const,
          image_url: { url: imageDataUrl, detail: 'low' as const },
        },
      ] satisfies ContentPart[],
    },
  ]

  let modelIndex = 0
  let model: string = VISION_MODELS[0]!

  for (;;) {
    let xaiRes: globalThis.Response
    try {
      xaiRes = await fetchWithTimeout(
        `${XAI_BASE}/chat/completions`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${apiKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            model,
            temperature: 0.3,
            max_tokens: 120,
            messages,
          }),
        },
        25_000,
      )
    } catch (e) {
      const ex = e as Error & { status?: number }
      if (ex.status === 504 || (e instanceof Error && e.name === 'AbortError')) {
        const err = new Error(
          'Scene description unavailable — try again or type your scene',
        ) as Error & { status?: number }
        err.status = 504
        throw err
      }
      throw e
    }

    const bodyText = await xaiRes.text()
    if (
      !xaiRes.ok &&
      isModelMissing(xaiRes.status, bodyText) &&
      modelIndex < VISION_MODELS.length - 1
    ) {
      modelIndex += 1
      model = VISION_MODELS[modelIndex]!
      console.warn(`[describe-scene] model unavailable, falling back to ${model}`)
      continue
    }

    if (!xaiRes.ok) {
      const err = new Error(
        'Scene description unavailable — try again or type your scene',
      ) as Error & { status?: number; details?: string }
      err.status = xaiRes.status >= 400 && xaiRes.status < 600 ? xaiRes.status : 502
      err.details = bodyText.slice(0, 500)
      throw err
    }

    let data: {
      choices?: Array<{ message?: { content?: string | null } }>
    }
    try {
      data = JSON.parse(bodyText) as typeof data
    } catch {
      throw Object.assign(new Error('Scene description unavailable — try again'), {
        status: 502,
      })
    }

    const raw = data.choices?.[0]?.message?.content
    const description = typeof raw === 'string' ? raw.trim() : ''
    if (!description) {
      throw Object.assign(
        new Error('Scene description unavailable — try again'),
        { status: 502 },
      )
    }

    return { description, model }
  }
}

const imageUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_IMAGE_BYTES, files: 1 },
  fileFilter: (_req, file, cb) => {
    const mime =
      normalizeMime(file.mimetype) || mimeFromFilename(file.originalname)
    if (!mime) {
      cb(new Error('Unsupported image type. Use JPEG, PNG, or WebP.'))
      return
    }
    cb(null, true)
  },
})

/**
 * Mount POST /api/describe-scene — short vision caption for Ask/Camera prefill.
 * Vision pass-through: image held in memory only for this request (see visionPassthrough.ts).
 * Consumes assist quota (shared with STT) after a successful caption.
 */
export function mountDescribeSceneRoutes(app: Express) {
  app.post('/api/describe-scene', (req: Request, res: Response, next: NextFunction) => {
    const ct = (req.headers['content-type'] || '').toLowerCase()
    if (ct.includes('multipart/form-data')) {
      imageUpload.single('image')(req, res, (err: unknown) => {
        if (err) {
          const msg =
            err instanceof Error ? err.message : 'Invalid multipart upload'
          const isSize =
            typeof err === 'object' &&
            err !== null &&
            'code' in err &&
            (err as { code?: string }).code === 'LIMIT_FILE_SIZE'
          const status = isSize ? 413 : 400
          const error = isSize
            ? `Image too large (max ${MAX_IMAGE_BYTES / (1024 * 1024)}MB)`
            : msg
          logApiError(req, {
            event: 'api_error',
            route: '/api/describe-scene',
            status,
            message: error,
            method: 'POST',
          })
          res.status(status).json({ error })
          return
        }
        next()
      })
      return
    }
    next()
  }, (req: Request, res: Response) => {
    const quota = checkAssistQuota(req, res)
    if (!quota.allowed) {
      res.status(402).json(quota.body)
      return
    }

    const apiKey = process.env.XAI_API_KEY?.trim()
    if (!apiKey) {
      res.status(503).json({
        error:
          'XAI_API_KEY is not set. Add it to .env (see .env.example) and restart the API server.',
      })
      return
    }

    let imageDataUrl: string | undefined

    if (req.file) {
      const parsed = dataUrlFromMultipartFile(req.file)
      if ('error' in parsed) {
        const isSize = /too large/i.test(parsed.error)
        const status = isSize ? 413 : 400
        logApiError(req, {
          event: 'api_error',
          route: '/api/describe-scene',
          status,
          message: parsed.error,
          method: 'POST',
        })
        res.status(status).json({ error: parsed.error })
        return
      }
      // Pass-through: in-memory only; release multer buffer after copy
      imageDataUrl = parsed.imageDataUrl
      releaseMultipartImageBuffer(req)
      scrubImageFieldsFromBody(req.body as Record<string, unknown>)
    } else {
      const body = (req.body ?? {}) as Record<string, unknown>
      const parsed = parseImageFromJsonBody(body)
      if ('error' in parsed) {
        const isSize = /too large/i.test(parsed.error)
        const status = isSize ? 413 : 400
        logApiError(req, {
          event: 'api_error',
          route: '/api/describe-scene',
          status,
          message: parsed.error,
          method: 'POST',
        })
        res.status(status).json({ error: parsed.error })
        return
      }
      imageDataUrl = parsed.imageDataUrl
      scrubImageFieldsFromBody(body)
    }

    void (async () => {
      try {
        const result = await describeSceneWithGrok(apiKey, imageDataUrl!)
        quota.consume()
        res.json({
          description: result.description,
          text: result.description,
          model: result.model,
        })
      } catch (e) {
        const ex = e as Error & { status?: number }
        const status =
          ex.status && ex.status >= 400 && ex.status < 600 ? ex.status : 502
        logApiError(req, {
          event: 'api_error',
          route: '/api/describe-scene',
          status,
          message: ex.message || 'Scene description unavailable',
          method: 'POST',
        })
        res.status(status).json({
          error: ex.message || 'Scene description unavailable — try again',
        })
      }
    })()
  })
}
