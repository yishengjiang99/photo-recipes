# Photo Recipes — Marketing Landing Handoff v2

**Audience:** High-end photography enthusiasts arriving from search / ads / share.  
**Goal:** Compelling conversion story — *point → Auto Optimize → trust dials → trial or waitlist* — without reading like a thin SaaS template.  
**Brand:** Darkroom field notes. Concrete. Quiet. Craft-first. **Not** filter / beauty AI / neon copilot.  
**Slogan (everywhere micro OK):** **Set the shot. Then take it.**  
**Elevator (north star):** *Point your phone at the shot — Photo Recipes Auto Optimizes shutter, ISO, and focus so you capture the technique, not fix it later.*  
**Voice/STT:** Secondary only — at most one quiet body/FAQ mention. Never hero, never H1/H2.  
**Tokens:** [`design-handoff-v1.md`](./design-handoff-v1.md) — `bg` `#0c0c0f`, `ink` `#f5f5f7`, `ink-secondary` `#c4c4cc`, `ink-tertiary` `#8b8b96`, `surface` `#16161c`, `border` `#2a2a33`, `accent` `#f43f5e`, `accent-soft` `#fb7185`, Instrument Serif + DM Sans.  
**Hero art:** [`assets/marketing/phones-duo-iphone-android-camera.png`](../assets/marketing/phones-duo-iphone-android-camera.png) (preferred) or [`iphone-duo-hero-web.png`](../assets/marketing/iphone-duo-hero-web.png).  
**Surfaces:** Live static `https://yishengjiang99.github.io/photo-recipes-site/` · in-app `/` (SEO) · app `/app`.  
**Supersedes:** [`design-handoff-landing-v1.md`](./design-handoff-landing-v1.md) for structure/copy locks. Keep v1 for archaeology.  
**Implementer:** Web Engineer. Backend waitlist: Resend segment + server `POST` (never expose API key in client).  
**Collaborators:** Marketing (keyword polish on meta/body; coordinate before changing locked H1) · Agentic Expert (status strings).

---

## 0. Why v2 (critique → fix)

| v1 / live feel | v2 fix |
|----------------|--------|
| Hero H1 clever but soft on *what it does* | Lock elevator-shaped H1: point phone → Auto Optimize shutter/ISO/focus |
| Thin “feature grid” without proof | Mid-page **dial moment**: before→after chips + status strip |
| No email capture | Premium **Get field notes** waitlist (Resend) |
| CTAs compete with GitHub / vague browse | Primary `Start free trial` · Secondary `Open Free Peek` · trust line under both |
| How-it-works lists steps but doesn’t sell apply | Show settable vs coach-only + live status examples |
| Pricing buried | Pricing band with Best value + trial CTA before FAQ |

**Conversion spine (keep in order):** Desire (hero) → Mechanism (how + dials) → Proof (recipe samples) → Offer (pricing) → Soft lead (waitlist) → Objections (FAQ) → Close (final CTA).

---

## 1. SEO / meta (draft — Marketing may refine)

| Field | Copy |
|-------|------|
| Title (~55–60) | `Photo Recipes — Auto Optimize shutter, ISO & focus` |
| Description (~155) | `Point your phone at the shot — Auto Optimize writes shutter, ISO, EV, WB, and focus for live capture. Field recipes · Free Peek · Pro trial.` |
| OG image | Duo phones asset; alt describes before→after shutter/ISO (never claim aperture write) |
| Canonical | Site env / `SITE_URL` |

**Keyword intent (natural, not stuffed):** camera settings app, auto optimize camera, photography recipes, shutter ISO focus, panning / HDR / depth of field settings, field photography checklist.

---

## 2. Page structure (top → bottom)

1. **Nav** (sticky)  
2. **Hero** — H1, elevator sub, dual CTA, trust, dual-phone  
3. **Proof strip** — one line of offer + settable chips (not logos)  
4. **How it works** — Sense → Reason → Apply → Verify → Capture + status examples  
5. **Dial moment** — before→after settings (hero conversion beat)  
6. **Settable vs coach-only** — honest capability callout  
7. **Recipe library teaser** — 3–4 technique cards → Open Free Peek  
8. **Pricing** — Free Peek vs Pro  
9. **Get field notes** — email waitlist (Resend)  
10. **FAQ** — accordion + JSON-LD  
11. **Final CTA band**  
12. **Footer**

