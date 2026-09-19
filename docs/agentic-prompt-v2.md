# Agentic Prompt v2 — Auto Optimize / Recommend

**Extends:** [`design-handoff-agentic-v1.md`](./design-handoff-agentic-v1.md)  
**Primary story:** Point the camera at the shot → Sense (viewfinder/image) → Auto Optimize → apply `phoneTargets` (AVFoundation levers).  
**Implements:** Sense → reason with tools → act (phone targets) → verify (mental check) → finalize  
**Server:** `server/recommend.ts` (`POST /api/recommend`)  
**Related:** `server/describeScene.ts` (viewfinder scene prefill), `server/stt.ts` (alternate input — transcripts feed the same recommend/apply path)

---

## 1. Full revised system prompt (copy-pasteable)

Keep this text in sync with `buildSystemPrompt()` in `server/recommend.ts`. Favorites and vision sense lines are interpolated at runtime.

```
You are the Photo Recipes field assistant for Auto Optimize (Camera) and Ask / Photo Vision (web + iOS).
Primary job: analyze the scene from the viewfinder (image + optional note) → select one catalog recipe → emit phoneTargets for Auto Optimize to apply (AVFoundation levers).
Tone: darkroom field notes — quiet, concrete, instructor-at-your-shoulder. Never chatty. Never invent recipes.

LOOP (strict):
1. SENSE — {vision | text}
2. REASON — Call list_presets. Optionally get_preset_details. Pick exactly ONE catalog id.
3. ACT / FINALIZE — Call select_preset with phoneTargets + coachOnly (+ panCue when motion/panning fits).
4. VERIFY — Targets match technique + control asks; ranges phone-plausible; aperture/ND/tripod in coachOnly; previewLUT never a capture filter; panCue only for panning/motion.

ALTERNATE INPUT (spoken / STT — secondary):
- Same Sense → recommend → phoneTargets apply path (not Ask text-field-only).
- Control adjustments: phoneTargets MUST include the relevant keys (not empty {}).

CRITICAL RULES:
- Catalog only; MUST use tools; finish with select_preset promptly.
- phoneTargets = AVFoundation levers only (all optional) — see §3. Never put hardware aperture in phoneTargets.
- coachOnly = aperture, nd, tripod, notes.
- teachWhy / tips / panCue / senseSummary — same as before.
[+ optional favorites line]
```

---

## 2. Tool schemas

### `list_presets` / `get_preset_details`

Unchanged from prior v2 (catalog list + full preset details).

### `select_preset` (finalize)

| Field | Required | Notes |
|-------|----------|--------|
| `presetId` | ✓ | Exact catalog id |
| `reason` | ✓ | Coach-style; 1–3 short sentences |
| `teachWhy` | ✓ | Teach mode one-liner; 1–2 sentences |
| `tips` | | Max 3 short field tips |
| `phoneTargets` | ✓ | Object; see §3 (may be `{}`) |
| `coachOnly` | ✓ | aperture / nd / tripod / notes |
| `panCue` | | `{ direction: left\|right\|either, note? }` |
| `senseSummary` | | One-line status |

**Validation (server):** unknown `presetId` rejected; empty `reason` / `teachWhy` rejected; `tips.length > 3` rejected; bad ranges on new keys rejected. Failed select does **not** end the loop.

---

## 3. phoneTargets schema (iOS Expert contract names)

All keys **additive optional**. Older iOS builds **ignore unknown keys**. Never put hardware aperture here.

### P0 — apply when device capability allows

| Key | Type | Gate / iOS apply notes |
|-----|------|------------------------|
| `shutter` | `string` | Recipe/UI string e.g. `"1/60"`. Keep alongside `exposureDurationSec`. |
| `exposureDurationSec` | `number` | Seconds for `setExposureModeCustom` (e.g. `0.01667`). Pair with `iso`. Range server: `>0…30`. |
| `iso` | `string \| number` | Lock / bias; `"auto"` or numeric. |
| `ev` | `string \| number` | Exposure bias e.g. `"+0.7"` or `-1`. |
| `whiteBalance` | `string \| { temperature?, tint? } \| { redGain?, greenGain?, blueGain? }` | Preset **or** locked temp/tint **or** device RGB gains (not mixed). Gains 0–8. |
| `focusMode` | `string` | `continuous` / `locked` / `near` / `infinity` |
| `focusPoint` | `{ x, y }` | Normalized **0–1**; omit if mode alone enough. |
| `lensPosition` | `number` | Locked focus **0…1** (`setFocusModeLocked`). |
| `zoom` | `number` | `videoZoomFactor` (1 = 1×). Prefer `cameraDevice` for optical switch. Server accepts `"2x"` → number. Range 0.5–16. |
| `cameraDevice` | `ultraWide \| wide \| tele` | Optical lens switch vs digital zoom only. |
| `torch` | `{ mode: off\|on\|auto, level?: 0…1 }` | Continuous light; level when `on`. |
| `flash` | `off \| on \| auto` | Still flash when PhotoOutput allows. |
| `lowLightBoost` | `boolean` | When device supports low-light boost. |
| `videoHDR` | `boolean` | When active format supports video HDR. |
| `frameRate` | `number` | Target fps (1–240); maps to min/max frame duration. |
| `preferFormatHint` | `string` | Soft activeFormat hint e.g. `"4k60"`, `"1080p30"`. |
| `bracket` | `{ stops: number[], count?: number }` | Multi-capture HDR / AE plan; stops −5…+5 EV; 1–9 entries. |
| `monitorSubjectAreaChange` | `boolean` | When true, iOS enables monitoring and should **re-trigger Auto Optimize** on change. |
| `maxPhotoDimensions` | `{ width, height }` | Preferred max photo pixels when PhotoOutput supports it. |

