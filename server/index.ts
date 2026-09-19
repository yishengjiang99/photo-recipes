import cookieParser from 'cookie-parser'
import cors from 'cors'
import dotenv from 'dotenv'
import express from 'express'
import multer from 'multer'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { checkAskGrokQuota, identityMiddleware } from './entitlements.ts'
import {
  MAX_IMAGE_BYTES,
  mimeFromFilename,
  normalizeMime,
  parseDataUrl,
  toDataUrl,
} from './image.ts'
import { recommendWithGrok } from './recommend.ts'
import {
  ensureStripePrices,
  getStripe,
  mountStripeRoutes,
  mountStripeWebhook,
} from './stripe.ts'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
// Local .env for dev. Production uses systemd EnvironmentFile=/etc/photo-recipes.env
dotenv.config({ path: path.resolve(__dirname, '../.env') })

const PORT = Number(process.env.PORT || 8787)
const app = express()

app.use(
  cors({
    origin: true,
    credentials: true,
  }),
)
app.use(cookieParser())

// Stripe webhook needs raw body — mount before express.json()
mountStripeWebhook(app)

// JSON body: text asks (~32kb) or base64 images (~4MB binary → ~5.5MB JSON)
app.use(express.json({ limit: '6mb' }))
app.use(identityMiddleware)

mountStripeRoutes(app)

const upload = multer({
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

app.get('/api/health', (_req, res) => {
  res.json({
    ok: true,
    hasKey: Boolean(process.env.XAI_API_KEY?.trim()),
    stripe: Boolean(getStripe()),
    vision: true,
  })
})

type ParsedRecommend = {
  message: string
  favorites?: string[]
  imageDataUrl?: string
}

function parseJsonRecommend(body: Record<string, unknown>): ParsedRecommend | { error: string } {
  const message =
    typeof body?.message === 'string'
      ? body.message.trim()
      : typeof body?.note === 'string'
        ? body.note.trim()
        : ''

  const favorites = Array.isArray(body.favorites)
    ? body.favorites.filter((f): f is string => typeof f === 'string')
    : undefined

  let imageDataUrl: string | undefined
  const imageField = body.image ?? body.imageBase64 ?? body.imageDataUrl
  if (typeof imageField === 'string' && imageField.trim()) {
    const raw = imageField.trim()
    if (raw.startsWith('data:')) {
      const parsed = parseDataUrl(raw)
      if ('error' in parsed) return { error: parsed.error }
      imageDataUrl = toDataUrl(parsed.mime, parsed.buffer)
    } else {
      // bare base64 — assume jpeg unless mime provided
      const mime =
        normalizeMime(typeof body.mime === 'string' ? body.mime : 'image/jpeg') ||
        'image/jpeg'
      try {
        const buffer = Buffer.from(raw.replace(/\s+/g, ''), 'base64')
        if (!buffer.length) return { error: 'Empty image data' }
        if (buffer.length > MAX_IMAGE_BYTES) {
          return { error: `Image too large (max ${MAX_IMAGE_BYTES / (1024 * 1024)}MB)` }
        }
        imageDataUrl = toDataUrl(mime, buffer)
      } catch {
        return { error: 'Invalid base64 image data' }
      }
    }
  }

  if (!message && !imageDataUrl) {
    return {
      error:
        'Provide a non-empty "message" and/or an image (JSON: image data URL / base64, or multipart file field "image").',
    }
  }

  return { message, favorites, imageDataUrl }
}

function runRecommend(
  req: express.Request,
  res: express.Response,
  parsed: ParsedRecommend,
) {
  const quota = checkAskGrokQuota(req, res)
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

  void (async () => {
    try {
      const result = await recommendWithGrok(apiKey, {
        message: parsed.message || (parsed.imageDataUrl ? 'Recommend a recipe for this photo.' : ''),
        favorites: parsed.favorites,
        imageDataUrl: parsed.imageDataUrl,
      })
      quota.consume()
      // Never echo image bytes back
      res.json({
        presetId: result.presetId,
        reason: result.reason,
        tips: result.tips,
        preset: result.preset,
        model: result.model,
        vision: Boolean(parsed.imageDataUrl),
      })
    } catch (err) {
      const e = err as Error & { status?: number; details?: string }
      const status = e.status && e.status >= 400 && e.status < 600 ? e.status : 502
      // Log message only — never image bytes or full request body
      console.error('[recommend]', e.message)
      res.status(status).json({
        error: e.message || 'Recommendation failed',
      })
    }
  })()
}

/** POST /api/recommend — text Ask Grok and/or Photo Vision (multipart or JSON). */
app.post('/api/recommend', (req, res) => {
  const ct = (req.headers['content-type'] || '').toLowerCase()
  if (ct.includes('multipart/form-data')) {
    upload.single('image')(req, res, (err: unknown) => {
      if (err) {
        const msg =
          err instanceof Error ? err.message : 'Invalid multipart upload'
        const isSize =
          typeof err === 'object' &&
          err !== null &&
          'code' in err &&
          (err as { code?: string }).code === 'LIMIT_FILE_SIZE'
        res.status(400).json({
          error: isSize
            ? `Image too large (max ${MAX_IMAGE_BYTES / (1024 * 1024)}MB)`
            : msg,
        })
        return
      }

      const message =
        typeof req.body?.message === 'string'
          ? req.body.message.trim()
          : typeof req.body?.note === 'string'
            ? req.body.note.trim()
            : ''

      let favorites: string[] | undefined
      if (typeof req.body?.favorites === 'string' && req.body.favorites.trim()) {
        try {
          const parsed = JSON.parse(req.body.favorites) as unknown
          if (Array.isArray(parsed)) {
            favorites = parsed.filter((f): f is string => typeof f === 'string')
          }
        } catch {
          favorites = undefined
        }
      }

      let imageDataUrl: string | undefined
      if (req.file) {
        const mime =
          normalizeMime(req.file.mimetype) ||
          mimeFromFilename(req.file.originalname)
        if (!mime) {
          res.status(400).json({
            error: 'Unsupported image type. Use JPEG, PNG, or WebP.',
          })
          return
        }
        if (req.file.size > MAX_IMAGE_BYTES) {
          res.status(400).json({
            error: `Image too large (max ${MAX_IMAGE_BYTES / (1024 * 1024)}MB)`,
          })
          return
        }
        // Buffer stays in memory briefly; never logged
        imageDataUrl = toDataUrl(mime, req.file.buffer)
      }

      if (!message && !imageDataUrl) {
        res.status(400).json({
          error: 'Multipart body must include an image file and/or a message field.',
        })
        return
      }

      runRecommend(req, res, { message, favorites, imageDataUrl })
    })
    return
  }

  const parsed = parseJsonRecommend((req.body ?? {}) as Record<string, unknown>)
  if ('error' in parsed) {
    res.status(400).json({ error: parsed.error })
    return
  }
  runRecommend(req, res, parsed)
})

async function start() {
  if (getStripe()) {
    await ensureStripePrices()
  } else {
    console.warn('[stripe] STRIPE_SECRET_KEY not set — checkout endpoints return 503')
  }

  app.listen(PORT, '0.0.0.0', () => {
    console.log(`Photo Recipes API listening on http://0.0.0.0:${PORT}`)
    console.log(
      process.env.XAI_API_KEY?.trim()
        ? 'XAI_API_KEY: present'
        : 'XAI_API_KEY: missing (POST /api/recommend will return 503)',
    )
    console.log(
      process.env.SESSION_SECRET?.trim()
        ? 'SESSION_SECRET: present'
        : 'SESSION_SECRET: missing (using insecure dev default — set for production)',
    )
  })
}

void start()
