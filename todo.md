# TODO — ProTune AI Camera
_Last updated: 2026-10-09 9:40 AM PT by Chief of Staff_

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
- [x] Submit workflow fix: drop stale /tmp/submit_app_store.py invocation — `56e838a` — 2026-10-08
- [x] Admin panel counts IAP as estimated MRR alongside Stripe — `bf28e01` — 2026-10-08
- [x] v1.3 listing: whatsnew/description + camera chrome screenshots — `dff9c14`, `6eaecfb` — 2026-10-08
- [x] Camera chrome revamp, tap-to-focus fix, selfie mode, named looks on-device, Low Angle library-only — `c86c6c7`, `f335f69`, `d5fd10f`, `7435230`, `fee4930` — 2026-10-08
- [x] Auto Optimize review fixes A–D + overexposure loop steps 1–6 — merges `7903c64`, `56b5aa6`, `d629ab6`, `7a25c90`, `b55ba82` — 2026-10-07
- [x] v1.2 resubmitted with build 53 (ITMS-91064 fixed: `NSPrivacyTracking` true with tracking domains) — WAITING_FOR_REVIEW, submit run 37546069519 — 2026-10-06
- [x] Remove AppsFlyer entirely (SDK, secret gates, privacy disclosure); keep Meta + SKAN — `7ce3c4c`, TestFlight build 54 — 2026-10-06
- [x] Funnel fix proposal: guided first win, success-based welcome quota, earned D1 reminder — `c400166`, `62e670e`, build 53 — 2026-10-06
- [x] Push: ship devices/push_tokens DDL in bundle, keep server data across deploys, cron tick — `a3efa0f` — 2026-10-06
- [x] Telemetry fix pass: come-shoot/D1 push, soft/hard paywall, auto-apply looks with undo, local-first Auto Optimize — `6462a8b`, `f7376ce`, build 52 — 2026-10-06
