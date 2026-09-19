# Photo Recipes — Agentic Auto Optimize Handoff v1

**Extends:** [`design-handoff-v1.md`](./design-handoff-v1.md) · [`design-handoff-camera-v1.md`](./design-handoff-camera-v1.md)  
**North star:** Agentic AI that **automatically optimizes** photo-taking:

> **Sense → reason with tools → apply camera settings → verify → capture**

**Aesthetic:** Darkroom field notes — quiet chrome, aperture-ring dials, one loud action. The agent is a **field assistant**, not a chat bubble or neon copilot.

**Primary surface:** Camera (iOS). Library recipes + Ask/Vision become **tools the agent can call**, not competing home screens.

---

## 0. Product model (UI consequences)

| Stage | What the system does | What the user sees |
|-------|----------------------|--------------------|
| **Sense** | Scene light / motion / subject cues (vision + meter) | Status: `Reading light…` / `Sensing motion…` |
| **Reason + tools** | Pick/confirm recipe, clamp to device, explain | Status: `Matching recipe…` / `Applying panning recipe…` |
| **Apply** | Write MODE / aperture / shutter / ISO (etc.) | Dials animate; before→after chip |
| **Verify** | Re-check exposure / blur risk | Status: `Checking exposure…` · optional warn chip |
| **Capture** | Ready for shutter (or auto-capture if user enabled) | Status: `Ready` · shutter emphasis |

**Auto Optimize** is the **primary CTA** on Camera (alongside shutter). Shutter still takes the photo; Auto Optimize runs the agent loop that prepares the session.

### Entitlements (align with existing Pro)
| | Free Peek | Pro |
|--|-----------|-----|
| Manual viewfinder + Auto mode | ✓ | ✓ |
| Auto Optimize runs / day | **1** (shared with Ask/Vision quota if product keeps one pool — confirm with CoS; UI assumes **1 combined agent run/day** on Free) | Unlimited |
| Teach mode (why) full copy | Short teaser | Full |
| Manual override after agent | Read-only ghost → upgrade to edit | Full dials |

---

## 1. Design principles

1. **Status over chat** — agent communication is a compact status line + chips, not a scrolling transcript on the viewfinder.
2. **Settings are visible** — every apply shows **before → after** so trust is earned.
3. **User can seize the wheel** — Manual override drawer always one tap away after/during a run (Pro).
4. **Teach mode is optional depth** — “Why?” reveals recipe + reasoning; default stays shoot-ready.
5. **One loud action** — Auto Optimize uses `accent`; shutter keeps ring+core language from camera handoff.
6. **No dual neon AI panels** — agent chrome uses scrims, hairlines, accent-muted pills only.

### Extra tokens
| Token | Value | Role |
|-------|--------|------|
| `agent-status-bg` | `rgba(0,0,0,0.55)` | Status pill over preview |
| `agent-running` | `#fb7185` (`accent-soft`) | Spinner / pulse on status |
| `agent-ready` | `#34d399` (`success`) | Ready state |
| `agent-warn` | `#e7b549` (`tip`) | Verify warnings |
| `diff-before` | `#8b8b96` | Before value in chip |
| `diff-after` | `#f5f5f7` | After value in chip |

---

## 2. Viewfinder chrome — Auto Optimize as primary CTA

### Bottom bar (portrait) — revised

```
┌─────────────────────────────────────────┐
│ [Gallery]   ( SHUTTER )   [Dials]       │
│                                         │
│     [ ⚡ Auto Optimize ]                │  ← full-width or prominent pill ABOVE shutter row
│     status / chips stack                │
└─────────────────────────────────────────┘
```

**Layout rule:** Auto Optimize sits **above** the shutter row as the **primary text CTA** (height 48–52, `accent` fill, white label, bolt or aperture icon). Shutter remains the physical capture control (center, large). Do **not** replace shutter with Auto Optimize.

**Alternative (landscape / iPad):** Auto Optimize as vertical accent button opposite shutter; same hierarchy.

### Idle label
- Free with quota: `Auto Optimize` · caption `1 left today`
- Free exhausted: `Auto Optimize` disabled 40% + tap → paywall  
- Pro: `Auto Optimize` · no quota caption

### While running
- Button → `Optimizing…` with spinner; non-reentrant (ignore double taps).
- Optional: Cancel text button `Stop` (`ink-secondary`) trailing on status row.

### After ready
- Button label returns to `Auto Optimize` (re-run).
- Secondary ghost: `Teach me why` (opens Teach mode §6).

---

## 3. Agent status line

**Placement:** Floating above Auto Optimize / bottom scrim, centered or leading; max 2 lines.

**Component:** Pill `agent-status-bg`, radius `pill`, padding 10×14, `body-sm` white.

| Phase | Example copy |
|-------|----------------|
| Sense | `Reading light…` · `Sensing motion…` · `Finding subject…` |
| Reason | `Matching a recipe…` · `Calling exposure tools…` |
| Apply | `Applying panning recipe…` · `Setting 1/60 · ISO 400…` |
| Verify | `Checking exposure…` · `Motion risk — holding shutter speed` |
| Ready | `Ready to capture` (icon check, `agent-ready` dot) |
| Error | `Couldn’t optimize — try again` (`danger`) |

**Motion:** soft pulse on leading dot while running (`agent-running`); steady `agent-ready` when done. 150ms fade between copy updates — no typewriter theater.

