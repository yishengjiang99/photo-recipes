# TODO — ProTune AI Camera
_Last updated: 2026-10-05 5:20 PM PT by Chief of Staff_

iOS-first; tip `93e2b72`. App display name / ASC name is **ProTune AI Camera** (`com.ragnus.mvp`). **v1.1 (build 46) is approved and READY_FOR_SALE** (submission `fd14c9ca` COMPLETE; live by the 2026-10-05 ~10:15 AM PT status check). The 1.1 train is now closed, so the next TestFlight upload needs a version bump. Open draft PRs #141 and #138 unchanged.

## Now (in progress)
- [ ] Bump marketing version past 1.1 (e.g. 1.2) before the next TestFlight upload: TF run 37390634954 from `93e2b72` failed with "train version '1.1' is closed" / CFBundleShortVersionString must be higher than approved 1.1 — iOS
- [ ] Viewfinder-first Auto Optimize — iOS
- [ ] Agentic camera levers (capability-gated; skip unsupported levers without failing apply) — iOS + Backend
- [ ] Creative looks — iOS + Design

## Next
- [ ] Triage draft PR #141 (agentic flow review: P0 `confidence`, fallback ladder, `verificationSummary`) — Chief of Staff
- [ ] Review PR #138 (iOS distribution SDKs + CPI research) — Chief of Staff

## Blocked / waiting on user
- (none)

## Done (recent)
- [x] Scene probe: silent viewfinder frame grab + 30 s fire-once throttle; "Get Down Low" renamed "Low Angle"; CVPixelBuffer ARC fixes (unit tests green at tip) — `5a4de20`, `8bf0df5`, `93e2b72` — 2026-10-05
- [x] Admin: "Last 8 hours" telemetry section + All/iOS/Web platform filter (deployed to photo.grepawk.com) — `d76c8cd`, `dd5b236` — 2026-10-05
- [x] v1.1 build 46 approved, READY_FOR_SALE (submission `fd14c9ca` COMPLETE) — ASC status run 37347060871 — 2026-10-05
- [x] v1.1 build 46 resubmitted WAITING_FOR_REVIEW (after build 45 rejected for 3.1.2(c)) — submit run 37265127324 `4b57ba6` — 2026-10-04
- [x] TestFlight build 46 (1.1; paywall legal links) VALID — run 37264015155 `0060ab3` — 2026-10-04
- [x] Paywall + listing: Terms of Use (EULA) and Privacy Policy links for Guideline 3.1.2(c) — `d8f639f`, `4b57ba6` — 2026-10-04
- [x] Landing: official App Store badge linking to product page (replaces dead #testflight button) — `0060ab3` — 2026-10-04
- [x] v1.1 build 45 submitted WAITING_FOR_REVIEW (ProTune listing + whatsNew; build VALID) — submit run 36773184671 `dc05f6a` — 2026-09-30
- [x] TestFlight build 45 (1.1; Info.plist MARKETING/CURRENT version plumbing) — run 36766758877 `7e24e8b` — 2026-09-30
- [x] Rebrand end-to-end to ProTune AI Camera (web, iOS strings, legal, listing) — `f2b7e71`, `520e42b` — 2026-09-30
