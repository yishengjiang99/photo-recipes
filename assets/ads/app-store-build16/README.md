# App Store screenshots — Build 16 (AI Camera - Auto Recipes)

HTML/Playwright generator for ASC screenshot mocks.

**On-image wordmark:** AI Camera  
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

## Polish notes (Build 16 fidelity)

- Recommend is **labeled** lower-left of shutter (sparkles + text), not a blank thumb
- Frame 1 dial burst uses larger mono + amber → arrows for ASC thumb readability
- Frame 5 is quiet (caption band only + AO + shutter; no mid-finder chrome noise)
- Accent `#E0A812` / `#F5C518` on AO fills only; shutter core stays neutral