**Layout:** Max content width **1040–1120px**. Section padding **80–112px** desktop · **56–72px** mobile. Soft rose radial only behind hero (`rgba(244,63,94,0.07)`). No purple orbs, chat bubbles, or mic-first chrome.

---

## 3. Nav

```
[mark] Photo Recipes     How  Recipes  Pricing  Notes     [Open Free Peek] [Start free trial]
```

| Element | Spec |
|---------|------|
| Sticky | `bg` @ 90% + `backdrop-blur`; `border-b` hairline |
| Links | `ink-secondary` → hover `ink`; anchors `#how` `#recipes` `#pricing` `#notes` |
| Open Free Peek | Ghost / ring; → `/app` |
| Start free trial | Accent filled `min-h-9` rounded-full; → paywall / Stripe / IAP path |
| Mobile | Keep **Start free trial** in bar; hamburger sheet for links + Free Peek |

---

## 4. Hero

### Layout

| Breakpoint | Structure |
|------------|-----------|
| ≥960px | 2-col: copy ~42% left · dual-phone ~58% right, vertically centered |
| &lt;960px | Copy → CTAs → trust → image full bleed below |

### Locked copy

| Slot | Text |
|------|------|
| Eyebrow | `Field technique · live capture` |
| **H1** (Instrument Serif) | `Point your phone at the shot — Auto Optimize shutter, ISO & focus` |
| Sub | `Photo Recipes writes exposure duration, ISO, EV, white balance, and focus on the live camera — so you capture the technique, not fix it later. Manual override anytime.` |
| Slogan line (optional under sub, `caption` italic) | `Set the shot. Then take it.` |
| Primary CTA | `Start free trial` |
| Secondary CTA | `Open Free Peek` |
| Trust | `Free Peek · 1 Auto Optimize/day · Pro $7.99/mo or $59.99/yr · 7-day trial` |

**Do not:** Lead with voice, “AI enhance,” filters, or GitHub.  
**Dual-phone alt:** `Photo Recipes on iPhone and Android — Auto Optimize camera with recipe dials.`

### Spacing
- H1: clamp ~2.15rem → 3.25rem, tracking tight, max ~14ch per visual line where possible  
- CTA gap: 12px; stack full-width buttons on &lt;400px  
- Image: radius `xl`, ring `border`, soft shadow — no chrome frames beyond art

---

## 5. Proof strip (under hero)

Single quiet row — not a logo farm:

```
[ Shutter ] [ ISO ] [ EV ] [ WB ] [ Focus ]   ·   zoom when available
```

- Chips: `surface` + `border`, `caption` / `sm`, accent label on first word  
- Optional trailing muted: `Coach-only: aperture · ND · tripod`  
- Desktop: centered horizontal · Mobile: wrap, left-aligned in content width

---

## 6. How it works (`#how`)

**H2:** `Sense. Reason. Apply. Verify. Shoot.`  
**Lead:** `One loop on the live viewfinder — status you can trust, dials you can override.`

| # | Title | Body | Status example |
|---|-------|------|----------------|
| 1 | Sense | Light, motion, subject — from the viewfinder note | `Reading light…` |
| 2 | Reason | Matches a field recipe; clamps to what the phone can set | `Matching a recipe…` |
| 3 | Apply | Writes shutter / ISO / EV / WB / focus | `Applying shutter & ISO…` |
| 4 | Verify | Soft pan ← → if you should reframe | `Checking exposure…` |
| 5 | Capture | You still press shutter | `Ready to capture` |

Cards: `surface`, radius `lg`, number in `accent-muted`. Icons line-weight only.  
Mobile: vertical stack · Desktop: 5-col or 3+2 wrap.

---

## 7. Dial moment (required conversion beat)

**Purpose:** Sell *agentic apply* visually — settings changed, not a filter preview.

**H2:** `Watch the dials move — then take the shot.`  
**Lead:** `Before → after chips show exactly what Auto Optimize wrote. Tap through Teach anytime.`

### Component: LandingDialProof

Desktop: 2-col — left faux viewfinder frame (static marketing crop or CSS mock) · right chip stack.  
Mobile: chips under a shorter viewfinder crop.

**Status pill (top of mock):** `Reading light…` → (static final) `Ready to capture`

**Before→after chips** (reuse agentic tokens `diff-before` / `diff-after`):

