# Grok Camera — iOS onboarding v1 (single screen)

**Bundle:** `com.ragnus.mvp` · **Brand:** Grok Camera  
**Status:** **Greenlit for iOS implementation** (CoS / user).  
**Canonical mock (portrait):** `assets/marketing/onboarding/08-single-screen-portrait.png`  
**Alt / earlier landscape exploration:** `08-single-screen.png` (do not implement landscape as primary).  
**Flow art:** `09-single-flow.png`  
**Palette:** Neutral Graphite + Signal Amber (A).

---

## Layout decision (locked)

**One screen** — tips via chevrons; **Get Started always visible** (never after a multi-page carousel).

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
- **Get Started** on the **first/only** screen.  
- Get Started → **camera permission only** → main camera.  
- **Push** = later (after first successful capture) — not on this screen.

---

## Tip content (3–4, cycle)

| # | Title | Body |
|---|-------|------|
| 1 | Auto Optimize | Point at the shot — we write shutter, ISO, EV, WB & focus. |
| 2 | Recommend & Looks | Recipe from the scene. Looks = capture grades, not beauty filters. |
| 3 | Capture | See settings change, then press shutter. Teach explains why. |
| 4 (optional) | Scene note | Optional note/dictate later — never required to start. |

Optional hero line: **AI camera coach — shutter, ISO, focus** or **Set the shot. Then take it.**

### Get Started
- CTA: **Get Started** (amber + `accentOnAccent` label)  
- Micro: **We'll ask for Camera access next.**

---

## Files

| File | Role |
|------|------|
| **`08-single-screen-portrait.png`** | **Canonical portrait mock (implement this)** |
| `09-single-flow.png` | Flow diagram |
| `08-single-screen.png` | Earlier non-portrait exploration |
| `01`–`07` | Multi-step explorations — superseded |

---

## iOS checklist

- [ ] Portrait first-run screen matching layout above  
- [ ] Chevron / swipe tip cycle; Get Started always enabled  
- [ ] Camera permission only on Get Started  
- [ ] Push deferred until after first successful capture  
- [ ] Palette A tokens  

---

*Designer · onboarding v1 · greenlit*
