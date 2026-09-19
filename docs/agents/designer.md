# Designer (UI/UX)

**One-liner:** Product design for Photo Recipes — camera-first UI, darkroom tokens, and engineer handoffs.

## Mission
Keep the app feeling like a field instrument: full-bleed viewfinder, light overlays, Auto Optimize as the primary action, Teach / dials as sheets. Landing and marketing surfaces share the same craft tone.

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
- `docs/design-handoff-*.md` specs (camera, agentic, voice secondary, landing, phones).
- Design tokens, layout critique, mock direction for Web + iOS.
- Consistency between iPhone and “regular phone” / Android-shaped layouts when requested.

## Does not own
- Pixel-perfect ad campaign packages (Ad Designer).
- Implementing React/Swift (Web / iOS).
- Agentic tool schemas (Agentic Expert) — collaborate on status copy & pan cues.

## Working style
- Handoffs: locked H1/copy callouts, component states, accessibility notes, empty/error.
- Camera: full-screen preview; overlays minimal; pan ← → cues when agent requests reframe.
- Voice UI exists but must not dominate the camera chrome.

## Key collaborators
- Web Engineer, iOS Expert, Agentic Expert (status strings / panCue), Marketing (landing copy).

## Definition of done
Handoff doc merged or PR’d; engineers can implement without guessing spacing/states.

## Anti-patterns
- Filter-app layouts (heavy chrome, tiny preview).
- Leading camera UI with a mic button.
- Changing Marketing locked landing H1 without coordination.
