# Photo Recipes — SEO Landing Page Handoff v1

**Audience:** Photographers discovering the product via search / ads / App Store referral.  
**Brand:** Darkroom field notes + **agentic camera** (sense → reason → apply → verify → capture).  
**Not:** Filter / AI-magic editor / neon copilot SaaS.  
**Tokens:** Reuse [`design-handoff-v1.md`](./design-handoff-v1.md) (`bg` `#0c0c0f`, `ink`, `ink-secondary`, `accent` `#f43f5e`, Instrument Serif + DM Sans).  
**Hero art:** [`assets/marketing/phones-duo-iphone-android-camera.png`](../assets/marketing/phones-duo-iphone-android-camera.png) or [`iphone-duo-hero-web.png`](../assets/marketing/iphone-duo-hero-web.png) — see phones / duo handoffs.  
**Implementer:** Web Engineer (Vite+React marketing route or static landing).

---

## 0. SEO / IA goals

| Goal | Design implication |
|------|-------------------|
| Rank for “photography field presets”, “camera auto optimize”, “depth of field recipe” | H1 + first paragraph carry real keywords; FAQ schema-ready |
| Convert to Free Peek / trial | One primary CTA pattern sitewide: **rose filled** |
| Clarify agentic ≠ filters | Hero + features say “applies real camera settings” |
| Mobile-first LCP | Hero image lazy-priority; fonts subset; no heavy video above fold |

**Suggested route:** `/` marketing landing · CTA into app `/app` or `/library` (existing).  
**Meta (draft):**  
- Title: `Photo Recipes — Agentic camera coach for real field settings`  
- Description: `Sense the scene, apply a photography recipe to your camera, and shoot with dials, steps, and checklists. Free Peek · Pro trial.`

---

## 1. Page structure (top → bottom)

1. **Nav**  
2. **Hero** (H1 + sub + CTAs + dual-phone)  
3. **Logo / trust strip** (optional, light)  
4. **How it works** (3–4 steps: Sense → Apply → Verify → Capture)  
5. **Features** (grid)  
6. **Dual-phone / product deep-dive** (alternate layout)  
7. **Pricing teaser**  
8. **FAQ**  
9. **Final CTA band**  
10. **Footer**

Max content width: **1040–1120px**. Section vertical rhythm: 64–96px desktop · 48–64 mobile. Background `#0c0c0f` throughout; optional soft rose radial behind hero only (`rgba(244,63,94,0.08)`).

---

## 2. Nav

```
[mark] Photo Recipes          Library  How it works  Pricing  FAQ     [Open app] [Start free trial]
```

- Sticky; `bg` @ 90% + blur optional.  
- `Open app` = outline / ghost.  
- `Start free trial` = accent filled (sm).  
- Mobile: hamburger → sheet; keep trial CTA visible in bar.

---

## 3. Hero

### Layout
| Breakpoint | Structure |
|------------|-----------|
| Desktop ≥960 | 2-col: copy left (~42%) · dual-phone art right (~58%) |
| Mobile | Copy stack → dual-phone image full width below CTAs |

### Copy (lock for v1)
- **Eyebrow:** `Field technique · live capture` (`overline`, `ink-tertiary`)  
- **H1 (serif `display-xl`):** `Recipes that set your camera — not just your mood.`  
- **Sub (`body` `ink-secondary`):** `Photo Recipes senses the scene, picks a field recipe, applies real dials, and coaches you to the shot. Agentic optimize. Manual override anytime.`  
- **Primary CTA:** `Start free trial` → paywall / Store / signup  
- **Secondary CTA:** `Browse Free Peek` → library (ghost/outline)  
- **Micro:** `7-day trial · Free Peek to browse · Cancel anytime` (`caption`)

### Dual-phone
- Use marketing asset (iPhone + Android Camera with Auto Optimize / pan cues preferred for “agentic” story; iPhone duo detail OK as alt).  
- Alt text: `Photo Recipes on iPhone and Android — Auto Optimize camera and recipe dials.`  
- No floating purple orbs / chat bubbles around devices.

---

## 4. How it works

**Section H2 (serif):** `Sense. Apply. Verify. Shoot.`

Four equal cards (`surface`, `border`, radius `lg`) or numbered horizontal steps:

