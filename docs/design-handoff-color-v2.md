# Photo Recipes — Color System v2

**Audience:** iOS Expert (primary) · Web Engineer (landing follow) · CoS  
**Ask:** New cohesive color scheme — darkroom / field-notes, premium iOS camera — not generic SaaS purple.  
**Supersedes for color only:** token tables in [`design-handoff-v1.md`](./design-handoff-v1.md) §2–4. Type, spacing, and component structure stay.  
**iOS-first:** Ship Camera / Auto Optimize chrome first; marketing/landing adopts the same tokens when Web is unpaused.  
**Do not:** Refine `docs/agents/*.md` as part of this work.

---

## 0. Preferred pick

**Ship: Palette A — Safelight Amber**

Why: Literally reads as darkroom (amber safelight), clear break from Tailwind-rose fatigue, excellent outdoor legibility on black viewfinder chrome, still photographic/premium — not fintech purple or neon AI.

Palettes B and C remain approved alternatives if product wants cooler metal (B) or a quieter evolution of today’s rose (C).

---

## 1. Current → problem (before)

| Token | Current | Issue |
|-------|---------|--------|
| `bg` | `#0c0c0f` | Fine near-black; slightly cool-neutral |
| `accent` | `#f43f5e` | Strong but overused; pink fog on hero/radial; reads “Tailwind rose SaaS” |
| `vision` | `#8b7cf6` | Purple AI cue — keep minimal or retire glow |
| Neutrals | zinc-ish | Workable; little warmth for “field notes / paper” |

**Keep:** Instrument Serif + DM Sans; single loud accent rule; quiet surfaces.

---

## 2. Three cohesive palettes

### A — Safelight Amber ★ preferred

**Mood:** Darkroom under safelight. Warm black, amber action, paper-warm ink.

| Token | Hex | OKLCH (approx) | Role |
|-------|-----|----------------|------|
| `bg` | `#0e0c0a` | `oklch(0.14 0.012 55)` | App / sheet background |
| `bg-elevated` | `#16120f` | `oklch(0.17 0.014 55)` | Soft panels |
| `surface` | `#1c1814` | `oklch(0.20 0.016 55)` | Cards / dials tray |
| `surface-2` | `#26201a` | `oklch(0.24 0.018 55)` | Nested wells |
| `border` | `#3a322a` | `oklch(0.32 0.018 60)` | Hairline |
| `border-strong` | `#52483c` | `oklch(0.40 0.022 60)` | Focused edge |
| `ink` | `#f7f1e8` | `oklch(0.96 0.015 85)` | Primary text |
| `ink-secondary` | `#cfc4b6` | `oklch(0.82 0.022 80)` | Body |
| `ink-tertiary` | `#9a8f82` | `oklch(0.65 0.020 75)` | Meta only |
| `accent` | `#e8a017` | `oklch(0.76 0.145 75)` | Primary CTA / Auto Optimize / shutter core tint |
| `accent-soft` | `#f0b84a` | `oklch(0.82 0.130 78)` | Hover / focus ring |
| `accent-muted` | `color-mix(in oklab, #e8a017 16%, transparent)` | — | Selected fills (no glow) |
| `tip` | `#d4a017` | `oklch(0.74 0.130 80)` | Tips (can share family with accent; slightly deeper) |
| `tip-bg` | `color-mix(in oklab, #d4a017 10%, transparent)` | — | Tips well |
| `success` | `#3dba8c` | `oklch(0.72 0.110 165)` | Trial / ready |
| `warn` | `#e0a045` | `oklch(0.76 0.120 70)` | Motion risk / soft warn |
| `danger` / `error` | `#e86a5c` | `oklch(0.68 0.145 30)` | Errors (transient) |
| `vision` | `#7a9bb8` | `oklch(0.68 0.055 240)` | Vision mode indicator only (steel blue, not purple) |
| `overlay` | `rgba(8,6,4,0.78)` | — | Modal / sheet scrim |

**Chip fills:** `surface-2` + `border`; active chip = `accent-muted` + `accent` label.  
**Category tints @ ~16% fill:** DoF `#6a9ad4` · Motion `#e8a017` · HDR `#9a8ec8` · Composition `#4cb8a0` · Favorites → accent.

---

### B — Selenium Silver (cool alternative)

**Mood:** Leica/Halide cool metal. Charcoal + silver + copper ember accent.

