# Photo Recipes — Color System v2 (shared web + iOS)

**Audience:** iOS Expert (implement first) · Web Engineer (landing follows) · CoS / Marketing  
**Surfaces:** (1) Live viewfinder chrome · (2) App sheets / library · (3) Marketing at `photo.grepawk.com`  
**Constraint:** **One shared token system.** Viewfinder chrome must stay **hue-neutral** so Creative Looks are not tint-biased.  
**Supersedes for color:** tables in [`design-handoff-v1.md`](./design-handoff-v1.md) §2–4 (type/spacing/layout stay).  
**Out of scope:** `docs/agents/*.md` edits.

---

## 0. Recommended system (ship this)

### **Neutral Graphite + Signal Amber**

| Layer | Choice | Why |
|-------|--------|-----|
| Neutrals | Near-black **achromatic graphite** (`#111111` family) | Darkroom / Halide / Darkroom-app pattern: photo is brightest; no warm/cool cast on live preview |
| Accent | **Signal Amber** `#F5C518` (active) / deeper `#E0A812` (filled CTA) | Classic-camera yellow active state (Halide Mark II); darkroom safelight cue; craft energy without SaaS purple |
| Semantics | Green success · amber warn · red danger | Category convention; Darkroom-app functional color map |
| Vision | Desaturated steel `#7A91A8` | Indicator only — **not** purple AI glow |

**CTA label on amber fills:** `#121212` (dark), not white — keeps contrast on bright signal.

**Alts researched (do not ship unless Yisheng overrides):**  
- **B — Neutral + Signal Blue** — higher “trust” association in psych lit; less camera-classic.  
- **C — Neutral + Carmine** — continuity with today’s rose; still risks “Tailwind SaaS” read.

---

## 1. Research grounding

Sources informing this system (CoS competitor/psych pass may refine; this is Design’s baseline):