| # | Title | Body |
|---|-------|------|
| 1 | Sense | Light, motion, and your scene note (viewfinder caption, voice, or type). |
| 2 | Reason | Matches a field recipe and clamps to what your lens can do. |
| 3 | Apply | Writes MODE / aperture / shutter / ISO — before→after chips you can trust. |
| 4 | Verify | Soft pan cues if you need to reframe; then you’re ready to capture. |

Keep icons line-weight, white/rose — **not** 3D AI mascots.

---

## 5. Features grid

**H2:** `Built for the field, not the feed.`

3×2 desktop · 1-col mobile. Each card: small overline + title + 2-line body.

| Feature | Point |
|---------|--------|
| Auto Optimize | One CTA runs the agent loop on the live viewfinder. |
| Recipe dials | Educational + live — aperture rings you can override. |
| Direction cues | Quiet left/right chevrons when you should pan — not a game HUD. |
| Voice + viewfinder note | Dictate or prefills from `From viewfinder`; always editable. |
| Ask / Photo Vision | Coach into a recipe when you’re stuck (quota on Free Peek). |
| Soft Pro funnel | Browse free; unlock unlimited optimize, manuals, checklists. |

---

## 6. Dual-phone deep-dive (mid page)

Full-bleed dark band; centered dual-phone again OR split:

- Left: still of Camera + `Auto Optimize` + status `Reading light…`  
- Right: bullets “Before → after settings”, “Teach mode: why this recipe”, “Manual override drawer”

**H2:** `An agent on your shoulder — dials you still control.`

---

## 7. Pricing teaser

Reuse paywall hierarchy (no Stripe error UI):

- Free Peek: browse recipes · 1 agent/Ask run per day (align with product)  
- Pro: unlimited Auto Optimize · manual dials · checklists · trial  
- Prices: **$59.99/yr** (Best value, primary button) · $7.99/mo  

**CTA:** `Start 7-day trial` (accent). Link `Compare plans` → anchor `#pricing` or modal.

---

## 8. FAQ (SEO)

**H2:** `Questions before you head out.`

Accordion (`border` hairlines). Markup with FAQPage JSON-LD (Web Engineer).

Draft Q&As:

1. **Is this an AI filter app?** No — it’s a field technique coach that applies **camera settings** and recipes for real capture.  
2. **What does Auto Optimize do?** Sense → match a recipe → apply dials → verify (with optional pan cues) → you shoot.  
3. **What’s free?** Browse the recipe library (Free Peek). Agent runs and advanced manuals are limited until Pro.  
4. **iPhone and Android?** Designed for both; see multi-phone handoff.  
5. **Can I override the agent?** Yes — manual dials drawer (Pro); teach mode explains why.  
6. **Is it affiliated with the book publisher?** Educational presets inspired by field recipes — not affiliated with the publisher.

---

## 9. Final CTA band

Centered, more padding:  
**H2:** `Go make the frame.`  
Primary `Start free trial` · Secondary `Open Free Peek`  
Same micro trust line as hero.

---

## 10. Footer

```
Photo Recipes                          Privacy  Terms  Contact
Field presets for live capture         © year
Educational · Not affiliated with the publisher
```

Links muted `ink-tertiary`; mark + wordmark left. No dense link farms.

---

## 11. Motion & a11y

- Prefer CSS fade/slide &lt; 200ms; respect `prefers-reduced-motion`.  
- Focus rings: `accent-soft`.  
- Contrast: body ≥ `ink-secondary` on `bg`.  
- Hero image `fetchpriority="high"`; below-fold images lazy.

---

## 12. Web Engineer checklist

- [ ] Route + semantic landmarks (`header` `main` `section` `footer`)  
- [ ] H1 once; logical heading order  
- [ ] Wire CTAs to app + checkout/trial  
- [ ] Dual-phone assets from `assets/marketing/` (responsive `srcset`)  
- [ ] FAQ accordion + JSON-LD  
- [ ] Meta title/description/OG image (use duo hero)  
- [ ] Tokens match `@theme` / handoff v1  
- [ ] Lighthouse SEO + a11y pass on mobile

### Out of scope
- Blog CMS, localized SEO clusters, cookie megabanner redesign  

---

*Designer · SEO landing v1 · for Web Engineer*
