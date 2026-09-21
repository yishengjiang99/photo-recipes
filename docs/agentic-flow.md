# Agentic Auto Optimize — flow charts

How Photo Recipes runs **Sense → Reason → Act → Verify** for from-viewfinder Auto Optimize.
**Verify** is a mental check before `select_preset` (not a fourth tool).  
Voice/STT is an **alternate input** into the same apply path — never the product lead.

Canonical schema/prompt: [`agentic-prompt-v2.md`](./agentic-prompt-v2.md) · iOS apply: [`CameraSession.applyPhoneTargets`](../ios/PhotoRecipes/Services/CameraSession.swift).

---

## 1. Product path (what the photographer sees)

```mermaid
flowchart LR
  A[Point phone at the shot] --> B[Auto Optimize]
  B --> C[Sense scene]
  C --> D[Match catalog recipe]
  D --> E[Apply phoneTargets]
  E --> F[Ready to capture]
  F --> G[Shutter]

  V[Voice / STT — secondary] -.-> D
```

Status copy examples: `Reading light…` → `Matching recipe…` → `Applying…` → `Ready to capture`.

---

## 2. End-to-end system

```mermaid
flowchart TB
  subgraph Client["iOS Camera"]
    VF[Viewfinder + optional scene note]
    AO[Auto Optimize CTA]
    APPLY[applyPhoneTargets]
    UI[Dials / panCue / Teach / creativeLook]
  end

  subgraph Server["POST /api/recommend"]
    Q[Quota / entitlements]
    LOOP[Grok tool loop]
  end

  subgraph XAI["xAI Grok"]
    M[Vision or text model]
  end

  VF --> AO
  AO -->|image + note| Q
  Q --> LOOP
  LOOP <-->|tools| M
  LOOP -->|preset + phoneTargets + coachOnly + teachWhy| APPLY
  APPLY --> UI
```

Clients: **iOS** Auto Optimize / Ask · **web** Ask & Photo Vision. Same API; only iOS runs `applyPhoneTargets` on AVCapture.

### Pass 1 vs Pass 2

| Pass | Where | What |
|------|-------|------|
| **1** | On-device | Instant local sense / recipe pick (no Grok) |
| **2** | Cloud | This tool loop via `/api/recommend` (quota-gated) |

---

## 3. Server tool loop (bounded)

```mermaid
sequenceDiagram
  participant App as iOS Auto Optimize / Ask · web Ask
  participant API as recommend.ts
  participant Grok as Grok
  participant Tools as Tool executor

  App->>API: message + optional imageDataUrl
  API->>Grok: system + user (vision detail low)
  Note over API,Grok: Round 0 tool_choice forces list_presets
  Grok->>Tools: list_presets (slim catalog)
  Tools-->>Grok: id / title / tags / blurb / keySettings
  opt Close call
    Grok->>Tools: get_preset_details(presetId)
    Tools-->>Grok: full dials / steps / tips
  end
  Grok->>Tools: select_preset(...)
  Tools-->>API: selection payload
  API-->>App: presetId, phoneTargets, coachOnly, panCue, teachWhy, creativeLook?
```

**Bounds:** `MAX_ROUNDS = 4`. Finish with `select_preset` promptly — do not re-list.

**Verify:** before calling `select_preset`, the model mentally checks targets vs scene — there is **no** `verify_*` tool.

### Failure / bound paths

```mermaid
flowchart TB
  REQ[POST /api/recommend] --> Q{Quota OK?}
  Q -->|no| E402[402 Free Peek / Pro required]
  Q -->|yes| LOOP[Grok tool loop]
  LOOP --> SEL{select_preset in time?}
  SEL -->|yes| OK[200 + phoneTargets]
  SEL -->|MAX_ROUNDS exceeded| E502a[502 did not call select_preset]
  LOOP --> XAI{xAI OK?}
  XAI -->|error| E502b[502 / upstream status]
```

| Outcome | Typical cause |
|---------|----------------|
| `402` | Free Peek daily limit |
| `502` — no `select_preset` | Model never finalized within `MAX_ROUNDS` |
| `502` / `4xx` from xAI | Model/key/vision availability |

---

## 4. Act: what gets applied vs coach-only

```mermaid
flowchart TB
  SEL[select_preset result] --> PT[phoneTargets]
  SEL --> CO[coachOnly]
  SEL --> PC[panCue]
  SEL --> TW[teachWhy / senseSummary]
  SEL --> CL[creativeLook — optional P1]

  PT --> AV[AVFoundation writes]
  AV --> S[shutter / exposureDurationSec + iso]
  AV --> E[ev / whiteBalance]
  AV --> F[focusMode / focusPoint / lensPosition]
  AV --> Z[zoom / cameraDevice]
  AV --> T[torch / flash / lowLightBoost / videoHDR]
  AV --> B[bracket burst / frameRate]
  AV --> M[monitorSubjectAreaChange → re-optimize]

  CO --> UI1[Teach / UI only — never apply]
  CO --> A[aperture / ND / tripod / notes]

  PC --> UI2[Pan chevrons — UI only]
  TW --> UI3[Teach sheet]
  CL --> CF[CIFilter bake preview + still]
```

**Never applied as device writes:** mechanical aperture, ND, tripod, `previewLUT` (preview-only), `simulatedAperture` (coach unless future OS API).

---

## 5. Primary vs secondary input

```mermaid
flowchart LR
  subgraph Primary
    P1[Viewfinder image] --> P2[Optional scene note]
    P2 --> P3[Auto Optimize]
  end

  subgraph Secondary
    S1[Mic / STT transcript] --> S2[Same /api/recommend]
  end

  P3 --> R[recommend tool loop]
  S2 --> R
  R --> A[Same applyPhoneTargets helper]
```

Spoken intents still map into `phoneTargets` (e.g. “slower shutter for panning”, “warm film look” → `creativeLook`).

---

## 6. Latency knobs (server)

```mermaid
flowchart LR
  A[Vision request] --> B[detail: low]
  A --> C[Force list_presets round 0]
  A --> D[Slim list_presets payload]
  A --> E[MAX_ROUNDS 4]
  B --> F[Fewer tokens]
  C --> G[Fewer wasted rounds]
  D --> F
  E --> H[Bound wall-clock]
```

Rough wall times after these knobs: **text ~5–10s** · **vision ~20–40s** (not sub-second). Client timeouts: **60s** request / **120s** resource.

---

## Related

- [`agentic-prompt-v2.md`](./agentic-prompt-v2.md) — prompts, schemas, failure modes  
- [`design-handoff-agentic-v1.md`](./design-handoff-agentic-v1.md) — UI / status chrome  
- [`agents/agentic-expert.md`](./agents/agentic-expert.md) — ownership
