# Photo Recipes — Multi-Phone Layout Handoff v1

**Covers:** iPhone (notch / Dynamic Island) **and** regular Android / smaller phones (360–400pt width).  
**Brand:** Darkroom field notes — quiet chrome, rose `#f43f5e` sparingly, **no neon AI / game HUD**.  
**Related:** [`design-handoff-camera-v1.md`](./design-handoff-camera-v1.md) · [`design-handoff-agentic-v1.md`](./design-handoff-agentic-v1.md) · [`design-handoff-iphone-duo-v1.md`](./design-handoff-iphone-duo-v1.md) · [`design-handoff-voice-v1.md`](./design-handoff-voice-v1.md)

---

## 1. Device classes

| Class | Logical width | Height class | Chrome notes |
|-------|---------------|--------------|--------------|
| **iPhone compact** | 390–430pt | tall | Island/notch; home indicator; large bottom safe area |
| **iPhone SE / mini** | 320–375pt | shorter | Tighter vertical; stack Auto Optimize above shutter with 8pt gaps |
| **Regular Android** | **360–400pt** (design at **360**) | varies; often shorter | Punch-hole or small top inset; **thicker bezels OK** in marketing; system nav bar (3-button or gesture) |
| **Android large / fold cover** | 411–448pt | — | Same components, more horizontal padding |

**Rule:** Do **not** design chrome that only works with Dynamic Island. Top actions use a generic **safe-area top inset** (min 12pt below status/cutout).

**Touch:** All primary controls ≥ **44×44pt** (Android: 48×48dp preferred for shutter / Auto Optimize).

---

## 2. Shared screen layouts (both platforms)

### Camera
- Top: flash · aspect · flip (icon row, 44pt hits).  
- Preview fills remaining width; bottom scrim holds: scene field + `From viewfinder` + mic · status · **Auto Optimize** · gallery / shutter / dials.  
- **Direction arrows** — see §3.  
- On **360pt / short height:** collapse scene field to one line; status single line; Auto Optimize full-width 48dp; shutter 72dp.

### Library
- Header + short intro (one line on small).  
- Field Coach compact (segmented Ask).  
- Filters horizontal scroll.  
- Recipe cards **single column** below 600pt; key setting large.

### Detail
- Title serif; dials **2×2** on width < 400pt (never squeeze four unreadably).  
- Steps full width; soft-gate checklist as existing pattern.

### Paywall
- Modal max-width 100% − 32pt padding on small phones.  
- Annual solid primary above monthly; comparison stacks **vertically** if height < 700pt.

---

## 3. Direction arrows (composition / pan cues)

**When:** Auto Optimize or an applied recipe needs the user to **pan / point** the camera (e.g. follow subject, reframe horizon, include foreground).

**What:** Soft **edge chevrons** (or slim arrows) over the viewfinder — typically **left and/or right**; optional up/down for tilt/reframe.

| Property | Spec |
|----------|------|
| Placement | 12–16pt inset from preview edge, vertically centered on that edge |
| Glyph | Chevron `‹` `›` or dual-chevron; stroke 1.5–2pt; **white @ 70–85%** with 1pt dark hairline shadow for daylight |
| Size | Hit/visual ~40–48pt tall; not a thick HUD bar |
| Label (optional) | One caption near bottom of preview: `pan with subject →` (`caption`, white@80%) |
| Motion | Opacity 55%↔90% over ~1.4s ease; optional 4pt nudge toward direction. **Reduce Motion:** static at 75% |
| Accent | Do **not** paint arrows rose by default; rose only if emphasizing a single primary direction |
| Dismiss | When agent marks aligned · user taps arrow · user taps preview · 8s timeout without re-prompt |
| Stacking | Below status/Auto Optimize chrome; above raw preview; never cover shutter |

**Copy examples:** `pan left` · `pan with subject →` · `tilt up for sky` · `include foreground ↓`

**Anti-patterns:** Racing stripes, radar wedges, Fortnite-style markers, constant multi-arrow spam.

---

## 4. Marketing duo layout (iPhone + regular phone)

Update to duo set when showing platform breadth:

| Slot | Device | Screen |
|------|--------|--------|
| A | iPhone | Camera + Auto Optimize + arrows (optional) |
| B | Regular Android (thicker bezel) | Camera **or** Recipe detail with dials |

Ground `#0c0c0f`; equal visual weight; see also [`design-handoff-iphone-duo-v1.md`](./design-handoff-iphone-duo-v1.md). Assets:

- `assets/marketing/phones-duo-iphone-android-camera.png`
- `assets/marketing/android-regular-screens-grid.png`

---

## 5. Platform chrome checklist

### iOS
- [ ] `safeAreaInsets` for Island + home indicator  
- [ ] Shutter clears home indicator by ≥8pt  

### Android
- [ ] Handle cutout + status bar; `WindowInsets` / edge-to-edge  
- [ ] 3-button nav: bottom chrome sits above nav bar  
- [ ] Don’t assume 19.5:9 — test ~18:9 and 16:9 short devices  
- [ ] Prefer opacity press states over loud Material ripples  

---

## 6. Engineer notes

- **iOS / Web:** Direction arrow overlay driven by cue enum: `panLeft | panRight | panUp | panDown | none` + optional caption.  
- **Agentic Expert:** Emit cue during Apply/Verify when composition requires reframe; clear on verify pass.  
- Layout tokens: mobile columns as §2.

---

*Designer · Multi-phone + direction arrows v1*
