# TODO — ProTune AI Camera
_Last updated: 2026-10-06 9:30 AM PT by Chief of Staff_

iOS-first; tip `673bc87`. App display name / ASC name is **ProTune AI Camera** (`com.ragnus.mvp`). **v1.1 (build 46) is live** (READY_FOR_SALE). **v1.2 build 48 was rejected twice as INVALID_BINARY** (ITMS-91064, privacy manifest). The `agent/meta-sdk` merge `b5a7fcf` also dropped the 1.2 attribution work from `main` (see Blocked). Open draft PRs #141 and #138 unchanged.

## Now (in progress)
- [ ] Fix ITMS-91064 on 1.2: Apple says "NSPrivacyTracking must be true if NSPrivacyTrackingDomains isn't empty" in `PrivacyInfo.xcprivacy`; build 48 (`c0dbdd9`) rejected on both submits (2026-10-06 ~1:14 AM and ~5:15 AM PT; submission `eb3630a6` UNRESOLVED_ISSUES). Needs a new build 49+ — iOS
- [ ] Viewfinder-first Auto Optimize — iOS
- [ ] Agentic camera levers (capability-gated; skip unsupported levers without failing apply) — iOS + Backend
- [ ] Creative looks — iOS + Design

## Next
- [ ] ASC "assign Internal Testing" failed with FORBIDDEN_ERROR for build 48 (run 37403187454) — iOS
- [ ] Triage draft PR #141 (agentic flow review: P0 `confidence`, fallback ladder, `verificationSummary`) — Chief of Staff
- [ ] Review PR #138 (iOS distribution SDKs + CPI research) — Chief of Staff

## Blocked / waiting on user
- [ ] Resubmit 1.2 via the submit workflow once a fixed build is VALID — User

## Done (recent)
- [x] Remove AppsFlyer entirely (SDK, secret gates, privacy disclosure); keep Meta + SKAN — 2026-10-06
- [x] Ads: ProTune 9:16 slider promo + selfie Reels v13–v16 (v16 Midwestern VO, -14 LUFS) in `docs/ads/` — `b11998a`, `0f90c77`, `41c20d6`, `cf39b2d`, `ecbb454` — 2026-10-05
- [x] Meta App Events SDK (FB App ID 1895534071416482; FB SDK 18.x) merged to main; iOS unit tests green — `7f217d9`…`f293263`, merge `b5a7fcf` — 2026-10-05
- [x] Submit workflow: full-history fetch for submit script extraction — `673bc87` — 2026-10-06
- [x] TestFlight build 48 (1.2; SKAN 4, AppsFlyer off pending key, ATT) uploaded VALID — run 37401786947 `c0dbdd9` — 2026-10-05
- [x] ASC 1.2 version prepared (What's New, App Privacy answers) — run 37400694607 `c0dbdd9` — 2026-10-05
- [x] Scene probe: silent viewfinder frame grab + 30 s fire-once throttle; "Get Down Low" renamed "Low Angle"; CVPixelBuffer ARC fixes — `5a4de20`, `8bf0df5`, `93e2b72` — 2026-10-05
- [x] Admin: "Last 8 hours" telemetry section + All/iOS/Web platform filter (deployed to photo.grepawk.com) — `d76c8cd`, `dd5b236` — 2026-10-05
- [x] v1.1 build 46 approved, READY_FOR_SALE (submission `fd14c9ca` COMPLETE) — ASC status run 37347060871 — 2026-10-05
- [x] v1.1 build 46 resubmitted WAITING_FOR_REVIEW (after build 45 rejected for 3.1.2(c)) — submit run 37265127324 `4b57ba6` — 2026-10-04
- [x] Paywall + listing: Terms of Use (EULA) and Privacy Policy links for Guideline 3.1.2(c) — `d8f639f`, `4b57ba6` — 2026-10-04
