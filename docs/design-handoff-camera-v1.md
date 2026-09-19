# Photo Recipes — Camera UI Handoff v1

**Extends:** [`design-handoff-v1.md`](./design-handoff-v1.md) (tokens, type, Darkroom field notes)  
**Product pivot:** Photo Recipes is an **advanced camera app**. Library recipes are not only educational — they **apply to live capture**.  
**Primary platform for this doc:** **iOS (SwiftUI + AVFoundation / Camera)**. Web may later mirror a limited “practice” viewfinder; do not block iOS on web.  
**Aesthetic:** Same Darkroom field notes language — quiet chrome, aperture-ring dials, one loud action (shutter / apply).

---

## 0. Product framing (design implications)

| Before | After |
|--------|--------|
| Field notes + simulated dials | Live viewfinder is home |
| Soft-gate checklists / Ask | Soft-gate **manual / advanced capture controls** |
| Recipes explain settings | Recipes **drive** MODE / aperture / shutter / ISO (and related) on the active session |

**Free Peek (camera):** live preview, shutter, basic auto exposure, browse & preview recipe recommendations (read-only dial readout).  
**Pro:** unlock **manual dials**, **Apply recipe → live session**, recipe-locked advanced controls (e.g. long exposure ranges, exposure compensation stack, focus peaking if shipped). Trial messaging matches existing Pro ($7.99/mo · **$59.99/yr primary** · 7-day trial).

Keep Ask Grok / Photo Vision as **coach into a recipe**, then hand off into Camera with that recipe staged — not a separate AI camera mode.

---

## 1. Design principles (camera-specific)

1. **Viewfinder is sacred** — chrome is thin, high-contrast, mostly black scrims + hairlines. No rose glow panels over the preview.
2. **Dials = physical language** — same DialCluster visual system as Detail, but interactive; values use `font-mono` / semibold.
3. **One primary capture action** — shutter is the only large filled control in the bottom safe area.
4. **Recipe is a session badge** — always visible when applied; easy to clear without leaving camera.
5. **Pro gate is clear, not muddy** — show locked dials at rest with a single upgrade strip; never pink-wash the entire preview.
6. **Outdoor legibility** — labels ≥ `ink-secondary`; critical EXIF/readouts white; minimum 44pt hits.

**Reuse tokens** from handoff v1 (`bg`, `surface`, `border`, `ink*`, `accent`, `tip`, radii, space). Camera adds:

| Token | Value | Role |
|-------|--------|------|
| `camera-scrim` | `rgba(0,0,0,0.45)` | Top/bottom chrome over preview |
| `camera-scrim-strong` | `rgba(0,0,0,0.72)` | Permission / error full covers |
| `shutter-ring` | `#f5f5f7` | Outer shutter ring |
| `shutter-core` | `#f43f5e` (`accent`) | Inner shutter (photo) · hold-to-video later optional |
| `recipe-badge-bg` | `rgba(244,63,94,0.18)` | Applied recipe chip |
| `ae-lock` | `#e7b549` (`tip`) | AE/AF lock indicator |

---

## 2. Information architecture

**Tab / root (iOS):** `Camera` (default) · `Library` · `Ask` (or Ask inside Library) · `Settings`  
Camera is the launch surface after pivot.

**Entry paths into Camera**
- Cold start → last camera / back camera, no recipe.
- Library → recipe Detail → **Open in Camera** / **Apply to capture**.
- Ask result → **Shoot with this recipe**.
- Deep link / widget (future): staged recipe id.

---

## 3. Screen: Viewfinder (default chrome)

### Layout (portrait primary; landscape: mirror chrome to edges)

```
┌─────────────────────────────┐
│ scrim top                   │
│ [Flash] [Ratio]    [Flip]   │  ← icon buttons, 44pt
│                             │
│     LIVE PREVIEW            │
│                             │
│  (optional grid 3×3, 20% white) │
│                             │
│ [Recipe badge or + Recipe]  │  ← floating above bottom scrim
│ scrim bottom                │
│ [Gallery]  ( SHUTTER )  [Dials] │
│     mode readout strip      │
└─────────────────────────────┘
```

### Top chrome
- **Flash:** Off / On / Auto — cycle; icon + tiny caption on long-press menu if needed.
- **Aspect:** `4:3` default (sensor), optional `1:1` / `16:9` crop guides only (don’t letterbox aggressively).
- **Flip:** front/back.
- **Status (trailing or under top):** tiny `4K` / `PHOTO` if modes expand later — default still **Photo**.

