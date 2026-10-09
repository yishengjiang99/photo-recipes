# iOS Distribution SDKs + CPI Research

> **DRAFT research brief · Marketing Expert · 2026-09-20**  
> Product: **Grok Camera / Photo Recipes** — iOS-first indie camera app; paid social → App Store; Pro **$7.99/mo**.  
> Prefer 2025–2026 sources; older figures labeled.

---

## 1. Meta SDK optimization mechanism

How the Meta / Facebook SDK for iOS helps optimize App Install and in-app conversion campaigns.

### App Events (client SDK)

- Integrate **Facebook SDK for iOS** (`FBSDKCoreKit` / Meta App Events). Events Manager uses these for targeting, measurement, and optimization ([Meta: Get Started with App Events on iOS](https://developers.facebook.com/docs/app-events/getting-started-app-events-ios/)).
- **Automatic App Event Logging** (unless disabled): **App Install**, **App Launch**, **Purchase** (StoreKit 1 all IAP types; StoreKit 2 non-consumables + subscriptions; consumables need `SKIncludeConsumableInAppPurchaseHistory` in Info.plist).
- **Standard events** (optimize / report): e.g. `Purchase`, `StartTrial` (`FBSDKAppEventNameStartTrial`), `Subscribe` / subscription start, `AddToCart`, `InitiatedCheckout`, plus others in the [App Events Reference](https://developers.facebook.com/docs/app-events/reference/).
- **Custom events**: e.g. tutorial complete, Auto Optimize used — usable for audiences and (when prioritized) for Aggregated Event Measurement / SKAN mapping; Advantage+ app campaigns can optimize to custom events via `custom_event_type = OTHER` + `custom_event_str` ([Advantage+ App Campaigns](https://developers.facebook.com/docs/app-ads/advantage-app-campaigns/)).

### Signals → Advantage+ / campaign optimization

- Ad sets optimize to goals such as `APP_INSTALLS`, `OFFSITE_CONVERSIONS` (in-app events), `APP_INSTALLS_AND_OFFSITE_CONVERSIONS`, or `VALUE` (purchase value / min ROAS) ([Advantage+ App Campaigns docs](https://developers.facebook.com/docs/app-ads/advantage-app-campaigns/)).
- Richer, prioritized conversion signals (install → activation → trial → subscribe) let Meta’s delivery system find users likelier to complete those events — not just cheap installs.
- **Client SDK vs Conversions API (CAPI) for app events:**
  - **SDK**: on-device events; subject to ATT / tracking flags; auto purchase logging; SKAN conversion-value updates can be coordinated via Meta’s schema.
  - **CAPI for app events**: server POST to Graph `/{dataset_id}/events` with `action_source: "app"`, `extinfo` (iOS `i2`), `advertiser_tracking_enabled`, optional hashed `user_data`; same dataset as SDK/MMP ([Conversions API for App Events](https://developers.facebook.com/docs/marketing-api/conversions-api/app-events)).
  - **Dedup**: match `event_id` + `event_name` across SDK and CAPI (within ~48h; near-simultaneous prefers browser/app event).
  - **Post-ATT practice**: keep SDK for install/launch + SKAN CV updates; send reliable **StartTrial / Subscribe / Purchase** from server (e.g. StoreKit / RevenueCat → CAPI) when the app may be backgrounded; avoid double-firing the same conversion without shared `event_id` ([RevenueCat community guidance](https://community.revenuecat.com/third-party-integrations-53/how-to-handle-meta-ads-skan-revenuecat-for-ios-subscriptions-server-to-server-vs-on-device-conflict-7761)).

### SKAdNetwork, AEM, Advanced Matching, App Ads Helper

| Mechanism | Role |
| --- | --- |
| **SKAdNetwork (SKAN)** | Apple’s privacy-preserving attribution; campaign-level postbacks + conversion values. Meta campaigns can set `campaign_attribution` to `SKADNETWORK`. Configure event priority / CV schema in Events Manager so Meta maps installs and post-install events correctly. |
| **Aggregated Event Measurement (AEM)** | Meta protocol to measure app (and web) events from iOS 14.5+ users **without** ATT opt-in; privacy measures (no raw IDs, aggregation, differential privacy). Apps/domains limited to **8 prioritized conversion events**. Set `campaign_attribution` to `AEM` when using this path ([AEM guide](https://developers.facebook.com/docs/app-events/guides/aggregated-event-measurement/); [AEM vs SKAN concepts](https://www.facebook.com/business/help/387440828988900); [SKAN/AEM limitations](https://developers.facebook.com/docs/app-ads/SKAdNetwork-aem-and-limitations/)). AEM is Meta-ecosystem only; SKAN still needed for cross-network Apple attribution. Meta began sending AEM signals to MMPs around **2024-10-09** (industry write-ups, e.g. [Segwise](https://segwise.ai/blog/meta-aem-vs-skan-2025-ios-attribution)). |
| **Advanced Matching** | Send hashed PII (email, phone, etc.) via SDK `setUserData` / Events Manager automatic matching (SDK 5.8+) to improve match rates when IDFA is unavailable ([Advanced Matching](https://developers.facebook.com/docs/app-events/advanced-matching/); [About advanced matching for app](https://www.facebook.com/business/help/2445860982357574)). |
| **App Ads Helper / Test Events** | Events Manager tooling to verify the app is receiving events (select app → Test Event → trigger in app) before spending ([App Events iOS getting started](https://developers.facebook.com/docs/app-events/getting-started-app-events-ios/)). |

### After iOS 14.5 ATT

- **Limited IDFA**: deterministic device-ID matching only when user authorizes tracking via ATT.
- **ATE / ATT status**: For Facebook SDK **14.5–16.x**, set `isAdvertiserTrackingEnabled` from ATT. For **FBSDK 17+ on iOS 17+**, Meta reads `ATTrackingManager.trackingAuthorizationStatus` automatically; do not rely on the deprecated setter ([Advertiser Tracking Enabled](https://developers.facebook.com/docs/app-events/guides/advertising-tracking-enabled/)).
- Without opt-in, Meta leans on **AEM**, **SKAN**, **modeled / probabilistic conversions**, and Advanced Matching — reporting and optimization are noisier than pre-ATT IDFA.
- Industry ATT opt-in often cited ~mid-20s% globally (e.g. Adjust trends ~35% among users who see the prompt as of early 2025 in one Adjust×AppLovin deck; Digital Applied cites ~**27%** global plateau entering **2026** — treat as directional, not Grok Camera–specific).

### Practical event map — iOS camera / subscription app

Fire (and prioritize for AEM/SKAN) roughly in this funnel order:

| Priority | Event | Type | Why |
| --- | --- | --- | --- |
| 1 | Install / ActivateApp | Auto / standard | Volume + learning |
| 2 | Tutorial complete / onboarding done | Custom | Quality install signal |
| 3 | **Auto Optimize used** (first activation) | Custom | Product north-star; ICP filter |
| 4 | Paywall view / InitiateCheckout | Standard or custom | Mid-funnel |
| 5 | **StartTrial** | Standard | Primary early optimize goal for Pro trial |
| 6 | **Subscribe** / **Purchase** | Standard | Paid conversion / value opt |

**Indie tip:** Until you have enough `Subscribe` volume (~50+/week is a common rule of thumb in industry practice — not a Meta SLA), optimize Meta to **StartTrial** or a high-intent custom event (Auto Optimize used), then graduate to Subscribe / VALUE.

---

## 2. Comparison — similar SDKs / stacks

| Stack | Purpose | iOS fit | Meta | TikTok | Google | ASA | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Meta SDK** | First-party app events → Meta ads opt + AEM/SKAN | Native Swift/ObjC | First-party | No | No | No | Required (or MMP→Meta) for Meta App campaigns |
| **Firebase / GA4 + Google Ads App campaigns** | Analytics + Google UAC / App campaigns; on-device conversion measurement | Strong | No | No | First-party | No | Not a cross-network MMP; SKAN schema via Firebase or MMP |
| **TikTok App Events / Business SDK** | Events → TikTok Events Manager; MAI / AEO / VBO | iOS + Android | No | First-party | No | No | SKAN support; don’t dual-update CV with another SDK without coordination ([TikTok App Events SDK](https://ads.tiktok.com/resources/help/article/about-the-tiktok-app-events-sdk?lang=en)) |
| **Apple Search Ads + AdServices** | Attribute ASA installs (campaign/ad group/keyword) | Native `AdServices` / `AAAttribution` | No | No | No | First-party | **No third-party SDK required**; token → `POST https://api-adservices.apple.com/api/v1/` ([Apple AdServices](https://developer.apple.com/documentation/adservices); [Measuring ad performance](https://ads.apple.com/app-store/help/attribution/0028-measuring-ad-performance)) |
| **AppsFlyer / Adjust / Branch / Singular / Kochava (MMPs)** | Cross-network attribution, SKAN hub, fraud, deep links, cost aggregation | All major | Via partner | Via partner | Via partner | Via AdServices + partner | Adds unified reporting vs stacking first-party SDKs; cost/complexity |
| **Snap / Reddit / etc.** | Network-specific app install events | Snap SDK / Pixel-like; Reddit more limited for apps | No | No | No | No | Useful later; Snap has App Install products; Reddit often web/click → store |

**MMPs add vs first-party SDKs:** single SKAN conversion-value owner, deduped multi-network attribution, fraud filters, deep linking / deferred deep links, unified spend + cohort dashboards. **They do not replace** Meta/TikTok signal quality for *that* network’s auction — you still need events flowing to each buyer (via MMP integration or first-party SDK).

---

## 3. Projected CPI ranges (cite; no fake precision)

Benchmarks disagree by methodology (SRN-reported vs MMP, global vs US, blended vs photo). Use **ranges**.

### iOS overall / US & global

| Scope | Range / figure | Period | Source |
| --- | --- | --- | --- |
| iOS CPI global | **$1.50–$3.50** | Published **2025-02-27** (largely 2024–early 2025 framing) | [Business of Apps — CPI Rates (2025)](https://www.businessofapps.com/ads/cpi/research/cost-per-install/) |
| North America CPI | **$2.50–$5.00** | Same BoA 2025 page | Business of Apps |
| AppsFlyer glossary averages | iOS **~$3.60**, Android **~$1.20**; North America **~$5.30** (vs LATAM ~$0.30) | Undated glossary page (treat as **older / evergreen**; not dated 2026) | [AppsFlyer — What is CPI](https://www.appsflyer.com/glossary/cost-per-install/) |
| Adjust×AppLovin trends | North America CPI **$3.09 → $2.90** YoY (2023→2024) | **2025** trends edition (2024 data) | [Adjust × AppLovin Mobile app trends 2025 (PDF)](https://adindex.ru/publication/analitics/search/330815/img/Adjust%20x%20AppLovin-mobile-app-trends-2025.pdf) |
| Cross-category avg iOS CPI | **~$5.84** (Android ~$1.92); claims Q1 2026 | **2026-04-21** secondary aggregator | [Digital Applied — Mobile App Marketing Statistics 2026](https://www.digitalapplied.com/blog/mobile-app-marketing-statistics-2026-install-data) — *aggregates Adjust/AppsFlyer/etc.; verify against primary MMP reports before budgeting* |

**Practical planning band for US iOS consumer apps (indie):** roughly **$3–$8 CPI** depending on creative, bid strategy, and whether you optimize for install vs trial — wider if optimizing Subscribe early.

### Photo / camera / creative apps

| Scope | Range / figure | Period | Source |
| --- | --- | --- | --- |
| Photo & Video **iOS CPI** | **~$3.04** (Android ~$0.98) | Claimed Q1 **2026** | Digital Applied 2026 (aggregator) |
| Photo & Video ASA **indicative CPI (US)** | **$2–$6** | Industry synthesis (undated blog; cites AppTweak/SplitMetrics/etc.) | [Watsspace — ASA CPI by industry](https://watsspace.com/blog/apple-search-ads-cpi-benchmark-by-industry/) |
| Photo & Video ASA **Search Results CPA** | **$1.03** category avg (**2025**); was $1.62 in 2024 | MobileAction **2026** Apple Ads benchmark report | [MobileAction — CPA search results](https://www.mobileaction.co/report/apple-ads-2026-benchmark-report/cpa-search-results-ads/) |

*Note: MobileAction “CPA” here = cost per download from Search Results ads — related to but not identical to all-network CPI.*

### By channel (Meta vs ASA vs TikTok vs Google)

| Channel | Cited CPI / CPA | Caveats | Source |
| --- | --- | --- | --- |
| **Apple Search Ads** | Ballpark avg CPI **~$1.42** (BoA App Marketing Costs); Digital Applied ASA **~$2.96** global; AppTweak-cited US median CPI often **higher** (~$4 in some 2026 agency roundups) | Intent traffic; scale-capped; CPT ≠ CPI | [BoA App Marketing Costs (2025-02-26)](https://www.businessofapps.com/marketplace/app-marketing/research/app-marketing-cost/); Digital Applied 2026; [mbadv agency comparison](https://www.mbadv.agency/apple-ads/apple-ads-vs-other-app-advertising-platforms) |
| **Meta (FB/IG)** | BoA key points: Facebook **~$3.75**, Instagram **~$3.50**; older BoA range FB **$1–$3** headline vs projected **$2–$5.50**; Digital Applied Meta Audience Network iOS CPI **~$3.18** | Creative- and vertical-dependent; iOS > Android | Business of Apps 2025; Digital Applied 2026 |
| **TikTok** | BoA avg **~$2.88**; range projections **~$1.75–$4**; Digital Applied TikTok iOS CPI **~$4.31** | Strong creative/video fit for camera demos | Business of Apps; Digital Applied |
| **Google App / UAC** | BoA **~$2.65** avg; range **~$1.50–$4.50**; Digital Applied Google iOS CPI **~$4.62** | Weaker for **iOS-only** indie (Play-centric inventory) | Business of Apps; Digital Applied |

**Missing / do not invent:** A single authoritative **2026 AppsFlyer Performance Index** Photo & Video × Meta × US table was not retrieved in this pass as a primary PDF. Prefer BoA + MobileAction + your own MMP/network dashboards once live.

---

## 4. Top 2–3 distributors — recommendation for Grok Camera / Photo Recipes

**ICP:** photography enthusiasts; viewfinder / **Auto Optimize** story; iOS App Store; Pro **$7.99/mo**; test budget **$300–few k**.

### Ranked channels

| Rank | Channel | Why for this product |
| --- | --- | --- |
| **1** | **Meta App Install / Advantage+ App campaigns** (FB + IG) | Matches existing creative/copy stack ([ad-copy-v2](./ad-copy-v2.md)); visual before/after + viewfinder demos; can optimize to StartTrial / custom “Auto Optimize used”; largest scalable social inventory for US iOS. Aligns with [budget-300-spend.md](./budget-300-spend.md). |
| **2** | **Apple Search Ads** | Highest-intent “camera / photo / night / manual” keywords; AdServices attribution **without** MMP; often better trial/sub quality than cheap social CPI; Photo & Video ASA CPA historically efficient (MobileAction 2025 Photo & Video **$1.03** Search CPA — category avg, not a guarantee). Start exact/brand + a few category terms. |
| **3** | **TikTok App Install** (test after Meta+ASA signal) | Native video for Auto Optimize demos; competitive CPI in BoA averages; requires TikTok App Events SDK (or MMP) + creative volume. Defer if $300 test — meta+ASA first. |

**Deprioritize at indie stage:** Google UAC (Android-skewed; weaker iOS-only ROI), Snap/Reddit paid (optional creative tests only), ad networks (AppLovin/Unity) aimed at gaming volume.

### MMP yes/no at this stage?

**No MMP required for $300–few k / 1–2 channels.**

- Ship **Meta SDK** (+ optional CAPI for trials/subs) for Meta.
- Use **AdServices** token for ASA.
- Add **TikTok App Events SDK** only when TikTok spend starts.
- Revisit **AppsFlyer / Adjust / Singular** when: (a) ≥2–3 paid networks concurrently, (b) SKAN CV conflicts, (c) need fraud + unified cohorts, or (d) monthly UA ≫ test budgets. Until then MMP cost/complexity usually exceeds value for a solo indie.

---

## 5. Source list

| # | Source | URL | Date / vintage |
| --- | --- | --- | --- |
| 1 | Meta — App Events iOS getting started | https://developers.facebook.com/docs/app-events/getting-started-app-events-ios/ | Live docs (accessed 2026-09-20) |
| 2 | Meta — App Events reference (StartTrial, Subscribe, etc.) | https://developers.facebook.com/docs/app-events/reference/ | Live docs |
| 3 | Meta — Advantage+ App Campaigns | https://developers.facebook.com/docs/app-ads/advantage-app-campaigns/ | Live docs |
| 4 | Meta — Aggregated Event Measurement | https://developers.facebook.com/docs/app-events/guides/aggregated-event-measurement/ | Live docs |
| 5 | Meta — SKAN / AEM limitations | https://developers.facebook.com/docs/app-ads/SKAdNetwork-aem-and-limitations/ | Live docs |
| 6 | Meta Business Help — AEM & SKAN concepts | https://www.facebook.com/business/help/387440828988900 | Live help |
| 7 | Meta — Advertiser Tracking Enabled | https://developers.facebook.com/docs/app-events/guides/advertising-tracking-enabled/ | Live docs (iOS 17+ ATT auto) |
| 8 | Meta — Advanced Matching | https://developers.facebook.com/docs/app-events/advanced-matching/ | Live docs |
| 9 | Meta — Conversions API for App Events | https://developers.facebook.com/docs/marketing-api/conversions-api/app-events | Live docs |
| 10 | Apple — AdServices / AAAttribution | https://developer.apple.com/documentation/adservices | Live docs |
| 11 | Apple Ads — Measuring ad performance | https://ads.apple.com/app-store/help/attribution/0028-measuring-ad-performance | Live help |
| 12 | TikTok — App Events SDK | https://ads.tiktok.com/marketing_api/docs?id=1740859017432066 (alt help: https://ads.tiktok.com/resources/help/article/about-the-tiktok-app-events-sdk?lang=en) | Live |
| 13 | Business of Apps — CPI Rates (2025) | https://www.businessofapps.com/ads/cpi/research/cost-per-install/ | **2025-02-27** |
| 14 | Business of Apps — App Marketing Costs (2025) | https://www.businessofapps.com/marketplace/app-marketing/research/app-marketing-cost/ | **2025-02-26** |
| 15 | MobileAction — Apple Ads 2026 CPA (Search Results) | https://www.mobileaction.co/report/apple-ads-2026-benchmark-report/cpa-search-results-ads/ | **2026** report (2025 yearly data) |
| 16 | Digital Applied — Mobile App Marketing Statistics 2026 | https://www.digitalapplied.com/blog/mobile-app-marketing-statistics-2026-install-data | **2026-04-21** (aggregator) |
| 17 | AppsFlyer — CPI glossary | https://www.appsflyer.com/glossary/cost-per-install/ | Undated / older averages |
| 18 | Adjust × AppLovin — Mobile app trends 2025 PDF | https://adindex.ru/publication/analitics/search/330815/img/Adjust%20x%20AppLovin-mobile-app-trends-2025.pdf | **2025** edition |
| 19 | Watsspace — ASA CPI by industry | https://watsspace.com/blog/apple-search-ads-cpi-benchmark-by-industry/ | Undated synthesis |
| 20 | RevenueCat — iOS attribution guide (SKAN/AEM) | https://www.revenuecat.com/blog/growth/ios-attribution-guide-skan-aem-probabilistic | Industry explainer |
| 21 | FolioKit — ASA AdServices without MMP | https://foliokit.io/blog/apple-search-ads-without-mmp | Practical indie guide |

---

*End of DRAFT brief. Numbers are cited ranges for planning — validate with live campaign data.*
