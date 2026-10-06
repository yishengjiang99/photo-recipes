import cookieParser from 'cookie-parser'
import cors from 'cors'
import dotenv from 'dotenv'
import express from 'express'
import multer from 'multer'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { checkAskGrokQuota, getGuestId, identityMiddleware } from './entitlements.ts'
import {
  MAX_IMAGE_BYTES,
  mimeFromFilename,
  normalizeMime,
} from './image.ts'
import {
  newRecommendCorrelationId,
  recommendWithGrok,
  shortGuestId,
} from './recommend.ts'
import {
  recommendWithGrokStream,
  writeSse,
} from './recommendStream.ts'
import {
  dataUrlFromMultipartFile,
  parseImageFromJsonBody,
  releaseMultipartImageBuffer,
  scrubImageFieldsFromBody,
} from './visionPassthrough.ts'
import {
  ensureStripePrices,
  getStripe,
  mountStripeRoutes,
  mountStripeWebhook,
} from './stripe.ts'
import { mountIapRoutes } from './iap.ts'
import { mountSttRoutes } from './stt.ts'
import { mountDescribeSceneRoutes } from './describeScene.ts'
import { mountWaitlistRoutes } from './waitlist.ts'
import { mountPushRoutes, pushHealthSnippet } from './push.ts'
import {
  logApiError,
  mountTelemetryRoutes,
  telemetryHealthSnippet,
} from './telemetry.ts'
import { mountAdminRoutes } from './admin.ts'
import { mountAttributionRoutes } from './attribution.ts'
import { getMysqlPool } from './mysql.ts'
import { ensurePushDevicesSchema } from './pushDevices.ts'

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
// Apple SKAdNetwork / AdAttributionKit postback copies (any content type) — before express.json()
mountAttributionRoutes(app)

// JSON body: text asks or base64 vision frames (phone JPEG as data URL).
// 100mb matches nginx client_max_body_size + MAX_IMAGE_BYTES (~100MB binary).
app.use(express.json({ limit: '100mb' }))
app.use(identityMiddleware)

mountStripeRoutes(app)
mountIapRoutes(app)
mountSttRoutes(app)
mountDescribeSceneRoutes(app)
mountWaitlistRoutes(app)
mountPushRoutes(app)
mountTelemetryRoutes(app)
mountAdminRoutes(app)

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
    stt: Boolean(process.env.XAI_API_KEY?.trim()),
    describeScene: Boolean(process.env.XAI_API_KEY?.trim()),
    waitlist: Boolean(process.env.RESEND_API_KEY?.trim()),
    ...pushHealthSnippet(),
    ...telemetryHealthSnippet(),
    admin: Boolean(process.env.ADMIN_PASSWORD?.trim() || process.env.ADMIN_TOKEN?.trim()),
  })
})

type ParsedRecommend = {
  message: string
  favorites?: string[]
  imageDataUrl?: string
}

/**
 * Parse recommend JSON. Image bytes stay in memory only (vision pass-through).
 * Scrubs image fields off `body` after a successful image parse.
 */
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
    const parsed = parseImageFromJsonBody(body)
    if ('error' in parsed) return { error: parsed.error }
    imageDataUrl = parsed.imageDataUrl
    scrubImageFieldsFromBody(body)
  }

  if (!message && !imageDataUrl) {
    return {
      error:
        'Provide a non-empty "message" and/or an image (JSON: image data URL / base64, or multipart file field "image").',
    }
  }

  return { message, favorites, imageDataUrl }
}


function clientPlatform(req: express.Request): string {
  const hdr = req.headers['x-client-platform']
  const raw = Array.isArray(hdr) ? hdr[0] : hdr
  if (typeof raw === 'string') {
    const p = raw.trim().toLowerCase()
    if (['ios', 'web', 'android', 'server'].includes(p)) return p
  }
  const ua = (req.headers['user-agent'] || '').toLowerCase()
  if (ua.includes('iphone') || ua.includes('ipad') || ua.includes('cfnetwork')) return 'ios'
  if (ua.includes('android')) return 'android'
  return 'web'
}

