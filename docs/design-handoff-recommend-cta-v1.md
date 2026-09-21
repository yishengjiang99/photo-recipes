# Recommend recipe — first-class CTA v1

**Audience:** Web Engineer · iOS Expert  
**Ask:** One tap to Recommend — no shutter-then-Recommend, no “open Field Coach → pick mode → Recommend.”  
**Framing:** Darkroom field notes. Voice secondary. Web **recommends** dials (does not write). iOS Camera **Auto Optimize writes** dials.  
**Color:** Palette A — filled primary uses Signal Amber + `accentOnAccent` label.

**Confirmed (Web investigation):** Primary **Recommend recipe** = capture frame from live viewfinder (if needed) **and** recommend in one tap; if a frame is already held, recommend that frame. Secondary only: **Retake** · **Upload** · **Describe**.

---

## 1. Cross-platform map (don’t invent divergent chrome)

| Surface | Primary (filled amber) | What it does | Secondary (outline / quiet) |
|---------|------------------------|--------------|-----------------------------|
| **Web** Camera / Field Coach | **Recommend recipe** | Grab live frame if none held → `/api/recommend` | Retake · Upload · Describe (text) · mic icon |
| **iOS Camera** | **Auto Optimize** | Sense → apply shutter/ISO/EV/WB/focus on device | **Recommend** (recipe coach from viewfinder/note — no Ask tab) · mic |
| **iOS Ask / Field Coach** | **Recommend a recipe** | Same one-tap recommend as web (note and/or photo) | Upload · Describe mode chips · mic |

**Why AO ≠ Recommend on iOS Camera:** AO *writes* phone settings. Recommend *picks a recipe* (coach / library handoff). Same “one tap from viewfinder” *idea*, different verbs — keep both visible; AO louder.

---

## 2. Web pattern (confirmed)

```
[ live viewfinder / held frame ]
[ ████████ Recommend recipe ████████ ]   ← only filled CTA
[ Retake ]  [ Upload ]  [ Describe ]     ← secondary; optional mic
```

### Tap behavior
1. If **no frame held** → capture current live viewfinder frame into hold, then recommend.  
2. If **frame already held** → recommend that frame (optionally merge scene note if present).  
3. Loading on primary: `Matching a recipe…` · disable primary + secondaries that would race.  
4. Success → existing recipe result / detail navigation.  
5. **Retake** → clear held frame, resume live preview (does not recommend).  
6. **Upload** → image picker → hold frame; **auto-recommend after upload** (same loading state on primary).  
7. **Describe** → expands text field; primary stays **Recommend recipe** and runs with text (+ held frame if any). Do **not** replace primary with a second button.

### Honesty line
`Recommends dials — does not write them in the browser`

---

## 3. iOS Camera (aligned, not identical chrome)

```
[ viewfinder ]
[ status / before→after / look chip ]
[ ⚡ Auto Optimize ]     ← filled primary
[ Recommend ]            ← outline secondary, always visible
```

- **Recommend** one-tap: From viewfinder frame and/or scene note → recommend result — **no Ask tab gate**, no mode picker.  
- Do not merge Recommend into Auto Optimize (different outcomes).  
- Quota / Pro soft-gate: same sheet as Ask, on tap — not a hidden second control.

---

## 4. iOS Ask panel

- Primary filled: **Recommend a recipe** (loading: `Matching a recipe…`).  
- Enabled when: note ≥ 1 char **or** photo attached **or** viewfinder frame available.  
- Upload / Describe are secondary; never a prerequisite before the primary appears.

---

## 5. Copy locks

| Slot | Copy |
|------|------|
| Web / Ask primary | `Recommend recipe` / `Recommend a recipe` |
| iOS Camera secondary | `Recommend` |
| Loading | `Matching a recipe…` |
| Empty (no camera + no note + no upload) | `Enable the camera or add a scene note` |
| Web honesty | `Recommends dials — does not write them in the browser` |

---

## 6. Anti-patterns

- Shutter/capture as a required step before Recommend on web.  
- Mode tabs that disable Recommend until chosen.  
- Two filled amber buttons on one surface.  
- On iOS Camera: Recommend equal weight to Auto Optimize.  
- Mic-led recommend path.

---

## 7. Engineer checklist

- [ ] Web: one filled Recommend = capture-if-needed + recommend  
- [ ] Web: Retake / Upload / Describe secondary only  
- [ ] iOS Camera: AO primary + always-visible Recommend secondary  
- [ ] iOS Ask: one-tap Recommend, no mode gate  
- [ ] Analytics: `recommend_cta_tap` + `surface` + `had_held_frame`  
- [ ] No `docs/agents/*.md` edits  

---

*Designer · recommend CTA v1 · Web confirmed capture+recommend · iOS AO/Recommend mapped*