| Token | Hex | OKLCH (approx) | Role |
|-------|-----|----------------|------|
| `bg` | `#0a0b0d` | `oklch(0.13 0.008 260)` | Background |
| `bg-elevated` | `#111317` | `oklch(0.16 0.010 260)` | Panels |
| `surface` | `#161920` | `oklch(0.19 0.012 260)` | Cards |
| `surface-2` | `#1e222b` | `oklch(0.23 0.014 260)` | Wells |
| `border` | `#2c313c` | `oklch(0.30 0.014 260)` | Hairline |
| `border-strong` | `#434956` | `oklch(0.38 0.016 260)` | Focus |
| `ink` | `#eef0f4` | `oklch(0.95 0.008 260)` | Primary |
| `ink-secondary` | `#b8bdc8` | `oklch(0.80 0.015 260)` | Body |
| `ink-tertiary` | `#858b98` | `oklch(0.64 0.018 260)` | Meta |
| `accent` | `#c47a4a` | `oklch(0.66 0.100 50)` | Copper ember CTA |
| `accent-soft` | `#d49268` | `oklch(0.72 0.090 52)` | Hover |
| `accent-muted` | `color-mix(in oklab, #c47a4a 15%, transparent)` | — | Fills |
| `tip` | `#c9a227` | `oklch(0.74 0.125 85)` | Tips |
| `success` | `#3aaf9a` | `oklch(0.70 0.095 175)` | Success |
| `warn` | `#d4a04a` | `oklch(0.75 0.110 75)` | Warn |
| `danger` | `#d96b6b` | `oklch(0.66 0.130 25)` | Error |
| `vision` | `#6b8fdb` | `oklch(0.66 0.100 265)` | Vision (restrained blue) |
| `overlay` | `rgba(5,6,8,0.80)` | — | Scrim |

---

### C — Carmine Emulsion (rose evolved)

**Mood:** Same photographic rose DNA, deeper carmine, cooler blacks — less candy, less pink fog.

| Token | Hex | OKLCH (approx) | Role |
|-------|-----|----------------|------|
| `bg` | `#0b0c10` | `oklch(0.14 0.010 270)` | Background |
| `bg-elevated` | `#12141a` | `oklch(0.17 0.012 270)` | Panels |
| `surface` | `#171920` | `oklch(0.20 0.012 270)` | Cards |
| `surface-2` | `#1f222c` | `oklch(0.24 0.014 270)` | Wells |
| `border` | `#2c3040` | `oklch(0.31 0.018 270)` | Hairline |
| `border-strong` | `#42485a` | `oklch(0.39 0.020 270)` | Focus |
| `ink` | `#f3f4f7` | `oklch(0.96 0.006 270)` | Primary |
| `ink-secondary` | `#c2c6d0` | `oklch(0.82 0.012 270)` | Body |
| `ink-tertiary` | `#8a8f9c` | `oklch(0.65 0.015 270)` | Meta |
| `accent` | `#d63856` | `oklch(0.60 0.175 15)` | Deeper carmine CTA |
| `accent-soft` | `#e85d76` | `oklch(0.68 0.155 15)` | Hover |
| `accent-muted` | `color-mix(in oklab, #d63856 14%, transparent)` | — | Fills |
| `tip` | `#e0b04a` | `oklch(0.78 0.120 80)` | Tips |
| `success` | `#34c492` | `oklch(0.74 0.110 165)` | Success |
| `warn` | `#e0a84a` | `oklch(0.78 0.115 75)` | Warn |
| `danger` | `#f07171` | `oklch(0.70 0.140 25)` | Error |
| `vision` | `#7b8fd4` | `oklch(0.68 0.080 270)` | Vision (desaturated) |
| `overlay` | `rgba(6,7,10,0.78)` | — | Scrim |

---

## 3. Camera / viewfinder overlays (iOS-first)

Apply on **full-bleed preview**. Prefer translucent dark scrims + high-contrast ink; accent only on Auto Optimize + active look/shutter accents.

| Token | Palette A value | Notes |
|-------|-----------------|-------|
| `camera-scrim` | `rgba(8,6,4,0.45)` | Top/bottom chrome |
| `camera-scrim-strong` | `rgba(8,6,4,0.78)` | Permission / error covers |
| `camera-chrome-ink` | `#f7f1e8` | Readouts (match `ink`) |
| `camera-chrome-ink-secondary` | `rgba(247,241,232,0.78)` | Secondary labels |
| `camera-hairline` | `rgba(247,241,232,0.18)` | Pill borders |
| `shutter-ring` | `#f7f1e8` | Outer ring |
| `shutter-core` | accent `#e8a017` | Inner (photo) |
| `status-pill-bg` | `rgba(28,24,20,0.72)` | Blur + surface |
| `status-pill-border` | `rgba(232,160,23,0.35)` | Optional when optimizing |
| `diff-before` | `#9a8f82` | Before value (`ink-tertiary`) |
| `diff-after` | `#f7f1e8` | After value |
| `look-chip-bg` | `rgba(232,160,23,0.18)` | Active/suggested look |
| `ae-lock` | tip `#d4a017` | AE/AF lock |