function recommendLogContext(req: express.Request, res: express.Response) {
  return {
    correlationId: newRecommendCorrelationId(),
    guestIdShort: shortGuestId(getGuestId(req, res)),
    platform: clientPlatform(req),
  }
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
        log: recommendLogContext(req, res),
      })
      quota.consume()
      // Never echo image bytes back
      res.json({
        presetId: result.presetId,
        // Alias for clients / product lock (recipeId ≡ presetId)
        recipeId: result.presetId,
        reason: result.reason,
        teachWhy: result.teachWhy,
        tips: result.tips,
        phoneTargets: result.phoneTargets,
        coachOnly: result.coachOnly,
        panCue: result.panCue,
        senseSummary: result.senseSummary,
        // One-release fallback: mirror of phoneTargets.creativeLook when present
        ...(result.creativeLook ? { creativeLook: result.creativeLook } : {}),
        preset: result.preset,
        model: result.model,
        vision: Boolean(parsed.imageDataUrl),
      })
    } catch (err) {
      const e = err as Error & { status?: number; details?: string }
      const status = e.status && e.status >= 400 && e.status < 600 ? e.status : 502
      // Log message only — never image bytes or full request body
      logApiError(req, {
        event: parsed.imageDataUrl ? 'optimize_error' : 'api_error',
        route: '/api/recommend',
        status,
        message: e.message || 'Recommendation failed',
        method: 'POST',
      })
      res.status(status).json({
        error: e.message || 'Recommendation failed',
      })
    }
  })()
}

/**
 * POST /api/recommend — text Ask Grok and/or Photo Vision (multipart or JSON).
 * Default: one-shot vision JSON (shrink in memory, recipes in prompt, no tools).
 * Legacy tool loop: RECOMMEND_TOOL_LOOP=1. Vision: never disk/DB image store.
 * Response: tips + presetId/recipeId + phoneTargets (+ coach fields). iOS applyPhoneTargets.
 */
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
        const status = isSize ? 413 : 400
        const error = isSize
          ? `Image too large (max ${MAX_IMAGE_BYTES / (1024 * 1024)}MB)`
          : msg
        logApiError(req, {
          event: 'optimize_error',
          route: '/api/recommend',
          status,
          message: error,
          method: 'POST',
        })
        res.status(status).json({ error })
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
        const parsed = dataUrlFromMultipartFile(req.file)
        if ('error' in parsed) {
          const isSize = /too large/i.test(parsed.error)
          const status = isSize ? 413 : 400
          logApiError(req, {
            event: 'optimize_error',
            route: '/api/recommend',
            status,
            message: parsed.error,
            method: 'POST',
          })
          res.status(status).json({ error: parsed.error })
          return
        }
        // Pass-through: in-memory data URL only; release multer buffer ref
        imageDataUrl = parsed.imageDataUrl
        releaseMultipartImageBuffer(req)
        scrubImageFieldsFromBody(req.body as Record<string, unknown>)
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
    const isSize = /too large/i.test(parsed.error)
    const status = isSize ? 413 : 400
    if (isSize || /image|base64|multipart/i.test(parsed.error)) {
      logApiError(req, {
        event: 'optimize_error',
        route: '/api/recommend',
        status,
        message: parsed.error,
        method: 'POST',
      })
    }
    res.status(status).json({ error: parsed.error })
    return
  }
  runRecommend(req, res, parsed)
})

/**
 * POST /api/recommend/stream — same input as /api/recommend; SSE progress + final result.
 * Shared contract for web Field Coach + iOS:
 *   event: phase | status | reasoning | content | result | error
 */
