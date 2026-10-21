# ProTune funnel re-check — history

## Stated baseline (user's own analysis, 2026-09-19 → 2026-10-06)
68 sessions → 45 camera opens → 33 optimize starts → 31 successes.
Conversions: sessions→camera 66.2%, camera→optimize-start 73.3%, start→success 93.9%.

## Method validation — FIRST RUN 2026-10-18 (proof run)
Telemetry read successfully: `ssh grepawk` (via egress-proxy ProxyCommand, key ~/.ssh/grepawk) → MySQL `telemetry_events` on photo.grepawk.com (db photo_recipes), SELECT only. Server timestamps are UTC; /etc/photo-recipes.env is not bash-sourceable (unquoted RESEND_FROM) — MYSQL_* lines were extracted separately; no credentials printed/stored.

The stated baseline could NOT be reproduced from the current table with any standard variant tried:
- distinct session_id, all platforms, UTC window: 211 / 89 / 53 / 51 (42.2% / 59.6% / 96.2%)
- distinct session_id, all platforms, PT window: 237 / 95 / 56 / 54 (40.1% / 58.9% / 96.4%)
- distinct session_id, iOS only, UTC: 102 / 74 / 45 / 43 (72.5% / 60.8% / 95.6%)
- distinct session_id, iOS only, PT: 121 / 80 / 48 / 46
- distinct anon_id, all platforms, UTC: 114 / 48 / 26 / 24 (42.1% / 54.2% / 92.3%)
- distinct anon_id, iOS only, UTC: 71 / 41 / 22 / 20
- raw event counts, UTC: — / 156 / 136 / 123
Also tried (none reproduce 68/45/33/31): snapshot timing at hourly cutoffs on Oct 6–7, received_at cutoff (no late rows), sessions with ≥2/≥3 events, "meaningful-event" sessions, excluding the 4 heaviest anon_ids (111 / 45 / 23 / 21), sliding 7-day windows, app_version slices (app_version is only populated on non-funnel events, so it cannot stage the funnel).
Conclusion: the user's 68/45/33/31 likely came from a cut that is not recoverable from the table as it stands today. OPERATIONAL BASELINE going forward = the task's primary definition applied to the baseline window, so all comparisons are like-for-like:
- Definition: distinct session_id per stage, all platforms, PT calendar windows, stages = any event / camera_open / auto_optimize_start / auto_optimize_success.
- Operational baseline (PT window 2026-09-19 → 2026-10-06): 237 / 95 / 56 / 54 → 40.1% / 58.9% / 96.4%.

## Run 2026-10-18 (proof run) — window 2026-10-11 → 2026-10-17 PT (trailing 7 complete days)
Primary definition: 257 sessions → 130 camera opens → 4 optimize starts → 68 successes.
Conversions: sessions→camera 50.6%, camera→optimize-start 3.1%, start→success n/a (68 successes vs 4 starts — impossible as a real funnel).
iOS only: 215 / 129 / 3 / 67. anon_id all platforms: 196 / 91 / 4 / 59.
Daily distinct sessions (PT): Oct 11: 15, 12: 15, 13: 70, 14: 27, 15: 28, 16: 17, 17: 85.

### Finding: instrumentation break, NOT a real conversion collapse
- `auto_optimize_start` events fell off a cliff from 2026-10-09 PT (Oct 8: 57 starts / 104 successes; Oct 9: 5/28; Oct 10: 1/45; Oct 12–16: 0 starts every day) while `auto_optimize_success` kept firing.
- In the current week, start events appear only from app_version 1.2 (and NULL-version rows); v1.3/v1.4/v1.5 emit ZERO starts but plenty of successes (42/29/16 success events by version). New events appeared instead: `ao_tap` (48 distinct sessions this week), `auto_optimize_verify`, `optimize_photo_captured`, `optimize_capture_abandoned` — the Auto Optimize flow was re-instrumented alongside the v1.3–v1.5 chrome/AO work.
- Real optimize completion did NOT collapse: camera→success = 68/130 = 52.3% this week vs 54/95 = 56.8% operational baseline; sessions→success 26.5% vs 22.8%.
- sessions→camera moved +10.5pp vs operational baseline (50.6% vs 40.1%) and −15.6pp vs stated baseline (66.2%) — under the 20pp reporting threshold either way. No genuine stage qualifies.

