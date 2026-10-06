# ProTune selfie reel v16 (Midwest VO)

File: `docs/ads/protune-selfie-reels-v16-midwest.mp4`. The picture is byte-identical to v15 (`render_v15.py`). 720x1280, 24 fps, 9.04 s, AAC 192k stereo, -14.0 LUFS.

The script is unchanged from v15. All four lines are re-voiced in one ElevenLabs voice: **"Curt - Midwestern Storyteller"**, voice ID `hU1ratPhBTZNviWitzAh` (shared library voice), model `eleven_multilingual_v2`, with stability 0.35, style 0.6 and speed 1.12-1.15 (`gen_v16.py`).
Curt's median pitch is 88 Hz, against about 96 Hz for v13's original voice. He scored as the closest timbre match among the Midwestern candidates and the earlier premade voices.

| Time (s) | Picture | VO |
|---|---|---|
| 0.05-2.39 | title card, then girl scene from 1.04 | One tap and AI edits your photos like a pro. |
| 2.78-3.94 | girl scene (optimize lands at 3.34) | Foggy to golden. |
| 4.37-6.15 | food / landscape from 4.29 | Food, landscapes, everything pops. |
| 6.50-8.97 | end card from ~6.45 | ProTune AI Camera. Free on the App Store. |

Music bed from 0 s (ducked under the VO). Whooshes at 0.90 / 4.15 / 6.30. `mix_v16.py` masters with a static gain plus a limiter.
v13's title-card SFX weren't kept: its separated non-vocal stem is about -60 dB, so it's effectively silent.
