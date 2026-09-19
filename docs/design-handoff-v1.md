# Photo Recipes — UI Redesign Handoff v1

**Product:** Field technique assistant (not filters / AI-magic photo editor)  
**Aesthetic:** Darkroom field notes — contact sheet, aperture rings, book pages  
**Stack alignment:** Vite+React (web) · SwiftUI (iOS) · existing tokens in `src/index.css`  
**Pricing unchanged:** Free Peek · Pro $7.99/mo · **$59.99/yr primary** · 7-day trial  
**Do not design around:** Stripe “not configured” error as a default UI state

---

## 1. Critique of current UI

### What’s keepable (do not throw away)
- **Editorial type pairing** — Instrument Serif (display) + DM Sans (UI) already signals “book of recipes,” not another SaaS dashboard.
- **Accent rose** (`#f43f5e`) — strong, photographic, memorable. Keep as the single primary action color.
- **Camera dials** — the signature craft object. Steps + dials + tips is the right detail skeleton.
- **Soft funnel** — browse free, soft-gate checklists / unlimited Ask. Correct product posture.
- **Category tags + book page numbers** — authentic to the “Recipes book” source; treat as first-class chrome.
- **Annual as Best Value + trial badge** — paywall hierarchy is basically right.

### What’s wrong
1. **Phone column forever on desktop** — ~⅓–½ width centered column wastes space and reads like a stretched mobile webview, not a field tool you open on a laptop between shoots.
2. **Competing neon AI chrome** — Ask Grok (rose glow) + Photo Vision (purple glow) dominate Library and steal attention from the catalog. Feels like an AI product with presets attached, not a field technique assistant with a coach tucked in.
3. **Muted text too quiet** — supporting copy, chips, gear labels, and Free Peek chrome sit near `#a1a1aa` / lower on near-black. Fine for decoration; bad for field readability (sun glare, small type).
4. **Weak library scan** — stacked identical cards with tiny gear icons and tiny “KEY SETTING” labels. Hard to pick a recipe in 2 seconds.
5. **Pro checklist muddy** — heavy dim + lock overlay makes the soft gate feel punitive/broken rather than a clear teaser.
6. **Ask panel dominance** — huge textarea + tiny suggestion chips + full-width CTA; chips feel secondary when they should be the fast path.
7. **Paywall CTAs as text links** — “Start free trial →” as white links underplan the annual card; annual needs a solid primary button.
8. **One accent doing too much** — filters, Upgrade, Ask CTA, category tags, locks, dials highlight all shout rose → hierarchy collapses.

### Design north star
**“Darkroom field notes.”** Quiet surfaces. One loud action. Dials and recipes are the hero. AI coach is a tool drawer, not a billboard.

---

## 2. Improved design direction

### Metaphor & mood
- Contact sheet / film rebate / aperture ring / handwritten field checklist.
- Slight grain or 1px film-edge hairlines optional; **no** heavy glassmorphism, **no** dual neon glows.
- Background stays near-black with a **cooler, quieter** wash (less pink fog). Reserve rose for CTAs and active states only.

### Type
| Role | Font | Use |
|------|------|-----|
| Display | Instrument Serif | Recipe titles, screen titles, price figures |
| UI / body | DM Sans | Labels, steps, chips, buttons |
| Mono (optional) | ui-monospace / JetBrains Mono | Dial values, EXIF-like key settings |

**Scale (rem @ 16px):**
| Token | Size | Weight | Line |
|-------|------|--------|------|
| `display-xl` | 2.25rem (36) | 400 serif | 1.15 |
| `display-lg` | 1.75rem (28) | 400 serif | 1.2 |
| `title` | 1.25rem (20) | 600 sans | 1.3 |
| `body` | 1rem (16) | 400/500 | 1.5 |
| `body-sm` | 0.875rem (14) | 400/500 | 1.45 |
| `caption` | 0.75rem (12) | 500 | 1.35 |
| `overline` | 0.6875rem (11) | 600 · tracking 0.08em · UPPER | 1.2 |

**Contrast rule:** Body and interactive labels ≥ `#c4c4cc` on `#0c0c0f`. Captions ≥ `#a8a8b3`. Never put essential copy below that.

