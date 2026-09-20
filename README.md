# Photo Recipes — iOS Field Camera

A native iOS camera app that turns a pocket field guide into live camera settings. Photo Recipes bundles five classic photography recipes, then uses on-device intelligence + Grok vision to **set exposure, focus, white balance, and zoom** on a real AVFoundation camera session.

Built for photographers who want the recipe *and* the dial position.

- **Camera-first:** the viewfinder is the home screen.
- **Auto Optimize:** one tap analyzes the scene and applies the best recipe locally, with an optional cloud refine.
- **Ask Grok / Photo Vision:** describe a scene or show the camera a photo and get a coached recommendation.
- **Pro:** manual A/S/M dials, apply recipe to live settings, full teach mode, and interactive field checklists.

> **iOS:** Pro is unlocked through **App Store subscriptions only** (StoreKit 2). No Stripe checkout inside the app.
> Web users can subscribe via Stripe on the companion web app.

## Download / TestFlight

The iOS app is the primary product. The repo contains the full Xcode project under [`ios/`](./ios/).

| | |
|---|---|
| Project | `cd ios && open PhotoRecipes.xcodeproj` |
| Platform | iOS 17+ |
| Bundle ID | `com.ragnus.mvp` |
| TestFlight | Run the **iOS TestFlight** GitHub Action, or archive locally with team `83D36RPMUM` |

Full App Store Connect setup, local StoreKit testing, and TestFlight checklist: **[ios/README.md](./ios/README.md)**.

## What it does

1. **Browse recipes** — five faithful presets transcribed from a “30 Recipes” photography book.
2. **Auto Optimize** — tap the pill above the shutter; the app senses the scene, picks the best recipe, and applies phone-friendly targets (shutter, ISO, EV, WB, focus, zoom, torch/flash).
3. **Recommend a recipe** — describe the scene or pick a photo; Grok returns the best recipe plus coaching.
4. **Shoot** — full-bleed live viewfinder with edge-to-edge overlays, pan cues, and a shutter that saves to Camera Roll.
5. **Learn** — each recipe includes steps, tips, gear, phone/advanced notes, and a “Why this?” teach sheet.

## Free Peek vs Photo Recipes Pro

| Feature | Free Peek | Pro |
|---|---|---|
| Live viewfinder + shutter → Camera Roll | ✓ | ✓ |
| Auto mode capture | ✓ | ✓ |
| Read-only recipe dials / pan cues | ✓ | ✓ |
| Auto Optimize Pass 1 (local, instant) | ✓ | ✓ |
| Auto Optimize Pass 2 (cloud refine) | 5 / day combined with Ask/Vision | Unlimited |
| Ask Grok / Photo Vision | 5 combined / day | Unlimited |
| Apply recipe → live exposure/focus/WB | — | ✓ |
| Manual A/S/M dials | — | ✓ |
| Full Teach mode | teaser | full |
| Interactive field checklist | — | ✓ |

**Pricing**

| Plan | Product ID | Price | Trial |
|---|---|---|---|
| **Yearly (primary CTA)** | `com.ragnus.mvp.pro.yearly` | **$59.99/yr** | 7-day free |
| Monthly | `com.ragnus.mvp.pro.monthly` | $7.99/mo | 7-day free |

## The five recipes

| Page | Recipe | Tags |
|------|--------|------|
| 28 | Sharp from Front to Back | Depth of field |
| 30 | How to Blur Moving Subjects | Motion (day / night sub-settings) |
| 32 | Keep a Moving Subject Sharp, With Motion Blur in the Background | Motion (panning + advanced flash) |
| 40 | Shake Up Your Perspective by Getting Down Low | Composition |
| 44 | Capture all the Brights and Darks With HDR | HDR (phone + camera methods) |

Preset data lives in `src/data/presets.ts` and is mirrored in `ios/PhotoRecipes/Data/BundledPresets.swift`.

## Repo layout

