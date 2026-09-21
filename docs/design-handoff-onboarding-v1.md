# Grok Camera — iOS onboarding v1 (single screen)

**Bundle:** `com.ragnus.mvp` · **Brand:** Grok Camera  
**Status:** Visual mock only — no eng until CoS + user review.  
**Mocks:** `assets/marketing/onboarding/` — **canonical:** `08-single-screen.png`  
**Palette:** Neutral Graphite + Signal Amber (A).

---

## Layout decision (user lock)

**One screen** (not a multi-page carousel before CTA):

```
┌─────────────────────────────┐
│        Grok Camera          │  wordmark
│                             │
│     〈   [ tip card ]   〉   │  chevron L/R cycles tips
│           · · ·             │  dots
│                             │
│     [  Get Started  ]       │  amber filled — ALWAYS on this screen
│  We'll ask for Camera next  │
└─────────────────────────────┘
```

- Tips cycle in-place via **← → chevrons** (and optional swipe).  
- **Get Started** is on the **first/only** screen — never gated behind finishing tips.  
- Get Started → **camera permission only** → main camera.  
- **Push** = later (after first successful capture) — not here.

Flow art: `09-single-flow.png`.

---

## Tip content (3–4, cycle)

| # | Title | Body |
|---|-------|------|
| 1 | Auto Optimize | Point at the shot — we write shutter, ISO, EV, WB & focus. |
| 2 | Recommend & Looks | Recipe from the scene. Looks = capture grades, not beauty filters. |
| 3 | Capture | See settings change, then press shutter. Teach explains why. |
| 4 (optional) | Scene note | Optional note/dictate later — never required to start. |

Landing hero value (above or instead of tip title when tip 1): **AI camera coach — shutter, ISO, focus** or slogan **Set the shot. Then take it.**

### Get Started
- CTA: **Get Started**  
- Micro: **We'll ask for Camera access next.**

---

## Files

| File | Role |
|------|------|
| **`08-single-screen.png`** | **Canonical single-screen mock** |
| `09-single-flow.png` | Flow diagram |
| `01`–`07` | Earlier multi-step explorations (superseded for product) |

---

*Designer · onboarding single-screen · user condensed*
