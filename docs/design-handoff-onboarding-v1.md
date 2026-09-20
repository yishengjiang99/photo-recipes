# Grok Camera — iOS onboarding landing v1 (visuals only)

**Bundle:** `com.ragnus.mvp` · **Brand on screens:** Grok Camera (Photo Recipes product / darkroom language)  
**Ask:** Don’t open cold into the camera permission sheet.  
**Status:** Mock / flow only — no eng implementation until CoS + user review.  
**Mocks:** `assets/marketing/onboarding/`  
**Palette:** Neutral Graphite + Signal Amber (A).

---

## Flow (locked)

```
Landing → Carousel (3–4) → Get Started → Camera permission → Main Camera
                                                      ↘
                         AFTER first successful capture → Push permission (LATER)
```

- **Get Started** requests **camera only** (mic later, contextual with voice/scene note).  
- **Push** never on Get Started / landing / carousel.

See `07-flow-diagram.png`.

---

## Recommended copy

### Landing (prefer `01-landing-hero.png`; alt `01b`)
- Wordmark: **Grok Camera**  
- Value: **AI camera coach — shutter, ISO, focus**  
- Or slogan: **Set the shot. Then take it.**  
- Sub: Auto Optimize dials · field looks · teach why  
- Chrome: Swipe to continue

### Carousel
| # | Title | Body |
|---|-------|------|
| 1 | Auto Optimize | Point at the shot — we write shutter, ISO, EV, WB & focus. |
| 2 | Recommend & Looks | Get a recipe from the scene. Field looks are capture grades — not beauty filters. |
| 3 | Capture with confidence | See settings change, then press shutter. Teach explains why. |
| 4 (optional) | Scene note (optional) | Add a short note or dictate later — never required to start. |

**Mock caveat:** Card 3 illustration must not imply on-device aperture writes — coach-only for aperture/ND/tripod. Prefer shutter/ISO/EV chips in final art.

### Get Started (`06-get-started.png`)
- Line: **Ready when you are.**  
- CTA: **Get Started** (amber fill, dark label)  
- Micro: **We'll ask for Camera access next.**  
- No notification copy.

---

## Files

| File | Role |
|------|------|
| `01-landing-hero.png` | Landing A (recommended) |
| `01b-landing-alt.png` | Landing B |
| `02-carousel-auto-optimize.png` | Carousel 1 |
| `03-carousel-recommend-looks.png` | Carousel 2 |
| `04-carousel-shutter.png` | Carousel 3 |
| `05-carousel-scene-note.png` | Carousel 4 optional |
| `06-get-started.png` | Primary CTA |
| `07-flow-diagram.png` | Eng flow |

---

*Designer · onboarding mocks v1 · review before code*