### Reported to user (last reported figures)
2026-10-18: reported the stop-condition finding — the optimize-start stage is no longer like-for-like (start event dropped in v1.3+, replaced by ao_tap/auto-run instrumentation) and the baseline needs resetting before the start/success stages can be compared again; also reported that the stated 68/45/33/31 baseline could not be reproduced from today's table (operational same-definition baseline 237/95/56/54 recorded above). Do NOT re-announce this same instrumentation break / baseline mismatch on later runs unless the definition changes again or a NEW stage movement appears under a reset baseline.
Last reported stage figures: sessions→camera 50.6% (130/257, week Oct 11–17 PT).

## Revenue funnel — FIRST READING 2026-10-18 (window 2026-10-11 → 2026-10-17 PT, same trailing-7-complete-days definition)
Method cross-check: primary funnel reproduced the proof run exactly (257 / 130 / 4 / 68), so the window handling is validated.
Revenue stages (distinct session_id per stage, all platforms, independent stage counts as in the primary definition):
- auto_optimize_success: 68 sessions (67 iOS + 1 web; 144 events)
- paywall_view: 69 sessions (67 iOS + 2 web; 91 events) — exceeds successes because paywall also opens via quota/settings/push/upgrade triggers (paywall_trigger: 92 sessions; paywall_view props had_success=1 for 59 sessions, =0 for 9, NULL for 4)
- trial_start: 0 sessions, 0 events — and ZERO rows all-time in telemetry_events. Event contract (remote main 184ab0a9): `trial_start` is emitted ONLY by the web Stripe success page (src/pages/Success.tsx, when verify returns status='trialing'); iOS emits NO first-party trial event — an iOS trial is only flagged to the Meta SDK (MetaEvents.logSubscriptionPurchase isTrial → AppEvents "StartTrial", StoreKitManager.swift), never to telemetry_events. purchase_success on iOS carries plan+source only, no trial flag. So the trial stage is unmeasurable from first-party telemetry for iOS, by construction.
- purchase_success: 2 sessions (both iOS; 2 events). All-time total is only 4 purchase_success rows ever (2026-10-05 yearly/storekit, 10-08 monthly/storekit v1.3, 10-13 monthly/storekit v1.4, 10-17 legacy-format with plan/source NULL).
Stage conversions (independent-count method): success→paywall_view 101.5% (not a true chained rate — see above), paywall_view→trial_start 0.0%, trial_start→purchase n/a, paywall_view→purchase_success 2.9% (2/69).
Supporting stages in window: paywall_plan_select 11 sessions (9 iOS + 2 web), purchase_start 11 sessions (9 iOS + 2 web), checkout_redirect 2 web sessions, paywall_dismiss 19 iOS sessions, purchase_restore 2 iOS sessions. purchase_cancelled / purchase_pending / purchase_failed / purchase_fail: ZERO events in window — 11 purchase_start sessions produced no recorded outcome event other than the 2 successes.
Same-session chaining caveat: success∩paywall_view = 58 sessions; success∩purchase_success = 0; paywall_view∩purchase_success = 2. The week's 2 purchases came from sessions that viewed the paywall but recorded no auto_optimize_success in that same session (purchase happened in a later session than the success), so a strict same-session chain reads 68 → 58 → 0 → 0 and understates revenue. The independent-count method above is the recorded series.
Revenue baseline going forward = this reading: 68 → 69 → 0 → 2. Last reported to user: 2026-10-18 (this first reading, via the revenue-funnel task).

