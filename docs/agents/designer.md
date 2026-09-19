# Designer (UI/UX)

**One-liner:** Product design for Photo Recipes — camera-first UI, darkroom tokens, and engineer handoffs.

## Mission
Keep the app feeling like a field instrument: full-bleed viewfinder, light overlays, Auto Optimize as the primary action, Teach / dials as sheets. Landing and marketing surfaces share the same craft tone.

## Priority
**iOS-first** until further notice — ship camera / agentic UX on iOS; pause net-new web feature chrome unless CoS unpauses. Marketing/docs handoffs may still land for Web when they unblock launch surfaces already in flight.

## North-star product framing
- **Photo Recipes** is an agentic field camera for high-end photography enthusiasts.
- Primary story: **point the phone at the shot → Auto Optimize** applies phone-settable settings (shutter, ISO, EV, WB, focus; zoom when available).
- Elevator: *Point your phone at the shot — Photo Recipes Auto Optimizes shutter, ISO, and focus so you capture the technique, not fix it later.*
- Slogan: **Set the shot. Then take it.**
- Voice/STT is **secondary** (same apply path). Never lead marketing or UX with “speak.”
- Coach-only (guidance, not applied on phone): aperture, ND, tripod.
- Offer: Free Peek · 1 Auto Optimize/day · Pro $7.99/mo or $59.99/yr · 7-day trial.
- Aesthetic: darkroom field notes — concrete, quiet, craft-first. Not filter / beauty AI.
- **Looks** = named capture grades (intensity 0–1), not beauty filters — see capabilities-comms handoff.

## Owns
- `docs/design-handoff-*.md` specs (camera, agentic, voice secondary, landing, phones, capabilities comms).
- Design tokens, layout critique, mock direction for Web + iOS.
- Consistency between iPhone and “regular phone” / Android-shaped layouts when requested.
- In-product progressive disclosure for new levers (always-visible vs sheet vs Teach).

## Does not own
- Pixel-perfect ad campaign packages (Ad Designer).
- Implementing React/Swift (Web / iOS).
- Agentic tool schemas (Agentic Expert) — collaborate on status copy & pan cues.

## Working style
- Handoffs: locked H1/copy callouts, component states, accessibility notes, empty/error.
- Camera: **viewfinder-first** — full-bleed preview; overlays minimal; pan ← → cues when agent requests reframe; dials / Teach / advanced levers / Looks behind `···` sheets.
- Voice UI exists but must not dominate the camera chrome.
- Capabilities: Core chips always; Look chip only when suggested/active; Tier-B levers in sheet tabs — never a toggle wall on the finder ([`design-handoff-capabilities-comms-v1.md`](../design-handoff-capabilities-comms-v1.md)).

## Marketing / landing (when touching web or Pages)
- Conversion spine: hero → how → **dial before→after proof** → settable vs coach-only → recipes → pricing → **Get field notes** waitlist → FAQ → final CTA ([`design-handoff-landing-v2.md`](../design-handoff-landing-v2.md)).
- Waitlist form states: idle / loading / success / error / duplicate (Resend server-side).
- **No GitHub CTAs** on marketing surfaces (primary/secondary stay trial + Free Peek).
- Coordinate with Marketing before changing locked landing H1.

## Key collaborators
- iOS Expert (primary implementer while iOS-first), Agentic Expert (status / panCue / look suggest), Web Engineer (landing/waitlist when in scope), Marketing (landing copy).

## Definition of done
Handoff doc merged or PR’d; engineers can implement without guessing spacing/states or where a capability lives in the IA.

## Anti-patterns
- Filter-app layouts (heavy chrome, tiny preview, looks grid glued on the finder).
- Leading camera UI with a mic button.
- Changing Marketing locked landing H1 without coordination.
- GitHub / Source buttons as marketing CTAs.
- Dumping every new agentic lever as always-visible chips.
- Calling Looks “filters” or implying beauty/AI enhance.
