# Photo Recipes — Voice Input Handoff v1

**Extends:** Field Coach (Ask) in [`design-handoff-v1.md`](./design-handoff-v1.md) · Camera / Auto Optimize in [`design-handoff-camera-v1.md`](./design-handoff-camera-v1.md) · [`design-handoff-agentic-v1.md`](./design-handoff-agentic-v1.md)  
**Scope:** Mic affordance, recording pulse, live transcript into the text field, stop/done — **Ask** and **Camera** (scene dictate for Auto Optimize / Ask).  
**Aesthetic:** Darkroom field notes — no neon waveform toys; small mic, quiet pulse, transcript as normal ink.

iOS + Web both implementing against this.

---

## 1. Where it lives

| Surface | Control placement | What transcript fills |
|---------|-------------------|----------------------|
| **Ask / Field Coach** (Describe scene) | Trailing inside textarea / note field | Scene description → same as typed Ask |
| **Camera** | Near Auto Optimize row **or** in a compact “Dictate scene” chip above status | Optional scene note the agent uses during Sense/Reason; does **not** replace shutter |

Photo Vision (file) mode: mic optional on the optional note field only — same component.

---

## 2. Components

### Mic button
- 44×44 hit; glyph mic (`ink-secondary`) on idle.
- Default: ghost / hairline circle on `surface` — **not** accent fill (accent reserved for Auto Optimize / primary CTAs).
- Disabled 40% when permission denied until Settings path, or while Ask request in flight.

### Recording pulse
- State: mic glyph → `accent` (or filled accent-muted circle) + **soft opacity pulse** 1.2s loop on ring only.
- Leading status caption optional: `Listening…` (`body-sm`, `ink-secondary`).
- Respect Reduce Motion: static accent ring, no pulse.
- **Do not** full-screen waveforms or glowing AI orbs.

### Transcript-in-field
- Partial results stream into the text field as the user speaks (append/replace per platform speech API).
- Same type styles as typed input (`body`, `ink`).
- Preserve any text the user already typed: append with a space unless caret mid-string (then insert at caret).
- Placeholder hides once non-empty.

### Stop / Done
- While recording, mic button **becomes Stop** (square glyph or `Stop` caption) — same hit target.
- Primary finish: **Stop** ends recognition and keeps transcript; focus stays in field.
- Optional trailing text button **Done** on Camera dictate chip = Stop + dismiss chip / collapse listening UI.
- Esc / system interrupt → Stop, keep partial transcript.

---

## 3. Permissions & errors

| State | UI |
|-------|-----|
| Not determined | Tap mic → system mic permission |
| Denied | Sheet: `Microphone is off` · `Open Settings` · `Type instead` |
| No speech / empty | Toast/caption: `Didn’t catch that — try again` · field unchanged |
| Network ASR fail (if cloud) | `Voice unavailable — type your scene` |

Never block Ask or Auto Optimize if mic fails — typing always works.

---

## 4. Behavior notes

- **One session at a time** — starting mic on Camera stops Ask mic and vice versa.
- **Auto Optimize:** if dictate produced text, agent may use it as an extra Sense hint; status can flash `Using your note…` once.
- **Free / Pro:** voice does not need a separate gate; existing Ask / Auto Optimize quotas still apply to the *run*, not to dictation.
- **Privacy copy (Settings, one line):** `Voice is converted to text for scene matching. We don’t keep audio clips.` (adjust if product stores otherwise.)

---

## 5. Engineer checklist (iOS + Web)

- [ ] Shared `VoiceDictateButton` + field binding (mic → listening pulse → stop → transcript).
- [ ] Wire into Field Coach Describe textarea + optional Vision note.
- [ ] Wire into Camera dictate affordance near Auto Optimize / status stack.
- [ ] Mic permission covers §3.
- [ ] Reduce Motion: no pulse.
- [ ] Web: `webkitSpeechRecognition` / suitable fallback; feature-detect and hide mic if unsupported.
- [ ] iOS: Speech framework / permissions; background audio session only while listening.

---

*Designer · Voice input v1 · light add for Ask + Camera*
