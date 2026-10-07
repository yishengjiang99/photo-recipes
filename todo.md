# TODO — ProTune AI Camera
_Last updated: 2026-10-06 5:15 PM PT by Chief of Staff_

iOS-first; tip `7ce3c4c`. App display name / ASC name is **ProTune AI Camera** (`com.ragnus.mvp`). **v1.1 (build 46) is live** (READY_FOR_SALE). **v1.2 build 53 (`62e670e`) is WAITING_FOR_REVIEW** (submission `d30b5a05`, submitted 2026-10-06 4:21 PM PT). Build 54 (`7ce3c4c`, AppsFlyer removed) is in TestFlight only. Open draft PRs #141 and #138 unchanged.

## Now (in progress)
- [ ] Viewfinder-first Auto Optimize — iOS
- [ ] Agentic camera levers (capability-gated; skip unsupported levers without failing apply) — iOS + Backend
- [ ] Creative looks — iOS + Design

## Next
- [ ] Verify the push pipeline end to end on prod (devices/push_tokens tables, cron tick, come-shoot/D1 sends) now that `a3efa0f` is deployed — Backend
- [ ] 1.2 in review is build 53, which predates the AppsFlyer removal in build 54 (SDK still bundled, no key); confirm the ASC App Privacy answers match whichever build ships — iOS
- [ ] ASC "assign Internal Testing" still fails with FORBIDDEN_ERROR (`betaGroups` GET_RELATIONSHIP not allowed; run 37547402949), though build 54 shows internal state IN_BETA_TESTING; "invite beta tester" returns 409 STATE_ERROR (run 37546733873) — iOS
- [ ] Triage draft PR #141 (agentic flow review: P0 `confidence`, fallback ladder, `verificationSummary`) — Chief of Staff
- [ ] Review PR #138 (iOS distribution SDKs + CPI research) — Chief of Staff

## Blocked / waiting on user
- [ ] 1.2 (build 53) waiting on App Review; release when approved — User

## Done (recent)
- [x] v1.2 resubmitted with build 53 (ITMS-91064 fixed: `NSPrivacyTracking` true with tracking domains) — WAITING_FOR_REVIEW, submit run 37546069519 — 2026-10-06
- [x] Remove AppsFlyer entirely (SDK, secret gates, privacy disclosure); keep Meta + SKAN — `7ce3c4c`, TestFlight build 54 — 2026-10-06
- [x] Funnel fix proposal: guided first win, success-based welcome quota, earned D1 reminder — `c400166`, `62e670e`, build 53 — 2026-10-06
- [x] Push: ship devices/push_tokens DDL in bundle, keep server data across deploys, cron tick — `a3efa0f` — 2026-10-06
- [x] Telemetry fix pass: come-shoot/D1 push, soft/hard paywall, auto-apply looks with undo, local-first Auto Optimize — `6462a8b`, `f7376ce`, build 52 — 2026-10-06
- [x] Telemetry: event allowlist removed, server accepts all events — `cacc1dc` — 2026-10-06
- [x] iOS build fixes: Facebook SPM archive provisioning scope, AppIcon compile, PrivacyInfo for ITMS-91064 — `1d9e92a`, `77f2b2e`, `f17d3b6` — 2026-10-06
- [x] Ads: ProTune 9:16 slider promo + selfie Reels v13–v16 (v16 Midwestern VO, -14 LUFS) in `docs/ads/` — `b11998a`, `0f90c77`, `41c20d6`, `cf39b2d`, `ecbb454` — 2026-10-05
- [x] Meta App Events SDK (FB App ID 1895534071416482; FB SDK 18.x) merged to main; iOS unit tests green — `7f217d9`…`f293263`, merge `b5a7fcf` — 2026-10-05
- [x] v1.1 build 46 approved, READY_FOR_SALE (submission `fd14c9ca` COMPLETE) — ASC status run 37347060871 — 2026-10-05
