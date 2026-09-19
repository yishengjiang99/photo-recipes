import cookieParser from 'cookie-parser'
import cors from 'cors'
import dotenv from 'dotenv'
import express from 'express'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { checkAskGrokQuota, identityMiddleware } from './entitlements.ts'
import { recommendWithGrok, type RecommendRequest } from './recommend.ts'
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

app.use(express.json({ limit: '32kb' }))
app.use(identityMiddleware)

mountStripeRoutes(app)

app.get('/api/health', (_req, res) => {
  res.json({
    ok: true,
    hasKey: Boolean(process.env.XAI_API_KEY?.trim()),
    stripe: Boolean(getStripe()),
  })
})

app.post('/api/recommend', async (req, res) => {
  const body = req.body as RecommendRequest
  const message = typeof body?.message === 'string' ? body.message.trim() : ''
  if (!message) {
    res.status(400).json({ error: 'Body must include a non-empty "message" string.' })
    return
  }

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

  const favorites = Array.isArray(body.favorites)
    ? body.favorites.filter((f): f is string => typeof f === 'string')
    : undefined

  try {
    const result = await recommendWithGrok(apiKey, { message, favorites })
    quota.consume()
    res.json({
      presetId: result.presetId,
      reason: result.reason,
      tips: result.tips,
      preset: result.preset,
    })
  } catch (err) {
    const e = err as Error & { status?: number; details?: string }
    const status = e.status && e.status >= 400 && e.status < 600 ? e.status : 502
    console.error('[recommend]', e.message, e.details ? '(details omitted from logs if sensitive)' : '')
    res.status(status).json({
      error: e.message || 'Recommendation failed',
    })
  }
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