**Accessibility:** VoiceOver announces status changes; Respect Reduce Motion (no pulse).

---

## 4. Before / after settings chip

**When:** Appears as soon as Apply commits values; stays until Clear / new run / timeout (session).

**Component:** Horizontal chip or compact card over preview (above status):

```
A  f/2.8 → f/8    ·    1/500 → 1/60    ·    ISO 100 → 400
```

- Before: `diff-before`, strikethrough optional  
- Arrow `→` hairline  
- After: `diff-after` semibold / mono  
- Leading recipe mark if a catalog recipe was chosen: small accent dot + truncated name

**Tap chip →** opens Manual override drawer pre-scrolled to dials (§5) or Teach mode if user has Teach toggled on.

**Clamp:** If device clamped, after value shows actual; tiny tip caption `clamped` under aperture/shutter as needed.

---

## 5. Manual override drawer

Same Manual dials overlay as camera handoff §4, with agent-specific additions:

1. **Header:** `Manual override` · subtitle `Agent set these — adjust anytime`  
2. **Banner when dirty:** `You changed the agent’s settings` + text button `Reset to agent`  
3. **Pro:** full interactive dials.  
4. **Free:** ghost dials + lock → Pro gate (`Override is Pro` / trial CTA).  
5. Closing drawer keeps overrides; status may show `Ready · manual` instead of pure agent ready.

**Entry:** Dials button · tap before/after chip · swipe up on readout strip.

---

## 6. Teach mode (“why”)

**Purpose:** Show the agent’s reasoning in field-manual language — recipe choice, tool results, tradeoffs — without turning Camera into chat.

### Entry
- After Ready: text button `Why this?` / `Teach me why`  
- Or toggle in Settings: `Teach mode` → auto-expand a short why card after each run

### Presentation
**Sheet (preferred)** mid-height over viewfinder:

1. **Title (serif):** recipe name or `Custom exposure`  
2. **One-liner:** `Panning recipe — keep subject sharp, blur background motion.`  
3. **Because list** (3 bullets max): sense findings (`Dim edge light`, `Subject moving left→right`)  
4. **What we set:** same before→after table, stacked  
5. **Watch out:** tip callout if verify warned (`Shutter at 1/60 — brace or use IS`)  
6. **Actions:** `Apply again` · `Pick another recipe` · `Done`

**Free Peek:** show title + one-liner + locked rest + Upgrade.  
**Pro:** full sheet.

**Tone:** instructor at your shoulder — short, concrete, no model jargon (“chain of thought”, “tool call #3”).

---

## 7. End-to-end flows (UI)

### A. Happy path
1. Open Camera → tap **Auto Optimize**.  
2. Status cycles Sense→Reason→Apply→Verify→Ready.  
3. Before/after chip appears; dials animate.  
4. User taps shutter.  
5. Optional: Why sheet.

### B. With staged recipe (from Library/Ask)
1. User already applied/staged a recipe badge.  
2. Auto Optimize **prefers** that recipe unless sense disagrees strongly.  
3. Status: `Using Sharp from Front to Back…` or `Switching to HDR — high contrast scene…` + update badge.

### C. Verify fail / soft warn
- Stay Ready but status uses `agent-warn`: `Ready · watch handshake at 1/30`.  
- Teach sheet opens Watch out first.

### D. Hard fail
- Status error; button re-enabled; no partial silent apply (roll back to pre-run settings unless user had manual dirty state).

### E. Auto-capture (Settings, default OFF)
- When ON and Ready: 500ms settle then soft shutter (with countdown ring). Design v1: specify control in Settings only; don’t enable by default.

---

## 8. Relationship to prior handoffs

| Doc | Still true | Change |
|-----|------------|--------|
| design-handoff-v1 | Tokens, Library, Detail, Paywall, Field Coach | Field Coach feeds **agent tools**; Camera is home |
| design-handoff-camera-v1 | Viewfinder, dials, permissions, apply recipe, Pro gates | Auto Optimize becomes primary CTA; Apply recipe can be agent-driven; teach + before/after required |

**Ask Grok / Photo Vision:** remain tool surfaces + manual coach; agent may invoke the same recommend pipeline during Reason. UI should not show a second Ask card on the viewfinder.

---

## 9. Engineer checklist

### iOS Expert (priority)
- [ ] Auto Optimize primary CTA on Camera chrome (§2).  
- [ ] Agent status component + copy table (§3); wire to real pipeline stages.  
- [ ] Before/after settings chip (§4) bound to session dial snapshot.  
- [ ] Manual override drawer with dirty/reset (§5).  
- [ ] Teach mode sheet (§6); Free teaser / Pro full.  
- [ ] Entitlement: gate repeat Auto Optimize + override per §0.  
- [ ] Theme tokens for agent status / diff colors.  
- [ ] Respect permission covers from camera handoff before running Sense.

### Web Engineer (secondary)
- [ ] Mirror status + before/after in any future web practice viewfinder.  
- [ ] Keep Detail educational dials visually aligned with agent after-values.

### Out of scope
- Full chat thread UI on camera  
- Showing raw tool JSON / model traces in production UI  
- Auto-post to social  

---

## 10. Definition of done

Camera presents Auto Optimize as primary CTA; runs show live status; applies are visible via before/after chips; user can override (Pro) and open Teach mode for why — all in Darkroom field notes language. CoS can route to iOS Expert.

---

*Designer · Agentic Auto Optimize handoff v1*
