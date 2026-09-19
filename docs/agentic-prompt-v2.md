# Agentic Prompt v2 — Auto Optimize / Recommend

**Extends:** [`design-handoff-agentic-v1.md`](./design-handoff-agentic-v1.md)  
**Implements:** Sense → reason with tools → act (phone targets) → verify (mental check) → finalize  
**Server:** `server/recommend.ts` (`POST /api/recommend`)  
**Related:** `server/describeScene.ts` (scene prefill), `server/stt.ts` (voice → scene note)

---

## 1. Full revised system prompt (copy-pasteable)

Keep this text in sync with `buildSystemPrompt()` in `server/recommend.ts`. Favorites and vision sense lines are interpolated at runtime.

```
You are the Photo Recipes field assistant for Auto Optimize (Camera) and Ask / Photo Vision (web + iOS).
Tone: darkroom field notes — quiet, concrete, instructor-at-your-shoulder. Never chatty. Never invent recipes.

LOOP (strict):
1. SENSE — {vision: Inspect the attached image plus any scene note. Infer light (direction/quality/contrast), motion, subject, depth cues, and dynamic range. Status-ready — think like a viewfinder caption, not a chat reply. | text: Infer light, motion, subject, and depth from the photographer's scene note. Status-ready field notes only.}
2. REASON — Call list_presets. Optionally get_preset_details for 1–2 candidates. Pick exactly ONE catalog id.
3. ACT / FINALIZE — Call select_preset with structured phoneTargets + coachOnly (+ panCue when motion/panning fits).
4. VERIFY (mental check before select_preset) — Targets match the recipe technique; shutter/ISO/EV are phone-plausible; aperture/ND/tripod stay in coachOnly; panCue only for panning/motion recipes.

CRITICAL RULES:
- Catalog only: never invent preset ids, titles, or off-catalog recipes.
- You MUST use tools. Do not free-form recommend without select_preset.
- phoneTargets = only what a phone camera API can apply: shutter, iso, ev, whiteBalance, focusMode.
- coachOnly = aperture, nd, tripod, notes — shown to the photographer, NOT applied on device.
- teachWhy = 1–2 short sentences for Teach mode ("Why this?").
- tips = max 3 short field tips.
- panCue = optional { direction: left|right|either, note? } when the subject moves and panning helps.
- senseSummary = optional one-line status (light/motion/subject).
- Bounded loop: finish with select_preset promptly. Do not keep listing after you know the answer.
- Match technique to the scene (sunset + dark foreground → HDR; kid/cyclist running → panning/motion; full-frame sharpness → depth of field; fresh angle → get low).
[+ optional favorites line]
```

---

## 2. Tool schemas

### `list_presets`

| | |
|--|--|
| **Args** | `{}` (no properties) |
| **Returns** | `{ presets: [{ id, title, page, tags, description, whenToUse, keySettings, gear }] }` |
| **When** | First reason step — always before inventing a pick |

### `get_preset_details`

| | |
|--|--|
| **Args** | `{ presetId: string }` (required) |
| **Returns** | Full preset: dials, steps, tips, gear, phoneTip, advancedTip, subVariants… |
| **Errors** | Unknown id → `Use an id from list_presets` |
| **When** | Optional depth on 1–2 candidates before finalize |

### `select_preset` (finalize)

| Field | Required | Notes |
|-------|----------|--------|
| `presetId` | ✓ | Exact catalog id |
| `reason` | ✓ | Coach-style (Ask / depth); 1–3 short sentences |
| `teachWhy` | ✓ | Teach mode one-liner; 1–2 sentences; no model jargon |
| `tips` | | Array of strings; **max 3** |
| `phoneTargets` | ✓ | Object; see §3 (may be empty `{}` if nothing phone-applicable) |
| `coachOnly` | ✓ | Object; aperture / nd / tripod / notes |
| `panCue` | | `{ direction: 'left'\|'right'\|'either', note? }` when panning fits |
| `senseSummary` | | One-line status: light / motion / subject |

**Validation (server):** unknown `presetId` rejected; empty `reason` / `teachWhy` rejected; `tips.length > 3` rejected; bad `panCue.direction` rejected. Failed select does **not** end the loop — model can retry with a valid id.

---

## 3. Phone-settable vs coach-only

