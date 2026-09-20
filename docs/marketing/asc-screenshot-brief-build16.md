# ASC Screenshot Brief — Build 16 (Grok Camera)

**Status:** DRAFT HTML/Playwright mocks for App Store Connect upload review.  
**App display name (LOCKED):** **Grok Camera**  
**Bundle ID (LOCKED):** `com.ragnus.mvp`  
**Subtitle (LOCKED for this cycle):** AI Auto: Shutter ISO Focus  
**Slogan:** Set the shot. Then take it.  
**Palette A — Signal Amber:** `#E0A812` (accent CTA); accent-soft `#F5C518`; label-on-amber `#121212`; bg `#111111`; surface `#1C1C1E`; ink `#F5F5F7`.  
**Viewfinder chrome:** hue-neutral (no amber wash on finder glass).

Historical note: former store working names included Grepawk Photos / Photo Recipes; on-image wordmark and ASC App Name for this cycle are **Grok Camera**.

## Frame set (5 required)

| # | File slug | Frame intent | Caption (DRAFT) |
| --- | --- | --- | --- |
| 1 | `01-ao-dial-burst` | Auto Optimize ApplyBurst — before→after shutter / ISO / EV / WB / focus | Auto Optimize writes shutter, ISO, EV, WB & focus |
| 2 | `02-recommend` | Recommend labeled lower-left + recipe apply with dials on finder | Recommend applies the recipe — dials on the finder |
| 3 | `03-stt-scene` | Scene coach box; STT secondary / optional (not hero) | Scene coach in the box (optional STT) |
| 4 | `04-manual-teach` | Manual dials + Teach / Why this? override | See shutter · ISO · EV · WB · focus — then override |
| 5 | `05-hero-value` | Hero value prop — slogan + **Grok Camera** | Set the shot. Then take it. |

## Sizes

- iPhone 6.7": **1290 × 2796** → `iphone-67-*.png`
- iPhone 6.1": **1179 × 2556** → `iphone-61-*.png`

## Constraints (do not violate)

- No beauty filters; no fake aperture applied as a written dial.
- STT is secondary — never the hero frame or lead caption.
- On-image wordmark: **Grok Camera** only (not App Name, not Grepawk Photos, not Photo Recipes).
- Prefer HTML/CSS UI chrome for dial readability over AI image generation.

## Generator

- Source: `assets/ads/app-store-build16/` (`frame.html` + `export.mjs`)
- Viewfinder still: `assets/ads/app-store-build16/assets/viewfinder-scene.jpg` (shared elevator scene)
- Exports land in `assets/app-store/screenshots/`

## Supersedes

Interim dial-burst MOCK set from `assets/ads/app-store-dial-v1/` (`iphone-*-0N-dial-burst.png`, `*-ao-cta.png`, `*-recipe-dials.png`, `*-field-look.png`, `*-ready-pan.png`) is **superseded** for ASC upload by this Build 16 set. Keep old files for reference until Marketing deletes them post-upload.

## Fidelity gaps (for Ad Designer polish)

- Chrome is HTML mock of Build 16 intent — not pixel-perfect device capture from TestFlight.
- Recommend callout position is illustrative (lower-left label + pill); match shipping UI spacing when device stills available.
- Scene coach / STT box copy is sample scene text; replace with a real coach string if product copy differs.
- Hero frame minimizes chrome for slogan readability — Ad Designer may prefer a quieter finder still or branded end card.
- No Dynamic Island / status-bar system chrome simulated.
