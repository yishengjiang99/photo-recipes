# ProTune selfie reel v19 (work in progress)

Brief: [`../video-agent-prompt.md`](../video-agent-prompt.md).

| File | What it is |
|---|---|
| `render.py` | Renderer: 1080x1920, 30 fps, 12 s, H.264. Composites two real images of the same shot into the shipped camera UI (Signal Amber on graphite, Photo Looks rail N/V/W/M/K). It does no grading of its own. |
| `protune-selfie-reels-v19-DRAFT-mock.mp4` | **Layout and timing draft only. Not for upload.** The "after" is an approximate grade of the v17 "before" frame, watermarked "MOCK AFTER". v17's model also fails the brief's "no stock models" rule. |

## Timeline
| Time (s) | Picture | Burned-in copy |
|---|---|---|
| 0-2.25 | Before selfie, tagged BEFORE | Your selfies are one tap from stunning. |
| 2.25-5 | Finger taps Auto Optimize (2.7); pill shows "Reading the light…" | Watch AI edit your photos like a pro. |
| 5-9 | Amber scan line reveals the after (5.0-5.9); Photo look pill and rail highlight; a before/after divider sweeps 7.0-8.6 to show it is the same photo | (same) |
| 9-12 | End card: icon, ProTune AI Camera, headline, "Free on the App Store", "1 free Auto Optimize a day" | |

## To finish
1. On an iPhone, take a selfie with flat light. Keep the untouched original, then tap Auto Optimize and keep the photo ProTune saves.
2. Render the final video and poster:
   ```
   python3 render.py --before raw.jpg --after protune.jpg --look W:Warm \
     --out ../protune-selfie-reels-v19.mp4 --poster ../protune-selfie-reels-v19-poster.webp
   ```
   `--look` takes the rail key and name of the Photo Look the app applied. Leave it out if none was applied.
3. Optional: add a sound bed. The draft has no audio track.
4. In Ads Manager: CTA Install Mobile App, AI disclosure OPT_IN.

## Open questions
- "Watch AI edit your photos" conflicts with `docs/marketing/ad-copy-v2.md` (real camera dials, not AI editing). The brief's wording is used.
- The blog post dated 2026-10-12 says selfie looks were not part of 1.4. Confirm they have shipped before this runs.
