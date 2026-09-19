# C3 — Recipe card UI Meta statics

Export-ready Photo Recipes ad creatives: recipe library, detail, dials close-up, and field checklist. Dark field-app aesthetic matched to live product tokens (DM Sans + Instrument Serif, rose accent `#f43f5e`, surfaces `#141418` / `#1c1c22`, bg `#0c0c0f`).

## Source files

| File | Role |
|------|------|
| `frame.html` | Self-contained creative. Query: `?variant=library\|detail\|dials\|checklist&size=1080x1350\|1080x1080\|1080x1920` |
| `export.mjs` | Playwright screenshot runner → `out/` |
| `out/c3-*.png` | 12 final PNGs (4 variants × 3 sizes) |

### Regenerate

```bash
cd /workspace/photo-recipes-ads/c3
npx playwright install chromium   # once
node export.mjs
```

## Output inventory

Exact filenames (absolute under this folder’s `out/`):

**Library**
- `c3-library-1080x1350.png` — 4:5 feed (PRIMARY)
- `c3-library-1080x1080.png` — 1:1
- `c3-library-1080x1920.png` — 9:16 Stories

**Detail** (hero recipe title + dials + blurb)
- `c3-detail-1080x1350.png`
- `c3-detail-1080x1080.png`
- `c3-detail-1080x1920.png`

**Dials** (shutter / aperture / ISO close-up)
- `c3-dials-1080x1350.png`
- `c3-dials-1080x1080.png`
- `c3-dials-1080x1920.png`

**Checklist** (field gear checklist)
- `c3-checklist-1080x1350.png`
- `c3-checklist-1080x1080.png`
- `c3-checklist-1080x1920.png`

Stories (9:16) keep key UI vertically centered with ~120px top / ~180px bottom clear for chrome.

## Hero recipe content (from product)

- Full title: *Keep a Moving Subject Sharp, With Motion Blur in the Background*
- Library short label: **Panning**
- Dials: Mode shutter-priority (S / Tv) · Shutter 1/30s · Aperture auto · ISO as needed
- Checklist: Camera (hand-held) · Flash (advanced) · Subject close enough for flash (advanced)

Library also shows: Sharp from Front to Back · How to Blur Moving Subjects · Panning (hero) · Get Down Low · HDR Brights & Darks

## Copy pairing (Marketing §4)

Burned-in text is minimal. Meta **primary text** and **CTA** live outside the image.

| Slot | Preferred | Notes |
|------|-----------|--------|
| On-image headline (library) | **H1** — “Field recipes for real shots” | Already on library frames |
| On-image headline (detail) | **H3** — “Shoot it right the first time” | Already on detail frames |
| On-image sub | “Not filters — camera technique” (H1 desc) | Library + detail only |
| Dials / checklist | Wordmark only | UI is the message |
| Primary text (ad set) | **PT2** (technique not filters) or **PT5** (direct offer) | Outside image |
| CTA button | **Learn More** | Meta standard |

Placeholders until Marketing finalizes remaining variants: treat any unused PT/H as `PT1` / `H1` in the ad manager until swapped.

Suggested pairings by creative:

| Creative | Image | Primary text | Headline (if dynamic) | CTA |
|----------|-------|--------------|------------------------|-----|
| Library | `c3-library-*` | PT2 | H1 | Learn More |
| Detail | `c3-detail-*` | PT2 | H3 | Learn More |
| Dials | `c3-dials-*` | PT2 or PT5 | H1 or H3 | Learn More |
| Checklist | `c3-checklist-*` | PT5 | H3 | Learn More |

## Brand / do-nots

- Tokens: accent sparingly (tags, active Mode dial, checklist check) — not neon AI glow
- No App Store badges, filter before/after grids, book branding, or Lightroom language
- Quiet wordmark “Photo Recipes” OK; soft dusk/bokeh gradient behind glass UI OK

## CapCut — subtle 6s Ken Burns from 4:5 stills

1. Import a PRIMARY still, e.g. `c3-library-1080x1350.png` (or detail/dials/checklist 4:5).
2. Set project to **1080×1350**, clip duration **6.0s**.
3. Select clip → **Animation** → **Combo** (or Keyframes):
   - Start (0s): Scale **100%**, Position centered.
   - End (6s): Scale **108–110%**, nudge Position **+1–2%** on X or Y (slow pan).
4. Keep motion linear / ease-in-out; avoid bounce. Optional: very light vignette only if it doesn’t fight the baked-in dusk bg.
5. Export H.264, 30fps, same 1080×1350. Loop by placing the same clip twice reversed (ping-pong) if you need seamless 12s without a hard cut.
6. Do **not** add App Store UI, neon glows, or heavy text overlays — Meta primary text stays in the ad unit.

Repeat for each of the four 4:5 variants for a set of quiet loops.