```
Shutter   1/500  →  1/60
ISO       100    →  400
EV        0      →  −0.3
WB        Auto   →  Daylight
Focus     Cont.  →  Locked
```

- Layout: each row = label + muted before + rose/ink after  
- Optional coach chip below (dashed border): `Coach-only · aperture f/8 · ND · tripod`  
- Micro: `Not a filter. Real capture settings.` (`caption` `ink-tertiary`)

**States:** Static for v2 ship is OK (no live camera on marketing). Prefer CSS/HTML chips over a heavy Lottie. If using a PNG, alt must name shutter/ISO/EV/WB/focus — never aperture-as-written.

**CTA under block:** Ghost `See how it works` → `#how` · or accent `Start free trial`.

---

## 8. Settable vs coach-only

Compact two-column callout (or single card with two lists):

| Agentic — we set on device | Coach-only guidance |
|----------------------------|---------------------|
| Shutter / exposure duration | Aperture |
| ISO | ND filter |
| EV bias | Tripod / support |
| White balance | |
| Focus lock / POI | |
| Zoom / lens when available | |

**H2:** `Honest about what the phone can write.`  
Keeps trust high for enthusiasts who hate fake aperture claims.

---

## 9. Recipe library teaser (`#recipes`)

**H2:** `Technique recipes, not LUTs.`  
**Lead:** `Panning, HDR, depth of field, motion — dials, steps, and teach-why tips.`

3–4 cards (link into `/app` presets when IDs exist):

| Title | One-liner |
|-------|-----------|
| Panning | Slow shutter + tracking cues — subject sharp, world streaks. |
| Depth of field | Focus strategy for front-to-back sharpness. |
| HDR / high contrast | Protect highlights; disciplined exposure targets. |
| Motion control | Freeze or blur on purpose — ISO and shutter paired. |

Footer of section: secondary `Open Free Peek` → `/app`.

---

## 10. Pricing (`#pricing`)

**H2:** `Free Peek vs Pro`  
Reuse paywall hierarchy; no Stripe error UI on marketing.

| | Free Peek | Pro |
|--|-----------|-----|
| Recipe library | Browse | Browse + checklists |
| Auto Optimize | 1 / day | Unlimited |
| Manual dials | — | Full |
| Teach mode | Teaser | Full |
| Price | $0 | **$59.99/yr** (Best value) · $7.99/mo |

- Mark yearly as Best value (accent outline badge)  
- Primary button on Pro card: `Start 7-day trial`  
- Micro: `Cancel anytime · Stripe on web · Apple IAP on iOS`

---

## 11. Get field notes — waitlist (`#notes`)

Premium email capture — **not** a spammy newsletter block.

### Positioning
- **Overline:** `Field notes`  
- **H2:** `Get field notes`  
- **Body:** `Occasional craft notes and launch updates — shutter discipline, not promo blasts. Unsubscribe anytime.`  
- **Promise line:** `No spam · No filter tips · Craft only`

### Layout
- Desktop: left copy (~45%) · right form card (`surface`, ring `border`, radius `xl`, padding 24–28)  
- Mobile: stack; form full width  
- Optional tiny mark / aperture glyph — quiet, not playful

### Form fields
| Field | Spec |
|-------|------|
| Email | Single input; `type=email`; placeholder `you@studio.email`; label visually hidden or floating |
| Submit | Accent filled: `Join the list` (or `Get field notes`) |
| Helper | `We’ll only use this for Photo Recipes field notes.` |

### States (required)

| State | UI |
|-------|-----|
| **Idle** | Email + submit enabled |
| **Loading** | Submit disabled; spinner or `Sending…`; input readonly |
| **Success** | Replace form with check + `You’re on the list.` + `We’ll write when it matters.` · optional secondary `Open Free Peek` |
| **Error (validation)** | Inline under input: `Enter a valid email.` · `aria-invalid` |
| **Error (server)** | Banner in card: `Couldn’t join right now. Try again.` · keep email value |
| **Duplicate** | Treat as soft success: `You’re already on the list.` |

### API / Resend (Web + Server)
- Client `POST` to app API (e.g. `/api/waitlist`) with `{ email }`  
- Server: Resend Contacts → segment `waitlist` or `field-notes` (create if missing)  
- Env: `RESEND_API_KEY` server-only  
- Idempotent on duplicate email  
- Rate-limit + honeypot optional  
- Never show raw Resend errors to users