**Rules**
- No full-screen rose/amber wash on the live preview.  
- Auto Optimize pill: `accent` fill or `accent-muted` + `accent` label — one loud control.  
- Before→after chips: neutral scrim; accent only on “after” if needed for scan (prefer ink after + tertiary before).  
- Looks intensity slider track: `border-strong`; fill: `accent`.

For B/C: swap hex families but keep the same token roles and opacity recipes.

---

## 4. Marketing / landing (follow iOS)

Same semantic tokens as app. Hero optional radial:

| Palette | Hero wash (max) |
|---------|-----------------|
| A | `rgba(232,160,23,0.07)` |
| B | `rgba(196,122,74,0.07)` |
| C | `rgba(214,56,86,0.06)` |

Primary CTA = `accent` filled. Secondary = `border` + `ink`. Waitlist success = `success`. No purple glows. No GitHub CTA chrome.

---

## 5. Contrast & a11y

| Pair | Requirement |
|------|-------------|
| `ink` on `bg` | ≥ 12:1 feel; near max |
| `ink-secondary` on `bg` | Body readable outdoors ≥ ~7:1 target |
| `accent` on `bg` for CTA text | Prefer **white/`ink` text on accent fill** for A (`#0e0c0a` or `#1a1208` on amber button label if amber too light — **use dark label `#1a1208` on accent buttons** for Palette A) |
| Palette A CTA label | **`#1a1208`** (not white) on `#e8a017` |
| Palette B/C CTA label | `#ffffff` / `#f5f5f7` on accent |

Focus rings: 2px `accent-soft` outside control.

---

## 6. Implementation notes

### iOS (SwiftUI)
- Add `Color` assets or `PhotoRecipesColor` enum mirroring token names.  
- Camera overlays use scrim tokens; don’t hardcode system `.yellow` for safelight — use `accent`.  
- Dynamic Type: keep contrast pairs above.

### Web (`src/index.css` `@theme`)
Replace current zinc/rose block with chosen palette when Web is unpaused. Example for **A**:

```css
@theme {
  --color-bg: #0e0c0a;
  --color-bg-elevated: #16120f;
  --color-surface: #1c1814;
  --color-surface-2: #26201a;
  --color-border: #3a322a;
  --color-border-strong: #52483c;
  --color-ink: #f7f1e8;
  --color-ink-secondary: #cfc4b6;
  --color-ink-tertiary: #9a8f82;
  --color-accent: #e8a017;
  --color-accent-soft: #f0b84a;
  --color-accent-muted: color-mix(in oklab, #e8a017 16%, transparent);
  --color-vision: #7a9bb8;
  --color-tip: #d4a017;
  --color-tip-bg: color-mix(in oklab, #d4a017 10%, transparent);
  --color-success: #3dba8c;
  --color-warn: #e0a045;
  --color-danger: #e86a5c;
}
```

Add `--color-warn` (new vs v1) for motion-risk chips.

---

## 7. Decision log

| Option | Ship? | One-liner |
|--------|-------|-----------|
| **A Safelight Amber** | **Yes (default)** | Darkroom literal; fresh vs rose; premium camera |
| B Selenium Silver | Alt | Cool metal / Halide-adjacent |
| C Carmine Emulsion | Alt | Continuity with current rose, quieter |

Product/CoS can switch default by renaming “preferred” in a follow-up; tokens stay role-stable.

---

## 8. Engineer checklist

- [ ] iOS: map tokens; Camera Auto Optimize + chips + sheets use A  
- [ ] iOS: CTA on amber uses dark label `#1a1208`  
- [ ] iOS: retire purple vision glow; use steel `vision`  
- [ ] Confirm look chips / status pills against live preview (no wash)  
- [ ] Web (later): swap `@theme` + landing radial  
- [ ] Spot-check success/warn/error on both surfaces  

---

*Designer · color system v2 · preferred: Safelight Amber*