| Finding | Implication for Photo Recipes |
|---------|-------------------------------|
| **Darkroom app** uses ~`rgb(17,17,17)` canvas so the photograph is never tint-competed; UI chrome is black/gray/white; color only when functional ([Darkroom design notes](https://blakecrosley.com/guides/design/darkroom)) | Viewfinder scrims + surfaces must be **hue-neutral**. Warm-black “safelight” *backgrounds* are rejected for live camera. |
| **Halide Mark II** treats UI as a camera; progressive disclosure; **single yellow** for active state — homage to classic cameras ([Apple Developer – Behind the Design](https://developer.apple.com/news/?id=x6bv1a36)) | One accent family for Auto Optimize / active / shutter core. Don’t scatter rose + purple + amber. |
| Halide Looks / Process Zero keep processing honest; chrome stays out of the way ([halide.cam](https://halide.cam/)) | Our Looks = capture grades; chrome must not pre-tint the finder. |
| Psych: cool hues often read more “trustworthy” than warm; lower saturation ↔ trust ([Kosova et al. summary](https://journals.rcsi.science/2782-2184/article/view/298120)) | Neutrals stay cool-neutral/achromatic for trust; **warm accent only at 10% of UI** (60-30-10 → accent ≈10%). |
| Mobile: one dominant accent teaches where to tap; dark mode prefers near-black gray over pure `#000` (OLED smear) | Graphite `#111` not pure black; single Signal Amber for primary actions. |
| Category: filter/beauty apps lean pink/purple neon | Avoid vision-purple glows; differentiate as **field camera**. |

**Hook for CoS research:** If competitor audit strongly favors blue CTAs for conversion on `photo.grepawk.com`, swap accent to **Alt B** without changing neutral tokens.

---

## 2. Before → after (vs current v1)

| Token | Current (v1) | v2 recommended | Note |
|-------|--------------|----------------|------|
| `bg` | `#0c0c0f` (cool zinc) | `#111111` | Truer neutral; OLED-friendly |
| `surface` | `#16161c` | `#1C1C1E` | Matches Apple dark gray ladder |
| `accent` | `#f43f5e` rose | `#E0A812` / signal `#F5C518` | Break rose SaaS; camera-yellow lineage |
| `vision` | `#8b7cf6` purple | `#7A91A8` steel | Kill AI-purple glow |
| Hero radial | rose fog | ≤6% amber **on marketing only** | **Never** on live viewfinder |
| Viewfinder scrim | generic black | Neutral black alpha | No amber in scrim RGB |

---

## 3. Shared token table (recommended)

OKLCH approx for implementers who prefer perceptual tweaks; **hex is source of truth for v2 ship**.

### Neutrals (hue ≈ 0 — do not warm)

| Token | Hex | OKLCH (approx) | Role |
|-------|-----|----------------|------|
| `bg` | `#111111` | `oklch(0.17 0 0)` | App + landing page bg |
| `bg-elevated` | `#161616` | `oklch(0.19 0 0)` | Soft panels |
| `surface` | `#1C1C1E` | `oklch(0.22 0.002 280)` | Cards, sheets (hair of cool OK) |
| `surface-2` | `#2C2C2E` | `oklch(0.28 0.002 280)` | Nested wells, dials tray |
| `border` | `#3A3A3C` | `oklch(0.34 0.002 280)` | Hairline |
| `border-strong` | `#545456` | `oklch(0.44 0.002 280)` | Focus / active card |
| `ink` | `#F5F5F7` | `oklch(0.97 0.002 280)` | Primary text / chrome ink |
| `ink-secondary` | `#C7C7CC` | `oklch(0.84 0.005 280)` | Body |
| `ink-tertiary` | `#8E8E93` | `oklch(0.66 0.01 280)` | Meta only |
| `overlay` | `rgba(0,0,0,0.72)` | — | Modal scrim (neutral black) |

### Accent + semantics

| Token | Hex | OKLCH (approx) | Role |
|-------|-----|----------------|------|
| `accent` | `#E0A812` | `oklch(0.76 0.145 85)` | Filled CTA, Auto Optimize, shutter core |
| `accent-soft` | `#F5C518` | `oklch(0.84 0.155 90)` | Active indicator / hover / focus ring |
| `accent-muted` | `color-mix(in oklab, #E0A812 16%, transparent)` | — | Selected fills (no glow) |
| `accent-on-accent` | `#121212` | `oklch(0.18 0 0)` | **Label text on amber buttons** |
| `tip` | `#E0A812` | same family | Tips border/icon (or match accent) |
| `tip-bg` | `color-mix(in oklab, #E0A812 10%, transparent)` | — | Tips well |
| `success` | `#30D158` | `oklch(0.78 0.17 145)` | Ready / trial (Apple-like green OK) |
| `warn` | `#FF9F0A` | `oklch(0.80 0.16 70)` | Motion risk |
| `danger` / `error` | `#FF453A` | `oklch(0.65 0.20 25)` | Errors |
| `vision` | `#7A91A8` | `oklch(0.68 0.04 245)` | Vision mode indicator only |

### Chips

| State | Fill | Label |
|-------|------|-------|
| Idle | `surface-2` + `border` | `ink-secondary` |
| Active / selected | `accent-muted` | `accent-soft` |
| Before (diff) | — | `ink-tertiary` |
| After (diff) | — | `ink` |
| Look suggested/active | `accent-muted` + hairline `accent` | Look name · intensity |

**Category tints @ ~14% fill (library only — not on finder):** DoF `#5B8DEF` · Motion `#FF9F0A` · HDR `#8B8DBF` · Composition `#64D2FF` · Favorites → accent.

---

## 4. Viewfinder chrome (critical)

**Rule:** Scrim RGB channels stay equal (or tiny cool). **No amber, rose, or purple in scrim fills.** Accent appears only on discrete controls (Optimize pill, shutter core, look chip border).

| Token | Value | Notes |
|-------|-------|-------|
| `camera-scrim` | `rgba(0,0,0,0.45)` | Top/bottom |
| `camera-scrim-strong` | `rgba(0,0,0,0.78)` | Permissions / errors |
| `camera-chrome-ink` | `#F5F5F7` | Readouts |
| `camera-chrome-ink-secondary` | `rgba(245,245,247,0.78)` | Secondary |
| `camera-hairline` | `rgba(255,255,255,0.16)` | Pill borders |
| `shutter-ring` | `#F5F5F7` | Outer |
| `shutter-core` | `accent` `#E0A812` | Inner photo |
| `status-pill-bg` | `rgba(28,28,30,0.72)` | Blur + surface |
| `status-pill-border` | `rgba(255,255,255,0.14)` | Default; optional `accent` @ 0.35 **only while optimizing** |
| `look-chip-bg` | `rgba(224,168,18,0.18)` | Chip only — not full-bleed wash |
| `ae-lock` | `warn` / tip | AE/AF lock |

Aligns with capabilities-comms: Core chips + optional Look chip; no tint wall.

---

## 5. Marketing / `photo.grepawk.com`

Same tokens. Landing may use:

- Soft accent radial **behind hero art only:** `rgba(224,168,18,0.06)` — never behind live camera.  
- Primary CTA: `accent` + `accent-on-accent` label.  
- Secondary: `border` + `ink`.  
- Waitlist success: `success`.  
- No GitHub CTA chrome. No purple glows.

---

## 6. Alternatives (research options)

### Alt B — Neutral Graphite + Signal Blue

Same neutrals. Swap:

| Token | Hex |
|-------|-----|
| `accent` | `#0A84FF` |
| `accent-soft` | `#409CFF` |
| `accent-muted` | mix 16% |
| `accent-on-accent` | `#FFFFFF` |

**When:** CoS conversion research favors trust-blue CTAs on web. Cost: less “classic camera” cue.

### Alt C — Neutral Graphite + Carmine

Same neutrals. Swap:

| Token | Hex |
|-------|-----|
| `accent` | `#D63856` |
| `accent-soft` | `#E85D76` |
| `accent-on-accent` | `#FFFFFF` |

**When:** Brand continuity with v1 rose is mandatory. Cost: SaaS-rose association remains.

---

## 7. CSS sketch (`@theme`) — recommended A

```css
@theme {
  --color-bg: #111111;
  --color-bg-elevated: #161616;
  --color-surface: #1c1c1e;
  --color-surface-2: #2c2c2e;
  --color-border: #3a3a3c;
  --color-border-strong: #545456;
  --color-ink: #f5f5f7;
  --color-ink-secondary: #c7c7cc;
  --color-ink-tertiary: #8e8e93;
  --color-accent: #e0a812;
  --color-accent-soft: #f5c518;
  --color-accent-muted: color-mix(in oklab, #e0a812 16%, transparent);
  --color-accent-on-accent: #121212;
  --color-vision: #7a91a8;
  --color-tip: #e0a812;
  --color-tip-bg: color-mix(in oklab, #e0a812 10%, transparent);
  --color-success: #30d158;
  --color-warn: #ff9f0a;
  --color-danger: #ff453a;
}
```

---

## 8. Implementation priority

1. **iOS Camera** — scrims, status, chips, Auto Optimize, shutter, sheets (Looks intensity track = accent).  
2. **iOS Library / paywall** — shared tokens.  
3. **Web** `@theme` + `photo.grepawk.com` landing — same tokens when unpaused.

---

## 9. Checklist

- [ ] Neutrals verified hue-neutral on device (no warm cast under Looks)  
- [ ] Accent only on discrete controls on finder — no amber wash  
- [ ] Amber CTA uses `#121212` label  
- [ ] Vision purple removed  
- [ ] `--color-warn` added  
- [ ] Landing hero radial ≤6% amber, optional  
- [ ] CoS/Yisheng confirm recommended A (or B/C) before full remap  

---

## 10. Decision

| System | Ship? |
|--------|-------|
| **Neutral Graphite + Signal Amber** | **Yes — recommended** |
| Alt B Signal Blue | Research override only |
| Alt C Carmine | Continuity override only |

---

*Designer · color v2 · research-backed shared system · viewfinder-neutral*