### A11y
- Associate label/`aria-describedby` for errors  
- Focus success heading on success  
- Don’t clear email until success confirmed

---

## 12. FAQ

**H2:** `Questions before you head out.`  
Accordion; FAQPage JSON-LD.

1. **Is this an AI filter app?** No — field technique coach and camera settings app. Applies real capture settings, not filters after the shot.  
2. **What does Auto Optimize change?** Shutter / exposure duration, ISO, EV, white balance, focus (zoom when available). Aperture, ND, tripod stay coach-only.  
3. **What’s free?** Free Peek: browse recipes · ~1 Auto Optimize/day until Pro.  
4. **What’s in Pro?** Unlimited Auto Optimize, manual dials, Teach, checklists. $59.99/yr or $7.99/mo · 7-day trial.  
5. **iPhone and Android?** Designed for both; duo art shows Auto Optimize + dials.  
6. **Can I override the agent?** Yes — manual dials (Pro). Teach explains why.  
7. **Do I need an account?** Browse Free Peek without buying; Pro via Stripe (web) / IAP (iOS).  
8. **What are field notes?** Occasional craft emails — not a daily blast. Join via Get field notes.  
9. **Voice?** Optional dictate for a scene note — same apply path as Auto Optimize. (Only place voice leads; keep short.)  
10. **Publisher affiliation?** Educational presets inspired by field recipes — not affiliated with the publisher.

---

## 13. Final CTA band

Centered, generous padding:  
**H2:** `Go make the frame.`  
**Sub:** `Set the shot. Then take it.`  
Primary `Start free trial` · Secondary `Open Free Peek`  
Trust line same as hero.  
Optional tertiary text link: `Get field notes` → `#notes`.

---

## 14. Footer

```
[mark] Photo Recipes                     How · Recipes · Pricing · Notes · Privacy · Terms
Field presets for live capture           © year
Educational · Not affiliated with the publisher
```

Muted `ink-tertiary`. **No GitHub / Source button.**

---

## 15. Motion & a11y

- Section fades ≤200ms; respect `prefers-reduced-motion`  
- Focus rings: `accent-soft`  
- One H1; logical H2/H3  
- Hero image `fetchpriority="high"`; below-fold lazy  
- Contrast: body ≥ `ink-secondary` on `bg`  
- Dial proof: don’t rely on color alone for before→after (use → or “to”)

---

## 16. Analytics events (Web)

| Event | When |
|-------|------|
| `cta_trial_click` | Start free trial |
| `cta_peek_click` | Open Free Peek |
| `waitlist_submit` | Form submit attempt |
| `waitlist_success` / `waitlist_error` | API result |
| `pricing_view` | `#pricing` in view |
| `dial_proof_view` | Dial moment in view |

---

## 17. Web Engineer checklist

- [ ] Replace v1 section order with v2 spine on `/` (and sync static Pages site if still used)  
- [ ] Locked H1 + CTAs + trust line  
- [ ] Dial moment component with before→after chips (static OK)  
- [ ] Settable vs coach-only callout  
- [ ] Pricing band with Best value  
- [ ] `#notes` waitlist UI + all form states  
- [ ] Server Resend contact → segment; no key in client  
- [ ] Remove any GitHub CTA if reintroduced  
- [ ] FAQ accordion + JSON-LD  
- [ ] Meta / OG / canonical  
- [ ] Mobile: trial CTA sticky-available; form usable one-handed  
- [ ] Lighthouse SEO + a11y on mobile  

### Out of scope
- Blog CMS, cookie megabanner redesign, fake testimonials, App Store badge walls pre-listing, voice-led hero, aperture-as-written claims.

---

## 18. Optional mock references

If generating mocks, prioritize:

1. Hero desktop 1280 — H1 + dual CTA + duo phones  
2. Dial moment — before→after chip stack  
3. Get field notes card — idle + success states  
4. Mobile hero stack (390 width)

Attach under `assets/marketing/` when produced; not required to start Web implementation from this doc.

---

## 19. Definition of done

Handoff on `main` (or open PR). Web can implement without guessing spacing, copy locks, or waitlist states. CoS + Web Engineer notified with doc URL.

---

*Designer · marketing landing v2 · for Web Engineer · Resend waitlist included*
