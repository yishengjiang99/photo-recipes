# Photo Recipes — SEO Landing Page Brief (Web Engineer)

**Goal:** Organic + paid landing that ranks for enthusiast camera-settings intent and converts to **first Auto Optimize** (or Ask on web) → trial.
**Audience / ICP:** High-end photography enthusiasts — serious hobbyists / enthusiasts with real cameras who use the phone as a companion field tool. Not casual filter users.
**Tone:** Precise, craft-forward, field technique — Darkroom field notes. Never beauty/AI-magic hype.
**Slogan:** **Set the shot. Then take it.** (marketing; Sense → Reason → Apply → Verify → Capture stays in How it works only.)

## URL / IA suggestions
- Primary: `/` or `/auto-optimize`
- Supporting SEO pages later: `/recipes/panning`, `/recipes/hdr`, `/camera-settings-for-landscape`, `/shutter-iso-focus-phone` (programmatic later)

## Meta
- **Title (~55–60):** Photo Recipes — Agentic Shutter, ISO & Focus Settings
- **Meta description (~150–160):** Point your phone at the shot — Auto Optimize sets shutter, ISO, and focus from the viewfinder. Capture the technique, not fix later. Free Peek · 1/day.
- **OG title/description:** same; OG image = viewfinder + before/after shutter/ISO/EV/WB/focus dials (not fake aperture)

## Hero
- **Elevator / primary one-liner:** Point your phone at the shot — Photo Recipes Auto Optimizes shutter, ISO, and focus so you capture the technique, not fix it later.
- **H1:** Point your phone at the shot — Auto Optimize shutter, ISO & focus
- **Subhead:** From viewfinder, Auto Optimize writes exposure duration, ISO, EV bias, white balance, and focus lock/POI on the live camera (zoom/lens when the device allows). Aperture, ND, and tripod stay coach guidance. Pan cues when you need to reframe. Teach mode shows why. Set the shot. Then take it.
- **Primary CTA:** Start Auto Optimize free
- **Secondary CTA:** Browse the recipe library
- **Trust/offer line:** Free Peek · 1 Auto Optimize/day · Pro from $7.99/mo · $59.99/yr · 7-day trial · iOS IAP

## Page sections (in order)
1. **Hero** (above — elevator leads)
2. **How Auto Optimize works** — 5 steps: Sense → Reason (recipe tools) → Apply → Verify → Capture. Show status copy examples (Reading light… / Ready to capture). Explicitly list **settable vs coach-only** (see below). Marketing slogan remains **Set the shot. Then take it.**
3. **Skill library** — recipe cards (panning, motion control, HDR, focus discipline, low angle). CTA: Open library
4. **From viewfinder Auto Optimize** — lead with live-preview scene note / From viewfinder; optional voice dictate as a quiet secondary line only (once on page)
5. **Direction cues** — soft pan L/R (up/down) chevrons while optimizing
6. **Teach mode** — Why this? short bullets naming which dials moved
7. **Free Peek vs Pro** — comparison table matching iOS entitlements (note: web may use Ask/Vision; iOS emphasizes Auto Optimize — be honest per surface)
8. **Social proof / empty** — placeholder for quotes later (enthusiast shooters, not filter users)
9. **FAQ**
10. **Final CTA** — Start free · See pricing

### How it works — settable vs coach-only (required callout)

**Agentic — we set on the live camera**
- Shutter / exposure duration
- ISO
- EV bias
- White balance
- Focus (lock / POI)
- Zoom / lens when the device allows

**Coach-only (guidance; say so briefly)**
- Aperture
- ND filter
- Tripod / support

## FAQ (copy)
Q: Is this Lightroom or a preset pack?
A: No. Photo Recipes helps high-end photography enthusiasts set the camera for the shot — recipes and Auto Optimize — not edit filters afterward.

Q: What do you actually change on the device?
A: Auto Optimize agentically sets shutter / exposure duration, ISO, EV bias, white balance, and focus lock/POI on the live camera, plus zoom/lens when the device allows. Aperture, ND filters, and tripod stay coach-only guidance — we don’t fake aperture writes.

