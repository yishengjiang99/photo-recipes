# ProTune selfie reel v15 (girl, fast optimize)

File: `docs/ads/protune-selfie-reels-v15-girl.mp4`. 720x1280, 24 fps, **9.04 s** (217 frames), H.264 + AAC 192k stereo, -14.0 LUFS.
Picture: `render_v15.py`. Audio: `mix_v15.py`. Source: `protune-selfie-reels-v13.mp4` (0f90c77).

## Timeline
| Time (s) | Picture | Audio |
|---|---|---|
| 0.00-1.04 | v13 title card ("Your selfies are ONE TAP from stunning") | **v13 original audio**: "One tap and AI edits your photos like a pro." (0.00-2.30) |
| 1.04-4.29 | Girl portrait slider scene, 3.25 s. Exposure -1.0 to +0.8 and Contrast -0.8 to +0.6 ease out from 1.19 to 3.34, photo goes foggy/dull to warm/vibrant, toggle flips to After at ~3.1, hold. Saturation / Sharpness / Color Balance / HDR Boost stay at 0.0 | v13 VO finishes at 2.30, seam at 2.62 into the music bed. 2.78-4.17 "Foggy to golden." |
| 4.29-~6.45 | v13 "ProTune sees this" food + landscape | whoosh 4.15. 4.37-6.31 "Food, landscapes, everything pops." |
| ~6.45-9.04 | v13 end card (ProTune AI Camera / App Store) | whoosh 6.30. 6.55-8.97 "ProTune AI Camera. Free on the App Store." |

Removed from v13: the phone-in-hand selfie/Optimize-tap scene (1.04-3.04), with its "Tap. Optimize." VO, and the city "AI Processing..." scene (3.04-9.04).

## Voice
- 0-2.62 s is v13's own audio, verbatim. The only processing is a static +0.5 dB gain plus a brickwall limiter on its transients.
- The new lines use ElevenLabs `eleven_multilingual_v2`, voice **"Roger"** (CwhRBWXzGAHq8TQ4Fs17), at speed 1.12. Roger was the closest of 12 premade male voices to v13's voice on pitch, formants and MFCC timbre (v13 at 96 Hz median F0, Roger at 108 Hz).
- The music bed (ElevenLabs sound-generation) fades in at the 2.62 s seam and ducks under the VO.
