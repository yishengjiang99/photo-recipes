# App Store screenshots — Build 16 (Grok Camera)

HTML/Playwright generator for ASC screenshot mocks.

**On-image wordmark:** Grok Camera  
**Signal Amber:** `#E0A812`  
**Slogan:** Set the shot. Then take it.

## Frames

1. AO dial burst (shutter/ISO/EV/WB/focus before→after)
2. Recommend labeled lower-left + recipe apply
3. Scene coach box (optional STT — secondary)
4. Manual dials / Teach
5. Hero value prop

## Export

```bash
npm install
npx playwright install chromium   # once
node export.mjs
```

Outputs 10 PNGs under `out/` at 1290×2796 (6.7") and 1179×2556 (6.1"). Copy to `assets/app-store/screenshots/` for ASC.

See `docs/marketing/asc-screenshot-brief-build16.md`.
