# ProTune AI Camera — "AI Processing..." 6-slider promo (9:16)

- `protune-ai-sliders-9x16.mp4`: 1080x1920, 30 fps, 6.0 s, H.264 yuv420p, no audio
- `poster.png`: end-state frame (5.8 s)
- `render.py`: renders the whole video (Pillow + numpy piped to ffmpeg). Run `python3 render.py`.
  It downloads the source photo once and checks its SHA-1. Inter fonts come from
  `docs/asc/screenshots/en-US/fonts`; IBM Plex Mono SemiBold (OFL) is in `fonts/` and stands in for SF Mono.

## Storyboard
A phone screen recording of the camera screen. `AI Processing...` sits in the top status pill, with the pulsing amber dot and a light shimmer.
The portrait on the left is graded per pixel from dull (under-exposed, flat, cool, desaturated) to vibrant and warm (golden key light from the upper right).
The right column has 6 slider cards: **Exposure** goes from -1.0 to +0.8 and **Contrast** from -0.8 to +0.6, both eased between 0.35 s and 5.45 s.
**Saturation, Sharpness, Color Balance, HDR Boost** stay at 0.0 with the knob centered the whole time.

## Styled after the real app (ios/PhotoRecipes)
- `Theme.swift`: graphite surfaces (#111111 / #1C1C1E), Signal Amber #E0A812 / #F5C518, ink #F5F5F7, 12/16 pt radii
- `Features/Camera/AgentStatusPill.swift`: black 55% capsule, pulsing amber dot (0.8 s), bodySm copy
- `Features/Camera/ManualDialsSheet.swift`: `evRow` surface card with overline label, `%+.1f` mono value, amber-tinted Slider
- `Features/Camera/CameraView.swift`: `shutterRow` (Recommend box with sparkles, white-ring/amber-core shutter, ellipsis.circle), floating black circle icons
- `docs/asc/screenshots/en-US`: Inter type and store-frame look

## Photo credit / license
"Brunette woman portrait (Unsplash).jpg" by Christopher Campbell. **CC0 1.0** (public domain dedication).
https://commons.wikimedia.org/wiki/File:Brunette_woman_portrait_(Unsplash).jpg
(original: https://unsplash.com/photos/3hoAon9Mc88, published under the pre-2017 Unsplash CC0 terms). SHA-1 `29612991a226c0f9dbdd33be0b8014ee4f00629c`.

## Notes
- The accent is the app's real Signal Amber, not the purple in the original brief, so the creative matches the shipped UI.
- The six slider names come from the creative brief. The shipping app's dials are Shutter / ISO / EV / WB / Focus.