Q: Does Auto Optimize “AI enhance” my photo?
A: No beauty filters or fake skies. It senses the scene, picks a technique recipe, and applies capture settings the phone can actually write (shutter, ISO, EV, WB, focus). Precise field technique — not AI magic.

Q: What’s free?
A: Browse the recipe library anytime. Free Peek includes 1 Auto Optimize per day (iOS). Pro unlocks unlimited optimize, manual dials, full Teach mode, and interactive checklists. Pricing: $7.99/mo or $59.99/yr · 7-day trial · Apple IAP on iOS.

Q: Do I need to type a scene note?
A: Usually From viewfinder is enough — the agent uses what you’re aiming at. Optional voice dictate is available if you prefer a short spoken note.

Q: Do I need an account?
A: Soft launch uses a guest session; Pro is via Apple IAP on iOS (Stripe on web).

Q: What are pan cues?
A: While optimizing, the agent may nudge you to pan left/right (or up/down) to improve the frame before you shoot.

Q: Who is this for?
A: High-end photography enthusiasts — serious hobbyists with real cameras who use the phone as a companion in the field. Not casual filter shoppers.

## Keyword targets
**Primary:** agentic camera settings, shutter ISO focus app, auto optimize camera settings, photography recipes for enthusiasts, EV bias white balance phone, focus lock photography, landscape photography settings, panning photography settings, HDR camera settings, from viewfinder camera settings
**Secondary:** teach mode photography, viewfinder camera assistant, photography skill library, motion blur settings, what shutter ISO for sunset, phone camera companion for enthusiasts
**Support long-tails for future pages:** camera settings for waterfall, how to pan with a camera, front to back sharpness settings, phone shutter speed for landscapes

**ICP note for SEO/copy:** Prefer “enthusiast,” “serious hobbyist,” “field technique,” “camera settings,” “shutter/ISO/focus,” “From viewfinder” over “filters,” “enhance,” “beautify,” voice-first hooks, or casual social-photo language. Voice is not a primary keyword target.

## On-page SEO checklist for Web Engineer
- One H1; H2s per section; recipe names in H3s where relevant
- Hero uses elevator one-liner; From viewfinder leads section 4
- Settable vs coach-only callout visible without burying in FAQ
- Internal links to recipe detail routes
- FAQ schema (JSON-LD) including “What do you actually change?”
- Fast LCP; CTA above fold on mobile
- Accessible dials imagery with alt text describing before→after shutter/ISO/EV/WB/focus (never claim aperture was written)
- Canonical + OG tags
- Do not stuff “AI” in title; one honest mention in FAQ/body max
- Voice at most once in body or FAQ — not in H1/H2 or hero

## Conversion events to wire
- CTA click Start Auto Optimize / Browse library
- First Auto Optimize complete (or web Ask)
- Paywall view / trial start / subscribe

## Copy bank — micro
- Status examples: Reading light… / Matching a recipe… / Applying shutter & ISO… / Locking focus… / Ready to capture
- Chip: From viewfinder
- Button: Auto Optimize · Teach me why
- Slogan: Set the shot. Then take it.
- Coach chip (optional): Coach-only: aperture · ND · tripod

## Out of scope for v1 landing
- Fake testimonials, App Store badge walls before listing is live, Lightroom comparison tables that read as competitor ads, beauty/filter positioning, implying on-device aperture writes, voice-led hero or section headlines.

---

## Implementer note (feat/seo-marketing-landing)

Web Engineer followed **Designer** [`docs/design-handoff-landing-v1.md`](../design-handoff-landing-v1.md) for locked hero (H1 / eyebrow / CTAs), page structure, and FAQ skeleton.

Marketing keywords from this brief are woven into **meta title/description**, feature bodies, how-it-works, and FAQ answers — without replacing Designer’s locked H1.

**Shipped routes:** `/` landing · `/app` library · `/app/preset/:id` · `/app/success`  
**TestFlight / store URL:** placeholder `#testflight` in `src/lib/site.ts` (`TESTFLIGHT_URL`) until a real link exists.  
**Canonical domain:** `import.meta.env.VITE_SITE_URL` or default in `src/lib/site.ts`.

Marketing may replace body/FAQ/meta later; coordinate with Design before changing locked H1.