### P1 — gated / preview

| Key | Type | Notes |
|-----|------|--------|
| `previewLUT` | `string` | **Preview-only** LUT id. MUST NOT be sold as a capture magic filter. Capture settings remain primary. |
| `simulatedAperture` | `number` | Only if OS supports; otherwise use **`coachOnly.aperture`**. Never fake hardware aperture. |

### coachOnly (not applied)

| Key | Notes |
|-----|--------|
| `aperture` | f-stop guidance / picture-style notes |
| `nd` | Filter advice |
| `tripod` | Boolean |
| `notes` | Free-form coach guidance |

---

## 4. Capability gates (document for iOS)

| Lever | Typical gate |
|-------|----------------|
| Custom exposure pair | `isExposureModeSupported(.custom)` + device min/max duration & ISO |
| `lensPosition` | `isLockingFocusWithCustomLensPositionSupported` |
| Locked WB gains / temp-tint | `isWhiteBalanceModeSupported(.locked)` + device gain ranges |
| `torch` / level | `hasTorch` / `isTorchAvailable`; clamp level |
| `flash` | Photo output flash supported for current device |
| `lowLightBoost` | `isLowLightBoostSupported` |
| `videoHDR` | Format / device HDR flags |
| `cameraDevice` | Discovery session has ultraWide / tele |
| `frameRate` / format hint | Format supports duration; fall back silently |
| `bracket` | Burst / bracket capture path available |
| `maxPhotoDimensions` | PhotoOutput max photo dimensions API |
| `previewLUT` | Preview pipeline only — never mutate captured file as “filter” |
| `simulatedAperture` | OS cinematic / simulated aperture APIs; else coachOnly |

iOS must **skip unsupported keys** without failing the whole apply.

---

## 5. Loop / failure modes / API shape

Loop, `tool_choice`, and failure modes unchanged from prior v2 (`MAX_ROUNDS=5`, catalog-only, 502 if no `select_preset`).

`POST /api/recommend` returns additive `phoneTargets` object (pass-through from `recommend.ts`). Older clients ignore unknown keys.

Example (subset):

```json
{
  "phoneTargets": {
    "shutter": "1/30",
    "exposureDurationSec": 0.0333,
    "iso": 100,
    "ev": 0,
    "focusMode": "locked",
    "lensPosition": 0.45,
    "focusPoint": { "x": 0.5, "y": 0.4 },
    "cameraDevice": "wide",
    "zoom": 1,
    "bracket": { "stops": [-2, 0, 2] },
    "monitorSubjectAreaChange": true
  },
  "coachOnly": { "aperture": "f/8", "tripod": false },
  "teachWhy": "Panning keeps the subject sharp while the background streaks."
}
```

---

## 6. Compatibility — primary vs secondary path

| Client | Contract |
|--------|----------|
| **iOS Auto Optimize (primary)** | Viewfinder → recommend → `applyPhoneTargets` on live `AVCapture` session. |
| **Voice / STT (secondary)** | Transcript → same recommend → **same** apply helper. |
| **Web Ask** | May ignore new keys until wired. |
| **Quota** | Free Peek Ask/Vision/Auto Optimize pool unchanged. |

---

## 7. Spoken-intent → phoneTargets (examples)

| Spoken intent | Targets |
|---------------|---------|
| "slower shutter for panning" | `shutter` + `exposureDurationSec` + `panCue` + `teachWhy` |
| "lock focus on the rider" | `focusMode: locked` + optional `focusPoint` / `lensPosition` |
| "go to 2x" / "ultra-wide" | `zoom` and/or `cameraDevice` |
| "torch on low" | `torch: { mode: "on", level: 0.2 }` |
| "bracket for HDR" | `bracket: { stops: [-2,0,2] }` |
| "re-optimize if subject moves" | `monitorSubjectAreaChange: true` |
| "daylight WB" / locked Kelvin | `whiteBalance` string or `{ temperature, tint }` |

---

## 8. iOS Expert — apply contract

1. Decode additively; ignore unknown keys.
2. Apply P0 keys only when capability gates pass; skip otherwise.
3. Shared apply helper for Auto Optimize button **and** spoken follow-ups.
4. `monitorSubjectAreaChange: true` → enable monitoring → re-trigger optimize on change.
5. `previewLUT` → preview pipeline only; never market as magic capture filter.
6. `simulatedAperture` → OS-gated; else show `coachOnly.aperture`.
7. Do **not** apply `coachOnly` to the session.

---

## 9. Server route notes

- `server/recommend.ts`: `PhoneTargets` type, `select_preset` JSON schema, `parsePhoneTargets` range validation, system prompt.
- `server/index.ts`: passes `phoneTargets` through unchanged on `POST /api/recommend` (no per-key stripping).
- Additive only — no AVFoundation implementation on server.

---

## 10. P0 vs future

| Tier | Keys |
|------|------|
| **P0 (this PR)** | exposureDurationSec, iso/ev union, lensPosition, whiteBalance unions, torch, flash, lowLightBoost, videoHDR, cameraDevice, frameRate, preferFormatHint, bracket, monitorSubjectAreaChange, maxPhotoDimensions (+ existing shutter/focus/zoom/focusPoint) |
| **P1 / gated** | previewLUT, simulatedAperture |
| **Document only / future** | Broader cinematic tracking, richer picture styles — do not block P0 |

---

*Agentic Expert · prompt v2 · AVFoundation phoneTargets expansion*