```
ios/                  # SwiftUI iOS app (primary)
  PhotoRecipes.xcodeproj
  PhotoRecipes/
    PhotoRecipesApp.swift
    MainTabView.swift
    Features/Camera/        # viewfinder, dials, Auto Optimize, teach sheet
    Services/               # CameraSession, LocalAutoOptimizeEngine, APIClient
    Resources/Info.plist    # camera / photo library / microphone permissions
src/                  # Vite + React 19 web app (companion)
server/               # Express API (Grok, Stripe web, IAP verify, telemetry)
deploy/               # nginx + systemd templates
docs/                 # design handoffs and telemetry docs
```

## Web companion

The same recipes and subscription tiers are also available as a mobile-friendly web app. Web Pro is handled through Stripe Checkout; iOS Pro is handled through StoreKit 2.

```bash
cd /workspace/photo-recipes
npm install
npm run dev:all
```

- Web: [http://localhost:5173](http://localhost:5173)
- API: [http://localhost:8787](http://localhost:8787)

Build and deploy details, API examples, and server secrets are preserved in the sections below for operators and contributors.

## Stack

- **iOS:** SwiftUI, AVFoundation, StoreKit 2, Vision
- **Web:** Vite + React 19 + TypeScript + Tailwind CSS v4
- **API:** Express + tsx with xAI Grok tool-calling (text + vision)
- **Billing:** Stripe Checkout (web) + StoreKit 2 IAP (iOS)
- **State:** `UserDefaults` on iOS; `localStorage` on web; `server/data/entitlements.json` for server-side quota

## Telemetry & App Privacy

In-house MySQL funnel analytics (`POST /api/telemetry`) — **no** TelemetryDeck/Sentry/session replay. Events are allowlisted; props never include photos or PII. Analytics are anonymized (`anon_id`). See [`docs/telemetry.md`](./docs/telemetry.md) and [`docs/telemetry-funnels.md`](./docs/telemetry-funnels.md).

Configure `MYSQL_*` + optional `TELEMETRY_READ_KEY` in `.env` / `/etc/photo-recipes.env`. The app builds and runs when MySQL is unset.

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

## Build

```bash
npm run build
npm run preview
```

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

## Example API calls

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

Ask Grok (Free Peek: 5 combined Ask/Photo Vision per day (env `FREE_DAILY_LIMIT`); then **402** paywall JSON):

```bash
curl -s -c /tmp/pr.jar -b /tmp/pr.jar http://localhost:8787/api/recommend \
  -H 'Content-Type: application/json' \
  -d '{"message":"sunset canyon with dark foreground","favorites":[]}'
```

Photo Vision — JSON with base64 / data URL (client compresses to JPEG ~1280px first):

```bash
# tiny 1×1 jpeg as a smoke test (replace with a real scene photo)
IMG=$(python3 -c "import base64; print('data:image/jpeg;base64,'+base64.b64encode(open('/path/to/scene.jpg','rb').read()).decode())")
curl -s -c /tmp/pr.jar -b /tmp/pr.jar http://localhost:8787/api/recommend \
  -H 'Content-Type: application/json' \
  -d "{\"message\":\"keep the subject sharp\",\"image\":\"$IMG\"}"
```

Photo Vision — multipart:

```bash
curl -s -c /tmp/pr.jar -b /tmp/pr.jar http://localhost:8787/api/recommend \
  -F 'image=@./scene.jpg;type=image/jpeg' \
  -F 'message=want silky water'
```

Vision uses **grok-4.6** (image + tools), falling back to `grok-4` if a model id is unavailable. MIME allowlist: `image/jpeg|png|webp` (max ~4MB). JPEG EXIF is stripped server-side; never log image bytes.

## License / attribution

Educational personal-use transcription of book recipes. Not affiliated with the book’s publisher or author.

## iOS details

For build instructions, architecture, IAP verify, push/deep-link setup, and the TestFlight device test plan, see **[ios/README.md](./ios/README.md)**.
