# App Store screenshots — dial-change hero frames v1

**Audience:** Ad Designer (export) · Marketing (captions / ASC) · iOS Expert (Build 7 captures)  
**Product ask:** Displays must show **camera settings being changed** — Auto Optimize applying dials — ideally the mid-finder **before→after dial burst** (Build 7), not a static chrome still.  
**UI source of truth:** Decluttered Camera (#76) + Palette A (Neutral Graphite + Signal Amber) + capabilities / recommend CTAs.  
**Out of scope:** `docs/agents/*.md` edits.

---

## Sizes (minimum)

| Slot | Device class | Pixel size (portrait) |
|------|----------------|------------------------|
| Required | iPhone 6.7" | **1290 × 2796** |
| Required | iPhone 6.1" | **1179 × 2556** |

Export both for every frame. Optional later: 6.5" / iPad if ASC asks.

**Safe area:** Keep dial burst + AO CTA in the center 70% vertically; avoid Dynamic Island / home-indicator collision. Caption band (if any) = top 12% or bottom 14% max — never covering dial chips.

---

## Capture preference

1. **Prefer real Build 7** (or current main Camera): decluttered finder (no Library/Coach/Settings tab bar), AO filled amber, before→after burst mid-apply.  
2. Simulator or device OK; use a real outdoor/field scene in the preview (not a solid color).  
3. Mockups only if capture fails — must still show **numeric dial deltas**, not beauty before/after.

**iOS Expert owns raw captures** (`assets/marketing/app-store/raw/` suggested).  
**Ad Designer owns final ASC exports** (crop, optional thin caption bar, both sizes).  
**Marketing owns** locked caption strings in ASC + listing sync.  
**Designer owns** this frame list / art direction.

---

## Frame list (5) — hero = settings changing

### Frame 1 — Dial burst (HERO / slot 1)
- **UI state:** Auto Optimize mid-apply or just after apply. Mid-finder **before→after chips** visible: shutter, ISO, EV, WB, focus (e.g. `1/500 → 1/60`, `100 → 400`). Status pill: `Applying shutter & ISO…` or `Ready to capture`.  
- **Chrome:** Decluttered — AO pill + shutter; no tab bar.  
- **Caption:** `Watch the dials move — shutter, ISO, focus`  
- **Must show:** Changing settings (the burst). **Must not:** Static empty finder; filter before/after photo.

### Frame 2 — Auto Optimize CTA + live apply
- **UI state:** AO highlighted / pressed or immediately pre-burst with status `Reading light…` → chips starting to appear.  
- **Caption:** `Point. Auto Optimize. Sets shutter, ISO & focus`  
- **Must show:** AO as primary + at least one dial delta or status proving agentic apply.

### Frame 3 — Recipe dials / Teach why
- **UI state:** Controls or Teach sheet **over** finder (or after AO) showing dial cluster with values that clearly moved; optional “Why this?” bullets naming shutter/ISO.  
- **Caption:** `Recipe dials you can trust — and override`  
- **Must show:** Dial readout values, not a marketing illustration of dials.

### Frame 4 — Field look chip (capture grade)
- **UI state:** Look chip suggested or active (`goldenHour · 0.6`) **plus** core setting chips still visible (settings + grade, not grade alone).  
- **Caption:** `Field look on the viewfinder — capture grade, not a filter`  
- **Must not:** Beauty/skin language; aperture-as-written.

### Frame 5 — Ready + pan cue (optional sixth if ASC allows)
- **UI state:** `Ready to capture` + soft pan ← or → chevron; shutter dominant; brief residual before→after strip OK.  
- **Caption:** `Ready to capture · Set the shot. Then take it.`  
- If only 5 slots: drop Frame 5 OR merge Ready into Frame 1 end-state. Prefer keeping Frames 1–4 mandatory; 5 optional.

**Priority order for ASC upload:** 1 → 2 → 3 → 4 → (5).

---

## Caption lock (Marketing)

| # | Caption (≤~50–60 chars display) |
|---|----------------------------------|
| 1 | Watch the dials move — shutter, ISO, focus |
| 2 | Point. Auto Optimize. Sets shutter, ISO & focus |
| 3 | Recipe dials you can trust — and override |
| 4 | Field look — capture grade, not a filter |
| 5 | Ready to capture · Set the shot. Then take it. |

Voice must not lead any caption.

---

## Art direction

- Palette A: neutral finder chrome; Signal Amber AO only.  
- Darkroom field notes — quiet caption type (sans); optional serif wordmark tiny.  
- No neon AI glow, no dual-phone clutter in slot 1, no GitHub, no App Store badge chrome inside the screenshot itself.  
- Never show Library/Coach/Settings tab bar in slots 1–2.

---

## Workflow

| Step | Owner |
|------|--------|
| 1. Capture Build 7 states per frame | **iOS Expert** |
| 2. Pick best stills; note build # | iOS Expert → Designer review if needed |
| 3. Crop/export 1290×2796 + 1179×2556; optional caption bar | **Ad Designer** |
| 4. Final caption check + ASC upload | **Marketing** |
| 5. Frame list / art direction | **Designer** (this doc) |

---

## Engineer / capture checklist (iOS)

- [ ] Build with decluttered Camera (tab bar hidden)  
- [ ] Trigger AO on a textured scene; screenshot during dial burst  
- [ ] Include shutter/ISO/EV/WB/focus deltas (no fake aperture write)  
- [ ] Drop PNGs under `assets/marketing/app-store/raw/` with names `frame-01-dial-burst.png` etc.  
- [ ] Ping Ad Designer with paths + build number  

---

*Designer · App Store dial-change screens v1*
