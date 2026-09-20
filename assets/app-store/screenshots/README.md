# App Store screenshots

Darkroom App Store screenshot exports for Grepawk Photos / Photo Recipes.

## Primary set (dial-change / AO apply) — interim MOCK

**Status:** Interim **MOCK** HTML/Playwright exports (Build 7 decluttered chrome + dial deltas). Prefer real device stills before ASC final upload when available. Marketing owns ASC upload.

**Signal Amber (Palette A):** `#E0A812` (from `ios/PhotoRecipes/Theme.swift`).

### Sizes

- iPhone 6.7": **1290 × 2796**
- iPhone 6.1": **1179 × 2556**

### Files + locked ASC captions

| File | Frame | Caption (Marketing lock) |
| --- | --- | --- |
| `iphone-67-01-dial-burst.png` / `iphone-61-01-dial-burst.png` | 1 HERO — dial burst mid-apply | Auto Optimize writes shutter, ISO, EV, WB & focus |
| `iphone-67-02-ao-cta.png` / `iphone-61-02-ao-cta.png` | 2 AO CTA + live apply | Point → Auto Optimize applies shutter, ISO, EV, WB, focus |
| `iphone-67-03-recipe-dials.png` / `iphone-61-03-recipe-dials.png` | 3 Recipe dials / Teach | See shutter · ISO · EV · WB · focus — then override |
| `iphone-67-04-field-look.png` / `iphone-61-04-field-look.png` | 4 Field look chip | Look grade + shutter/ISO/EV/WB/focus on the viewfinder |
| `iphone-67-05-ready-pan.png` / `iphone-61-05-ready-pan.png` | 5 Ready + pan (nice-to-have) | Ready — shutter, ISO, focus set · then take it |

Frames **1–4 required** for ASC; frame **5** optional. Every frame 1–4 shows **Shutter, ISO, EV, WB, Focus** before→after deltas (no aperture-as-applied; no beauty/filter photo B/A).

### Source

- Generators: `assets/ads/app-store-dial-v1/frame.html` + `export.mjs`
- Viewfinder still: `assets/ads/app-store-dial-v1/assets/viewfinder-scene.jpg` (shared elevator scene)
- UI fidelity: Build 7 ApplyBurstBanner / BeforeAfterChip / LookChip; decluttered finder (··· overflow only, no Library/Coach/Settings tab bar)

---

## Superseded static set (6.5" / 6.7")

Earlier static chrome stills (PR #45). **Superseded for ASC** by the dial-change MOCK set above when Marketing uploads the new frames. Kept for reference:

| File | Theme |
| --- | --- |
| `iphone-67-01-auto-optimize.png` … `iphone-67-04-pan-cue.png` | Static AO / dials / looks / pan |
| `iphone-65-01-auto-optimize.png` … `iphone-65-04-pan-cue.png` | Same themes @ 1242×2688 |

### Drafts

Earlier draft exports live under `drafts/`.
