# Photo Recipes — iPhone Duo Marketing Handoff v1

**Brand:** Darkroom field notes — quiet near-black ground (`#0c0c0f`), rose accent `#f43f5e` sparingly, serif display + sans UI, **no neon AI chrome**.  
**Related:** [`design-handoff-camera-v1.md`](./design-handoff-camera-v1.md) · [`design-handoff-agentic-v1.md`](./design-handoff-agentic-v1.md) · [`design-handoff-voice-v1.md`](./design-handoff-voice-v1.md)

---

## 1. Duo composition (story)

Two phones, one product story: **sense/optimize → craft recipe**.

| | **Phone A — Camera** | **Phone B — Recipe detail** |
|--|----------------------|-----------------------------|
| Role | Live capture + agent | Field technique payoff |
| Must show | Viewfinder; scene field; **`From viewfinder` chip**; **mic**; status e.g. `Reading light…`; **Auto Optimize** rose CTA; shutter (white ring + rose core); dials affordance | Serif recipe title (e.g. *Sharp from Front to Back*); category pill (DEPTH OF FIELD); **four circular dials**; STEPS; tips callout; checklist |
| Must not show | Chat threads, purple glow, tone-curve / filter sliders | Marketing sparkle overload, “AI magic” badges |

**Hardware:** Modern iPhone, dark titanium / black, Dynamic Island OK, slight inward angle (~6–10°), soft ground reflection optional.  
**Ground:** Flat `#0c0c0f` or neutral charcoal; soft vignette OK; no marble/wood lifestyle table unless a separate lifestyle set.

**Hierarchy:** Auto Optimize is the only large filled rose control on Phone A; Phone B uses rose for category / step numerals only.

---

## 2. Layout & safe margins

### Pair frame (master marketing canvas)
- **Target export:** `1320 × 2868` px @1x (tall pair poster — phones stacked or side-by-side with large vertical margin).  
- **Alternate landscape hero:** `2400 × 1350` (≈16:9 web) or native generated 16:9 master.  
- **Side-by-side safe margins:** ≥ 6% canvas width left/right; ≥ 8% top/bottom; gap between phones ≥ 4% width.  
- **Do not** crop Dynamic Island or home indicator; keep ≥ 24px padding inside device bezels for UI (already in screen mock).

### App Store screenshot slot (single device crop)
If store requires one phone: prefer **Phone A** for “Auto Optimize” capability shot, **Phone B** for “Recipes / dials” shot — export each device frame separately in a follow-up if needed.

---

## 3. Export sizes & variants

| Asset | Size / ratio | Use |
|-------|----------------|-----|
| `assets/marketing/iphone-duo-hero-web.png` | 16:9 master | Web landing hero, Twitter/X, docs |
| `assets/marketing/iphone-duo-appstore.png` | 3:4 master | App Store / vertical ads |
| `assets/marketing/iphone-duo-appstore-portrait-alt.png` | 9:16 exploratory | **Alternate only** — drifted UI; do not use as source of truth |
| Pair poster target | **1320 × 2868** @1x | Center master on `#0c0c0f`; letterbox/pillarbox as needed |
| Web hero target | **2400 × 1350** | Upscale/crop from 16:9 master |

**Color:** sRGB. Prefer PNG for UI sharpness; JPEG OK for social if compressed carefully.

---

## 4. Asset paths (repo)

```
assets/marketing/
  iphone-duo-hero-web.png           # primary landscape duo (Camera + Detail)
  iphone-duo-appstore.png           # primary vertical duo (aligned to handoffs)
  iphone-duo-appstore-portrait-alt.png  # non-canonical alt — ignore for brand QA
  README.md
```

Regenerate from this handoff if product UI drifts (Field Coach / voice / agent status copy).

---

## 5. Copy lock (on-device, for regenerations)

**Phone A**
- Scene example: `Sunset light in a narrow canyon`
- Chip: `From viewfinder`
- Status: `Reading light…`
- CTA: `Auto Optimize`

**Phone B**
- Title: `Sharp from Front to Back`
- Tag: `DEPTH OF FIELD`
- Dials: MODE `A / Av` · APERTURE `f/11` · SHUTTER `auto` · ISO `auto` (or `as needed`)

---

## 6. QA checklist

- [ ] Rose accent only on CTAs / tags — no dual neon glows  
- [ ] Mic + From viewfinder visible on Camera phone  
- [ ] Dials (not filter sliders) on Detail phone  
- [ ] Background near-black, quiet  
- [ ] Both devices fully inside safe margins  
- [ ] Filename + path committed under `assets/marketing/`

---

*Designer · iPhone duo marketing v1*


---

## Addendum — iPhone + Android duo

For platform breadth, pair iPhone + **regular Android** (thicker bezels). Spec: **[`design-handoff-phones-v1.md`](./design-handoff-phones-v1.md)** §4. Assets: `assets/marketing/phones-duo-iphone-android-camera.png`.
