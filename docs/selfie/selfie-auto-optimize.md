# Selfie-aware Auto Optimize (iOS)

On the **front camera with a real face**, every Auto Optimize run (Optimize button,
voice AO, deep link, first-capture / subject-change re-runs) passes AO's computed
targets through `SelfieAutoPolicy` (`ios/PhotoRecipes/Services/SelfieAutoPolicy.swift`),
which picks one of the five selfie looks and merges that preset's capture light.
iOS-only: the server look/tool contract and AO prompts are unchanged.

## Selection (first match wins)

| # | Signal (`SceneFeatures`) | Look | Reason |
|---|---|---|---|
| 1 | `sceneEV100 < 5.0` · or EV unknown and `meteredISO ≥ 1250` · or `nightOrLights ≥ 0.5` and EV < 7 | selfieLowLight | low light |
| 2 | `subjectDeltaStops ≤ −1.0` (face ≥ 1 stop under frame median) · or ≤ −0.5 with `highlightClipFraction ≥ 0.10` | selfieGlow | backlit |
| 3 | `subjectDeltaStops ≥ +0.8` · or `highlightClipFraction ≥ 0.05` and `percentileSpreadStops ≥ 7` | selfieStudio | harsh light |
| 4 | ≤ 2 faces and face area `< 0.035` of frame | selfiePortrait | small in frame |
| 5 | ≤ 2 faces, outdoor busy group (landscape / architecture / vehicle / plantOrFlower / sky ≥ 0.5), `indoor < 0.5` | selfiePortrait | busy background |
| 6 | otherwise | selfieNatural | even light |

Face gate: `subjectKind == .face`, finite `subjectBox`, face area ≥ 0.008. 3+ faces never get Portrait blur.

## Precedence

- Look: **forced look** (voice / named APPLY-FILTERS) > **user's manual pick this session**
  (drawer grid or intensity drag, filter rail, suggested-chip Apply, Library selfie preset)
  > selfie choice > AO's LookSuggester look / Pass 2 server look. Tracked by
  `CameraSession.activeLookOwner` (`LookOwner.auto / .user / .forced`).
- Targets: AO authoritative for shutter / ISO / WB / focus / zoom; EV = AO's, dropped under
  AO custom exposure, else the preset's face lift; flash + lowLightBoost + face AF/AE from
  the preset; Studio WB hold only when AO set no WB; look intensity = AO's (0.35…0.8) or 0.55.
- No face / back camera → AO output unchanged.

## Feedback

`AppliedFeedback.swift`: ~0.6 s warm edge glow with a single shimmer lap, a face bracket
pop (~0.9 s), a soft haptic and a "✨ Selfie · Soft Glow · low light" pill in the status
slot for 2 s (replaces the status and the dial burst for that run; never stacks). Reduce
Motion: fades only. Never hit-testable; the bracket hides when the drawer is open and
stays clear of the drawer handle / look rail (`SideChromeLayout`). Other AO applies get
the edge glow only.

## Telemetry

`selfie_auto`: `look_id`, `reason`, `forced_override` (1 when a forced/user look kept the
finder), `kept_owner`, `replaced_look` (1 when an AO/server non-selfie look was replaced),
`trigger`, `run_id`. No PII, no face geometry.

## P0 fix (TestFlight build 78): front-camera AO went black

Safety rails (code: `ios/PhotoRecipes/Services/ExposureSafety.swift`):

- **Front camera, low light → no custom shutter/ISO.** `SettingsSolver.applySelfieAdjustments` drops the
  custom write (`FrontExposurePolicy`) when EV100 < 7, the plan is already under auto, or the planned shutter
  is shorter than what auto metered; exposure stays on continuous AE with a non-negative EV face lift.
- **Every custom write is clamped to the live `device.activeFormat`** (`ExposureClamp`), not the published capabilities.
- **Darkening guard** (`ExposureSafetyGuard`): after apply, exposure product / `exposureTargetOffset` / measured
  preview luma vs the pre-AO auto state. > ~1 stop darker than intended or near-black → continuous AE/AF, unlocked,
  status "kept auto exposure". The verify copy reports the measured correction, never `|initialError|`.
- **Session (re)start** resets to continuous AE/AF, zero bias, unlocked (`SessionRestartPolicy`).
- **Selfie decision is final on front**: Pass 2 never applies a server look, flash, focus lock, zoom or exposure on
  the front camera (`LookPrecedence`, `pass2IntentTargets(isFrontCamera:)`).
- **Front flash** only ON for the selfie Low Light look with a Retina Flash (`FrontFlashPolicy`).
- Face gate also accepts a front `.human` close-up ≥ 0.15 of the frame, plus a padded/brightened face-detection
  retry for faces that overflow the frame; metered ISO ≥ 1250 always means Low Light.
