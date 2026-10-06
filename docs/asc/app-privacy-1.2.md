# App Privacy answers — ProTune AI Camera 1.2 (com.ragnus.mvp, Apple ID 6813991381)

1.2 adds the **AppsFlyer** SDK (`AppsFlyerFramework-Static` 7.0.2) for install attribution of X App
Install ads, an **App Tracking Transparency** prompt after onboarding, and SKAdNetwork /
AdAttributionKit postback copies to grepawk.com. The App Store "App Privacy" label must be updated
**before 1.2 is submitted**.

The public App Store Connect API has no endpoint for App Privacy, and the `iris` endpoint rejected
our API key when we tried it for Music Reader (and again for this app; see
`asc-prepare-version.yml` → "Probe App Privacy API"). So enter these answers by hand:

**App Store Connect → ProTune AI Camera → App Privacy → Edit (Data Types) → answer each type → Publish.**

Sources of truth: `ios/PhotoRecipes/Resources/PrivacyInfo.xcprivacy` (app code), AppsFlyer's bundled
`PrivacyInfo.xcprivacy`, AppsFlyer's nutrition-label guide
(https://support.appsflyer.com/hc/en-us/articles/207032086), and the privacy policy at
https://photo.grepawk.com/privacy (updated 2026-10-05).

## Step 1 — "Do you or your third-party partners collect data from this app?"

**Yes, we collect data from this app.**

## Step 2 — Data types to tick

| Category | Data type | Who collects it |
|---|---|---|
| Location | **Coarse Location** | AppsFlyer (country / region derived from IP) |
| User Content | **Photos or Videos** | Our API + xAI (Recommend / Auto Optimize vision frames, per request) |
| User Content | **Audio Data** | Our API + xAI (cloud speech-to-text fallback for scene dictation) |
| User Content | **Other User Content** | Our API + xAI (typed scene notes / Ask text) |
| Identifiers | **Device ID** | AppsFlyer (IDFA only if ATT allowed, IDFV, AppsFlyer ID); our guest / anon id and APNs token |
| Purchases | **Purchase History** | AppsFlyer (`af_start_trial`, `af_subscribe`: product, price, currency); our API (StoreKit receipt verification) |
| Usage Data | **Product Interaction** | AppsFlyer (install, launches, `first_auto_optimize`); our in-house telemetry |
| Usage Data | **Advertising Data** | AppsFlyer / X (which ad, campaign and network led to the install) |
| Diagnostics | **Performance Data** | AppsFlyer (launch timing used for fraud detection) |
| Diagnostics | **Other Diagnostic Data** | Our API (`api_error` / `optimize_error` events) |
| Other Data | **Other Data Types** | AppsFlyer (device model, OS version, language, time zone, IP address, user agent) |

Leave everything else unticked: Contact Info (the email waitlist is web-only, not in the app),
Health & Fitness, Financial Info, Precise Location, Sensitive Info, Contacts, Emails or Text Messages,
Gameplay Content, Customer Support, Browsing History, Search History, User ID, Credit Info,
Other Financial Info, Crash Data (no crash SDK), Other Usage Data.

## Step 3 — Per data type answers

Purposes use Apple's labels: *Third-Party Advertising*, *Developer's Advertising or Marketing*,
*Analytics*, *Product Personalization*, *App Functionality*, *Other Purposes*.

| Data type | Purposes | Linked to the user's identity? | Used for tracking? |
|---|---|---|---|
| Coarse Location | Developer's Advertising or Marketing; Analytics | **Yes** | **Yes** |
| Photos or Videos | App Functionality | No | No |
| Audio Data | App Functionality | No | No |
| Other User Content | App Functionality | No | No |
| Device ID | Third-Party Advertising; Developer's Advertising or Marketing; Analytics; App Functionality | **Yes** | **Yes** |
| Purchase History | Developer's Advertising or Marketing; Analytics; App Functionality | **Yes** | **Yes** |
| Product Interaction | Developer's Advertising or Marketing; Analytics | **Yes** | **Yes** |
| Advertising Data | Developer's Advertising or Marketing; Analytics | **Yes** | **Yes** |
| Performance Data | App Functionality | **Yes** | No |
| Other Diagnostic Data | App Functionality; Analytics | No | No |
| Other Data Types | Developer's Advertising or Marketing; Analytics; App Functionality | **Yes** | **Yes** |

Notes on the choices:
- **Tracking = Yes** for everything AppsFlyer sends: when the user allows ATT, AppsFlyer links the
  IDFA with X's ad data to measure our campaigns, which is "tracking" under Apple's definition. This
  is also why the app shows the ATT prompt (`NSUserTrackingUsageDescription`).
- **Third-Party Advertising** on Device ID matches the purpose AppsFlyer declares in its own
  privacy manifest, so the label agrees with Xcode's generated privacy report. We do not show ads in
  the app; the measurement purpose is covered by *Developer's Advertising or Marketing*.
- **Linked = Yes** for AppsFlyer data because it is keyed to device identifiers.
- Photos, audio and scene text are sent for a single request and are not stored or tied to an
  identity (unchanged from 1.1).

## Resulting label (what the product page should show)

- **Data Used to Track You:** Location, Identifiers, Purchases, Usage Data, Other Data
- **Data Linked to You:** Location, Identifiers, Purchases, Usage Data, Diagnostics, Other Data
- **Data Not Linked to You:** User Content, Diagnostics

## Also check before submitting 1.2

- Privacy Policy URL stays `https://photo.grepawk.com/privacy` (now discloses AppsFlyer).
- App Review notes: mention the ATT prompt appears ~1 s after onboarding (or ~3 s after launch for
  users who onboarded on 1.1) and only in builds with an AppsFlyer dev key.
- AppsFlyer dashboard: add app `id6813991381`, enable the X Ads integration (MACT / SKAN
  interoperation), and set the SKAN conversion-value mode.