app.post('/api/recommend/stream', (req, res) => {
  const ct = (req.headers['content-type'] || '').toLowerCase()

  const startStream = (parsed: ParsedRecommend) => {
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

    res.status(200)
    res.setHeader('Content-Type', 'text/event-stream; charset=utf-8')
    res.setHeader('Cache-Control', 'no-cache, no-transform')
    res.setHeader('Connection', 'keep-alive')
    res.setHeader('X-Accel-Buffering', 'no')
    if (typeof (res as { flushHeaders?: () => void }).flushHeaders === 'function') {
      ;(res as { flushHeaders: () => void }).flushHeaders()
    }

    const ac = new AbortController()
    req.on('close', () => ac.abort())

    void recommendWithGrokStream(
      apiKey,
      {
        message:
          parsed.message ||
          (parsed.imageDataUrl ? 'Recommend a recipe for this photo.' : ''),
        favorites: parsed.favorites,
        imageDataUrl: parsed.imageDataUrl,
        log: recommendLogContext(req, res),
      },
      {
        onPhase: (phase) => writeSse(res, 'phase', { phase }),
        onStatus: (message) => writeSse(res, 'status', { message }),
        onReasoning: (delta) => writeSse(res, 'reasoning', { delta }),
        onContent: (delta) => writeSse(res, 'content', { delta }),
        onResult: (result) => {
          quota.consume()
          writeSse(res, 'result', result)
        },
        onError: (error, status) => {
          writeSse(res, 'error', { error, status })
          logApiError(req, {
            event: parsed.imageDataUrl ? 'optimize_error' : 'api_error',
            route: '/api/recommend/stream',
            status: status && status >= 400 && status < 600 ? status : 502,
            message: error,
            method: 'POST',
          })
        },
      },
      { signal: ac.signal },
    )
      .catch((err: Error & { status?: number }) => {
        if (!res.writableEnded) {
          writeSse(res, 'error', {
            error: err.message || 'Recommendation failed',
            status: err.status,
          })
        }
      })
      .finally(() => {
        if (!res.writableEnded) res.end()
      })
  }

  if (ct.includes('multipart/form-data')) {
    upload.single('image')(req, res, (err: unknown) => {
      if (err) {
        const msg = err instanceof Error ? err.message : 'Invalid multipart upload'
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
          event: 'optimize_error',
          route: '/api/recommend/stream',
          status,
          message: error,
          method: 'POST',
        })
        res.status(status).json({ error })
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
          const parsedFav = JSON.parse(req.body.favorites) as unknown
          if (Array.isArray(parsedFav)) {
            favorites = parsedFav.filter((f): f is string => typeof f === 'string')
          }
        } catch {
          favorites = undefined
        }
      }

      let imageDataUrl: string | undefined
      if (req.file) {
        const parsedImg = dataUrlFromMultipartFile(req.file)
        if ('error' in parsedImg) {
          const isSize = /too large/i.test(parsedImg.error)
          const status = isSize ? 413 : 400
          logApiError(req, {
            event: 'optimize_error',
            route: '/api/recommend/stream',
            status,
            message: parsedImg.error,
            method: 'POST',
          })
          res.status(status).json({ error: parsedImg.error })
          return
        }
        imageDataUrl = parsedImg.imageDataUrl
        releaseMultipartImageBuffer(req)
        scrubImageFieldsFromBody(req.body as Record<string, unknown>)
      }

      if (!message && !imageDataUrl) {
        res.status(400).json({
          error: 'Multipart body must include an image file and/or a message field.',
        })
        return
      }
      startStream({ message, favorites, imageDataUrl })
    })
    return
  }

  const parsed = parseJsonRecommend((req.body ?? {}) as Record<string, unknown>)
  if ('error' in parsed) {
    const isSize = /too large/i.test(parsed.error)
    const status = isSize ? 413 : 400
    if (isSize || /image|base64|multipart/i.test(parsed.error)) {
      logApiError(req, {
        event: 'optimize_error',
        route: '/api/recommend/stream',
        status,
        message: parsed.error,
        method: 'POST',
      })
    }
    res.status(status).json({ error: parsed.error })
    return
  }
  startStream(parsed)
})


/**
 * Prefer JSON over Express/HTML default pages for body-too-large and unhandled errors.
 * nginx 413 HTML still wins if the request never reaches Node — raise client_max_body_size.
 */
app.use(
  (
    err: unknown,
    req: express.Request,
    res: express.Response,
    next: express.NextFunction,
  ) => {
    if (!err) {
      next()
      return
    }
    const e = err as Error & {
      type?: string
      status?: number
      statusCode?: number
    }
    const isTooLarge =
      e.type === 'entity.too.large' ||
      e.status === 413 ||
      e.statusCode === 413 ||
      (typeof e.message === 'string' &&
        /request entity too large/i.test(e.message))
    if (isTooLarge) {
      logApiError(req, {
        event: 'api_error',
        route: req.path || req.url || '/',
        status: 413,
        message: 'Request entity too large',
        method: req.method,
      })
      if (!res.headersSent) {
        res.status(413).json({
          error: 'Request entity too large',
          hint: `Max body size is ~${MAX_IMAGE_BYTES / (1024 * 1024)}MB`,
        })
      }
      return
    }
    const status =
      e.status && e.status >= 400 && e.status < 600
        ? e.status
        : e.statusCode && e.statusCode >= 400 && e.statusCode < 600
          ? e.statusCode
          : 500
    logApiError(req, {
      event: 'api_error',
      route: req.path || req.url || '/',
      status,
      message: (e.message || 'Internal server error').slice(0, 200),
      method: req.method,
    })
    if (!res.headersSent) {
      res.status(status).json({
        error: status === 500 ? 'Internal server error' : e.message || 'Request failed',
      })
    }
  },
)

async function start() {
  const mysqlPool = getMysqlPool()
  console.log(
    mysqlPool
      ? 'MySQL: pool ready (telemetry persistence on)'
      : 'MySQL: unset — telemetry accepts events but does not persist',
  )
  if (mysqlPool) {
    void ensurePushDevicesSchema().then((ok) => {
      if (ok) console.log('MySQL: devices + push_tokens schema ready')
    })
  }
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
        : 'XAI_API_KEY: missing (POST /api/recommend, /api/recommend/stream, /api/stt, /api/describe-scene will return 503)',
    )
    console.log(
      process.env.SESSION_SECRET?.trim()
        ? 'SESSION_SECRET: present'
        : 'SESSION_SECRET: missing (using insecure dev default — set for production)',
    )
  })
}

void start()
