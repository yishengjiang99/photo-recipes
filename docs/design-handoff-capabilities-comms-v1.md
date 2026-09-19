# Photo Recipes — In-product Capabilities Comms v1 (iOS-first)

**Audience:** iOS Expert + Agentic Expert (+ CoS for relay).  
**Question:** How do we explain *new* agentic levers + Creative Looks without overwhelming enthusiasts or turning Camera into a filter app?  
**Platform:** **iOS-first** until further notice. Web marketing can echo later; do not block iOS on web UI.  
**Extends:** [`design-handoff-camera-v1.md`](./design-handoff-camera-v1.md), [`design-handoff-agentic-v1.md`](./design-handoff-agentic-v1.md).  
**Aesthetic:** Darkroom field notes · full-bleed viewfinder · dials/Teach as sheets · voice secondary · **Looks = capture grades, not beauty filters**.

---

## 0. TL;DR (for CoS)

1. **Always visible:** Auto Optimize + status + core before→after (shutter / ISO / EV / WB / focus) + optional **Look chip** when a look is active.  
2. **Progressive disclosure:** Advanced levers live in **Dials sheet** tabs (Core · Light · Lens · Capture · Looks) — never a wall of toggles on the viewfinder.  
3. **Looks:** Named capture grades with intensity 0–1; live preview; Auto Optimize may *suggest* a look as a chip — user confirms; never silent beauty skin.  
4. **First-run:** 3 coach marks max (Optimize → chips → ··· for more). Teach sheet explains *why* including look + advanced writes.  
5. **Trust language:** “Wrote on camera” vs “Coach-only” vs “Look grade (capture)” — never “filter” / “enhance face.”

---

## 1. Capability tiers (IA)

### Tier A — Core story (always teachable in one breath)

Point → **Auto Optimize** → writes **shutter / ISO / EV / WB / focus** (+ zoom/lens when available).  
Slogan remains: **Set the shot. Then take it.**

### Tier B — New agentic levers (power users; disclose on demand)

| Group | Levers |
|-------|--------|
| Exposure | Custom exposure |
| Lens | Lens position · UW / Wide / Tele |
| Color | WB temp / tint |
| Light tools | Torch / flash · Low-light boost |
| Video / format | Video HDR · fps / format |
| Capture quality | Photo quality · Brackets / HDR |
| Session | Subject re-optimize |

### Tier C — Creative Looks pack (named grades)

`crispCool` · `warmGlow` · `warmPop` · `editorialRed` · `softVintage` · `monoInk` · `goldenHour` · `loFiPunch` · `tealOrange` · `blockbuster` · `moodyFilm` · `coolBlue` · `softDream` · `filmGrain`

- Intensity **0–1** (default ~0.55–0.7 when agent suggests).  
- **Live on viewfinder** while adjusting.  
- Auto Optimize **may suggest**; never apply a look without a visible chip / undo.  
- Positioning copy: **capture grade** / **look** — not filter, LUT beauty, or “AI skin.”

### Tier D — Coach-only (unchanged)

Aperture · ND · tripod — guidance only; never claim device write.

---

## 2. What’s always visible vs progressive

### Always on viewfinder (overlays only)

```
[ status pill ]     e.g. Reading light… / Ready to capture
[ before→after ]    Core chips (collapsed → expand)
[ Look chip ]       Only if look active or suggested (dismissible)
[ ⚡ Auto Optimize ]
[ shutter ]
[ ··· ]             Opens Controls sheet (dials / looks / teach)
```

- **Do not** pin fps, torch, Video HDR, brackets, or the full looks grid on-canvas.  
- Pan ← → cues stay ephemeral (agentic handoff).  
- Mic stays de-emphasized (existing voice handoff).

### Progressive — Controls sheet (`···`)

Single sheet, segmented or tabs:

| Tab | Contents |
|-----|----------|
| **Core** | Shutter · ISO · EV · WB · Focus (+ zoom). Same as today. |
| **Light** | Torch/flash · Low-light boost · custom exposure extras |
| **Lens** | UW / Wide / Tele · lens position |
| **Capture** | Photo quality · brackets/HDR · Video HDR · fps/format |
| **Looks** | Grid of look names + intensity slider + “Suggested” badge |

Footer of sheet: **Teach why** link · **Reset to Auto** · Pro gate if needed.

### Library / Ask

- Recipes still stage **Core** (+ optional look id).  
- Don’t dump Tier B list on Library cards — one line max: `+ Look: goldenHour` when relevant.

---

## 3. Auto Optimize: before→after + Look chip

### Core chips (required)

After apply, show compact before→after for **Tier A** (same agentic chip pattern):

```
Shutter  1/500 → 1/60
ISO      100 → 400
EV       0 → −0.3
WB       Auto → Daylight
Focus    Cont. → Locked
```

- Collapsed default: one line `5 settings updated ▾`  
- Expanded: full stack  
- Tap → Core tab of Controls sheet

### Look chip (when relevant)

| State | UI |
|-------|-----|
| **Suggested** | Chip: `Look · goldenHour · 0.6` + `Apply` / `Dismiss` |
| **Active** | Chip: `goldenHour · 0.6` + `×` clear · tap opens Looks tab |
| **None** | No chip (don’t reserve empty chrome) |

