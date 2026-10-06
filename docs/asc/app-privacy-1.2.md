# App Privacy answers — ProTune AI Camera 1.2 (com.ragnus.mvp, Apple ID 6813991381)

1.2 adds **Meta App Events** (FacebookCore) for install attribution of Meta / X App Install
ads, an **App Tracking Transparency** prompt after onboarding, and SKAdNetwork /
AdAttributionKit postback copies to grepawk.com. AppsFlyer was removed. The App Store
"App Privacy" label must be updated **before 1.2 is submitted**.

The public App Store Connect API has no endpoint for App Privacy, and the `iris` endpoint rejected
our API key when we tried it for Music Reader (and again for this app; see
`asc-prepare-version.yml` → "Probe App Privacy API"). So enter these answers by hand:

**App Store Connect → ProTune AI Camera → App Privacy → Edit (Data Types) → answer each type → Publish.**

Sources of truth: `ios/PhotoRecipes/Resources/PrivacyInfo.xcprivacy` (app code), FacebookCore's
bundled `PrivacyInfo.xcprivacy`, and the privacy policy at
https://photo.grepawk.com/privacy (updated 2026-10-06).

## Step 1 — "Do you or your third-party partners collect data from this app?"

**Yes, we collect data from this app.**

## Step 2 — Data types to tick

| Category | Data type | Who collects it |
|---|---|---|
| User Content | **Photos or Videos** | Our API + xAI (Recommend / Auto Optimize vision frames, per request) |
| User Content | **Audio Data** | Our API + xAI (cloud speech-to-text fallback for scene dictation) |
| User Content | **Other User Content** | Our API + xAI (typed scene notes / Ask text) |
| Identifiers | **Device ID** | Meta (IDFA only if ATT allowed, Meta anon id); our guest / anon id and APNs token |
| Purchases | **Purchase History** | Meta (`StartTrial` / `fb_mobile_purchase`: product, price, currency); our API (StoreKit receipt verification) |
| Usage Data | **Product Interaction** | Meta (install / session `activateApp`); our in-house telemetry |
| Diagnostics | **Other Diagnostic Data** | Our API (`api_error` / `optimize_error` events) |

Leave everything else unticked: Contact Info (the email waitlist is web-only, not in the app),
Health & Fitness, Financial Info, Precise Location, Coarse Location, Sensitive Info, Contacts,
Emails or Text Messages, Gameplay Content, Customer Support, Browsing History, Search History,
User ID, Credit Info, Other Financial Info, Crash Data (no crash SDK), Advertising Data,
Performance Data, Other Usage Data, Other Data Types.

## Step 3 — Per data type answers

Purposes use Apple's labels: *Third-Party Advertising*, *Developer's Advertising or Marketing*,
*Analytics*, *Product Personalization*, *App Functionality*, *Other Purposes*.

| Data type | Purposes | Linked to the user's identity? | Used for tracking? |
|---|---|---|---|
| Photos or Videos | App Functionality | No | No |
| Audio Data | App Functionality | No | No |
| Other User Content | App Functionality | No | No |
| Device ID | Third-Party Advertising; Developer's Advertising or Marketing; Analytics; App Functionality | **Yes** | **Yes** |
| Purchase History | Developer's Advertising or Marketing; Analytics; App Functionality | **Yes** | **Yes** |
| Product Interaction | Developer's Advertising or Marketing; Analytics | **Yes** | **Yes** |
| Other Diagnostic Data | App Functionality; Analytics | No | No |

Notes on the choices:
- **Tracking = Yes** for Device ID / Purchases / Product Interaction that Meta sends: when the user
  allows ATT, Meta can link the IDFA with ad data to measure our campaigns, which is "tracking"
  under Apple's definition. This is also why the app shows the ATT prompt
  (`NSUserTrackingUsageDescription`).
- **Third-Party Advertising** on Device ID matches Meta's measurement purpose in the privacy
  report. We do not show ads in the app; the measurement purpose is also covered by
  *Developer's Advertising or Marketing*.
- **Linked = Yes** for Meta data because it is keyed to device / app-instance identifiers.
- Photos, audio and scene text are sent for a single request and are not stored or tied to an
  identity (unchanged from 1.1).
- `PrivacyInfo.xcprivacy` declares `NSPrivacyTracking=true` with tracking domain
  `ep1.facebook.com` only (ITMS-91064).

## Resulting label (what the product page should show)

- **Data Used to Track You:** Identifiers, Purchases, Usage Data
- **Data Linked to You:** Identifiers, Purchases, Usage Data
- **Data Not Linked to You:** User Content, Diagnostics

## Also check before submitting 1.2

- Privacy Policy URL stays `https://photo.grepawk.com/privacy` (discloses Meta App Events; no AppsFlyer).
- App Review notes: mention the ATT prompt appears after onboarding via Meta
  (`MetaEvents.requestTrackingIfNeeded` on becomeActive).
- SKAdNetwork / AdAttributionKit postback copies still go to grepawk.com (see `Attribution.swift`
  and `server/attribution.ts`).

## Meta App Events (1.2)

The app embeds Meta’s FacebookCore SDK for install/session (`activateApp`) and trial/purchase App
Events. ATT-gated; `ep1.facebook.com` is declared as a tracking domain in `PrivacyInfo.xcprivacy`.