| Setting | Bucket | Why |
|---------|--------|-----|
| Shutter speed | **phoneTargets.shutter** | AVFoundation / Camera2 can set exposure duration |
| ISO | **phoneTargets.iso** | Device ISO lock / bias |
| EV / exposure compensation | **phoneTargets.ev** | Common phone API |
| White balance | **phoneTargets.whiteBalance** | Auto / daylight / cloudy / etc. |
| Focus mode | **phoneTargets.focusMode** | Continuous / locked / near / infinity cues |
| Aperture (f-stop) | **coachOnly.aperture** | Most phones have fixed or non-API aperture; show as guidance |
| ND filter | **coachOnly.nd** | Physical / accessory advice |
| Tripod | **coachOnly.tripod** | Boolean recommendation |
| Brace / flash / rear-curtain / etc. | **coachOnly.notes** | Free-form coach guidance |

iOS Auto Optimize may still map catalog `preset.dials` locally today; `phoneTargets` is the agentic contract for future apply without conflating coach-only values.

---

## 4. Loop: sense → list/details → select → verify

```
round ≤ MAX_ROUNDS (5)
  ├─ tool_choice: "required" on early rounds until list/details seen
  │    (falls back to "auto" if the model rejects "required")
  ├─ no tool_calls → nudge user message: must call list_presets → select_preset
  ├─ list_presets / get_preset_details → continue
  ├─ select_preset ok → return RecommendResult (end)
  ├─ select_preset error (unknown id, missing teachWhy, …) → tool error to model, continue
  └─ after list + round≥2 without select → nudge: finalize now
if exit without select → HTTP 502: "did not call select_preset within the tool-call limit"
```

**tool_choice strategy (documented + implemented):**

| Condition | `tool_choice` |
|-----------|----------------|
| No successful list/details yet, round &lt; 2 | `"required"` (retry `"auto"` on 400/422) |
| Otherwise | `"auto"` |

---

## 5. Failure modes

| Failure | Behavior |
|---------|----------|
| Empty message and no image | 400 — message or image required |
| Unknown `presetId` in select | Tool error; loop continues |
| Missing `reason` / `teachWhy` | Tool error; loop continues |
| `tips` &gt; 3 | Tool error; loop continues |
| Model free-chats (no tools) | Nudge; continue rounds |
| Never calls `select_preset` by round 5 | 502 clear error string |
| xAI model 404 | Fall back vision/text model queue |
| `tool_choice: required` rejected | One retry with `auto` |
| Missing `XAI_API_KEY` | 503 from index |
| Free Peek quota exhausted | 402 from entitlements (unchanged) |

---

## 6. API response shape (additive)

`POST /api/recommend` JSON (existing fields kept; new fields additive for iOS/web):

```json
{
  "presetId": "panning-sharp-subject",
  "reason": "…",
  "teachWhy": "Panning keeps the subject sharp while the background streaks.",
  "tips": ["Start at 1/30", "Rotate from the hips", "Follow through after the shutter"],
  "phoneTargets": { "shutter": "1/30", "iso": "auto", "ev": "0", "focusMode": "continuous" },
  "coachOnly": { "aperture": "auto", "tripod": false, "notes": "Brace elbows; pan with subject" },
  "panCue": { "direction": "left", "note": "Match subject speed left→right" },
  "senseSummary": "Cyclist moving left; soft side light",
  "preset": { "...": "full RecipePreset" },
  "model": "grok-4.6",
  "vision": true
}
```

Older clients that ignore unknown keys (current iOS `RecommendResponse`, web FieldCoach) keep working.

---

## 7. Compatibility — iOS Auto Optimize + web Ask/Vision

| Client | Contract |
|--------|----------|
| **iOS Auto Optimize** | Still uses `presetId` / `reason` / `preset` / `tips`. Can adopt `teachWhy`, `phoneTargets`, `panCue`, `senseSummary` for Teach sheet + apply without schema break. |
| **iOS Ask** | Same recommend endpoint; additive fields optional. |
| **Web FieldCoach / Ask** | Reads `reason`, `tips`, `preset`; new fields ignored until UI wired. |
| **describe-scene** | Status-ready scene note → feeds Sense as text/note; not a recommend. |
| **STT** | Photo keyterms bias; transcript becomes scene note for recommend. |
| **Quota** | Free Peek Ask/Vision/Auto Optimize pool unchanged (`checkAskGrokQuota`). |

---

## 8. Branch / base notes

This PR is based on `feat/fieldcoach-voice-input` (PR #4) so `describeScene.ts` / `stt.ts` and their index mounts ship with aligned field-coach tone. Prefer merging #4 first, or merge this PR which includes those routes.

---

*Agentic Expert · prompt v2*
