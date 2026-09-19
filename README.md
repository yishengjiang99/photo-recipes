# Photo Recipes

A mobile-friendly web app of photography field presets, transcribed from pages of a “30 Recipes” photography book. Use it on location for steps, gear checklists, and educational camera dials — or ask Grok which recipe fits your scene.

**Soft funnel:** browsing presets is always free (Free Peek). Ask Grok is limited to **1/day** on Free Peek; **Photo Recipes Pro** unlocks unlimited Ask Grok + interactive field checklists via Stripe Checkout (7-day trial).

## Stack

- Vite + React 19 + TypeScript
- Tailwind CSS v4
- React Router
- Express + tsx API (`server/`) with xAI Grok tool-calling
- Stripe Checkout subscriptions + webhook entitlements
- Favorites & checklist progress in `localStorage`
- Entitlements / Ask quota in gitignored `server/data/entitlements.json`

## Presets (from book pages)

| Page | Recipe | Tags |
|------|--------|------|
| 28 | Sharp from Front to Back | Depth of field |
| 30 | How to Blur Moving Subjects | Motion (day / night sub-settings) |
| 32 | Keep a Moving Subject Sharp, With Motion Blur in the Background | Motion (panning + advanced flash) |
| 40 | Shake Up Your Perspective by Getting Down Low | Composition |
| 44 | Capture all the Brights and Darks With HDR | HDR (phone + camera methods) |

Preset data lives in `src/data/presets.ts` (shared with the API).

## Pricing (Photo Recipes Pro)

| Plan | Amount | Notes |
|------|--------|--------|
| Monthly | **$7.99**/mo (799¢ USD) | 7-day free trial |
| Annual | **$59.99**/yr (5999¢ USD) | **Primary CTA / Best value**, 7-day free trial |

- Free Peek: browse presets; Ask Grok **1/day**
- Pro: unlimited Ask Grok + field checklists

## Environment

Copy `.env.example` to `.env` (never commit `.env`):

```bash
cp .env.example .env
```

```
XAI_API_KEY=
PUBLIC_BASE_URL=http://localhost:5173
SESSION_SECRET=change-me-to-a-long-random-string
STRIPE_SECRET_KEY=
STRIPE_WEBHOOK_SECRET=
STRIPE_PRICE_MONTHLY=
STRIPE_PRICE_YEARLY=
```

| Variable | Purpose |
|----------|---------|
| `XAI_API_KEY` | Grok recommendations |
| `PUBLIC_BASE_URL` | Stripe success/cancel + billing portal return URL |
| `SESSION_SECRET` | HMAC for httpOnly guest + Pro cookies |
| `STRIPE_SECRET_KEY` | Stripe API |
| `STRIPE_WEBHOOK_SECRET` | Webhook signature verification |
| `STRIPE_PRICE_MONTHLY` / `STRIPE_PRICE_YEARLY` | Optional; if missing and secret key is set, API **auto-creates** product “Photo Recipes Pro” and the two recurring prices |

Without `XAI_API_KEY`, `POST /api/recommend` returns **503**. Without Stripe keys, checkout endpoints return **503** (browsing still works).

## Run locally (frontend + API)

```bash
cd /workspace/photo-recipes
npm install
npm run dev:all
```