### Bottom chrome
- **Gallery thumb** — last capture; opens Photos/limited library sheet.
- **Shutter** — 72–80pt outer ring (`shutter-ring`), 58–64pt inner fill (`shutter-core`). Press scale 0.94. Disabled state 40% opacity when permission missing.
- **Dials affordance** — aperture-ring glyph button; opens Manual dials overlay (Pro) or Pro gate sheet (Free).

### Mode readout strip (always on)
Single line, mono/`body-sm`, white text with black hairline shadow for glare:
`A · f/5.6 · 1/125 · ISO 200`  
When recipe applied, prefix chip (see §5).

### Grid / level (Settings toggles)
- Rule-of-thirds: 1px `rgba(255,255,255,0.22)`.
- Horizon level: tip-colored when ±1° (optional v1.1).

### Do / Don’t
- **Do** keep chrome ≤ 20% of vertical space combined (top+bottom scrims).  
- **Don’t** put Ask Grok cards or library lists on top of the preview.  
- **Don’t** use purple vision glow on camera chrome.

---

## 4. Overlay: Manual dials

**Trigger:** Dials button, or swipe up from bottom readout, or “Edit dials” on applied recipe.

**Presentation:** Bottom sheet / drawer over viewfinder (preview still visible dimmed 15% via light scrim — not full blackout). Height ~42–48% of screen. Grabber + title `Manual` · trailing `Done`.

**Dial row (match Detail DialCluster, interactive):**

| Dial | Values (v1) | Notes |
|------|-------------|--------|
| MODE | Auto · P · A/Av · S/Tv · M | Free Peek: Auto only interactive; others locked |
| APERTURE | device-supported stops | Enabled in A/M |
| SHUTTER | device-supported | Enabled in S/M; long times Pro if hardware allows |
| ISO | Auto + discrete | Enabled in M / when unlocked |

**Interaction**
- Rotate / horizontal scrub on dial; haptic tick per stop.
- Focused dial: `border-strong` ring (not dashed rose scream).
- Live readout strip updates immediately.
- **AE/AF lock:** tap preview → yellow box + `ae-lock` pill `AE/AF LOCK`.

**Educational footnote** (one line, `ink-tertiary`): `Educational recipes · real capture uses device limits`.

---

## 5. State: Apply recipe

### Staging (from Library / Detail / Ask)
1. User taps **Apply to Camera** / **Shoot with recipe**.  
2. Navigate to Camera tab; show toast/badge staging: `Ready: Sharp from Front to Back`.  
3. If Free Peek → open **Pro gate** (§7) before writing constrained values; still allow viewing the recipe’s recommended dials as **read-only ghost dials**.  
4. If Pro → write session: set MODE + available parameters; clamp to device capabilities; show conflicts.

### Applied chrome
- Floating **recipe badge** (pill): accent-muted fill · accent border · serif/semibold title truncated · `×` clear.  
  Example: `Applied · Sharp from Front to Back ✕`
- Readout strip: values that came from recipe marked with small accent dot.
- Optional secondary: `Steps` icon opens a **compact step sheet** (checklist from recipe) — Pro for interactive checks; Free sees first steps + upgrade (same soft-gate pattern as Detail).

### Conflict / clamp banner
If recipe asks f/16 but lens max is f/4:
- Non-blocking banner above bottom scrim: `Aperture clamped to f/4 for this lens` (`tip` border).  
- Keep recipe badge; show adjusted values in readout.

### Clear recipe
- Badge `×` or long-press badge → confirm sheet `Remove recipe from this session?` · Remove / Keep.  
- Returns MODE toward Auto (or last manual without recipe).

### Capture with recipe
- Shutter behaves normally; metadata/write: store `recipeId` + applied dial snapshot in app DB / EXIF user comment if feasible (iOS Expert decides; design only requires in-app “last recipe used” on gallery thumb tooltip).

---

## 6. States: Permission & errors

### Camera permission — not determined
Full-screen `camera-scrim-strong` over black (no stolen preview frames).  
- Display title: `Camera access` (serif).  
- Body: `Photo Recipes needs the camera to apply field recipes to live capture.`  
- Primary: `Continue` → system permission dialog.  
- Secondary text button: `Not now` → Library.

### Camera permission — denied / restricted
Same cover.  
- Title: `Camera is off`  
- Body: `Enable camera in Settings to shoot with recipes.`  
- Primary: `Open Settings`  
- Secondary: `Browse recipes` → Library.

