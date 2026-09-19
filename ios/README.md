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
| **Yearly (primary CTA)** | `com.yishengjiang.photorecipes.pro.yearly` | $59.99/yr | 7-day free |
| Monthly | `com.yishengjiang.photorecipes.pro.monthly` | $7.99/mo | 7-day free |

Subscription group name suggestion: **Photo Recipes Pro**. Put yearly at the higher service level / primary ranking. These IDs are hard-coded in `StoreKitManager.swift` (`IAPProductID`) and `Products.storekit` — keep them identical everywhere.

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
APPLE_IAP_PRODUCT_MONTHLY=com.yishengjiang.photorecipes.pro.monthly
APPLE_IAP_PRODUCT_YEARLY=com.yishengjiang.photorecipes.pro.yearly
APPLE_IAP_ISSUER_ID=        # App Store Connect → Users and Access → Keys → Issuer ID
APPLE_IAP_KEY_ID=           # In-App Purchase key id
APPLE_IAP_PRIVATE_KEY=      # PEM contents of AuthKey_XXX.p8 (or path via your secret manager)
```

**Dev / soft TestFlight:** without Apple API keys and `NODE_ENV !== production`, verify decodes the JWS/JSON payload shape and grants Pro for known product IDs (signature **not** checked). Production refuses unverified grants.

**Next for production:** wire `verifyWithAppleServerAPI` to [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi) Get Transaction Info using the `.p8` key.

## App Store Connect + TestFlight checklist (decisions for you)

1. **Apple Developer Program** membership active.
2. Create App ID `com.yishengjiang.photorecipes` with In-App Purchase capability.
3. Create app record in App Store Connect; attach subscription group **Photo Recipes Pro**.
4. Create the two auto-renewable products with the exact IDs above; add 7-day free trial introductory offers.
5. Paid Apps Agreement + banking/tax complete (subscriptions won’t clear otherwise).
6. Sandbox testers: Users and Access → Sandbox → Testers.
7. Xcode: StoreKit Configuration file for local; or sandbox Apple ID on device.
8. Archive → Upload → TestFlight external/internal. Soft launch: no Stripe Adaptive Sheet for unlock — IAP only.
9. Privacy nutrition labels: photo library (Ask Vision), purchase history.
10. Optional later: Server Notifications V2 URL for subscription lifecycle → same entitlements store.

## Soft TestFlight path

1. Run API with `SESSION_SECRET` + `XAI_API_KEY` (recommend); IAP env optional for sandbox UX.
2. Set Settings → API base URL to your HTTPS API (ATS: localhost allowed via `NSAllowsLocalNetworking`).
3. Use `Products.storekit` in the Run scheme for simulator purchases without ASC products.
4. On device TestFlight: real sandbox IAP once products are Created/Ready to Submit.
5. After purchase, app calls `/api/iap/verify` then refreshes `/api/subscription-status` — checklists + unlimited Ask unlock when `pro: true`.

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
