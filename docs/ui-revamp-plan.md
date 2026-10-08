# ProTune Camera UI Revamp Plan

## Goal
Make the camera UI as clean as the reference (photo 1): one clear message,
minimal chips, obvious hierarchy. Remove the clutter in the current UI (photo 2).

## Principles
1. **One message at a time.** Never show the same text in two places.
2. **Human words, not jargon.** "Brightened 2 stops" not "-2.1 EV residual".
3. **Progressive disclosure.** Advanced details (iterations, readback values)
   go behind a tap, not on the main screen.
4. **The viewfinder is sacred.** Every pill/chip must earn its pixels.

---

## Issues in current UI (photo 2)

| # | Problem | Where |
|---|---|---|
| 1 | Duplicate exposure text (yellow carousel + dark pill, same message) | Mid-screen |
| 2 | Technical jargon: "-2.1 EV off target", "iteration(s)", "residual" | Both pills |
| 3 | Contradictory: "corrected in 2 iterations" but "residual -2.1 EV" | Message copy |
| 4 | Pill stacking: AE/AF LOCK + Panning + camera + ... all crowded at top | Top bar |
| 5 | Too many action rows: "From viewfinder / steady scene" + Auto Optimize + Hold to compare + Undo + "Panning 3 settings updated" | Bottom half |
| 6 | "Pan with the subject" hint competes with shutter button | Bottom |
| 7 | "Crisp Cool · 0.6" dismissable chip + separate "Steady scene" — unclear relationship | Mid-screen |

## Target UI (photo 1)

- Top: flash, AE/AF LOCK pill, flip camera, ... — 4 items max, generous spacing
- Center: focus square only
- One human-readable status line: "Brightened 2 stops, still a bit dark"
- Two context chips max: look chip ("✨ Crisp Cool 0.6"), scene chip ("〰️ Steady scene")
- Mode label ("Panning") above shutter, subtle
- Bottom: gallery, shutter, mode — nothing else

---

## Changes

### 1. Single status message (fixes #1, #2, #3)
- **Remove** `session.clampMessages.append(contentsOf: verifyNotes)` in
  `AutoOptimizeController.swift` — verify notes go only to `verifyWarning`.
- **Rewrite** verify note copy to human-readable:
  - Was: "Exposure was -2.1 EV off target — corrected in 2 iteration(s); residual -2.1 EV."
  - Now: "Brightened 2 stops, still a bit dark" / "Brightened 2 stops" / "A bit dark"
- Rule: if residual ≤ 0.3 EV, don't mention it (correction succeeded).
  If residual > 0.3 EV, say "still a bit dark/bright" — never "residual".
- **Done** (this session).

### 2. Collapse the bottom action stack (fixes #5)
Current has 5 rows competing. Target has 1 (shutter row).

- **Merge** "Hold to compare" + "Undo" into a single row that appears only
  after Auto Optimize runs (not persistently).
- **Fold** "Panning · 3 settings updated" into the mode label above the
  shutter — tap to expand details, don't show a separate pill.
- **Remove** the "From viewfinder / steady scene" row — the "Steady scene"
  chip already conveys this.

### 3. Top bar breathing room (fixes #4)
- AE/AF LOCK and Panning mode shouldn't both be pills at the top.
- **Keep** AE/AF LOCK as a pill (it's a state the user set).
- **Demote** Panning to the subtle mode label above the shutter (as in photo 1).
- Result: flash, AE/AF LOCK, flip, ... — 4 items with spacing.

### 4. Chip consolidation (fixes #7)
- "Crisp Cool · 0.6" (look) and "Steady scene" (detection) are different
  concepts — keep both, but make the distinction visual:
  - Look chip: ✨ icon, tappable to change look
  - Scene chip: 〰️ icon, informational only (no X button)
- **Remove** the X dismiss button on the look chip in the viewfinder —
  dismissal belongs in the look picker, not as chrome on the camera.

### 5. Hint text (fixes #6)
- "Pan with the subject" should be a transient coachmark on first Panning
  mode use, not a persistent label.
- Show once per mode, dismiss on shutter press or after 5 seconds.

### 6. Detail drawer (progressive disclosure)
- Technical details (iterations, ISO/shutter readback, residual EV) move to
  a "Details" disclosure inside the post-optimize result sheet.
- Developers and curious users can still find them; they don't clutter
  the viewfinder.

---

## Files to touch
- `ios/PhotoRecipes/Services/AutoOptimizeController.swift` — copy rewrite (done),
  remove clampMessages duplication (1-line)
- `ios/PhotoRecipes/Features/Camera/CameraView.swift` — bottom stack collapse,
  top bar layout, chip consolidation, transient hint
- `ios/PhotoRecipes/Features/Camera/AgentStatusPill.swift` — single-message logic
- `ios/PhotoRecipes/Features/Camera/TeachModeSheet.swift` — details drawer

## Out of scope
- Changing the Auto Optimize engine behavior (exposure planner, closed-loop)
- The Ask/voice UI
- Onboarding flow

## Acceptance
- Fresh Auto Optimize run shows: one status line, ≤2 chips, shutter row — nothing else
- No technical jargon visible without tapping "Details"
- No duplicate text anywhere on screen
- Matches photo 1 layout for the steady-state viewfinder
