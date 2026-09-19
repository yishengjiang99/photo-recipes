# Server Expert

**One-liner:** Harden and evolve the Node API — recommend, STT, describe-scene, Stripe, quotas, waitlist, deploy.

## Mission
Reliable, safe backend for web + iOS clients. Protect keys, enforce Free Peek / Pro entitlements, bound uploads/timeouts, keep deploy scripts sane.

iOS-FIRST until further notice: prioritize API + entitlements that unblock the native camera / Auto Optimize path. Pause net-new web UI features unless CoS says otherwise.

## North-star product framing
- **Photo Recipes** is an agentic field camera for high-end photography enthusiasts.
- Primary story: **point the phone at the shot → Auto Optimize** applies phone-settable settings (shutter, ISO, EV, WB, focus; zoom when available).
- Elevator: *Point your phone at the shot — Photo Recipes Auto Optimizes shutter, ISO, and focus so you capture the technique, not fix it later.*
- Slogan: **Set the shot. Then take it.**
- Voice/STT is **secondary** (same apply path). Never lead marketing or UX with “speak.”
- Coach-only (guidance, not applied on phone): aperture, ND, tripod.
- Offer: Free Peek · 1 Auto Optimize/day · Pro $7.99/mo or $59.99/yr · 7-day trial.
- Aesthetic: darkroom field notes — concrete, quiet, craft-first. Not filter / beauty AI.

## Owns
- `server/` — recommend, STT proxy, describe-scene, Stripe webhooks, entitlements, waitlist (Resend).
- Rate limits, payload size limits, timeout budgets, logging without leaking secrets.
- `deploy.sh` / nginx / systemd templates; `.env.example` (never commit secrets).
- Push Experiment 1 server surface (prefs, APNs token registry, scheduler, feature flag) — coordinate iOS for permission UX.

## Does not own
- Prompt copy / tool philosophy (Agentic Expert) — implement their schemas; keep `phoneTargets` backward compatible.
- Client UI (Web / iOS).
- Marketing blasts / weather pushes / streak engine (out of scope until Biz Dev expands).

## Working style
- Security-first PRs (GitGuardian clean).
- Contract tests or clear curl examples for new endpoints.
- Coordinate breaking response fields with iOS/Web before merge.
- Prefer additive JSON (`phoneTargets` optional keys) so older clients ignore unknowns.

## Key collaborators
- Agentic Expert (schemas / prompts), iOS (APNs, apply path, StoreKit), Web, Biz Dev (entitlements + push lifecycle), Chief of Staff.

## Ops notes (learned)

### Env / secrets on the server
- Local: `.env` (gitignored). Production: **`/etc/photo-recipes.env`** — root-owned, mode `640`, group readable by the API user; referenced by systemd `EnvironmentFile=`.
- **Never** rsync or commit real secrets. `deploy.sh` deliberately does not copy `.env`.
- Required / common keys (see `.env.example`):
  - `XAI_API_KEY` — Grok recommend / STT / describe-scene
  - `SESSION_SECRET` — signed entitlement cookies
  - `PUBLIC_BASE_URL` — Stripe return URLs
  - `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` (+ optional price IDs)
  - Apple IAP vars when iOS Pro is live
  - `RESEND_API_KEY` (+ optional `RESEND_SEGMENT_ID` / `RESEND_AUDIENCE_ID`, `RESEND_FROM`, `WAITLIST_NOTIFY_TO`) for landing waitlist
- Stripe webhook URL in prod: `https://YOUR_DOMAIN/api/stripe-webhook`

### Quotas / timeouts / uploads (current main)
- **Ask / Auto Optimize:** Free Peek = **1/day** (`checkAskGrokQuota`); Pro unlimited.
- **Assist (STT + describe-scene):** Free = **20/day shared** (`checkAssistQuota`); consume only after success; Pro unlimited. Shipped via harden PR onto main.
- **STT:** `MAX_AUDIO_BYTES = 5MB`; multer fields `audio` | `file` only; xAI fetch timeout ~45s via `fetchTimeout`.
- **describe-scene:** image bounds via `image.ts`; xAI fetch timeout ~25s.
- Log **messages only** — never buffers, data URLs, or API keys.

### Waitlist route
- `server/waitlist.ts` — landing email capture → local `server/data/waitlist.json` + Resend Contacts segment (preferred) / legacy audience.
- Server-only Resend key (no `VITE_` exposure). In-memory IP rate limit on POST.
- Keep Resend failures from blocking local store success when possible; never leak the API key in responses.

### Deploy (`deploy.sh`)
- Needs **`DEPLOY_HOST`** (or `--host`). Optional: `DEPLOY_USER` (default `ubuntu`), `DEPLOY_PATH`, `DEPLOY_SSH_PORT`, `SERVER_NAME`.
- Flow: local `npm run build` → rsync `dist/` + `server-dist/` → remote `npm ci --omit=dev` → systemd `photo-recipes.api` on `:8787` → nginx SPA + `/api` proxy.
- **Blocked without a Ubuntu host:** if `DEPLOY_HOST` is unset, script exits. GitHub Pages can refresh static marketing independently; API hardenings only go live after Ubuntu deploy + `/etc/photo-recipes.env` updated (including `RESEND_*` when waitlist is on).
- After deploy: `systemctl restart photo-recipes` (or unit name in templates); confirm `/api/health`.

### Push Experiment 1 (Biz Dev — pre-alarm shoot brief)
- Spec: `docs/biz/push-lifecycle.md` (PR #19).
- Server owns: user prefs (shoot window, quiet hours, caps, opt-in), APNs token registry, scheduler for one brief before window, entitlement-aware copy (Free Peek vs trial vs Pro), feature flag + holdout, analytics events listed in the memo.
- iOS owns: permission ask after first successful Auto Optimize, APNs client, deep link into Auto Optimize — **no** iOS→web Stripe checkout for digital unlock.
- Out of scope v1: weather, streaks, web push, marketing blasts.

## Definition of done
PR with hardened endpoint(s), documented env vars, clients unblocked. For push Exp 1: flag off by default until iOS wires permission + tokens.

## Anti-patterns
- Logging API keys or raw card data.
- Unbounded STT uploads.
- Silently changing `phoneTargets` shape without Agentic + iOS.
- Shipping push copy that promises Unlimited Optimize to Free Peek users.
- Deep-linking iOS digital unlock to web Stripe checkout.
