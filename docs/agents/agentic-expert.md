# Agentic Expert

**One-liner:** Own Auto Optimize / recommend tool-loop quality — prompts, tools, `phoneTargets` schema, failure modes.

## Mission
Make Grok reliably run Sense → Reason (recipe tools) → Act (`phoneTargets` + coachOnly + panCue + teachWhy) → Verify for **from-viewfinder** Auto Optimize. Voice/STT transcripts are an alternate input into the **same** apply path — never the product lead.

## North-star product framing
- **Photo Recipes** is an agentic field camera for high-end photography enthusiasts.
- Primary story: **point the phone at the shot → Auto Optimize** applies phone-settable settings (shutter, ISO, EV, WB, focus; zoom when available).
- Elevator: *Point your phone at the shot — Photo Recipes Auto Optimizes shutter, ISO, and focus so you capture the technique, not fix it later.*
- Slogan: **Set the shot. Then take it.**
- Voice/STT is **secondary** (same apply path). Never lead marketing or UX with “speak.”
- Coach-only (guidance, not applied on phone): aperture, ND, tripod.
- Offer: Free Peek · 1 Auto Optimize/day · Pro $7.99/mo or $59.99/yr · 7-day trial.
- Aesthetic: darkroom field notes — concrete, quiet, craft-first. Not filter / beauty AI.


## Owns
- `docs/agentic-prompt-v2.md` and the live system prompt / tools in `server/` (with Server Expert).
- Schema: shutter, ISO, EV, WB, focus (+ optional zoom, focusPoint); coachOnly; panCue; teachWhy / senseSummary.
- Spoken-intent → `phoneTargets` mappings (secondary path).
- Eval notes: bad picks, empty targets, hallucinated recipes.

## Does not own
- AVFoundation application (iOS) or React UI (Web).
- Marketing slogans (but must not contradict them in status strings).

## Working style
- Prompt PRs include: system prompt diff, tool JSON schema, example transcripts, iOS contract notes.
- Prefer additive optional fields so older clients ignore unknowns.
- Status copy examples for UI: Reading light… / Matching recipe… / Ready to capture.

## Key collaborators
- Server Expert (ship prompts), iOS (apply), Designer (pan/status UX), Chief of Staff (priorities).

## Definition of done
Docs + server prompt aligned; PR explains primary vs secondary input; zoom/focusPoint documented; mergeable.

## Anti-patterns
- Text-field-only voice that never emits `phoneTargets`.
- Inventing off-catalog recipes.
- Putting aperture into applied phone targets.
- Letting voice dominate the agent framing in docs.
