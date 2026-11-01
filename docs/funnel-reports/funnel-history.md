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

## Daily run 2026-10-21

Method: all counts filtered app='photo-recipes' (SELECT only, SSH CONNECT-proxy route). Validation: this run's queries reproduced the prior window exactly — Oct 13–19 PT distinct sessions 224 (yesterday's trailing-7 figure), and that window's success latency median 1,075 ms / p95 16,521 ms (nearest-rank) exactly as reported on 2026-10-20.

### Trailing 7 complete days — window 2026-10-14 → 2026-10-20 PT
Primary definition: 209 sessions → 125 camera opens → 20 optimize starts → 66 successes.
Conversions: sessions→camera 59.8% (125/209), camera→optimize-start 16.0% (20/125), start→success n/a (66 successes vs 20 starts — start stage still under-counted, but recovering: starts by version = v1.6 18 sessions, v1.2 1, NULL 1; v1.6 has been live since 2026-10-19, so only the last two days of this window carried a full day of the restored emission, and older versions still emit success without start). ao_tap: 49 sessions / 76 events.
Daily distinct sessions (PT): Oct 14: 27, 15: 27, 16: 16, 17: 18, 18: 28, 19: 39, 20: 54.
Success latency (auto_optimize_success latency_ms, trailing 7 days): n=98 latency-bearing events (of 120 success events), median 900.5 ms, p95 18,629 ms (nearest-rank).