### Color (refined tokens)
| Token | Hex | Role |
|-------|-----|------|
| `bg` | `#0c0c0f` | App background |
| `bg-elevated` | `#121216` | Soft panels |
| `surface` | `#16161c` | Cards |
| `surface-2` | `#1e1e26` | Nested wells, dials tray |
| `border` | `#2a2a33` | Default hairline |
| `border-strong` | `#3f3f4a` | Focused / active card edge |
| `ink` | `#f5f5f7` | Primary text |
| `ink-secondary` | `#c4c4cc` | Body / descriptions |
| `ink-tertiary` | `#8b8b96` | Meta only (page #, educational) |
| `accent` | `#f43f5e` | Primary CTA, active filter, favorite filled |
| `accent-soft` | `#fb7185` | Hover / focus ring tint |
| `accent-muted` | `rgba(244,63,94,0.14)` | Soft selected fills (not glow) |
| `vision` | `#8b7cf6` | Photo Vision mode indicator only (not whole card glow) |
| `tip` | `#e7b549` | Tips callout border/icon text |
| `tip-bg` | `rgba(231,181,73,0.08)` | Tips well |
| `success` | `#34d399` | Trial badge |
| `danger` | `#f87171` | Errors (Stripe, API) — transient only |
| `overlay` | `rgba(0,0,0,0.72)` | Modal scrim |

**Category tints (subtle left rail / tag fill, not full card paint):**
- Depth of Field → cool `#5b8def` @ 18% fill  
- Motion → warm `#f59e0b` @ 18%  
- HDR → `#a78bfa` @ 18%  
- Composition → `#2dd4bf` @ 18%  
- Favorites → accent  

### Spacing & radii
- **Space scale:** 4 · 8 · 12 · 16 · 24 · 32 · 48 · 64  
- **Card padding:** 16 (mobile) / 20 (desktop)  
- **Section gap:** 24–32  
- **Radii:** `sm` 8 · `md` 12 · `lg` 16 · `pill` 999 · dials stay circular  
- **Touch targets:** ≥ 44×44 on mobile; chips height 36–40  

### Components (system)
1. **AppShell** — header + content max-width (see breakpoints).  
2. **FieldCoach** — unified Ask (text | photo) with segmented control; quiet border, no dual glow.  
3. **FilterChips** — one filled accent for active; others `border` + `ink-secondary`.  
4. **RecipeRow / RecipeCard** — title + key setting large; gear as readable chips; category left accent.  
5. **DialCluster** — keep; stronger value type; one “focus” dial via `border-strong` not dashed rose scream.  
6. **StepList** — numbered wells with `ink` body.  
7. **TipsCallout** — amber, not competing with accent CTAs.  
8. **SoftGate** — fade last 40% of checklist + solid upgrade bar (not muddy full lock soup).  
9. **PaywallModal** — annual solid primary button; monthly secondary outline.  

### Motion
- 150–200ms ease for hover/press.  
- Dial entrance keep `dial-in` but subtler (−4° not −8°).  
- Prefer border/background shifts over colored box-shadow glows.

---

## 3. Redesigned screen specs

### Breakpoints
| Name | Width | Layout notes |
|------|-------|--------------|
| `mobile` | < 640 | Single column · content pad 16 · full-bleed cards |
| `tablet` | 640–1023 | Content max 640 · pad 24 |
| `desktop` | ≥ 1024 | Content max **960** · Library: coach left or top strip + **2-col recipe grid** |
| `wide` | ≥ 1280 | Content max **1040** · optional 3-col grid if ≥9 recipes later |

**Kill:** eternal ~420px centered column on large screens.

---

### A. Library

**Goal:** Find a recipe in seconds; coach is available but not louder than the catalog.

**Header**
- Left: logo mark + “Photo Recipes” (serif 18–20) + subtitle `Field presets · 30 Recipes book` (`caption`, `ink-tertiary`).
- Right: `Free Peek` outline pill · `Upgrade` solid accent (sm).  
- Sticky on scroll (mobile).

**Title block**
- `Recipe library` → `display-lg`.  
- One short line only: “Shoot checklists + dials. Ask when you’re stuck.” (`body-sm`, `ink-secondary`). Drop the long three-line muted essay.

**Field Coach (unified)**
- Single card, `surface`, `border` 1px, **no** rose/purple outer glow.  
- Segmented control: **Describe scene** | **From photo**.  
- Badge: `Free Peek · 1 left today` (`caption`).  
- Describe: textarea min-height 88 (not huge); **suggestion chips row first** (wrap, height 36, `ink-secondary` / `border`); primary button `Recommend a recipe`.  
- Photo: dropzone dashed `border-strong`, `Choose photo`, optional note 1-line, button `Recommend from photo` (accent; vision mode shows small violet dot on segment).  
- Desktop: coach sits in a **compact strip** above filters (collapsed height ~200–240), not a double billboard.

**Filters**
- Horizontal scroll on mobile; wrap on desktop.  
- Active = `accent` fill; inactive = outline.

**Recipe list / grid**
- Mobile: stacked cards.  
- Desktop ≥1024: **2 columns**, gap 16.  
- Each card:
  - Left 3px category tint bar.  
  - Row: category overline + `p.28` meta + favorite heart (44 hit).  
  - Title: serif `title` / `display` ~22–24.  
  - One-line description `body-sm` `ink-secondary` (truncate 2 lines max).  
  - Footer: **Key setting** as mono/semibold `body` (large enough to read at arm’s length) · gear as text chips (“Camera · Phone · Tripod”) not tiny icon soup.  

**Footer disclaimer** — `caption` `ink-tertiary`, single line.

---

### B. Detail (Recipe)

**Goal:** Dial → steps → tips → checklist. Field-usable outdoors.

**Nav row:** `← Library` · Favorite. Both `ink-secondary`, 44 hit.

**Hero**
- Category pill (tinted) + `Book p.28`.  
- Title `display-xl`.  
- Description `body` `ink-secondary`.  
- Gear as compact chip row (readable labels).

**When to use** — icon + `title` section label; body `ink-secondary` (not near-invisible).

**Recommended dials**
- Tray `surface-2`, label row: “Recommended dials” · `Educational · simulated` overline.  
- 4 dials; values in mono or semibold sans ≥14px.  
- Warning under dials: `body-sm` `ink-secondary` (or tip color if caution).  
- Desktop: dials in one row; mobile: 2×2.

**Steps** — numbered circles in `accent-muted` fill with `accent` numeral (not loud solid rose discs if it fights CTAs). Body `ink`.

**Tips** — keep amber callout; title overline; bullets `body-sm`.

**Field checklist (Free Peek soft gate)**
- Show **first item fully**; remaining items visible but progressive mask (gradient to `bg`, last ~40%).  
- Bottom bar (always clear): lock glyph + one line benefit + solid `Upgrade · 7-day trial`.  
- Pro: interactive checkboxes, persist as today.

**Do not** wash the whole block into unreadable pink mud.

---

### C. Ask (text + photo) — states inside Field Coach

**Empty / ready**
- Segmented control.  
- Chips visible without scrolling past a giant textarea.  
- Quota caption always visible.

**Loading**
- Button → spinner + “Matching a recipe…” · disable double-submit.  
- No extra neon.

**Result**
- Inline result card under coach: recipe title (serif) + one-sentence why + `Open recipe` accent button + `Try another`.  
- Prefer scroll-to-result over a blocking modal on mobile.

**Error / quota exhausted**
- Calm banner `surface-2` + upgrade CTA; don’t mimic Stripe error chrome.

---

### D. Paywall (Pricing modal)

**Goal:** Annual primary; trial clear; comparison scannable; **no** Stripe config error in happy path.

**Structure**
1. Pill: `Soft upgrade · browse stays free`.  
2. Title: `Photo Recipes Pro` serif.  
3. Sub: one sentence Free Peek vs Pro (`ink-secondary`).  
4. **Annual card first** — `border` accent, `Best value` badge, green `7-day free trial`, price serif large, `≈ $5/mo · save vs monthly`, **solid white or accent button** `Start free trial` (prefer solid `ink` on accent or solid accent on dark — pick **filled accent + white label** for primary).  
5. Monthly — quieter border; outline button `Start free trial`.  
6. Comparison: two columns Free Peek | Pro; Pro checks use `accent`; Free uses `ink-secondary`.  
7. Errors (Stripe missing, network): compact `danger` inline alert **below** CTAs, not replacing the plan cards. Hide entirely when configured.

**Backdrop:** `overlay` + blur optional; modal `surface` max-width 440 mobile / 480 desktop; radius `lg`.

---

## 4. Design tokens (implement in `@theme` + SwiftUI Asset/Color)

```css
@theme {
  --font-sans: "DM Sans", ui-sans-serif, system-ui, sans-serif;
  --font-display: "Instrument Serif", Georgia, serif;
  --font-mono: ui-monospace, "SF Mono", Menlo, monospace;

  --color-bg: #0c0c0f;
  --color-bg-elevated: #121216;
  --color-surface: #16161c;
  --color-surface-2: #1e1e26;
  --color-border: #2a2a33;
  --color-border-strong: #3f3f4a;
  --color-ink: #f5f5f7;
  --color-ink-secondary: #c4c4cc;
  --color-ink-tertiary: #8b8b96;
  --color-accent: #f43f5e;
  --color-accent-soft: #fb7185;
  --color-accent-muted: color-mix(in oklab, #f43f5e 14%, transparent);
  --color-vision: #8b7cf6;
  --color-tip: #e7b549;
  --color-success: #34d399;
  --color-danger: #f87171;

  --radius-sm: 8px;
  --radius-md: 12px;
  --radius-lg: 16px;
  --radius-pill: 999px;

  --space-1: 4px;
  --space-2: 8px;
  --space-3: 12px;
  --space-4: 16px;
  --space-5: 24px;
  --space-6: 32px;
  --space-7: 48px;
  --space-8: 64px;

  --shadow-card: 0 8px 24px -12px rgba(0,0,0,0.55);
  /* avoid colored glow as default elevation */
}
```

**Migrate from current:** rename `--color-muted` → split into `ink-secondary` / `ink-tertiary`; add borders & vision/tip; widen layout containers in `Layout.tsx`.

---

## 5. Engineer handoff checklist

### Web Engineer (Vite + React) — implement first
- [ ] Expand `@theme` tokens in `src/index.css` per §4; replace ad-hoc zinc/rose utility soup where possible.
- [ ] `Layout.tsx`: raise max-width to 960/1040; responsive padding; remove “always narrow phone column.”
- [ ] Merge `AskGrok.tsx` + `PhotoVision.tsx` into **FieldCoach** with segmented control; strip dual glow; chips-first layout.
- [ ] `Library.tsx`: shorten intro; 2-col grid ≥1024; recipe cards show **key setting** large + text gear chips + category rail.
- [ ] `FilterBar.tsx`: contrast/active states per tokens.
- [ ] `PresetCard.tsx`: new hierarchy; hover = `border-strong` + slight lift, not heavy rose shadow.
- [ ] `PresetDetail.tsx`: dials / steps / tips spacing; **SoftGate** gradient teaser + clear upgrade bar.
- [ ] `CameraDials.tsx`: value type size ↑; focus dial via `border-strong`.
- [ ] `PricingModal.tsx`: solid primary on annual; outline monthly; Stripe error as optional alert only.
- [ ] Global: body/description text → `ink-secondary`; ensure WCAG-ish contrast for field use.
- [ ] Smoke: Library → Detail → Ask text → Ask photo → Upgrade modal (no reliance on Stripe error UI).

### iOS Expert (SwiftUI) — align in parallel
- [ ] Port Color tokens to Asset Catalog / `Theme.swift` (same hex values).
- [ ] Typography: display serif if available (or New York) + DM Sans / system SF for UI; match scale roles.
- [ ] Library: native list (mobile) matching card hierarchy; Field Coach as compact section with `Picker` segment.
- [ ] Detail: dials cluster, steps, tips, soft-gated checklist same behavior.
- [ ] Paywall: StoreKit/Stripe-equivalent plans — annual primary button treatment identical.
- [ ] Do not invent a divergent purple “AI skin”; vision mode = small indicator only.
- [ ] Dynamic Type: body/secondary sizes scale; dials remain legible at larger sizes.

### Out of scope for this handoff
- New recipes / copywriting rewrite of book content  
- Stripe infra setup (engineering ops, not UI)  
- Marketing site / App Store screenshots (can follow once UI ships)

### Definition of done
Web matches §3 layouts at mobile + desktop breakpoints; tokens live in one place; iOS shares token values and component hierarchy; CoS can forward this doc as the single source of truth.

---

*Designer · Photo Recipes UI redesign v1 · handoff for Web Engineer + iOS Expert*


---

## Addendum — Camera (product pivot)

Live capture UI (viewfinder, dials overlay, apply recipe, permissions, Pro gate) lives in **[`design-handoff-camera-v1.md`](./design-handoff-camera-v1.md)**. Library/Detail/Ask/Paywall in this doc still apply; Camera is now the home surface and recipes drive the live session.


---

## Addendum — Agentic Auto Optimize

See **[`design-handoff-agentic-v1.md`](./design-handoff-agentic-v1.md)** and the Camera addendum. Auto Optimize is the primary Camera CTA; Library/Ask become agent tools + coach surfaces.
