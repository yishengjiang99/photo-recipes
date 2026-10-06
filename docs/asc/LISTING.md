# App Store listing — ProTune AI Camera (en-US)

Source of truth for the ASC listing. `scripts/asc/upload_photo_recipes_listing.py` reads the
fastlane-layout files under `docs/asc/metadata/` and pushes them to App Store Connect
(bundle `com.ragnus.mvp`). Limits are Apple's. Never use the word "Grok" anywhere in the
upload-ready listing (Apple rejected it on the sister app before); say "AI" / "Auto Optimize".

The fenced Subtitle / Promotional text / Keywords / Description blocks are the **upload-ready**
copy and must equal `metadata/en-US/*.txt` (fastlane deliver layout).
Check: `python3 docs/asc/check_copy.py`.

Status: listing v3 (name/subtitle confirmed, description rewritten benefit-led with a stronger
above-the-fold hook, keywords rebuilt v3 — no spaces, no name/subtitle repeats, high-traffic
single-word terms — promo text sharpened to a benefit-led hook, screenshots regenerated with
large hero text). Upload + verify with the manual workflow (script
`scripts/asc/upload_photo_recipes_listing.py`, VERIFY_ONLY=true for a dry run). Submitting for
review is a separate manual step, run by the owner only.

## Name (30)
```
ProTune AI Camera
```

Recommendation: keep. 24/30 chars, "AI Camera" front-loaded for search, and this name already
survived a trademark rejection (Sep 2026) — renaming now re-opens review for no search gain.
Alt (ties to the slogan "Set the shot. Then take it."): `AI Camera - Shot Recipes` (25).

## Subtitle (30)
```
AI Auto: Shutter ISO Focus
```

Confirmed: 27/30, names the concrete dials photographers search for (shutter, ISO, focus).
Alt: `Auto Optimize: Pro Dials` (25).

## Promotional text (170)
```
Your iPhone, shooting like a pro. Tap Auto Optimize — shutter, ISO, EV, white balance and focus set themselves. Real capture dials, not filters.
```

## Keywords (100, comma-separated, no spaces after commas)
```
photography,exposure,hdr,manual,night,raw,dslr,panning,landscape,portrait,bracketing,aperture,macro
```

Rebuilt so no keyword repeats a word already in the name or subtitle (Apple combines them for
search; repeats waste the 100 chars). "camera"/"shutter"/"ISO"/"focus" live in name+subtitle.
v3: dropped spaced terms ("white balance", "long exposure" — Apple splits on spaces, wasting
chars) and added high-traffic single-word terms photographers actually search: manual, night,
raw, dslr, aperture, macro.

## Description (4000)
```
Better photos from your iPhone — no f-stops required. Point at the scene, tap Auto Optimize, and the camera sets itself: real shutter, ISO, EV, white balance and focus dials, written for you.

ProTune AI Camera is a field camera for photographers who want the recipe AND the dial position. Auto Optimize reads the scene, picks the right photo recipe, and writes real capture dials on your iPhone — shutter, ISO, EV, white balance, focus and zoom. Not filters. Real dials.

WHAT AUTO OPTIMIZE SETS
• Shutter / exposure duration
• ISO
• EV bias
• White balance (temp & tint)
• Focus lock
• Zoom / lens and torch, when the scene calls for it

EVERY DIAL, EXPLAINED
Teach Mode shows which recipe was chosen, which dials moved and why — an instructor over your shoulder, not a chat wall.

REAL DIALS, NOT FILTERS
Field looks are capture grades applied live in the viewfinder — golden hour, mono ink, teal orange and more — with intensity you control. Never beauty filters. Never sky replacement.

FREE PEEK VS PRO
• Free: browse every recipe, live viewfinder, 1 Auto Optimize per day
• AI Camera Pro: unlimited Auto Optimize, manual dials, full Teach Mode, interactive field checklists
$7.99/month or $59.99/year with a 7-day free trial. Subscriptions via Apple In-App Purchase.
Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

BUILT FOR THE FIELD
Recipes come from classic field technique — panning, motion control, HDR, focus discipline, low angle — each with dials, steps and checklists.
```

## What's New
```
Auto Optimize now reads the scene straight from the live viewfinder, with no shutter sound or flash, and your typed scene notes are never overwritten. The Get Down Low recipe is now called Low Angle. Camera memory and stability fixes for longer shoots.
```

## Support URL
```
https://photo.grepawk.com/support
```

## Marketing URL
```
https://photo.grepawk.com
```

## Privacy Policy URL
```
https://photo.grepawk.com/privacy
```

## Copyright
```
2026 Yisheng Jiang
```

## Categories
- Primary: `PHOTO_AND_VIDEO`
- Secondary: `EDUCATION`

## TestFlight: What to Test
```
Point at a scene and tap Auto Optimize: the app should pick a photo recipe and apply shutter, ISO, EV, white balance and focus to the live viewfinder. Try Teach Mode ("Why this?") after a run, and the field looks. Free Peek allows 1 Auto Optimize per day without purchase. Please report wrong recipe picks or dials that don't stick.
```

## URLs: publishing status
Support/privacy/marketing URLs confirmed live in App Store Connect 2026-09-30
(`https://photo.grepawk.com[/support|/privacy]`) — the earlier grepawk.com/photo-recipes/*.html
guesses were wrong and have been replaced.

## App Privacy
Camera and photo library access are used for capture and Auto Optimize. Confirm the privacy
nutrition label in the App Store Connect web UI (the public ASC API has no endpoint for it).

## Screenshots
Brand style: Signal Amber `#E0A812` on dark `#111111` (the app's palette), large ExtraBold hero
text at the top of every frame explaining the functionality, hero frame first. Generated by
`docs/asc/screenshots/en-US/make_store_screenshots.py` (Pillow + numpy + Inter; viewfinder still
from `source/viewfinder-scene.jpg`, UI chrome drawn as mock frames — not pixel-perfect device
captures). Order: 01 Set the shot, 02 Auto Optimize dials, 03 Real dials not filters,
04 Teach Mode, 05 Field looks.

| ASC display type | Size | Files |
|---|---|---|
| `APP_IPHONE_67` (6.9" iPhone) | 1320 × 2868 | `screenshots/en-US/iphone-69-0{1,2,3,4,5}-*.png` |
| `APP_IPAD_PRO_3GEN_129` (13" iPad) | 2064 × 2752 | `screenshots/en-US/ipad-13-0{1,2,3,4,5}-*.png` |

The older sets under `assets/app-store/screenshots/` (build16 HTML mocks, 6.7"/6.1") are superseded
for ASC upload by this set. Keep them for reference until after upload.
