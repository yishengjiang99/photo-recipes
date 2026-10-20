# ProTune release telemetry loop — state

last_analyzed_version: 1.6
analyzed_date: 2026-10-19
live_since: 2026-10-19 ~10:38 AM PDT (READY_FOR_SALE, build 84, per app-review-watch state.json)

## v1.6 first-day analysis (run 2026-10-19 ~17:31 PDT, release day so far, PT windows)
- Event flow today (events/sessions): app_open 25/21, camera_open 19/15, auto_optimize_start 4/3, auto_optimize_success 8/6. No stage vanished; auto_optimize_start is back in the wild — all 4 start events today are v1.6 (v1.5 emitted 0 starts, 4 successes). v1.6 today: app_open 7, camera_open 8, start 4, success 4 events.
- Storage integrity: PASS. Today's success props_json key counts: v1.6 = 39 keys, v1.5 = 36 keys — both well above the old 24-key cap (fix 8fc0dc4c holding; no truncation).
- Funnel (distinct session_id): release day so far 22 → 15 camera → 3 start → 6 success; revenue: paywall_view 9 sessions, trial_start 0, purchase_success 1 (v1.5, yearly/storekit, 04:54 PT; all-time purchase_success now 5 rows). Trailing 7 complete days (Oct 12–18 PT): 272 → 134 → 3 → 68; revenue 73 paywall / 0 trial / 2 purchase — reproduces the weekly re-check exactly.
- Latency (v1.6 successes today, n=4): values 398/403/411/589 ms → median 407 ms, p95 ≈ 589 ms, vs running baseline median 1,056 ms / p95 11,716 ms. Directional only (n=4). The day's slow tail (2,732 ms and 28,473 ms) was on v1.5 events.
- Interpretation: partial first day, small denominators — v1.6 volume is still ramping as users update; nothing here indicates breakage.
