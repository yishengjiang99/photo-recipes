# Photo Recipes — iOS (SwiftUI)

Native field-technique assistant for iOS 17+.

**Design handoff v1 aligned** — tokens, Library card hierarchy, Field Coach (segmented Describe | From photo), Detail SoftGate, and Paywall match `docs/design-handoff-v1.md` (“Darkroom field notes”). Browse the same five book recipes offline, Ask Grok (text + Photo Vision), and unlock **Photo Recipes Pro** via **StoreKit 2 In-App Purchase only**.

> **Monetization lock:** On iOS, Pro is unlocked **only** through App Store subscriptions. Do **not** offer Stripe web checkout inside the iOS app to unlock digital Pro features (App Review risk). Web Stripe remains for the web app only.

## Open in Xcode

**Option A — checked-in project (preferred)**

```bash
cd ios
open PhotoRecipes.xcodeproj
```

**Option B — regenerate with XcodeGen**

```bash
brew install xcodegen
cd ios
xcodegen generate   # reads project.yml
open PhotoRecipes.xcodeproj
```

- **Bundle ID:** `com.yishengjiang.photorecipes`
- **Deployment:** iOS 17+
- Select the **PhotoRecipes** scheme → run on a simulator or device.
- For StoreKit local testing: Scheme → Edit Scheme → Run → Options → StoreKit Configuration → `PhotoRecipes/Resources/Products.storekit`

Copy `Config/Debug.xcconfig.example` → `Config/Debug.xcconfig` for local overrides (optional; gitignore your private copy).

## Product IDs (create these in App Store Connect)

| Plan | Product ID | Price | Trial |
|------|------------|-------|-------|
| **Yearly (primary CTA)** | `com.ragnus.mvp.pro.yearly` | $59.99/yr | 7-day free |
| Monthly | `com.ragnus.mvp.pro.monthly` | $7.99/mo | 7-day free |

Subscription group name suggestion: **Photo Recipes Pro**. Put yearly at the higher service level / primary ranking. These IDs are hard-coded in `StoreKitManager.swift` (`IAPProductID`) and `Products.storekit` — keep them identical everywhere.


## Camera + Auto Optimize (v1 field camera)

Photo Recipes is a **field camera**: the Camera tab is the home surface. Recipes and Ask/Vision stage settings into a live AVFoundation session — no beauty filters, no fake skies.

### Capabilities

| Capability | Free Peek | Pro |
|---|---|---|
| Live viewfinder + shutter → Camera Roll | ✓ | ✓ |
| Auto mode capture | ✓ | ✓ |
| See recipe dials (read-only / ghost) | ✓ | ✓ |
| **Auto Optimize** (vision → recipe → apply) | **1 / day** | Unlimited |
| Apply recipe → live settable exposure/focus/WB | ✗ | ✓ |
| Manual MODE A/S/M dials | ✗ (Auto only) | ✓ |
| Teach mode (“Why this?”) full copy | Teaser | Full |
| Interactive field checklist while shooting | ✗ | ✓ |

**Auto Optimize quota:** Free Peek gets **1 Auto Optimize/day** (parallel counter in `AutoOptimizeController`; Ask/Vision quota remains separate). Documented choice for v1.

### Agentic MVP loop

1. **Sense** — capture a probe JPEG from the session  
2. **Reason** — `POST /api/recommend` with vision + field prompt  
3. **Act** — map preset dials via `RecipeCameraMapper` → apply **settable** AVFoundation params (custom exposure duration+ISO, EV bias, focus POI/lock, WB lock). Aperture is **guidance overlay only**.  
4. **Verify** — soft status step only (multi-round probe loop is a hook for later, max N=1–2)  
5. **Commit** — user taps shutter; optional Teach sheet explains why  

UI chrome follows `docs/design-handoff-camera-v1.md` + `docs/design-handoff-agentic-v1.md` (Auto Optimize pill above shutter, status pill, before→after chip, manual override dirty/reset, Teach sheet).

### Full-bleed overlay (canonical)

Live preview is **edge-to-edge**; chrome is ZStack overlays only (`design-handoff-camera-v1`). Compact Auto Optimize pill (40–44), status, collapsible scene + mic, shutter — dials/Teach/grid behind `···`. Thin ~96–120pt bottom scrim on top of the feed.