- Web: [http://localhost:5173](http://localhost:5173) (Vite proxies `/api` → API)
- API: [http://localhost:8787](http://localhost:8787)

### Stripe webhook (local)

```bash
stripe listen --forward-to localhost:8787/api/stripe-webhook
# put the whsec_… value into STRIPE_WEBHOOK_SECRET and restart the API
```

Production webhook URL (nginx proxies `/api`):

```
https://YOUR_DOMAIN/api/stripe-webhook
```

Subscribe to at least: `checkout.session.completed`, `customer.subscription.updated`, `customer.subscription.deleted`.

### Example API calls

Health:

```bash
curl -s http://localhost:8787/api/health
```

Subscription status (sets guest cookie):

```bash
curl -s -c /tmp/pr.jar -b /tmp/pr.jar http://localhost:8787/api/subscription-status
```

Create Checkout (yearly = primary CTA):

```bash
curl -s -c /tmp/pr.jar -b /tmp/pr.jar http://localhost:8787/api/create-checkout-session \
  -H 'Content-Type: application/json' \
  -d '{"plan":"yearly"}'
# → { "sessionId", "url", "plan" } — open url in browser
```

Verify after redirect to `/success?session_id=…`:

```bash
curl -s -c /tmp/pr.jar -b /tmp/pr.jar http://localhost:8787/api/verify-checkout-session \
  -H 'Content-Type: application/json' \
  -d '{"sessionId":"cs_test_…"}'
```

Billing portal (requires Pro cookie from verify/webhook):

```bash
curl -s -c /tmp/pr.jar -b /tmp/pr.jar http://localhost:8787/api/billing-portal \
  -X POST -H 'Content-Type: application/json' -d '{}'
```

Ask Grok (Free Peek: 1/day; then **402** paywall JSON):

```bash
curl -s -c /tmp/pr.jar -b /tmp/pr.jar http://localhost:8787/api/recommend \
  -H 'Content-Type: application/json' \
  -d '{"message":"sunset canyon with dark foreground","favorites":[]}'
```

## Build

```bash
npm run build
npm run preview
```

## Features

- Preset library cards (title, blurb, gear icons, key settings)
- **Ask Grok** — Free Peek 1/day; Pro unlimited; soft 402 paywall modal CTA
- Detail view: steps, tips, equipment, when-to-use, phone/advanced notes + AI reason banner
- Field checklist / step-by-step mode (Pro-gated; steps remain readable)
- Simulated camera dials for recommended settings
- Filter by technique tags + favorites
- Upgrade / Pricing modal (yearly highlighted + trial badge), Free/Pro badge, Manage billing
- `/success?session_id=` verify → httpOnly signed Pro cookie
- Dark photo-app aesthetic

## Deploy (Ubuntu + nginx + systemd)

Use `./deploy.sh` to build locally and publish to a remote Ubuntu host. nginx serves `dist/`; systemd runs the API on port **8787** with `/api` proxied.

```bash
chmod +x deploy.sh
DEPLOY_HOST=your.server.example ./deploy.sh
# or
./deploy.sh -H your.server.example -u ubuntu -p /var/www/photo-recipes -n your.server.example
```

| Variable / flag | Default | Meaning |
|-----------------|---------|---------|
| `DEPLOY_HOST` / `-H` | _(required)_ | SSH host |
| `DEPLOY_USER` / `-u` | `ubuntu` | SSH user |
| `DEPLOY_PATH` / `-p` | `/var/www/photo-recipes` | App directory on server |
| `DEPLOY_SSH_PORT` / `-P` | `22` | SSH port |
| `SERVER_NAME` / `-n` | `_` | nginx `server_name` |
| `--skip-build` | | Reuse existing `dist/` + `server-dist/` |
| `--dry-run` | | Print remote plan without applying |

**What gets synced:** `dist/`, `server-dist/`, `package.json`, `package-lock.json`, `deploy/` templates.  
**Never synced:** `.env`, `.env.*`, `node_modules`, `.git`, `src/`, `server/data/`.

### Server secrets

Create `/etc/photo-recipes.env` on the host (deploy creates an empty stub if missing):

```bash
sudo tee /etc/photo-recipes.env <<'ENV'
XAI_API_KEY=your_key_here
PORT=8787
PUBLIC_BASE_URL=https://your.domain
SESSION_SECRET=long-random-string
STRIPE_SECRET_KEY=sk_live_…
STRIPE_WEBHOOK_SECRET=whsec_…
# Optional pins (else auto-create on boot):
# STRIPE_PRICE_MONTHLY=price_…
# STRIPE_PRICE_YEARLY=price_…
ENV
sudo chmod 640 /etc/photo-recipes.env
sudo chown root:www-data /etc/photo-recipes.env
sudo systemctl restart photo-recipes
```

### Stripe webhook (production)

In [Stripe Dashboard → Webhooks](https://dashboard.stripe.com/webhooks), add endpoint:

```
https://YOUR_DOMAIN/api/stripe-webhook
```

Copy the signing secret into `STRIPE_WEBHOOK_SECRET`. Ensure nginx proxies `/api/` (including this path) to the Node service — do not buffer/rewrite the raw body.

### Remote services

- `photo-recipes.service` — `node server-dist/index.js` (EnvironmentFile=/etc/photo-recipes.env)
- nginx site `photo-recipes` — static SPA + `location /api/` → `http://127.0.0.1:8787`

```bash
sudo systemctl status photo-recipes
curl -s http://127.0.0.1:8787/api/health
```

Local production smoke test (after `npm run build`):

```bash
# load env then:
npm start   # API on :8787; use vite preview or any static server for dist/
```

## License / attribution

Educational personal-use transcription of book recipes. Not affiliated with the book’s publisher or author.
