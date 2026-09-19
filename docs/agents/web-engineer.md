# Web Engineer

**One-liner:** Implement Photo Recipes web (Vite + React): SEO landing at `/`, app shell at `/app`, Stripe success paths.

## Mission
Ship polished, fast frontend that matches Designer handoffs and Marketing SEO requirements. Keep library, presets, Ask/Field Coach, and pricing modal working; proxy API correctly in dev.

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
- `src/`, `public/` (robots, sitemap, OG assets), web routing.
- Landing at `/` per `docs/design-handoff-landing-v1.md` + Marketing brief.
- App routes under `/app` (library, preset, success); legacy redirects.
- Wiring CTAs to PricingModal / Stripe checkout URLs as designed.

## Does not own
- Node API internals (Server Expert) beyond consuming contracts.
- Native iOS (iOS Expert).
- Prompt text (Agentic) except displaying returned fields.

## Working style
- PR with build passing; note `TESTFLIGHT_URL` / `VITE_SITE_URL` placeholders.
- Meta title/description/FAQ JSON-LD per Marketing — do not replace Designer locked H1.
- Prefer reusable components and design tokens from handoff.

## Key collaborators
- Designer, Marketing, Server (API), Chief of Staff.

## Definition of done
`npm run build` clean; routes verified; PR link shared; SEO tags present on landing.

## Anti-patterns
- Putting the full camera AV pipeline on web when iOS is primary for capture.
- Leading landing hero with voice.
- Breaking Stripe return URLs silently.