Shared `CameraSession.applyPhoneTargets` (PR #11) applies shutter/ISO/EV/WB/focusMode plus optional **`zoom`** (`videoZoomFactor`) and **`focusPoint` {x,y}** (0–1). `panCue` → chevrons; `teachWhy` / `coachOnly` → Teach sheet.

### phoneTargets capability matrix (apply v2 · wire #21)

All keys optional; unsupported keys are **skipped** (clamp/coach banners). Never pretends aperture was set.

| Key | AVFoundation API | Fallback |
|-----|------------------|----------|
| `shutter` / `exposureDurationSec` + `iso` | `setExposureModeCustom(duration:iso:)` | Guidance + clamp banner |
| `ev` | `setExposureTargetBias` | Skip if unsupported |
| `focusMode` / `focusPoint` | POI + locked / continuous / auto | Guidance |
| `lensPosition` | `setFocusModeLocked(lensPosition:)` | Guidance if unsupported |
| `whiteBalance` string / `{temperature,tint}` / `{redGain,greenGain,blueGain}` | Locked WB gains / temp–tint helper | Guidance |
| `zoom` | `videoZoomFactor` | Clamped to device min/max |
| `cameraDevice` `ultraWide`\|`wide`\|`tele` | DiscoverySession optical switch | Prefer over zoom-only; banner if missing |
| `torch` `{mode,level}` | `setTorchModeOn(level:)` / off / auto | Skip if no torch |
| `flash` | `AVCapturePhotoSettings.flashMode` | Skip if unsupported |
| `lowLightBoost` | `automaticallyEnablesLowLightBoostWhenAvailable` | Skip if unsupported |
| `videoHDR` | `automaticallyAdjustsVideoHDREnabled` / format HDR | Skip if format lacks HDR |
| `frameRate` / `preferFormatHint` | `activeFormat` + min/max frame duration | Soft skip |
| `bracket.stops` | Sequential EV-bias burst (HW bracket when available) | Best-effort; limits in apply notes |
| `monitorSubjectAreaChange` | `isSubjectAreaChangeMonitoringEnabled` + observer → debounced Auto Optimize (~1.5s) | Off when false/absent |
| `maxPhotoDimensions` | `AVCapturePhotoOutput.maxPhotoDimensions` (iOS 16+) | Skip on older OS |
| `previewLUT` | Preview overlay only (`CameraPreviewView`) | **Never** baked into JPEG |
| `creativeLook` `{id,intensity}` | CIFilter capture grade; bake preview **and** still at intensity>0 (default 0.55); Look chip Apply/Dismiss — never silent | Not a beauty filter; suggest via chip |
| `simulatedAperture` | OS-gated if API exists | Else coach / `coachOnly.aperture` |
| `coachOnly.aperture` / `nd` / `tripod` | — | UI guidance only |


### Viewfinder pan / point cues

Quiet edge chevrons (`ViewfinderPanCuesView`) cue reframing from the active recipe + optional agent status:

| Cue | When |
|---|---|
| Left + right | Motion / panning recipes (or status mentioning pan / motion) |
| Down | Composition / get-low recipes (or status mentioning low / kneel) |
| Up | Optional — only from agent status hooks (`look up` / `raise`) |

Hide when no recipe and Auto Optimize is idle; clear with recipe clear. Ink/white @ ~0.7; soft pulse unless Reduce Motion.

### Small-phone layout

Camera chrome is compact-aware (`GeometryReader` + `horizontalSizeClass`): on ~320–375pt widths / short heights (SE, 375×667), Auto Optimize CTA shrinks to 44pt, shutter row uses tighter side frames, and horizontal padding drops so bottom chrome + status fit without overflowing Pro Max–only spacing. Mentally target 375×667 and 390×844.


### Device fallbacks

- Ultra-wide / some formats: custom exposure unavailable → guidance + clamp banner  
- Fixed phone lens: aperture never written to hardware  
- Torch/flash: cycled Off/On/Auto when supported  
- ILC Sony/Canon remote APIs: **out of scope** (later)

### Permissions (`Info.plist`)


## Voice / Grok STT + scene prefill

- **Mic** on Field Coach (Describe / optional photo note) and Camera (scene field above Auto Optimize).
- **Pattern:** tap to talk → tap Stop → audio uploads to `POST /api/stt` (Grok). No live partials in v1; v1.1 may add WSS `interim_results` / `smart_turn` via a server proxy.
- **API key stays on the server** — never embedded in the app.
- **Describe scene:** Camera on appear (and Refresh) calls `POST /api/describe-scene` with a viewfinder probe JPEG. Soft-fails to the placeholder. Chip: `From viewfinder`.
- **Quota:** STT + describe-scene do **not** burn Ask / Auto Optimize quota. Optimize still does.
- **Camera mic:** after STT, always runs the **same** Auto Optimize → `apply` / `applyPhoneTargets` path as the button (uses Optimize quota). Ask mic only fills the text field.
- **Privacy:** voice becomes text for scene matching; we don’t keep audio clips.
- **Permission:** `NSMicrophoneUsageDescription` in Info.plist.

- `NSCameraUsageDescription` — live capture  
- `NSPhotoLibraryAddUsageDescription` — save to Camera Roll  
- `NSPhotoLibraryUsageDescription` — Ask vision picker  
- `NSMotionUsageDescription` — horizon level  

### Architecture (new)

```
Features/Camera/   CameraView, preview, pan cues, dials, agent chips, teach sheet
Services/          CameraSession, RecipeCameraMapper, AutoOptimizeController,
                   CameraRouter, HorizonMonitor, PhotoLibrarySaver
```

### Pro gating (documented choice)

- **Free:** live view, shutter, Auto mode, read-only recipe dials, **1 Auto Optimize/day**, Teach teaser  
- **Pro:** Apply recipe to live session, manual A/S/M dials, unlimited Auto Optimize, full Teach, interactive checklist  


## Architecture

```
ios/
  README.md
  project.yml                          # XcodeGen (optional regenerate)
  Config/Debug.xcconfig.example
  PhotoRecipes.xcodeproj/              # hand-written; opens in Xcode
  PhotoRecipes/
    PhotoRecipesApp.swift              # App + AppModel bootstrap
    MainTabView.swift                  # Library | Field Coach | Settings
    Theme.swift
    Models/                            # Recipe, dials, API DTOs
    Data/BundledPresets.swift          # all 5 presets from src/data/presets.ts
    Services/
      APIClient.swift                  # health, subscription-status, recommend, iap/verify
      EntitlementsStore.swift          # Free Peek / Pro, favorites, checklist
      StoreKitManager.swift            # StoreKit 2 purchase + restore
    Features/
      Library/  Detail/  Ask/  Paywall/  Settings/
    Resources/
      Info.plist  Products.storekit  Assets.xcassets
```

**API base URL** is editable in Settings (UserDefaults). Default placeholder: `https://photo-recipes.example.com`. Point at your deployed origin or `http://localhost:8787` when the API is reachable from the simulator.

`URLSession` uses shared cookie storage (`credentials`-equivalent) so guest/`pr_sub` cookies from `/api/subscription-status` and `/api/iap/verify` persist.

## Features (done)

| Feature | Notes |
|---------|--------|
| Library | Cards, tag filter, favorites (UserDefaults), offline bundled presets |
| Detail | Steps, tips, dials UI, variants, gear checklist (Pro toggles; steps always readable) |
| Field Coach | Segmented Describe / From photo + `PhotosPicker` → `POST /api/recommend` (JPEG base64 vision). Handles **402** paywall + **503** missing key |
| Session | Cookie session; subscription-status on launch; Free Peek / Pro badge |
| Paywall | **Yearly primary**, monthly secondary, 7-day trial badge; StoreKit 2 only |
| Settings | API URL, health check, restore purchases, billing note (Apple subscriptions) |
| Server | `POST /api/iap/verify` + `GET /api/iap/products` (see below) |

## Server: IAP verify

`server/iap.ts` mounts:

- `POST /api/iap/verify` — body `{ signedTransaction, productId, plan }` → upserts Pro entitlement (same cookie path as Stripe) for the guest session
- `GET /api/iap/products` — echoes configured product IDs

### Env vars (never commit secrets)

```bash
# Required in production for real Apple verification:
APPLE_IAP_BUNDLE_ID=com.yishengjiang.photorecipes
APPLE_IAP_PRODUCT_MONTHLY=com.ragnus.mvp.pro.monthly
APPLE_IAP_PRODUCT_YEARLY=com.ragnus.mvp.pro.yearly
APPLE_IAP_ISSUER_ID=        # App Store Connect → Users and Access → Keys → Issuer ID
APPLE_IAP_KEY_ID=           # In-App Purchase key id
APPLE_IAP_PRIVATE_KEY=      # PEM contents of AuthKey_XXX.p8 (or path via your secret manager)
```

**Dev / soft TestFlight:** without Apple API keys and `NODE_ENV !== production`, verify decodes the JWS/JSON payload shape and grants Pro for known product IDs (signature **not** checked). Production refuses unverified grants.

**Next for production:** wire `verifyWithAppleServerAPI` to [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi) Get Transaction Info using the `.p8` key.

## TestFlight soft-launch path

### App Store Connect setup

- [ ] App record exists for bundle ID `com.yishengjiang.photorecipes`.
- [ ] Create the **Photo Recipes Pro** subscription group and these StoreKit 2 products:
  - Yearly: `com.ragnus.mvp.pro.yearly`
  - Monthly: `com.ragnus.mvp.pro.monthly`
- [ ] Add a **7-day free introductory offer** to both products.
- [ ] Set the Xcode signing team and enable In-App Purchase + Push Notifications for the App ID.
- [ ] Add the 1024×1024 App Store icon before uploading the archive.
- [ ] Finish Paid Apps Agreement, banking/tax, and sandbox tester setup.

For local/sandbox StoreKit testing, use `ios/PhotoRecipes/Resources/Products.storekit` in the Xcode Run scheme (Edit Scheme → Run → Options → StoreKit Configuration). Keep its product IDs identical to `StoreKitManager.swift` and App Store Connect. TestFlight uses ASC sandbox products, not the local configuration file.

### Build and API

1. Archive the Release build with the signing team above, upload it, and add an internal TestFlight tester.
2. In the app, set **Settings → API base URL** to the deployed HTTPS API (or a simulator-reachable local URL). Do not ship the placeholder URL.
3. For push Experiment 1, configure the server with `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID=com.yishengjiang.photorecipes`, and `APNS_P8_PATH` (or `APNS_P8_CONTENTS`), then set `PUSH_EXP1_ENABLED=true`. Keep the `.p8` key out of git.

### Push and deep-link path

- Debug/device builds use the `aps-environment` entitlement **sandbox**; TestFlight/App Store Release builds use **production**. Register the matching environment with `POST /api/push/register`.
- Do not ask on install or launch. After the first successful **Auto Optimize** reaches Apply/ready, show the notification permission prompt once; only register the APNs token after permission is granted (or if permission was already granted).
- The notification deep link is `photo-recipes://auto-optimize`; a tap opens Camera and stages Auto Optimize.
- Push is fail-soft when the server flag or `APNS_*` credentials are absent; verify the server flag and APNs credentials before testing delivery.

### Device test plan

- [ ] **Auto Optimize:** capture a probe, run AO, confirm Apply changes the live camera settings, then capture.
- [ ] **Recommend CTA:** test both text and photo paths; confirm the CTA reaches the recommendation result and handles the API base URL.
- [ ] **Look chip:** when a look is suggested, confirm Apply bakes it into preview + still; Dismiss leaves capture neutral.
- [ ] **Push timing:** no prompt on install/launch; first successful AO triggers one prompt; accept/deny is not repeated on later AO runs.
- [ ] **Push deep link:** tap a delivered notification and confirm `photo-recipes://auto-optimize` opens the Camera AO flow.

## Done vs next

**Done in this PR**

- Full SwiftUI app under `ios/` with 5 faithful presets
- API client (health, subscription-status, recommend text+image, iap/verify)
- StoreKit 2 scaffolding + Products.storekit (7-day trial offers)
- Server IAP routes + env documentation
- README monetization decision (IAP-only on iOS)
- Design handoff v1 aligned (Theme tokens, Library, Field Coach, SoftGate, Paywall)

**Next (your Mac / ASC)**

- Open Xcode, set Team signing, drop App Icon 1024²
- Create ASC products + wire production Apple Server API verify
- Point default API URL at production host
- TestFlight build; confirm 402 → paywall → purchase → Pro cookie
- Optional: Shared Secret / ASN V2 webhooks; unify web Stripe Pro with IAP via account linking (out of scope for soft launch)

## Pricing reminder

| Tier | Ask Grok / Vision | Checklists |
|------|-------------------|------------|
| Free Peek | 1 combined / day | Steps readable; toggles locked |
| Pro | Unlimited | Interactive |

Prices: **$7.99/mo** or **$59.99/yr** (yearly primary) + **7-day trial**.
