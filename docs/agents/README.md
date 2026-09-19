# Staff agent prompts

Baseline system prompts for Photo Recipes staff bots. Paste the body of a role file into that bot’s description / system briefing, or keep this folder as the source of truth and sync profiles from here.

## Roles

| Role | File |
|------|------|
| Chief of Staff | [`chief-of-staff.md`](./chief-of-staff.md) |
| Marketing Expert | [`marketing-expert.md`](./marketing-expert.md) |
| Biz Dev | [`biz-dev.md`](./biz-dev.md) |
| Ad Designer | [`ad-designer.md`](./ad-designer.md) |
| Designer (UI/UX) | [`designer.md`](./designer.md) |
| Web Engineer | [`web-engineer.md`](./web-engineer.md) |
| iOS Expert | [`ios-expert.md`](./ios-expert.md) |
| Server Expert | [`server-expert.md`](./server-expert.md) |
| Agentic Expert | [`agentic-expert.md`](./agentic-expert.md) |

## Product agent (not staff)

The **in-app Auto Optimize / recommend** Grok system prompt lives in [`../agentic-prompt-v2.md`](../agentic-prompt-v2.md) and is implemented under `server/`. Agentic Expert owns keeping those in sync. Staff prompts below do **not** replace that file.

## Shared framing

## North-star product framing
- **Photo Recipes** is an agentic field camera for high-end photography enthusiasts.
- Primary story: **point the phone at the shot → Auto Optimize** applies phone-settable settings (shutter, ISO, EV, WB, focus; zoom when available).
- Elevator: *Point your phone at the shot — Photo Recipes Auto Optimizes shutter, ISO, and focus so you capture the technique, not fix it later.*
- Slogan: **Set the shot. Then take it.**
- Voice/STT is **secondary** (same apply path). Never lead marketing or UX with “speak.”
- Coach-only (guidance, not applied on phone): aperture, ND, tripod.
- Offer: Free Peek · 1 Auto Optimize/day · Pro $7.99/mo or $59.99/yr · 7-day trial.
- Aesthetic: darkroom field notes — concrete, quiet, craft-first. Not filter / beauty AI.

## How to update

1. Edit the role file here.
2. PR to `main`.
3. Chief of Staff (or the role owner) syncs the bot profile description if it diverges.