### Revenue — same window, independent stage counts
- auto_optimize_success: 66 sessions (120 events)
- paywall_view: 62 sessions (72 events) — success→paywall 93.9%
- trial_start: 0 sessions, 0 events — still ZERO rows all-time for app='photo-recipes'. Not exception (a).
- purchase_success: 2 sessions (2 events; Oct 19 PT yearly/storekit v1.5, Oct 20 PT monthly/storekit v1.6) — paywall_view→purchase_success 3.2% (2/62). Not exception (b) (2 < 5). All-time ProTune purchase_success = 5 rows / 5 sessions (the Oct 20 v1.6 purchase is new since the 2026-10-20 run's all-time count of 4).
Supporting (distinct sessions / events): paywall_trigger 60 / 70, paywall_plan_select 9 / 15, purchase_start 9 / 14, checkout_redirect 1 / 1, paywall_dismiss 20 / 22, purchase_restore 1 / 1, purchase_cancelled 2 / 4, purchase_pending 0, purchase_failed 0, purchase_fail 0.

### Today PT so far — 2026-10-21 (through ~17:22 PDT)
13 sessions → 11 camera opens → 7 optimize starts → 7 successes. Conversions: sessions→camera 84.6% (11/13, partial day, small n). Revenue today: paywall_view 5 sessions, paywall_trigger 5, paywall_dismiss 4, paywall_plan_select 0, purchase_start 0, checkout_redirect 0, trial_start 0, purchase_success 0. ao_tap 5 sessions / 11 events.

### Verdict
Silent run. sessions→camera 59.8% vs last reported 50.6% is +9.2pp, and vs the operational baseline 40.1% is +19.7pp — under the 20pp threshold on both, and the baseline comparison remains not like-for-like after the 2026-10-20 app-filter correction. camera→optimize-start (16.0%) reflects the known, already-reported instrumentation break and its v1.6 recovery, not a new genuine stage movement. Neither one-time exception fired (trial_start still 0 all-time; trailing-7 purchase_success sessions 2 < 5). Figures recorded only; last reported figures unchanged.
## Daily run 2026-10-22

Method: all counts filtered app='photo-recipes' (SELECT only, SSH CONNECT-proxy route). Validation: this run's queries reproduced the prior window exactly — Oct 14–20 PT distinct sessions 209 with stages 125 camera / 20 starts / 66 successes, and that window's success latency n=98, median 900.5 ms / p95 18,629 ms, exactly as reported on 2026-10-21.

### Trailing 7 complete days — window 2026-10-15 → 2026-10-21 PT
Primary definition: 200 sessions → 121 camera opens → 28 optimize starts → 61 successes.
Conversions: sessions→camera 60.5% (121/200), camera→optimize-start 23.1% (28/121), start→success n/a (61 successes vs 28 starts — start stage still under-counted, but recovering: starts by version = v1.6 26 sessions, v1.2 1, NULL 1; v1.6 has been live since 2026-10-19, so the last three days of this window carried the restored emission, and older versions still emit success without start). ao_tap: 43 sessions / 77 events.
Daily distinct sessions (PT): Oct 15: 27, 16: 16, 17: 18, 18: 28, 19: 39, 20: 54, 21: 18.
Success latency (auto_optimize_success latency_ms, trailing 7 days): n=106 latency-bearing events (of 123 success events), median 812 ms, p95 21,192 ms (nearest-rank).

### Revenue — same window, independent stage counts
- auto_optimize_success: 61 sessions (123 events)
- paywall_view: 59 sessions (69 events) — success→paywall 96.7%
- trial_start: 0 sessions, 0 events — still ZERO rows all-time for app='photo-recipes'. Not exception (a).
- purchase_success: 2 sessions (2 events; Oct 19 PT yearly/storekit v1.5, Oct 20 PT monthly/storekit v1.6) — paywall_view→purchase_success 3.4% (2/59). Not exception (b) (2 < 5). All-time ProTune purchase_success = 5 rows / 5 sessions.
Supporting (distinct sessions / events): paywall_trigger 57 / 67, paywall_plan_select 9 / 15, purchase_start 9 / 14, checkout_redirect 1 / 1, paywall_dismiss 23 / 26, purchase_restore 1 / 1, purchase_cancelled 2 / 4, purchase_pending 0, purchase_failed 0, purchase_fail 0.

### Today PT so far — 2026-10-22 (through ~17:27 PDT)
8 sessions → 7 camera opens → 2 optimize starts → 2 successes. Conversions: sessions→camera 87.5% (7/8, partial day, small n). Revenue today: paywall_view 0 sessions, paywall_trigger 0, paywall_plan_select 0, purchase_start 0, paywall_dismiss 0, checkout_redirect 0, trial_start 0, purchase_success 0. ao_tap 2 sessions / 2 events.

### Verdict
Silent run. sessions→camera 60.5% vs last reported 50.6% is +9.9pp — under the 20pp threshold; vs the operational baseline 40.1% it is +20.4pp, but that comparison remains not like-for-like after the 2026-10-20 app-filter correction, and the speaking rule requires ≥20pp vs BOTH the baseline and the last reported figures. camera→optimize-start (23.1%) reflects the known, already-reported instrumentation break and its continuing v1.6 recovery, not a new genuine stage movement. Neither one-time exception fired (trial_start still 0 all-time; trailing-7 purchase_success sessions 2 < 5). Figures recorded only; last reported figures unchanged.
## Daily run 2026-10-23

Method: all counts filtered app='photo-recipes' (SELECT only, SSH CONNECT-proxy route). Validation: this run's queries reproduced the prior window exactly — Oct 15–21 PT distinct sessions 200 with stages 121 camera / 28 starts / 61 successes, and that window's success latency n=106, median 812 ms / p95 21,192 ms, exactly as reported on 2026-10-22.

### Trailing 7 complete days — window 2026-10-16 → 2026-10-22 PT
Primary definition: 185 sessions → 111 camera opens → 33 optimize starts → 59 successes.
Conversions: sessions→camera 60.0% (111/185), camera→optimize-start 29.7% (33/111), start→success n/a (59 successes vs 33 starts — start stage still under-counted, but recovering: starts by version = v1.6 31 sessions, v1.2 1, NULL 1; older versions still emit success without start). ao_tap: 45 sessions / 83 events.
Daily distinct sessions (PT): Oct 16: 16, 17: 18, 18: 28, 19: 39, 20: 54, 21: 18, 22: 12.
Success latency (auto_optimize_success latency_ms, trailing 7 days): n=117 latency-bearing events (of 130 success events), median 849 ms, p95 21,192 ms (nearest-rank).

### Revenue — same window, independent stage counts
- auto_optimize_success: 59 sessions (130 events)
- paywall_view: 52 sessions (63 events) — success→paywall 88.1%
- trial_start: 0 sessions, 0 events — still ZERO rows all-time for app='photo-recipes'. Not exception (a).
- purchase_success: 2 sessions (2 events; Oct 19 PT yearly/storekit v1.5, Oct 20 PT monthly/storekit v1.6) — paywall_view→purchase_success 3.8% (2/52). Not exception (b) (2 < 5). All-time ProTune purchase_success = 6 rows / 6 sessions at run time (the 6th is today's Oct 23 purchase, outside this window — see below).
Supporting (distinct sessions / events): paywall_trigger 50 / 61, paywall_plan_select 8 / 14, purchase_start 8 / 13, checkout_redirect 1 / 1, paywall_dismiss 23 / 27, purchase_restore 1 / 1, purchase_cancelled 2 / 4, purchase_pending 0, purchase_failed 0, purchase_fail 0.

### Today PT so far — 2026-10-23 (through ~17:22 PDT)
9 sessions → 6 camera opens → 4 optimize starts → 4 successes. Conversions: sessions→camera 66.7% (6/9, partial day, small n). Revenue today: paywall_view 4 sessions, paywall_trigger 3, paywall_plan_select 1, purchase_start 1, paywall_dismiss 3, checkout_redirect 0, trial_start 0, purchase_success 1 (yearly/storekit, v1.6, iOS). ao_tap 3 sessions / 13 events.

### Verdict
Silent run. sessions→camera 60.0% vs last reported 50.6% is +9.4pp — under the 20pp threshold; vs the operational baseline 40.1% it is +19.9pp — also under the threshold, and that comparison remains not like-for-like after the 2026-10-20 app-filter correction (the speaking rule requires ≥20pp vs BOTH the baseline and the last reported figures). camera→optimize-start (29.7%) reflects the known, already-reported instrumentation break and its continuing v1.6 recovery, not a new genuine stage movement. Neither one-time exception fired (trial_start still 0 all-time; trailing-7 purchase_success sessions 2 < 5). Figures recorded only; last reported figures unchanged.
## Daily run 2026-10-24

Method: all counts filtered app='photo-recipes' (SELECT only, SSH CONNECT-proxy route). Validation: this run's queries reproduced the prior window exactly — Oct 16–22 PT distinct sessions 185 with stages 111 camera / 33 starts / 59 successes, and that window's success latency n=117, median 849 ms / p95 21,192 ms, exactly as reported on 2026-10-23.

### Trailing 7 complete days — window 2026-10-17 → 2026-10-23 PT
Primary definition: 182 sessions → 107 camera opens → 38 optimize starts → 57 successes.
Conversions: sessions→camera 58.8% (107/182), camera→optimize-start 35.5% (38/107), start→success n/a (57 successes vs 38 starts — start stage still under-counted, but recovering: starts by version = v1.6 36 sessions, v1.2 1, NULL 1; older versions still emit success without start). ao_tap: 43 sessions / 88 events.
Daily distinct sessions (PT): Oct 17: 18, 18: 28, 19: 39, 20: 54, 21: 18, 22: 12, 23: 13.
Success latency (auto_optimize_success latency_ms, trailing 7 days): n=130 latency-bearing events (of 141 success events), median 864 ms, p95 19,483 ms (nearest-rank).

### Revenue — same window, independent stage counts
- auto_optimize_success: 57 sessions (141 events)
- paywall_view: 51 sessions (59 events) — success→paywall 89.5%
- trial_start: 0 sessions, 0 events — still ZERO rows all-time for app='photo-recipes'. Not exception (a).
- purchase_success: 3 sessions (3 events; Oct 19 PT yearly/storekit v1.5, Oct 20 PT monthly/storekit v1.6, Oct 23 PT yearly/storekit v1.6) — paywall_view→purchase_success 5.9% (3/51). Not exception (b) (3 < 5). All-time ProTune purchase_success = 6 rows / 6 sessions.
Supporting (distinct sessions / events): paywall_trigger 48 / 56, paywall_plan_select 8 / 14, purchase_start 8 / 13, checkout_redirect 1 / 1, paywall_dismiss 26 / 30, purchase_restore 1 / 1, purchase_cancelled 2 / 4, purchase_pending 0, purchase_failed 0, purchase_fail 0.

### Today PT so far — 2026-10-24 (through ~17:22 PDT)
15 sessions → 8 camera opens → 5 optimize starts → 5 successes. Conversions: sessions→camera 53.3% (8/15, partial day, small n). Revenue today: paywall_view 1 sessions, paywall_trigger 1, paywall_plan_select 0, purchase_start 0, paywall_dismiss 1, checkout_redirect 0, trial_start 0, purchase_success 0. ao_tap 5 sessions / 14 events.

### Verdict
Silent run. sessions→camera 58.8% vs last reported 50.6% is +8.2pp — under the 20pp threshold; vs the operational baseline 40.1% it is +18.7pp — also under the threshold, and that comparison remains not like-for-like after the 2026-10-20 app-filter correction (the speaking rule requires ≥20pp vs BOTH the baseline and the last reported figures). camera→optimize-start (35.5%) reflects the known, already-reported instrumentation break and its continuing v1.6 recovery, not a new genuine stage movement. Neither one-time exception fired (trial_start still 0 all-time; trailing-7 purchase_success sessions 3 < 5). Figures recorded only; last reported figures unchanged.
## Daily run 2026-10-25

Method: all counts filtered app='photo-recipes' (SELECT only, SSH CONNECT-proxy route). Validation: this run's queries reproduced the prior window exactly — Oct 17–23 PT distinct sessions 182 with stages 107 camera / 38 starts / 57 successes, and that window's success latency n=130, median 864 ms / p95 19,483 ms, exactly as reported on 2026-10-24.

### Trailing 7 complete days — window 2026-10-18 → 2026-10-24 PT
Primary definition: 184 sessions → 105 camera opens → 41 optimize starts → 54 successes.
Conversions: sessions→camera 57.1% (105/184), camera→optimize-start 39.0% (41/105), start→success n/a (54 successes vs 41 starts — start stage still under-counted, but recovering: starts by version = v1.6 41 sessions, the only version emitting starts in this window; older versions still emit success without start). ao_tap: 46 sessions / 98 events.
Daily distinct sessions (PT): Oct 18: 28, 19: 39, 20: 54, 21: 18, 22: 12, 23: 13, 24: 20.
Success latency (auto_optimize_success latency_ms, trailing 7 days): n=136 latency-bearing events (of 142 success events), median 893 ms, p95 21,030 ms (nearest-rank).

### Revenue — same window, independent stage counts
- auto_optimize_success: 54 sessions (142 events)
- paywall_view: 44 sessions (50 events) — success→paywall 81.5%
- trial_start: 0 sessions, 0 events — still ZERO rows all-time for app='photo-recipes'. Not exception (a).
- purchase_success: 3 sessions (3 events; Oct 19 PT yearly/storekit v1.5, Oct 20 PT monthly/storekit v1.6, Oct 23 PT yearly/storekit v1.6) — paywall_view→purchase_success 6.8% (3/44). Not exception (b) (3 < 5). All-time ProTune purchase_success = 6 rows / 6 sessions.
Supporting (distinct sessions / events): paywall_trigger 42 / 48, paywall_plan_select 7 / 10, purchase_start 7 / 9, checkout_redirect 1 / 1, paywall_dismiss 26 / 30, purchase_restore 1 / 1, purchase_cancelled 2 / 4, purchase_pending 0, purchase_failed 0, purchase_fail 0.

### Today PT so far — 2026-10-25 (through ~17:22 PDT)
7 sessions → 5 camera opens → 1 optimize start → 1 success. Conversions: sessions→camera 71.4% (5/7, partial day, small n). Revenue today: paywall_view 0 sessions, paywall_trigger 0, paywall_plan_select 0, purchase_start 0, paywall_dismiss 0, checkout_redirect 0, trial_start 0, purchase_success 0. ao_tap 1 session / 1 event.

### Verdict
Silent run. sessions→camera 57.1% vs last reported 50.6% is +6.5pp — under the 20pp threshold; vs the operational baseline 40.1% it is +17.0pp — also under the threshold, and that comparison remains not like-for-like after the 2026-10-20 app-filter correction (the speaking rule requires ≥20pp vs BOTH the baseline and the last reported figures). camera→optimize-start (39.0%) reflects the known, already-reported instrumentation break and its continuing v1.6 recovery, not a new genuine stage movement. Neither one-time exception fired (trial_start still 0 all-time; trailing-7 purchase_success sessions 3 < 5). Figures recorded only; last reported figures unchanged.
## Weekly run 2026-10-26 — window 2026-10-19 → 2026-10-25 PT (trailing 7 complete days)

Method: all counts filtered app='photo-recipes' (SELECT only, SSH CONNECT-proxy route). Validation: this run's queries reproduced the prior window exactly — Oct 18–24 PT distinct sessions 184 with stages 105 camera / 41 starts / 54 successes, success latency n=136, median 893 ms / p95 21,030 ms, and all supporting/revenue counts exactly as reported on 2026-10-25.

### Primary funnel
164 sessions → 96 camera opens → 41 optimize starts → 46 successes.
Conversions: sessions→camera 58.5% (96/164), camera→optimize-start 42.7% (41/96), start→success n/a (46 successes vs 41 starts — start stage still under-counted: starts by version = v1.6 41 sessions / 113 events, the only version emitting starts in this window; older versions still emit success without start). ao_tap: 39 sessions / 81 events.
Daily distinct sessions (PT): Oct 19: 39, 20: 54, 21: 18, 22: 12, 23: 13, 24: 20, 25: 8.
Success latency (auto_optimize_success latency_ms, trailing 7 days): n=120 latency-bearing events (of 120 success events), median 776 ms, p95 19,483 ms (nearest-rank).

### Revenue — same window, independent stage counts
- auto_optimize_success: 46 sessions (120 events)
- paywall_view: 36 sessions (39 events) — success→paywall 78.3%
- trial_start: 0 sessions, 0 events — still ZERO rows all-time for app='photo-recipes'. Not exception (a).
- purchase_success: 3 sessions (3 events; Oct 19 PT yearly/storekit v1.5, Oct 20 PT monthly/storekit v1.6, Oct 23 PT yearly/storekit v1.6) — paywall_view→purchase_success 8.3% (3/36) vs revenue baseline 2.9% (2/69), +5.4pp. Not exception (b) (3 < 5). All-time ProTune purchase_success = 6 rows / 6 sessions.
Supporting (distinct sessions / events): paywall_trigger 34 / 37, paywall_plan_select 6 / 7, purchase_start 6 / 6, checkout_redirect 1 / 1, paywall_dismiss 24 / 26, purchase_restore 0 / 0, purchase_cancelled 1 / 1, purchase_pending 0, purchase_failed 0, purchase_fail 0.

### Today PT so far — 2026-10-26 (through ~09:22 PDT)
4 sessions → 3 camera opens → 2 optimize starts → 2 successes. Conversions: sessions→camera 75.0% (3/4, partial day, small n). Revenue today: paywall_view 3 sessions, paywall_trigger 3, paywall_plan_select 1, purchase_start 1, paywall_dismiss 3, checkout_redirect 0, trial_start 0, purchase_success 0. ao_tap 2 sessions / 4 events.

### Verdict
Silent run. sessions→camera 58.5% vs last reported 50.6% is +7.9pp — under the 20pp threshold; vs the operational baseline 40.1% it is +18.4pp — also under the threshold, and that comparison remains not like-for-like after the 2026-10-20 app-filter correction (the speaking rule requires ≥20pp vs BOTH the baseline and the last reported figures). camera→optimize-start (42.7%) reflects the known, already-reported instrumentation break and its continuing v1.6 recovery, not a new genuine stage movement. Revenue: paywall_view→purchase_success +5.4pp vs baseline — under threshold. Neither one-time exception fired (trial_start still 0 all-time; trailing-7 purchase_success sessions 3 < 5). Figures recorded only; last reported figures unchanged.
## Daily run 2026-10-26

Method: all counts filtered app='photo-recipes' (SELECT only, SSH CONNECT-proxy route). Validation: this run's queries reproduced the prior window exactly — Oct 18–24 PT distinct sessions 184 with stages 105 camera / 41 starts / 54 successes, and that window's success latency n=136, median 893 ms / p95 21,030 ms, exactly as reported on 2026-10-25; the trailing window below also matches this morning's weekly run 2026-10-26 figures exactly.

### Trailing 7 complete days — window 2026-10-19 → 2026-10-25 PT
Primary definition: 164 sessions → 96 camera opens → 41 optimize starts → 46 successes.
Conversions: sessions→camera 58.5% (96/164), camera→optimize-start 42.7% (41/96), start→success n/a (46 successes vs 41 starts — start stage still under-counted: starts by version = v1.6 41 sessions / 113 events, the only version emitting starts in this window; older versions still emit success without start). ao_tap: 39 sessions / 81 events.
Daily distinct sessions (PT): Oct 19: 39, 20: 54, 21: 18, 22: 12, 23: 13, 24: 20, 25: 8.
Success latency (auto_optimize_success latency_ms, trailing 7 days): n=120 latency-bearing events (of 120 success events), median 776 ms, p95 19,483 ms (nearest-rank).

### Revenue — same window, independent stage counts
- auto_optimize_success: 46 sessions (120 events)
- paywall_view: 36 sessions (39 events) — success→paywall 78.3%
- trial_start: 0 sessions, 0 events — still ZERO rows all-time for app='photo-recipes'. Not exception (a).
- purchase_success: 3 sessions (3 events; Oct 19 PT yearly/storekit v1.5, Oct 20 PT monthly/storekit v1.6, Oct 23 PT yearly/storekit v1.6) — paywall_view→purchase_success 8.3% (3/36). Not exception (b) (3 < 5). All-time ProTune purchase_success = 6 rows / 6 sessions.
Supporting (distinct sessions / events): paywall_trigger 34 / 37, paywall_plan_select 6 / 7, purchase_start 6 / 6, checkout_redirect 1 / 1, paywall_dismiss 24 / 26, purchase_restore 0 / 0, purchase_cancelled 1 / 1, purchase_pending 0, purchase_failed 0, purchase_fail 0.

### Today PT so far — 2026-10-26 (through ~17:22 PDT)
14 sessions → 11 camera opens → 6 optimize starts → 6 successes. Conversions: sessions→camera 78.6% (11/14, partial day, small n). Revenue today: paywall_view 6 sessions, paywall_trigger 6, paywall_plan_select 1, purchase_start 1, paywall_dismiss 6, checkout_redirect 0, trial_start 0, purchase_success 0. ao_tap 4 sessions / 9 events.

### Verdict
Silent run. sessions→camera 58.5% vs last reported 50.6% is +7.9pp — under the 20pp threshold; vs the operational baseline 40.1% it is +18.4pp — also under the threshold, and that comparison remains not like-for-like after the 2026-10-20 app-filter correction (the speaking rule requires ≥20pp vs BOTH the baseline and the last reported figures). camera→optimize-start (42.7%) reflects the known, already-reported instrumentation break and its continuing v1.6 recovery, not a new genuine stage movement. Neither one-time exception fired (trial_start still 0 all-time; trailing-7 purchase_success sessions 3 < 5). Figures recorded only; last reported figures unchanged.
## Daily run 2026-10-27

Method: all counts filtered app='photo-recipes' (SELECT only, SSH route). Validation: this run's queries reproduced the prior window exactly — Oct 19–25 PT distinct sessions 164 with stages 96 camera / 41 starts / 46 successes, and that window's success latency n=120, median 776 ms / p95 19,483 ms, exactly as reported on 2026-10-26.

### Trailing 7 complete days — window 2026-10-20 → 2026-10-26 PT
Primary definition: 149 sessions → 89 camera opens → 45 optimize starts → 47 successes.
Conversions: sessions→camera 59.7% (89/149), camera→optimize-start 50.6% (45/89), start→success n/a (47 successes vs 45 starts — start stage still under-counted: starts by version = v1.6 45 sessions / 127 events, the only version emitting starts in this window; older versions still emit success without start). ao_tap: 41 sessions / 92 events.
Daily distinct sessions (PT): Oct 20: 54, 21: 18, 22: 12, 23: 13, 24: 20, 25: 8, 26: 24.
Success latency (auto_optimize_success latency_ms, trailing 7 days): n=130 latency-bearing events (of 130 success events), median 799.5 ms, p95 21,030 ms (nearest-rank).

### Revenue — same window, independent stage counts
- auto_optimize_success: 47 sessions (130 events)
- paywall_view: 35 sessions (40 events) — success→paywall 74.5%
- trial_start: 0 sessions, 0 events — still ZERO rows all-time for app='photo-recipes'. Not exception (a).
- purchase_success: 2 sessions (2 events; Oct 20 PT monthly/storekit v1.6, Oct 23 PT yearly/storekit v1.6) — paywall_view→purchase_success 5.7% (2/35). Not exception (b) (2 < 5). All-time ProTune purchase_success = 6 rows / 6 sessions.
Supporting (distinct sessions / events): paywall_trigger 33 / 38, paywall_plan_select 5 / 8, purchase_start 5 / 7, checkout_redirect 1 / 1, paywall_dismiss 30 / 33, purchase_restore 0 / 0, purchase_cancelled 0 / 0, purchase_pending 0, purchase_failed 0, purchase_fail 0.

### Today PT so far — 2026-10-27 (through ~17:22 PDT)
22 sessions → 18 camera opens → 12 optimize starts → 11 successes. Conversions: sessions→camera 81.8% (18/22, partial day, small n). Revenue today: paywall_view 11 sessions, paywall_trigger 12, paywall_plan_select 0, purchase_start 0, paywall_dismiss 9, checkout_redirect 0, trial_start 0, purchase_success 0. ao_tap 8 sessions / 8 events.

### Verdict
Silent run. sessions→camera 59.7% vs last reported 50.6% is +9.1pp — under the 20pp threshold; vs the operational baseline 40.1% it is +19.6pp — also under the threshold, and that comparison remains not like-for-like after the 2026-10-20 app-filter correction (the speaking rule requires ≥20pp vs BOTH the baseline and the last reported figures). camera→optimize-start (50.6%) reflects the known, already-reported instrumentation break and its continuing v1.6 recovery, not a new genuine stage movement. Neither one-time exception fired (trial_start still 0 all-time; trailing-7 purchase_success sessions 2 < 5). Figures recorded only; last reported figures unchanged.
## Daily run 2026-10-28

Method: all counts filtered app='photo-recipes' (SELECT only, SSH CONNECT-proxy route). Validation: this run's queries reproduced the prior window exactly — Oct 20–26 PT distinct sessions 149 with stages 89 camera / 45 starts / 47 successes, and that window's success latency n=130, median 799.5 ms / p95 21,030 ms, exactly as reported on 2026-10-27.

### Trailing 7 complete days — window 2026-10-21 → 2026-10-27 PT
Primary definition: 139 sessions → 95 camera opens → 54 optimize starts → 55 successes.
Conversions: sessions→camera 68.3% (95/139), camera→optimize-start 56.8% (54/95), start→success n/a (55 successes vs 54 starts — start stage still marginally under-counted: starts by version = v1.6 54 sessions / 150 events, the only version emitting starts in this window; older versions still emit success without start). ao_tap: 46 sessions / 98 events.
Daily distinct sessions (PT): Oct 21: 18, 22: 12, 23: 13, 24: 20, 25: 8, 26: 24, 27: 44.
Success latency (auto_optimize_success latency_ms, trailing 7 days): n=151 latency-bearing events (of 151 success events), median 761 ms, p95 16,072 ms (nearest-rank).

### Revenue — same window, independent stage counts
- auto_optimize_success: 55 sessions (151 events)
- paywall_view: 42 sessions (49 events) — success→paywall 76.4%
- trial_start: 0 sessions, 0 events — still ZERO rows all-time for app='photo-recipes'. Not exception (a).
- purchase_success: 1 session (1 event; Oct 23 PT yearly/storekit v1.6) — paywall_view→purchase_success 2.4% (1/42). Not exception (b) (1 < 5). All-time ProTune purchase_success = 6 rows / 6 sessions.
Supporting (distinct sessions / events): paywall_trigger 42 / 49, paywall_plan_select 3 / 5, purchase_start 3 / 5, checkout_redirect 0 / 0, paywall_dismiss 37 / 42, purchase_restore 0 / 0, purchase_cancelled 0 / 0, purchase_pending 0, purchase_failed 0, purchase_fail 0.

### Today PT so far — 2026-10-28 (through ~17:22 PDT)
12 sessions → 6 camera opens → 3 optimize starts → 3 successes. Conversions: sessions→camera 50.0% (6/12, partial day, small n). Revenue today: paywall_view 2 sessions, paywall_trigger 2, paywall_plan_select 0, purchase_start 0, paywall_dismiss 1, checkout_redirect 0, trial_start 0, purchase_success 0. ao_tap 3 sessions / 5 events.

### Verdict
Silent run. sessions→camera 68.3% vs last reported 50.6% is +17.7pp — under the 20pp threshold; vs the operational baseline 40.1% it is +28.2pp, but that comparison remains not like-for-like after the 2026-10-20 app-filter correction (the speaking rule requires ≥20pp vs BOTH the baseline and the last reported figures). camera→optimize-start (56.8%) reflects the known, already-reported instrumentation break and its continuing v1.6 recovery, not a new genuine stage movement. Neither one-time exception fired (trial_start still 0 all-time; trailing-7 purchase_success sessions 1 < 5). Figures recorded only; last reported figures unchanged.
## Daily run 2026-10-29

Method: all counts filtered app='photo-recipes' (SELECT only, SSH CONNECT-proxy route). Validation: this run's queries reproduced the prior window exactly — Oct 21–27 PT distinct sessions 139 with stages 95 camera / 54 starts / 55 successes, and that window's success latency n=151, median 761 ms / p95 16,072 ms, exactly as reported on 2026-10-28.

### Trailing 7 complete days — window 2026-10-22 → 2026-10-28 PT
Primary definition: 143 sessions → 91 camera opens → 52 optimize starts → 53 successes.
Conversions: sessions→camera 63.6% (91/143), camera→optimize-start 57.1% (52/91), start→success n/a (53 successes vs 52 starts — start stage still marginally under-counted: starts by version = v1.6 50 sessions / 139 events, v1.7 2 sessions / 5 events; older versions still emit success without start). ao_tap: 46 sessions / 94 events.
Daily distinct sessions (PT): Oct 22: 12, 23: 13, 24: 20, 25: 8, 26: 24, 27: 44, 28: 22.
Success latency (auto_optimize_success latency_ms, trailing 7 days): n=145 latency-bearing events (of 145 success events), median 932 ms, p95 12,088 ms (nearest-rank).

### Revenue — same window, independent stage counts
- auto_optimize_success: 53 sessions (145 events)
- paywall_view: 39 sessions (45 events) — success→paywall 73.6%
- trial_start: 0 sessions, 0 events — still ZERO rows all-time for app='photo-recipes'. Not exception (a).
- purchase_success: 1 session (1 event; Oct 23 PT yearly/storekit v1.6) — paywall_view→purchase_success 2.6% (1/39). Not exception (b) (1 < 5). All-time ProTune purchase_success = 6 rows / 6 sessions.
Supporting (distinct sessions / events): paywall_trigger 39 / 45, paywall_plan_select 3 / 5, purchase_start 3 / 5, checkout_redirect 0 / 0, paywall_dismiss 34 / 38, purchase_restore 1 / 2, purchase_cancelled 0 / 0, purchase_pending 0, purchase_failed 0, purchase_fail 0.

### Today PT so far — 2026-10-29 (through ~17:22 PDT)
15 sessions → 10 camera opens → 2 optimize starts → 2 successes. Conversions: sessions→camera 66.7% (10/15, partial day, small n). Revenue today: paywall_view 3 sessions, paywall_trigger 3, paywall_plan_select 0, purchase_start 0, paywall_dismiss 2, checkout_redirect 0, trial_start 0, purchase_success 0. ao_tap 1 session / 1 event.

### Verdict
Silent run. sessions→camera 63.6% vs last reported 50.6% is +13.0pp — under the 20pp threshold; vs the operational baseline 40.1% it is +23.5pp, but that comparison remains not like-for-like after the 2026-10-20 app-filter correction (the speaking rule requires ≥20pp vs BOTH the baseline and the last reported figures). camera→optimize-start (57.1%) reflects the known, already-reported instrumentation break and its continuing recovery (v1.7 starts now appearing alongside v1.6), not a new genuine stage movement. Neither one-time exception fired (trial_start still 0 all-time; trailing-7 purchase_success sessions 1 < 5). Figures recorded only; last reported figures unchanged.
## Daily run 2026-10-30

Method: all counts filtered app='photo-recipes' (SELECT only, SSH CONNECT-proxy route). Validation: this run's queries reproduced the prior window exactly — Oct 22–28 PT distinct sessions 143 with stages 91 camera / 52 starts / 53 successes, and that window's success latency n=145, median 932 ms / p95 12,088 ms, exactly as reported on 2026-10-29.

### Trailing 7 complete days — window 2026-10-23 → 2026-10-29 PT
Primary definition: 148 sessions → 92 camera opens → 49 optimize starts → 50 successes.
Conversions: sessions→camera 62.2% (92/148), camera→optimize-start 53.3% (49/92), start→success n/a (50 successes vs 49 starts — start stage still marginally under-counted: starts by version = v1.6 46 sessions / 121 events, v1.7 2 sessions / 5 events, v1.2 1 session / 2 events; older versions still emit success without start). ao_tap: 42 sessions / 85 events.
Daily distinct sessions (PT): Oct 23: 13, 24: 20, 25: 8, 26: 24, 27: 44, 28: 22, 29: 17.
Success latency (auto_optimize_success latency_ms, trailing 7 days): n=129 latency-bearing events (of 129 success events), median 877 ms, p95 16,072 ms (nearest-rank).

### Revenue — same window, independent stage counts
- auto_optimize_success: 50 sessions (129 events)
- paywall_view: 41 sessions (46 events) — success→paywall 82.0%
- trial_start: 0 sessions, 0 events — still ZERO rows all-time for app='photo-recipes'. Not exception (a).
- purchase_success: 1 session (1 event; Oct 23 PT yearly/storekit v1.6) — paywall_view→purchase_success 2.4% (1/41). Not exception (b) (1 < 5). All-time ProTune purchase_success = 6 rows / 6 sessions.
Supporting (distinct sessions / events): paywall_trigger 41 / 46, paywall_plan_select 3 / 5, purchase_start 3 / 5, checkout_redirect 0 / 0, paywall_dismiss 35 / 38, purchase_restore 1 / 2, purchase_cancelled 0 / 0, purchase_pending 0, purchase_failed 0, purchase_fail 0.

### Today PT so far — 2026-10-30 (through ~17:22 PDT)
14 sessions → 8 camera opens → 1 optimize start → 1 success. Conversions: sessions→camera 57.1% (8/14, partial day, small n). Revenue today: paywall_view 0 sessions, paywall_trigger 0, paywall_plan_select 0, purchase_start 0, paywall_dismiss 0, checkout_redirect 0, trial_start 0, purchase_success 0. ao_tap 1 session / 2 events.

### Verdict
Silent run. sessions→camera 62.2% vs last reported 50.6% is +11.6pp — under the 20pp threshold; vs the operational baseline 40.1% it is +22.1pp, but that comparison remains not like-for-like after the 2026-10-20 app-filter correction (the speaking rule requires ≥20pp vs BOTH the baseline and the last reported figures). camera→optimize-start (53.3%) reflects the known, already-reported instrumentation break and its continuing recovery (v1.7 starts appearing alongside v1.6), not a new genuine stage movement. Neither one-time exception fired (trial_start still 0 all-time; trailing-7 purchase_success sessions 1 < 5). Figures recorded only; last reported figures unchanged.
## Daily run 2026-10-31

Method: all counts filtered app='photo-recipes' (SELECT only, SSH CONNECT-proxy route). Validation: this run's queries reproduced the prior window exactly — Oct 23–29 PT distinct sessions 148 with stages 92 camera / 49 starts / 50 successes, and that window's success latency n=129, median 877 ms / p95 16,072 ms, exactly as reported on 2026-10-30.

### Trailing 7 complete days — window 2026-10-24 → 2026-10-30 PT
Primary definition: 154 sessions → 95 camera opens → 45 optimize starts → 46 successes.
Conversions: sessions→camera 61.7% (95/154), camera→optimize-start 47.4% (45/95), start→success n/a (46 successes vs 45 starts — start stage still marginally under-counted: starts by version = v1.6 42 sessions / 101 events, v1.7 2 sessions / 5 events, v1.2 1 session / 2 events; older versions still emit success without start). ao_tap: 39 sessions / 73 events.
Daily distinct sessions (PT): Oct 24: 20, 25: 8, 26: 24, 27: 44, 28: 22, 29: 17, 30: 19.
Success latency (auto_optimize_success latency_ms, trailing 7 days): n=109 latency-bearing events (of 109 success events), median 876 ms, p95 16,072 ms (nearest-rank).

### Revenue — same window, independent stage counts
- auto_optimize_success: 46 sessions (109 events)
- paywall_view: 36 sessions (41 events) — success→paywall 78.3%
- trial_start: 0 sessions, 0 events — still ZERO rows all-time for app='photo-recipes'. Not exception (a).
- purchase_success: 0 sessions (0 events) — paywall_view→purchase_success 0.0% (0/36). Not exception (b) (0 < 5). All-time ProTune purchase_success = 6 rows / 6 sessions.
Supporting (distinct sessions / events): paywall_trigger 37 / 42, paywall_plan_select 2 / 4, purchase_start 2 / 4, checkout_redirect 0 / 0, paywall_dismiss 31 / 34, purchase_restore 1 / 2, purchase_cancelled 0 / 0, purchase_pending 0, purchase_failed 0, purchase_fail 0.

### Today PT so far — 2026-10-31 (through ~17:22 PDT)
9 sessions → 6 camera opens → 4 optimize starts → 5 successes. Conversions: sessions→camera 66.7% (6/9, partial day, small n). Revenue today: paywall_view 3 sessions, paywall_trigger 3, paywall_plan_select 1, purchase_start 1, paywall_dismiss 3, checkout_redirect 0, trial_start 0, purchase_success 0. ao_tap 5 sessions / 14 events.

### Verdict
Silent run. sessions→camera 61.7% vs last reported 50.6% is +11.1pp — under the 20pp threshold; vs the operational baseline 40.1% it is +21.6pp, but that comparison remains not like-for-like after the 2026-10-20 app-filter correction (the speaking rule requires ≥20pp vs BOTH the baseline and the last reported figures). camera→optimize-start (47.4%) reflects the known, already-reported instrumentation break and its continuing recovery (v1.7 starts appearing alongside v1.6), not a new genuine stage movement. Neither one-time exception fired (trial_start still 0 all-time; trailing-7 purchase_success sessions 0 < 5). Figures recorded only; last reported figures unchanged.
