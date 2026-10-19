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
3. Add the voiceover and sound (the draft already has it):
   ```
   python3 audio.py --video ../protune-selfie-reels-v19.mp4 --out ../protune-selfie-reels-v19.mp4.tmp.mp4 \
     --models KOKORO_DIR --espeak PIPER_DIR --vocab kokoro_onnx/config.json && mv ../protune-selfie-reels-v19.mp4.tmp.mp4 ../protune-selfie-reels-v19.mp4
   ```
4. In Ads Manager: CTA Install Mobile App, AI disclosure OPT_IN.

## Open questions (resolved 2026-10-19)
- Copy: "Your selfies are one tap from stunning. Watch AI edit your photos like a pro." is the exact body copy on all three live ads (poster v17, poster v18, video v17), verified against Meta on 2026-10-19. The brief's wording stays; the conflict with docs/marketing/ad-copy-v2.md is noted but the live, winning copy governs.
- Selfie looks have shipped: the Photo Looks rail (none + 5 looks, keys N/V/W/M/K) has been in the shipped camera UI since v1.3, and the selfie presets are in the bundled presets on main and in the live 1.6 build. The 2026-10-12 blog note predates that wiring.

## Voiceover
Local TTS, no API key: Kokoro-82M (ONNX, Apache-2.0) voice `af_heart`, phonemes from espeak-ng (`tts.py`). `audio.py` mixes the VO with a tap click (2.7 s), a whoosh into the reveal (4.85 s), a divider click (7.0 s), an end-card chime (9.1 s) and a soft pad ducked under the voice; AAC 192k stereo, about -14 LUFS, -1.5 dBTP.

| Time (s) | VO |
|---|---|
| 0.15-1.98 | Your selfies are one tap from stunning. |
| 2.90-4.97 | Watch AI edit your photos like a pro. |
| 9.20-11.67 | ProTune AI Camera. Free on the App Store. |

Inputs (downloaded once, not committed):
- `kokoro-v1.0.onnx`, `voices-v1.0.bin` from github.com/thewh1teagle/kokoro-onnx releases (model-files-v1.0)
- espeak-ng library + data from the rhasspy/piper 2023.11.14-2 linux tarball (`piper/` folder)
- `config.json` (vocab) from the kokoro-onnx repo, `src/kokoro_onnx/`

Other voices: `--voice am_michael` (male), `bf_emma` (British). v16's ElevenLabs voice ("Curt", `../protune-ai-sliders-9x16/gen_v16.py`) needs `ELEVENLABS_API_KEY`.
