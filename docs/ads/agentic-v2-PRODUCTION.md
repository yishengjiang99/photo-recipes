# Agentic v2 statics — production notes

**ICP:** High-end photography enthusiasts / workshop alumni — craft dials over vibes.

**Copy:** Marketing Expert [`ad-copy-v2.md`](../marketing/ad-copy-v2.md) — verbatim.  
**Locked to:** `docs/marketing/ad-copy-v2.md` on main (enthusiast + device controls).

## On-device vs coach-only (UI mocks)

| Class | Controls |
|-------|----------|
| **On-device (agent applies)** | shutter / exposure duration · ISO · EV bias · WB · focus lock/POI (zoom optional) |
| **Coach-only (not on phone)** | aperture · ND · tripod — dashed “Coach-only” row when shown |

## Build

```bash
cd /workspace/photo-recipes-ads/agentic-v2
node export.mjs
cp out/*.png <repo>/assets/ads/agentic-v2/
```

## Variants × sizes

| Variant | On-frame story |
|---------|----------------|
| `ao-primary` | Dial hero (5 chips: shutter·ISO·EV·WB·focus) + AO pill + `Reading light…` / Applying |
| `before-after` | Same 5 chips + Ready + coach-only row (aperture/ND/tripod) |
| `pan-cues` | Soft L/R + `pan with subject →` + mini S/ISO/EV chips |
| `viewfinder-voice` | Dial hero + From viewfinder + mic + AO |

Sizes: 1080×1350, 1080×1080, 1080×1920.

## Tokens

`#0c0c0f` / `#141418` / `#1c1c22` / `#fafafa` / `#a1a1aa` / `#f43f5e` · DM Sans + Instrument Serif · mono/tabular dials.

## QA one-liners

- **ao-primary:** Dial before→after is the hero; AO rose pill clear; no beauty filter cues.
- **before-after:** shutter·ISO·EV·WB·focus·zoom all readable; coach-only labeled.
- **pan-cues:** Soft chevrons + caption; mini dial chips prove settings still matter.
- **viewfinder-voice:** Mic + From viewfinder visibly tied to same dial strip.