## Run 2026-10-19 — window 2026-10-12 → 2026-10-18 PT (trailing 7 complete days)
Method validated again this run: same definition reproduced the prior window exactly (Oct 11–17 PT: 257 / 130 / 4 / 68) and the operational baseline exactly (PT 2026-09-19 → 2026-10-06: 237 / 95 / 56 / 54). Read via SSH CONNECT-proxy tunnel to grepawk → MySQL telemetry_events, SELECT only; PT windows converted to UTC (PDT, +07:00 boundaries).
Primary definition: 272 sessions → 134 camera opens → 3 optimize starts → 68 successes.
Conversions: sessions→camera 49.3% (134/272), camera→optimize-start 2.2% (3/134), start→success n/a (68 vs 3 — instrumentation break, denominator <10).
Daily distinct sessions (PT): Oct 12: 15, 13: 70, 14: 27, 15: 28, 16: 17, 17: 85, 18: 30.
Comparison: sessions→camera +9.2pp vs operational baseline (40.1%), −16.9pp vs stated baseline (66.2%), −1.3pp vs last reported (50.6%, Oct 11–17) — under the 20pp threshold on every comparison. Camera→success 50.7% (68/134) vs 56.8% operational baseline; sessions→success 25.0% vs 22.8%.
Optimize-start stage: still NOT like-for-like — the already-reported (2026-10-18) instrumentation break. Starts by version this week: NULL 1 session, v1.2 1 session, v1.6 1 session (4 events — the restored auto_optimize_start emission from 2cbdc31e appearing only in the then-unreleased 1.6 build; v1.6 build 84 was WAITING_FOR_REVIEW throughout this window and went READY_FOR_SALE on 2026-10-19 at the 10:15 PDT review-watch check, after the window closed — so the Oct 19–25 window will be the first with 1.6 live, and the start-stage baseline question should be revisited then). ao_tap: 50 sessions / 96 events. Do NOT re-announce the break; no reset baseline yet because 1.6 has not shipped.
Verdict: no stage qualifies under the speaking rule (≥20pp vs BOTH baselines AND last reported, denominator ≥10). Silent run — figures recorded only.

### Revenue funnel — Run 2026-10-19 (same window, same method, independent stage counts)
- auto_optimize_success: 68 sessions (135 events)
- paywall_view: 73 sessions (97 events) — success→paywall 107.4% (artifact of extra paywall entry points, as before)
- trial_start: 0 sessions, 0 events — still ZERO rows all-time in telemetry_events. Not exception (a).
- purchase_success: 2 sessions (2 events; Oct 13 PT v1.4 iOS, Oct 17 PT version NULL iOS) — paywall_view→purchase_success 2.7% (2/73) vs revenue baseline 2.9% (2/69). Not exception (b) (weekly distinct sessions 2 < 5). All-time purchase_success total is now 5 rows / 5 distinct sessions (was 4 rows as of 2026-10-18).
Supporting (distinct sessions / events): paywall_trigger 96 / 180, paywall_plan_select 11 / 20, purchase_start 11 / 19, checkout_redirect 1 / 1, paywall_dismiss 19 / 30, purchase_restore 2 / 2, purchase_cancelled 1 / 3, purchase_pending 0, purchase_failed 0, purchase_fail 0.
Revenue verdict: no stage moved ≥20pp vs both the revenue baseline (68 → 69 → 0 → 2, Oct 11–17) and the last reported figures (same reading), and neither one-time exception fired. Silent run — figures recorded only.
Last reported figures unchanged: sessions→camera 50.6% (130/257, Oct 11–17 PT) plus the 2026-10-18 instrumentation-break / baseline-reset report and the 2026-10-18 revenue first reading.

