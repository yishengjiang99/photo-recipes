# Agentic Prompt v2 — Auto Optimize / Recommend

**Extends:** [`design-handoff-agentic-v1.md`](./design-handoff-agentic-v1.md)  
**Implements:** Sense → reason with tools → act (phone targets) → verify (mental check) → finalize  
**Server:** `server/recommend.ts` (`POST /api/recommend`)  
**Related:** `server/describeScene.ts` (scene prefill), `server/stt.ts` (voice → camera intents / Auto Optimize apply path — not text-field-only)

---

## 1. Full revised system prompt (copy-pasteable)

Keep this text in sync with `buildSystemPrompt()` in `server/recommend.ts`. Favorites and vision sense lines are interpolated at runtime.

```
You are the Photo Recipes field assistant for Auto Optimize (Camera) and Ask / Photo Vision (web + iOS).
Tone: darkroom field notes — quiet, concrete, instructor-at-your-shoulder. Never chatty. Never invent recipes.

LOOP (strict):
1. SENSE — {vision: Inspect the attached image plus any scene note. Infer light (direction/quality/contrast), motion, subject, depth cues, and dynamic range. Status-ready — think like a viewfinder caption, not a chat reply. | text: Infer light, motion, subject, and depth from the photographer's scene note. Status-ready field notes only.}
2. REASON — Call list_presets. Optionally get_preset_details for 1–2 candidates. Pick exactly ONE catalog id (keep current recipe if it fits, or a better catalog match).
3. ACT / FINALIZE — Call select_preset with structured phoneTargets + coachOnly (+ panCue when motion/panning fits).
4. VERIFY — Targets match the recipe technique and any spoken control ask; shutter/ISO/EV/zoom phone-plausible; aperture/ND/tripod in coachOnly; panCue only for panning/motion.

VOICE / SPOKEN CAMERA INTENTS:
- STT transcripts may be camera control asks — still call tools and emit phoneTargets (same apply path as Auto Optimize / AVCapture). Never text-field-only.
- Examples: "slower shutter for panning" → shutter + panCue; "lock focus on the rider" → focusMode (+ focusPoint); "go to 2x" → zoom; EV/WB similarly.
- Control adjustments: phoneTargets MUST include the relevant keys (not empty {}).

CRITICAL RULES:
- Catalog only: never invent preset ids, titles, or off-catalog recipes.
- You MUST use tools. Do not free-form recommend without select_preset.
- phoneTargets = phone-settable: shutter, iso, ev, whiteBalance, focusMode, zoom, focusPoint.
- coachOnly = aperture, nd, tripod, notes — NOT applied on device.
- teachWhy / tips / panCue / senseSummary — same as before.
- Bounded loop: finish with select_preset promptly.
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

| Setting | Bucket | Why / iOS contract |
|---------|--------|--------------------|
| Shutter speed | **phoneTargets.shutter** | AVFoundation exposure duration (`string`, e.g. `"1/30"`) |
| ISO | **phoneTargets.iso** | Device ISO lock / bias (`string`) |
| EV / exposure compensation | **phoneTargets.ev** | Common phone API (`string`, e.g. `"+0.7"`) |
| White balance | **phoneTargets.whiteBalance** | Auto / daylight / cloudy / etc. (`string`) |
| Focus mode | **phoneTargets.focusMode** | Continuous / locked / near / infinity (`string`) |
| Focus point | **phoneTargets.focusPoint** | Optional `{ x, y }` floats **0–1** for tap-to-focus; omit if `focusMode` alone is enough |
| Zoom | **phoneTargets.zoom** | Number = `AVCaptureDevice.videoZoomFactor` (1 = 1×, 2 = 2×). Clients may map discrete values to lens switch (0.5 UW, 1 wide, 2 tele). Server also accepts `"2x"` strings and normalizes to a number. |
| Aperture (f-stop) | **coachOnly.aperture** | Most phones have fixed or non-API aperture; show as guidance |
| ND filter | **coachOnly.nd** | Physical / accessory advice |
| Tripod | **coachOnly.tripod** | Boolean recommendation |
| Brace / flash / rear-curtain / etc. | **coachOnly.notes** | Free-form coach guidance |

**Additive / optional:** every `phoneTargets` key is optional. Older iOS builds that do not know `zoom` / `focusPoint` must **ignore unknown keys** (JSON decode with unknown keys discarded). Do not require new keys for catalog-only Auto Optimize.

iOS Auto Optimize applies `phoneTargets` to the live `AVCapture` session (same path for voice follow-ups and button Auto Optimize). `coachOnly` stays UI-only.

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
  "phoneTargets": { "shutter": "1/30", "iso": "auto", "ev": "0", "focusMode": "continuous", "zoom": 1, "focusPoint": { "x": 0.5, "y": 0.4 } },
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
| **STT** | Photo keyterms bias; transcript is a **camera intent** for the shared Auto Optimize apply path (recommend → phoneTargets → AVCapture) — not Ask text-field-only. |
| **Quota** | Free Peek Ask/Vision/Auto Optimize pool unchanged (`checkAskGrokQuota`). |

---

## 8. Voice → STT → recommend tools → apply phoneTargets

Voice is **not** text-field-only. It shares the Auto Optimize apply path:

```
Mic capture
  → POST /api/stt (Grok STT, photo keyterms)
  → transcript as recommend `message` (spoken camera intent and/or scene note)
  → POST /api/recommend (agent tools: list_presets → select_preset)
  → response.phoneTargets (+ panCue if needed) applied to AVCapture session
  → optional teachWhy / tips shown in Teach / coach UI
