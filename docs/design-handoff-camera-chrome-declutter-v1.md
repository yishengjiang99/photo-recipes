# iOS Camera chrome declutter v1

**Audience:** iOS Expert  
**Problem:** Library / Coach / Settings (tab bar + any on-finder duplicates) eat the viewfinder and obscure shutter / Auto Optimize.  
**Goal:** Viewfinder-first. **Auto Optimize + shutter** stay primary. Safelight Amber / Palette A tokens unchanged.  
**Out of scope:** `docs/agents/*.md` · web (already shipping its own shell fix).

---

## Layout decision (ship this)

### 1. Hide the tab bar on Camera

While `selectedTab == .camera`, **hide the system tab bar** (full-bleed preview to the home indicator).

```
┌─────────────────────────────┐
│ [flash]     [flip]    [ ··· ] │  safe-area top overlays only
│                             │
│        LIVE VIEWFINDER      │  100% width/height under overlays
│                             │
│   [status] [chips]          │
│   [⚡ Auto Optimize]        │  filled amber + accentOnAccent
│   [ Recommend ]             │  outline secondary (handoff #50)
│        (  shutter  )        │  center, large
└─────────────────────────────┘
     ← no Library / Coach / Settings strip
```

### 2. Destinations live in `···` (overflow)

Top-trailing **`···`** (44pt) opens a **menu or compact list sheet** (not a second tab bar):

| Row | Action |
|-----|--------|
| Library | `router.selectedTab = .library` |
| Coach | `router.selectedTab = .ask` |
| Settings | `router.selectedTab = .settings` |
| Controls / dials | existing Controls sheet (if not already a dedicated control) |

Use SF Symbol `ellipsis.circle` or `ellipsis`. Quiet ink on scrim — **not** accent-filled.

### 3. Tab bar returns off-camera

On Library / Coach / Settings, show the tab bar again (or a leading **Camera** control that selects `.camera`). Prefer:

- Tab bar visible on non-camera tabs so users can jump without hunting `···`.
- Selected tab tint = Palette A accent; unselected = `inkTertiary`.

### 4. Preserve on the finder (do not remove)

| Keep | Notes |
|------|--------|
| Auto Optimize | Filled primary pill |
| Shutter | Center primary capture |
| Recommend | Outline secondary — always visible, no Ask gate |
| Status / before→after / look chip | Ephemeral overlays |
| Flash / flip | Top leading/trailing cluster opposite or beside `···` |
| Pan cues | When agent requests |

### 5. Remove / demote

| Remove from finder | Where it goes |
|--------------------|---------------|
| Persistent Library / Coach / Settings as large chrome | `···` menu only while on Camera |
| Any duplicate nav pills that mirror tabs | Delete on-finder copies |
| Accent-filled Camera tab when already on Camera | N/A once tab bar hidden on Camera |

---

## Hierarchy (loud → quiet)

1. Shutter  
2. Auto Optimize  
3. Recommend · status chips  
4. Flash / flip / `···`  
5. Destinations (Library / Coach / Settings) — **not on-canvas**

---

## Sketch (ASCII)

**Camera (tab bar hidden)**

```
  ⚡        flip      ···
           preview
      AO (amber filled)
      Recommend (ghost)
         ◉ shutter
```

**`···` sheet**

```
  Library     >
  Coach       >
  Settings    >
```

**Library (tab bar visible)**

```
  [content]
  ─────────────
  Camera | Library | Coach | Settings
```

---

## Engineer checklist

- [ ] Hide tab bar when Camera selected (`toolbar(.hidden, for: .tabBar)` or equivalent)  
- [ ] `···` menu → Library / Coach / Settings via router  
- [ ] No large persistent Library/Coach/Settings on viewfinder  
- [ ] AO + shutter + Recommend layout unchanged in role (AO filled, Recommend outline)  
- [ ] Palette A tokens; no new accent wash on preview  
- [ ] Coach marks still ≤3; update copy if they pointed at tabs  

---

## Definition of done

User can shoot with AO/shutter without three destination tabs covering controls; Library/Coach/Settings still one overflow tap away.

---

*Designer · camera chrome declutter v1 · for iOS Expert*