**Agent status examples:**  
`Matching a recipe…` → `Applying shutter & ISO…` → `Suggesting look: warmGlow…` → `Ready to capture`

If look suggested: status may read `Ready · look suggested` until user applies or dismisses.

### Intensity

- Slider only inside Looks tab / look detail — not a second floating dial on the finder.  
- Live preview while dragging; commit on release.  
- Haptic light tick optional at 0 / 0.5 / 1.

---

## 4. First-run / coach marks (max 3)

Show once (Settings → “Show camera tips” to replay). Dimmed scrim, one spotlight each:

1. **Auto Optimize** — “Point at the shot. We set shutter, ISO, EV, WB, and focus.”  
2. **Before→after chips** — “See exactly what changed. Tap to tweak.”  
3. **··· Controls** — “Light, lens, capture tools, and Looks live here — so the finder stays clear.”

**Do not** coach-mark every new lever. Power features discover via sheet + Teach.

Skip if user already completed ≥1 successful Auto Optimize (optional heuristic).

---

## 5. Teach “why” (sheet)

Entry: Teach control · tap chip · post-optimize “Why this?”

Structure:

1. **Recipe / intent** (serif title)  
2. **What we wrote (Core)** — before→after table  
3. **What we wrote (Advanced)** — only rows that changed (torch on, Tele, etc.)  
4. **Look** — if any: name, intensity, one craft sentence (“Cool contrast for overcast steel”)  
5. **Coach-only** — aperture / ND / tripod notes  
6. **Subject re-optimize** — CTA: `Re-optimize on subject` when available

Tone: field notebook, short bullets — not a chat essay.

---

## 6. Empty / error / gated states

| State | Copy / UI |
|-------|-----------|
| No recipe / cold start | Finder only; Optimize enabled; no look chip |
| Optimize failed | Status `Couldn’t optimize` · chip `Retry` · keep last good settings |
| Lever unsupported on device | Row disabled + caption `Not available on this camera` |
| Look failed to apply | Toast `Look couldn’t apply` · clear suggested chip |
| Pro gate (advanced / looks pack if gated) | Sheet over finder: `Unlock Looks & manual controls` · trial CTA — **no pink wash on preview** |
| Permission denied | Existing camera permission cover |
| Low light / boost on | Quiet status `Low-light boost on` — not a banner wall |
| Bracket capture | Status `Bracket 2/3…` then return to Ready |

---

## 7. Naming & copy rules

| Prefer | Avoid |
|--------|--------|
| Look / capture grade | Filter, beauty, enhance, magic skin |
| Wrote / applied settings | AI-enhanced your photo |
| Suggested look | Auto-beautified |
| Controls / dials | Effects panel, FX rack |
| Intensity | Strength / drama (OK in craft copy sparingly) |

**Display names for looks** (UI title case; ids stay camelCase):

| id | Label |
|----|-------|
| crispCool | Crisp Cool |
| warmGlow | Warm Glow |
| warmPop | Warm Pop |
| editorialRed | Editorial Red |
| softVintage | Soft Vintage |
| monoInk | Mono Ink |
| goldenHour | Golden Hour |
| loFiPunch | Lo-Fi Punch |
| tealOrange | Teal & Orange |
| blockbuster | Blockbuster |
| moodyFilm | Moody Film |
| coolBlue | Cool Blue |
| softDream | Soft Dream |
| filmGrain | Film Grain |

---

## 8. Density rules (anti overwhelm)

1. Viewfinder chrome count after optimize: **status + chips row + Optimize + shutter + ···** (± pan, ± look).  
2. Never show &gt;1 suggested look at once.  
3. Tier B changes appear in Teach / sheet — not as 12 simultaneous chips.  
4. Optional “More changes” link under core chips opens Capture/Light tabs if Tier B wrote anything.  
5. Looks grid: 2-col on phone; search/filter later — v1 is scrollable grid with Suggested pin.

---

## 9. Relationship to marketing

- App Store / landing stay on **Tier A elevator**.  
- Looks & Tier B are **in-product discovery** + optional later marketing beat — don’t lead ads with a 14-look wall.  
- No GitHub CTAs on marketing (landing v2).

---

## 10. iOS Engineer checklist

- [ ] Viewfinder stays full-bleed; advanced UI only in sheet tabs  
- [ ] Core before→after + optional Look chip states (suggested / active / none)  
- [ ] Auto Optimize may emit look suggestion; require explicit Apply  
- [ ] Looks intensity 0–1 live preview  
- [ ] Coach marks ≤3, replayable in Settings  
- [ ] Teach includes Core + Advanced deltas + Look + coach-only  
- [ ] Unsupported levers disabled with caption  
- [ ] Pro gate sheet (if applicable) without washing preview  
- [ ] Copy audit: no “filter” / beauty language  
- [ ] Align status strings with Agentic Expert  

### Out of scope
- Web parity for all levers  
- Voice-led onboarding of looks  
- Pixel ad packages for each look (Ad Designer later)

---

## 11. Definition of done

Engineers can place every new capability in **always / sheet / teach / first-run** without inventing chrome. Enthusiasts see Core trust first; power features open through ··· and Teach.

---

*Designer · capabilities comms v1 · iOS-first*