### Capture hardware errors
Inline banner (not full screen) for session failures:  
- `Camera in use by another app`  
- `Capture failed — try again`  
Use `danger` only for hard failures; tip/warning for recoverable.

### Photo Library (gallery thumb)
If denied: gallery button opens explanation sheet → Settings; shutter still works.

**Copy tone:** calm, field-manual — no playful AI copy on permission screens.

---

## 7. Pro gate (advanced controls)

### What is gated (camera)
| Capability | Free Peek | Pro |
|------------|-----------|-----|
| Live viewfinder + shutter | ✓ | ✓ |
| Auto mode capture | ✓ | ✓ |
| See recipe recommended dials (read-only) | ✓ | ✓ |
| **Apply recipe → live session** | ✗ | ✓ |
| **Manual MODE A/S/M + dials** | ✗ | ✓ |
| Interactive field checklist while shooting | ✗ | ✓ |
| Ask Grok / Vision quota | existing rules | unlimited |

### Gate UI patterns
1. **From Dials button (Free):** present paywall modal (existing Pricing / StoreKit sheet) with eyebrow `Manual dials are Pro`.  
2. **From Apply to Camera (Free):** sheet mid-height over viewfinder — recipe title + ghost dials + solid `Upgrade · 7-day trial` + `Keep browsing`. Do **not** dim the whole preview into mud; use standard modal scrim.  
3. **Locked dials preview:** dials visible at 100% opacity but non-interactive; lock glyph on MODE row; tap any locked dial → gate sheet.

Annual remains **primary CTA** on paywall.

---

## 8. Motion & haptics

- Shutter: light impact on press, success on save.  
- Dial tick: selection haptic per stop.  
- Recipe apply: dials animate 280ms ease to target values (`dial-in` cousin); badge fades in 150ms.  
- Avoid continuous colored glow animations on chrome.

---

## 9. Breakpoints / devices

| Surface | Notes |
|---------|--------|
| iPhone portrait | Primary layout above |
| iPhone landscape | Top icons → trailing edge; shutter → trailing; dials sheet still bottom in portrait-lock optional (prefer allow landscape chrome) |
| iPad | Preview centered max; chrome denser; dials can be **persistent trailing column** (320pt) on Pro iPad landscape |
| Web (later) | Optional “practice viewfinder” using webcam — out of scope for iOS v1 ship |

---

## 10. Engineer checklist — iOS Expert (priority)

- [ ] Camera tab as default root; AVCamera preview + permission flows §6.  
- [ ] Viewfinder chrome §3 (flash, flip, shutter, gallery, dials button, readout strip).  
- [ ] Manual dials overlay §4 wired to capture device controls; respect device limits.  
- [ ] Apply recipe session model §5 (stage / apply / clamp / clear); badge + readout.  
- [ ] Pro gate §7 via existing StoreKit Pro entitlement; Free = auto + read-only recipe dials.  
- [ ] Theme tokens: add camera scrim / shutter / recipe-badge to `Theme.swift` (hex aligned with v1).  
- [ ] Entry points: Detail + Ask → `Apply to Camera`.  
- [ ] Do not block on web implementation.

### Web Engineer (secondary / later)
- [ ] Detail + Library CTAs copy: `Apply to Camera` can deep-link / show “Open in iOS app” until web capture exists.  
- [ ] Keep educational DialCluster on Detail in sync visually with camera dials.

### Out of scope (v1 camera)
- Video / timelapse modes  
- RAW / ProRes  
- Full Lightroom-style grading  
- AR overlays  

---

## 11. Definition of done

iOS can present viewfinder chrome, permission covers, manual dials (Pro), apply/clear recipe with clamp messaging, and Pro gate sheets — all in Darkroom field notes language, reusable tokens from handoff v1. CoS can route this doc to iOS Expert as the camera source of truth.

---

*Designer · Camera UI handoff v1 · extends design-handoff-v1.md*


---

## Addendum — Agentic Auto Optimize

North star loop (sense → reason/tools → apply → verify → capture) and UI (Auto Optimize CTA, status, before/after chip, override, teach mode): **[`design-handoff-agentic-v1.md`](./design-handoff-agentic-v1.md)**.


---

## Addendum — Voice input

Dictate scene for agent hints: see **[`design-handoff-voice-v1.md`](./design-handoff-voice-v1.md)**.


---

## Addendum — Direction arrows & multi-phone

Pan/point chevrons on viewfinder + regular Android layouts: **[`design-handoff-phones-v1.md`](./design-handoff-phones-v1.md)** §3–4.