```

| Step | Owner | Contract |
|------|-------|----------|
| STT | Server `stt.ts` | `{ text }` transcript — camera intent vocabulary |
| Recommend | Server `recommend.ts` | Tools + `phoneTargets` / `panCue` / `teachWhy` |
| Apply | **iOS** (Ios Expert) | Map `phoneTargets` → session (shutter/ISO/EV/WB/focus/zoom/focusPoint); show `panCue`; optional Teach sheet |
| Web Ask | Web | May still treat transcript as Field Coach text until wired; ignore unknown keys |

**Same apply path:** button Auto Optimize and voice follow-ups both end in applying `phoneTargets` to the capture session. Voice must not only fill an Ask text field.

---

## 9. Spoken-intent → phoneTargets mappings

| Spoken intent (example) | phoneTargets / extras |
|-------------------------|------------------------|
| "slower shutter for panning" | `shutter` (e.g. `"1/30"`) + **`panCue`** `{ direction, note? }` + `teachWhy` |
| "lock focus on the rider" | `focusMode: "locked"` + optional **`focusPoint: { x, y }`** (0–1) if a region can be inferred |
| "zoom in" / "go to 2x" | **`zoom`** number (`2` = 2× `videoZoomFactor`; lens-switch hint OK) |
| "pull EV down a stop" | `ev: "-1"` |
| "daylight white balance" | `whiteBalance: "daylight"` |
| "keep ISO low" | `iso: "100"` (or scene-appropriate) |
| Full scene Auto Optimize (no control tweak) | Full `phoneTargets` from recipe technique; may omit `zoom` / `focusPoint` |

When the user asks for a **control adjustment**, `select_preset` must still run (catalog id may stay the current recipe or switch to a better match) and **`phoneTargets` must include the keys that match the ask** — do not finalize with `{}` for a shutter/focus/zoom request.

---

## 10. iOS Expert — schema contracts to implement

Leave wiring to Ios Expert; server/doc contract:

1. **Decode additively** — ignore unknown `phoneTargets` keys on older builds.
2. **`zoom?: number`** — set `AVCaptureDevice.videoZoomFactor` (clamp to device min/max). Optionally map 0.5 / 1 / 2 to ultra-wide / wide / tele lens switch when available.
3. **`focusPoint?: { x, y }`** — 0–1 normalized; drive tap-to-focus / focus-of-interest. If omitted, apply `focusMode` only.
4. **Shared apply** — voice recommend responses use the **same** apply helper as Auto Optimize (shutter, ISO, EV, WB, focus, zoom).
5. **`panCue`** — overlay / coach cue only; not an AVCapture lock.
6. **`teachWhy`** — Teach mode sheet; optional after apply.

---

## 11. Branch / base notes


This PR is based on `feat/fieldcoach-voice-input` (PR #4) so `describeScene.ts` / `stt.ts` and their index mounts ship with aligned field-coach tone. Prefer merging #4 first, or merge this PR which includes those routes.

---

*Agentic Expert · prompt v2*
