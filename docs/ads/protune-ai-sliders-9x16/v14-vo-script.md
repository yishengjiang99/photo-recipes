# ProTune selfie reel v14 (girl): VO script and audio

File: `docs/ads/protune-selfie-reels-v14-girl.mp4`. 720x1280, 24 fps, 13.79 s, H.264 + AAC 192k stereo, -14.0 LUFS integrated, -1.5 dBTP.
Built from `protune-selfie-reels-v13.mp4` (commit 0f90c77). The city "AI Processing..." scene (3.04-9.04 s) is
swapped for the CC0 portrait slider scene (`render_v13_cut.py`). Every other frame is unchanged.

| Time (s) | Scene | VO line |
|---|---|---|
| 0.05-1.2 | Hook card "Your selfies are ONE TAP from stunning" | One tap. Stunning selfies! |
| 1.9-2.5 | Selfie before/after, finger taps Optimize | Hit Optimize. |
| 3.2-5.6 | **New:** girl portrait, AI moves Exposure -1.0 to +0.8 and Contrast -0.8 to +0.6 | AI tunes exposure and contrast, by itself. |
| 6.2-8.2 | Girl portrait finishes warm (toggle on After) | From foggy and flat, to warm and glowing. |
| 9.15-10.9 | "ProTune sees this" food + landscape | Food, landscapes, everything pops. |
| 11.35-13.3 | End card | ProTune AI Camera. Free on the App Store. |

The v13 VO it replaces was: "One tap and AI edits your photos like a pro. / Tap. Optimize. / AI turns the sliders by itself. /
Watch dull food photos turn mouthwatering and flat landscapes burst with color. / ProTune AI camera. / Download on the App Store."

Audio chain (`mix_vo.py`):
- VO: ElevenLabs `eleven_multilingual_v2`, premade voice "Liam" (TX3LPaxmHKxFdv7VOQHJ), with stability 0.32, style 0.65, speed 1.12-1.2. Each line is trimmed and placed on the scene cuts.
- Music: a 14 s upbeat electronic bed made with ElevenLabs sound-generation. It ducks under the VO with a sidechain compressor (ratio 10, 300 ms release) and fades out at the end.
- SFX: generated whooshes just before the 1.04 / 3.04 / 9.04 / 11.2 s cuts.
- Mastering: two-pass loudnorm to -14 LUFS / -1.5 dBTP.
- v13 had VO only, with no music bed. The stems were checked with demucs.
