# Recommend recipe — first-class CTA v1

**Audience:** Web Engineer · iOS Expert  
**Ask:** One tap to Recommend — no “open Field Coach → pick mode → Recommend” gate.  
**Framing:** Darkroom field notes. **Camera / Auto Optimize stays the capture primary** on iOS. Voice secondary. Web Field Coach **recommends** (does not write dials).  
**Color:** Palette A — filled Recommend uses Signal Amber + `accentOnAccent` label when it’s a primary action on that surface.

---

## 1. Principle

| Surface | Loudest action | Recommend role |
|---------|----------------|----------------|
| iOS Camera (viewfinder) | **Auto Optimize** | Secondary always-visible chip — never replaces AO |
| Web Camera / Field Coach home | **Recommend recipe** (web can’t write dials) | **Primary** filled CTA — always visible |
| Ask / Library coach panel | Recommend | Primary; mode is progressive disclosure, not a prerequisite |

**Rule:** Default path uses **From viewfinder** (or current scene note / last frame) with **no mode picker required**. Advanced modes (type / photo pick / voice) live as optional chips *beside or under* the primary button — not a step before it.

---

## 2. Default behavior (both platforms)

1. User taps **Recommend recipe** (or compact **Recommend**).  
2. Payload (first available):  
   - live viewfinder frame / last captured preview frame, **or**  
   - non-empty scene note / “From viewfinder” chip text, **or**  
   - empty → still fire with `From viewfinder` sentinel so the agent senses from image if present; if neither note nor image, show inline error `Add a short scene note or enable camera` under the button (don’t open a sheet first).  
3. Button → loading: `Matching a recipe…` · disabled.  
4. Success → navigate / sheet to recipe result (existing recommend → detail flow).  
5. Mic remains a quiet icon; never the only path to Recommend.

---

## 3. Layout patterns

### A. Web Camera / Field Coach (`/app` camera tab)

```
[ viewfinder / photo well ]
[ scene note …………… ] [mic]
[ ████ Recommend recipe ████ ]   ← accent filled, full width, always on
[ From viewfinder ] [Photo] [Type]  ← optional mode chips; cosmetic defaults only
```

- Remove any flow that requires selecting Describe vs Photo **before** the button enables.  
- If a mode chip is selected, it only changes payload; Recommend stays enabled whenever default path can run.  
- Keep one-line honesty: `Recommends dials — does not write them in the browser`.

### B. iOS Camera (viewfinder)

```
… status / chips …
[ scene chip ▾ ] [mic]
[ ⚡ Auto Optimize ]     ← primary (accent)
[ Recommend ]            ← ghost/outline or compact secondary pill, same row or directly under AO
```

- Recommend opens coach recommend with From viewfinder / scene note — **does not** push Ask tab first.  
- If Free Peek quota applies, same soft gate as Ask (sheet), not a hidden second button.  
- Do not put Recommend in `···` only.

### C. iOS Ask / Field Coach panel

- Segmented mode (Describe / Photo) may remain for power users but **default = Describe** with Recommend always visible and enabled when note ≥ 1 char **or** photo attached **or** “use viewfinder” toggle on.  
- Primary button label: `Recommend a recipe` (loading: `Matching a recipe…`).  
- Photo path label when photo attached: same primary button (don’t rename to a second CTA that replaces the first).

---

## 4. Copy locks

| Slot | Copy |
|------|------|
| Primary (web) | `Recommend recipe` |
| Primary (iOS Ask) | `Recommend a recipe` |
| Compact (iOS Camera) | `Recommend` |
| Loading | `Matching a recipe…` |
| Empty error | `Add a scene note or enable the camera` |
| Web honesty | `Recommends dials — does not write them in the browser` |

---

## 5. Anti-patterns

- Mode tabs that disable Recommend until a mode is chosen.  
- Recommend only inside an overflow / second sheet.  
- Leading with mic to get a recommendation.  
- On iOS Camera: making Recommend equal visual weight to Auto Optimize (AO stays louder).  
- Dual CTAs both filled amber competing on the same row (web: one filled; iOS Camera: AO filled, Recommend outline).

---

## 6. Engineer checklist

- [ ] Web Field Coach: one always-visible filled Recommend; modes optional  
- [ ] Web: default From viewfinder / note / frame without extra click  
- [ ] iOS Camera: Recommend secondary pill always visible near AO  
- [ ] iOS Ask: Recommend enabled without mandatory mode gate  
- [ ] Analytics: `recommend_cta_tap` with `surface=camera|ask|web_camera`  
- [ ] No `docs/agents/*.md` edits  

---

*Designer · recommend CTA v1 · for Web + iOS*
