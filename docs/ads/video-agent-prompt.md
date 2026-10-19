# Agent prompt: create the next ProTune selfie video ad

Copy everything below the line into a fresh agent session.

---

You are creating a new video ad for **ProTune AI Camera** (iOS app, App Store id 6813991381). The ad runs on Facebook/Instagram as an app-install ad. Your deliverable is one vertical video plus its poster frame, ready to upload to Meta Ads Manager.

## What already works (match this bar)

The current winning video is `protune-selfie-reels-v17.mp4` in this repo's `docs/ads/` folder (GitHub: https://github.com/yishengjiang99/photo-recipes/blob/main/docs/ads/protune-selfie-reels-v17.mp4). Study it first. It wins because it shows a **real-time transformation moment**: a finger taps the app's Optimize button and the selfie visibly improves in the same shot. Creative direction from our reviewer, and it is binding: **a real transformation, nothing fake-looking.** No stock models, no beauty filters the app does not actually produce, no staged "after" photos from another tool.

## The job

Create the next video in the series (name it `protune-selfie-reels-v19.mp4`, poster `protune-selfie-reels-v19-poster.webp`, and place both in `docs/ads/`).

1. Pick a new genuine before photo (a selfie with an obvious, fixable flaw: flat light, dull color, cluttered background light).
2. Produce the "after" with the app's real processing only: run the photo through ProTune's Auto Optimize / Photo Looks (source code under `ios/` in this repo) and capture the true output. The before and after must be the same photo, differing only by what the app actually does.
3. Structure (about 12 seconds):
   - 0–2 s: the "before" selfie, with the hook — the viewer should feel the flaw immediately.
   - 2–5 s: a finger taps **Auto Optimize** on the real app UI.
   - 5–9 s: the transformation moment — the photo transitions to the real optimized result, ideally with the app's Photo Looks panel visible, as in v17.
   - 9–12 s: end card: app name "ProTune AI Camera", the headline below, and an install call to action.
4. Copy, use exactly:
   - Headline/body: "Your selfies are one tap from stunning. Watch AI edit your photos like a pro."
   - CTA: Install Mobile App.
5. Technical spec: vertical 9:16, 1080×1920, H.264 MP4, captions burned in so it works muted, text large enough to read on a phone, no audio required (add a simple upbeat track only if you have a licensed one).
6. Disclose AI in the upload metadata when the file is used (the campaign runs with AI disclosure OPT_IN).

## Acceptance check before you call it done

- The transformation is real: before/after are the same photo and the after is genuine app output.
- The hook lands in the first 2 seconds.
- It reads clearly with the sound off.
- Nothing in the video promises an effect the app does not produce.

Save the two files in `docs/ads/` and report the file paths when finished.