## METHOD CORRECTION — 2026-10-20 (read before any future run)
The telemetry_events table is SHARED across apps (column `app`: photo-recipes 9,774 rows, omr-sheet-cam 472, grepawk-photos 34). All historical queries above counted every app. Rules from now on: ALWAYS filter app='photo-recipes'. Known contamination: purchase_success all-time for ProTune = 4 rows, not 5 (id 8785, Oct 17, is omr-sheet-cam — a Music Reader purchase). Revenue-stage counts in windows including Oct 17 carry small omr additions (paywall_view +3 sess, paywall_trigger +27 sess in Oct 13-19); the sessions denominator carried +72 omr sessions in Oct 13-19 (ProTune-only sessions 224; sessions->camera ProTune-only = 68.3%). camera_open / auto_optimize_* counts are unaffected (omr emits none). Stripe web sales: checkout starts exist (Oct 11, Oct 13) but NO stripe purchase_success is ever recorded — the web success path does not emit it; Stripe revenue must be read from Stripe, never inferred from telemetry. ASC remains the App Store revenue ledger of record.

## Daily run 2026-10-20

Method: first daily run under the 2026-10-20 correction — all counts filtered app='photo-recipes' (SELECT only, SSH CONNECT-proxy route). Validation: this run's trailing-7 sessions→camera (ProTune-only) reproduces the correction note's figure exactly (153/224 = 68.3%). Comparisons against the operational baseline and last reported figures are NOT like-for-like for session-denominator stages (the old counts included omr-sheet-cam / grepawk-photos sessions); camera_open / auto_optimize_* stage counts are unaffected by the filter.

### Trailing 7 complete days — window 2026-10-13 → 2026-10-19 PT
Primary definition: 224 sessions → 153 camera opens → 11 optimize starts → 78 successes.
Conversions: sessions→camera 68.3% (153/224), camera→optimize-start 7.2% (11/153), start→success n/a (78 successes vs 11 starts — start stage still under-counted, but recovering: starts by version = v1.6 9 sessions, v1.2 1, NULL 1; v1.6 went live 2026-10-19, so only the last day of this window carried the restored emission). ao_tap: 55 sessions / 101 events.
Daily distinct sessions (PT): Oct 13: 69, 14: 27, 15: 27, 16: 16, 17: 18, 18: 28, 19: 39. (Oct 17 reads 18 ProTune-only vs 85 in the old all-apps series — the difference is omr-sheet-cam's Oct 17 volume.)
Success latency (auto_optimize_success latency_ms, trailing 7 days): n=117 events, median 1,075 ms, p95 16,521 ms.

### Revenue — same window, independent stage counts
- auto_optimize_success: 78 sessions (148 events)
- paywall_view: 80 sessions (102 events) — success→paywall 102.6% (extra paywall entry points, as before)
- trial_start: 0 sessions, 0 events — still ZERO rows all-time for app='photo-recipes'. Not exception (a).
- purchase_success: 2 sessions (2 events) — paywall_view→purchase_success 2.5% (2/80). Not exception (b) (2 < 5). All-time ProTune purchase_success = 4 rows / 4 sessions.
Supporting (distinct sessions / events): paywall_trigger 79 / 102, paywall_plan_select 11 / 20, purchase_start 11 / 19, checkout_redirect 1 / 1, paywall_dismiss 22 / 31, purchase_restore 2 / 2, purchase_cancelled 2 / 4, purchase_pending 0, purchase_failed 0, purchase_fail 0.

### Today PT so far — 2026-10-20 (through ~17:22 PDT)
46 sessions → 16 camera opens → 4 optimize starts → 4 successes. Conversions: sessions→camera 34.8% (16/46, partial day, small n). Revenue today: paywall_view 4 sessions, paywall_trigger 3, paywall_plan_select 1, purchase_start 1, paywall_dismiss 2, checkout_redirect 1, trial_start 0, purchase_success 0. ao_tap 4 sessions.

### Verdict
Silent run. sessions→camera 68.3% vs last reported 50.6% is +17.7pp (under the 20pp threshold) and is not like-for-like anyway (app filter changed the denominator); the ≥20pp-vs-operational-baseline gap (+28.2pp) is a method artifact of removing 72 non-ProTune sessions from the Oct 13–19 denominator, not a stage movement. Neither one-time exception fired (trial_start still 0 all-time; trailing-7 purchase_success sessions 2 < 5). Figures recorded only; last reported figures unchanged.
