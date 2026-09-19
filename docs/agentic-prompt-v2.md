# Agentic Prompt v2 — Auto Optimize / Recommend

**Extends:** [`design-handoff-agentic-v1.md`](./design-handoff-agentic-v1.md)  
**Primary story:** Point the camera at the shot → Sense (viewfinder/image) → Auto Optimize → apply `phoneTargets` (AVFoundation levers).  
**Implements:** Sense → reason with tools → act (phone targets) → verify (mental check) → finalize  
**Server:** `server/recommend.ts` (`POST /api/recommend`)  
**Related:** `server/describeScene.ts` (viewfinder scene prefill), `server/stt.ts` (alternate input — transcripts feed the same recommend/apply path)  
**iOS contract names:** `ios/PhotoRecipes/Models/RecommendResponse.swift` `PhoneTargets` CodingKeys

---

## 1. Full revised system prompt (copy-pasteable)

Keep this text in sync with `buildSystemPrompt()` in `server/recommend.ts`. Favorites and vision sense lines are interpolated at runtime.

```
You are the Photo Recipes field assistant for Auto Optimize (Camera) and Ask / Photo Vision (web + iOS).
Primary job: analyze the scene from the viewfinder (image + optional note) → select one catalog recipe → emit phoneTargets for Auto Optimize to apply (AVFoundation levers).
Tone: darkroom field notes — quiet, concrete, instructor-at-your-shoulder. Never chatty. Never invent recipes.

PRIMARY PATH: viewfinder → Auto Optimize → phoneTargets on AVCapture.
ALTERNATE INPUT: voice/STT secondary into the SAME recommend → apply path (not Ask text-field-only).

LOOP (strict):
1. SENSE — {vision | text}
2. REASON — Call list_presets. Optionally get_preset_details. Pick exactly ONE catalog id.
3. ACT / FINALIZE — Call select_preset with phoneTargets + coachOnly (+ panCue when motion/panning fits).
4. VERIFY — Targets match technique + control asks; ranges phone-plausible; aperture/ND/tripod in coachOnly; previewLUT never a capture filter; panCue only for panning/motion.

CRITICAL RULES:
- Catalog only; MUST use tools; finish with select_preset promptly.
- phoneTargets = AVFoundation levers only (all optional) — see §3. Prefer smallest useful set. Never put hardware aperture in phoneTargets.
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

## 3. phoneTargets schema (aligned to iOS CodingKeys)

All keys **additive optional**. Older iOS builds **ignore unknown keys**. Never put hardware aperture here.

### P0 — apply when device capability allows

| Key | Type | Gate / iOS apply notes |
|-----|------|------------------------|
| `shutter` | `string` | Recipe/UI string e.g. `"1/60"`. Keep alongside `exposureDurationSec`. |
| `exposureDurationSec` | `number` | Seconds for `setExposureModeCustom` (e.g. `0.01667`). Pair with `iso`. Range: `>0…30`. |
| `iso` | `string \| number` | Lock / bias; `"auto"` or numeric. |
| `ev` | `string \| number` | Exposure bias e.g. `"+0.7"` or `-1`. |
| `whiteBalance` | `string \| { temperature?, tint? } \| { redGain?, greenGain?, blueGain? }` | Preset **or** locked temp/tint **or** device RGB gains. Gains (0, 8]. |
| `focusMode` | `string` | `continuous` / `locked` / `near` / `infinity` |
| `focusPoint` | `{ x, y }` | Normalized **0–1**; omit if mode alone enough. |
| `lensPosition` | `number` | Locked focus **0…1** (`setFocusModeLocked`). Gate: `isLockingFocusWithCustomLensPositionSupported`. |
| `zoom` | `number` | `videoZoomFactor` (1 = 1×). Prefer `cameraDevice` for optical switch. `"2x"` → number. Range 0.5–16. |
| `cameraDevice` | `ultraWide \| wide \| tele \| dual \| triple` | Optical / multi-cam vs digital zoom. iOS maps to `builtIn*` / virtual devices. |
| `torchMode` | `off \| on \| auto` | Continuous fill / night assist. Gate: `hasTorch`. |
| `torchLevel` | `number` | Intensity **0…1** when `torchMode` is `on`. |
| `flashMode` | `off \| on \| auto` | Stills flash on PhotoOutput. Gate: `isFlashAvailable`. |
| `lowLightBoostEnabled` | `boolean` | Gate: `isLowLightBoostSupported`. |
| `videoHDR` | `boolean` | When active format supports video HDR. |
| `automaticallyAdjustsVideoHDREnabled` | `boolean` | Auto HDR toggle when available (additive). |
| `frameRate` | `number` | Target fps (1–240) → min/max frame duration. |
| `preferFormatHint` | `string` | Soft activeFormat hint e.g. `"high-fps"`, `"4k60"`, `"cinematic"`. |
| `minFrameDuration` / `maxFrameDuration` | `string` | Explicit durations e.g. `"1/120"` / `"1/24"` (optional). |
| `bracket` | `{ stops: number[], count?: number }` | Multi-capture AE/HDR plan; stops −5…+5 EV; iOS executes burst. |
| `subjectAreaChangeMonitoringEnabled` | `boolean` | Enable monitoring → **re-trigger Auto Optimize** on `subjectAreaDidChange`. |
| `photoQualityPrioritization` | `speed \| balanced \| quality` | `AVCapturePhotoOutput.photoQualityPrioritization`. |
| `maxPhotoDimensions` | `{ width, height }` | When PhotoOutput supports max photo dimensions (iOS 16+). |

### P1 — gated / preview (do not block P0)

| Key | Type | Notes |
|-----|------|--------|
| `previewLUT` | `string` | **Preview-only** LUT id. MUST NOT be sold as a capture magic filter. Capture settings remain primary. |
| `simulatedAperture` | `number` | Only if OS supports; otherwise **`coachOnly.aperture`**. Never fake hardware aperture. |
| Cinematic subject tracking | — | **Document only** — do not emit / do not block P0. |

### coachOnly (not applied)

| Key | Notes |
|-----|--------|
| `aperture` | f-stop guidance |
| `nd` | Filter advice |
| `tripod` | Boolean |
| `notes` | Free-form coach guidance |

---

## 4. Capability gates (iOS apply)

| Lever | Typical gate |
|-------|----------------|
| Custom exposure pair (`exposureDurationSec` + `iso`) | `isExposureModeSupported(.custom)` + device min/max duration & ISO |
| `lensPosition` | `isLockingFocusWithCustomLensPositionSupported` |
| Locked WB gains / temp-tint | `isWhiteBalanceModeSupported(.locked)` + `isLockingWhiteBalanceWithCustomDeviceGainsSupported`; clamp ≤ `maxWhiteBalanceGain` |
| `torchMode` / `torchLevel` | `hasTorch` / `isTorchAvailable`; clamp level |
| `flashMode` | Photo output flash supported for current device |
| `lowLightBoostEnabled` | `isLowLightBoostSupported` |
| `videoHDR` / auto HDR | Format / device HDR flags |
| `cameraDevice` | Discovery session has ultraWide / tele / multi-cam |
| `frameRate` / format / frame durations | Format supports duration; fall back silently |
| `bracket` | Burst / bracket capture path available |
| `photoQualityPrioritization` | PhotoOutput prioritization API |
| `maxPhotoDimensions` | PhotoOutput max photo dimensions API |
| `previewLUT` | Preview pipeline only — never mutate captured file as “filter” |
| `simulatedAperture` | OS cinematic / simulated aperture APIs; else coachOnly |

iOS must **skip unsupported keys** without failing the whole apply. Server may accept legacy aliases (`flash`, `lowLightBoost`, `monitorSubjectAreaChange`, `torch: {mode,level}`) and normalize to iOS CodingKeys.

---

## 5. Loop / failure modes / API shape

Loop, `tool_choice`, and failure modes unchanged from prior v2 (`MAX_ROUNDS=5`, catalog-only, 502 if no `select_preset`).

`POST /api/recommend` returns additive `phoneTargets` object (pass-through from `recommend.ts` via `index.ts`). Older clients ignore unknown keys.

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
    "torchMode": "off",
    "bracket": { "stops": [-2, 0, 2] },
    "subjectAreaChangeMonitoringEnabled": true,
    "photoQualityPrioritization": "quality"
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
| **Web Ask** | May ignore new keys until wired. **Web feature work paused** unless API contract only. |
| **Quota** | Free Peek Ask/Vision/Auto Optimize pool unchanged. |

---

## 7. Spoken-intent → phoneTargets (examples)

| Spoken intent | Targets |
|---------------|---------|
| "slower shutter for panning" | `shutter` + `exposureDurationSec` + `panCue` + `teachWhy` |
| "lock focus on the rider" | `focusMode: locked` + optional `focusPoint` / `lensPosition` |
| "go to 2x" / "ultra-wide" | `zoom` and/or `cameraDevice` |
| "torch on low" | `torchMode: "on"`, `torchLevel: 0.2` |
| "flash off" | `flashMode: "off"` |
| "bracket for HDR" | `bracket: { stops: [-2,0,2] }` |
| "re-optimize if subject moves" | `subjectAreaChangeMonitoringEnabled: true` |
| "daylight WB" / locked Kelvin | `whiteBalance` string or `{ temperature, tint }` |

---

## 8. iOS Expert — apply notes (coordinate)

1. Decode additively; ignore unknown keys (already true for Codable keyed decode).
2. Apply P0 keys only when capability gates pass; skip + optional clamp message otherwise.
3. Shared apply helper for Auto Optimize button **and** Camera voice follow-ups.
4. `exposureDurationSec` + parseable `iso` → `setExposureModeCustom` when supported.
5. `subjectAreaChangeMonitoringEnabled: true` → enable monitoring → re-trigger optimize on change.
6. `bracket` → execute multi-capture AE burst (do not fake single-frame HDR).
7. `previewLUT` → preview pipeline only; never market as magic capture filter.
8. `simulatedAperture` → OS-gated; else show `coachOnly.aperture`.
9. Map `cameraDevice` short names → `builtInUltraWideCamera` / wide / tele / dual-triple virtual devices.
10. Decode additive keys not yet in CodingKeys when ready: `automaticallyAdjustsVideoHDREnabled`, `preferFormatHint`, `minFrameDuration`, `maxFrameDuration`, `photoQualityPrioritization`, `maxPhotoDimensions`, `previewLUT`.
11. Do **not** apply `coachOnly` to the session. Do **not** put aperture into applied targets.

---

## 9. Server Expert — route notes (coordinate)

- `server/recommend.ts`: `PhoneTargets` type, `select_preset` JSON schema, `parsePhoneTargets` range validation, system prompt (this doc).
- `server/index.ts`: passes whole `phoneTargets` through on `POST /api/recommend` (no per-key stripping) — **no change required** beyond existing pass-through.
- Additive only — no AVFoundation implementation on server.
- Web UI work remains paused; API contract-only is fine.

---

## 10. P0 vs future

| Tier | Keys |
|------|------|
| **P0 (this PR)** | exposureDurationSec, iso/ev union, lensPosition, whiteBalance unions, torchMode/torchLevel, flashMode, lowLightBoostEnabled, videoHDR, automaticallyAdjustsVideoHDREnabled, cameraDevice (+ dual/triple), frameRate, preferFormatHint, min/maxFrameDuration, bracket, subjectAreaChangeMonitoringEnabled, photoQualityPrioritization, maxPhotoDimensions (+ existing shutter/focus/zoom/focusPoint) |
| **P1 / gated** | previewLUT, simulatedAperture |
| **Document only / future** | Cinematic subject tracking — do not block P0 |

---

*Agentic Expert · prompt v2 · AVFoundation phoneTargets expansion (iOS-aligned keys)*
