# ProTune ads — decision log (running)

Running record of campaign decisions for ProTune AI Camera - Installs (campaign 52591274976908). Every decision gets an entry here with the analysis it rests on, per the user's instruction 2026-10-19 ("Keep a running log in the same file"). Newest entries at the bottom.

Daily practice (user instruction 2026-10-19 21:11 PT): this file is updated every day with the day's best decision for the campaign, and that decision is confirmed with the user before anything is executed. Renamed 2026-10-19 from decision-log-2026-10-19-posters-off.md to decision-log.md so the same file carries every day.

---

## 2026-10-19 — Posters turned off

**Decision (user directive, 2026-10-19 21:04 PT: "Turn off the posters"):** pause both poster ads in the ProTune install campaign. The ad set runs video-only until the user decides otherwise.

Ads paused:
- Poster v17 — ad 52593456502508
- Poster v18 — ad 52594203955308

Still running:
- Video v17 — ad 52593456485708 ("Selfie Looks v17")
- Video v20 — ad 52594503138708 ("Selfie Looks v20", activated 2026-10-19 21:02 PT)

Campaign 52591274976908 / ad set 52591298515708 unchanged; budget unchanged at $40/day. Poster v19 and v20 images exist in this folder (docs/ads) but were never uploaded to Meta; they stay unused unless the user directs otherwise.

## Cited analysis

Meta's in-product AI performance snapshot for this campaign, shared by the user 2026-10-19 ~21:03 PT:

- Cost per Mobile App Install, ad set level: **$4.47**, stated as 7.40% above a peer median of $4.17. Campaign-level CPI in the same snapshot: $5.27.
- 28-day cost trend: 57.97% favorable (cost per install improving).
- Engagement gap (the number this decision rests on): **CTR 20.22%** for "ProTune - AI Camera - Selfie Looks v17" (the video) vs **CTR 5.08%** for "ProTune - AI Camera - Poster v17". The video creative engages at roughly 4x the poster's rate.
- The snapshot's "top 25% of peers achieve costs around $11.06 or lower" line is internally inconsistent with its own $4.17 median and was disregarded.
- The snapshot recommended (1) a website-visitor retargeting layer — not applicable here: app-install account with no dataset connected, verified 2026-10-19; and (2) more iterations of the winning "Selfie Looks" concept — already executed the same evening (posters v19/v20, video v20).

Consistent with our own steering data: the v17 video has been the campaign's champion creative throughout; posters have trailed it on every comparison since launch.

## Follow-up

The 12-hour reevaluation (scheduled 2026-10-20 ~06:22 PT) now reads as a video-vs-video comparison: v17 (17s, established) vs v20 (10s, voiceover, transformation up front). Pause verification (read back 2026-10-19 21:05 PT): both posters confirmed PAUSED / effective CAMPAIGN_PAUSED; video v17 ACTIVE; video v20 ACTIVE with effective_status now ACTIVE (fully processed and delivering). Campaign and ad set ACTIVE throughout.

## 2026-10-20 — Campaign restarted, video-only, original ad paused at ad level

Context: the 12-hour reevaluation (06:22 PT, run at the user's request) found the campaign PAUSED again — the third external pause (after Oct 15 and Oct 18). It had been verified ACTIVE at 21:05 PT on Oct 19; no agent job touched Meta overnight. Nothing was delivering.

Reevaluation numbers, last 3 days (campaign total $96.34, 11 installs, $8.76 blended CPI):
- Original ad 52591299779708: $9.49, 6 installs, $1.58 CPI, 331 impressions
- Poster v17: $14.79, 4 installs, $3.70 CPI
- Poster v18: $25.38, 1 install, $25.38 CPI
- Video v17: $44.99, 1,622 impressions, installs not reported at ad level
- Video v20: $1.69, 72 impressions (first hours)

Two findings drove the decision:
1. The original ad was ACTIVE-configured all along — dark only while the campaign/ad set were off — which is how it spent $9.49 and took 6 installs during the Oct 18–19 live window. "Stays paused" in earlier notes was wrong at the ad level.
2. All 11 installs in the window were attributed to the three image ads and zero to the videos despite ~half the spend — read as an ad-level attribution artifact, not evidence the videos produced nothing (blended CPI and engagement data say otherwise). The original's $1.58 CPI is 6 installs: a hint, not a verdict.

Decision (user, 2026-10-20 08:01 PT: "Restart the campaign — videos only, pause the original first"): pause the original at the ad level, then restart the campaign. Posters stay off per the 2026-10-19 decision.

Executed and verified (08:07 PT): campaign ACTIVE / effective ACTIVE; ad set ACTIVE / effective ACTIVE; original PAUSED; poster v17 and v18 PAUSED; video v17 and v20 ACTIVE and delivering. Budget unchanged at $40/day.

## 2026-10-20 — Campaign STOPPED (revenue) + funnel review

Decision (user, 2026-10-20 08:37 PT): "We need to stop the ads for now and pause the daily routine on this. It's not generating close to enough revenue to justify ad spending." Executed and verified (08:38 PT): campaign 52591274976908 PAUSED at the campaign level; ad set and both video ads effective CAMPAIGN_PAUSED; the configured lineup is preserved exactly (videos active-configured, posters + original paused), so a restart restores the video-only setup as-is. Budget setting untouched ($40/day).

Routines (user's calls, 2026-10-20): the daily decision cycle and the daily delivery watchdog are PAUSED. The weekly steering review is KEPT and now carries this funnel review every week, with an explicit verdict on whether the revenue picture has changed enough to revisit the stop.

### Funnel review (run 2026-10-20, trailing 7 complete days Oct 13-19 PT; method validated by exact reproduction of the prior window)

Canonical funnel (distinct sessions): 296 sessions -> 153 camera (51.7%) -> 11 optimize starts -> 78 successes (camera->success 51.0%, sessions->success 26.4%). Starts are recovering with v1.6 (11 start sessions vs 3 last week; today Oct 20 all start sessions are v1.6 — the restored emission is firing in the wild).
Revenue: 78 success -> 83 paywall_view -> 0 trial_start -> 3 purchase_success (paywall->purchase 3.6%). Supporting: paywall_trigger 106, plan_select 12, purchase_start 12, dismiss 24, restore 2, cancelled 2.
Latency (iOS successes, n=117 with latency): median 1,075 ms, p95 14,589 ms (baseline median 1,056 / p95 11,716) — median flat, the slow tail ran heavier; 7.7% of runs over 10 s.
All-time: purchase_success 5 rows total; trial_start 0 rows ever (no iOS first-party trial event exists).
Movement check: no stage moved >= 20 points vs baselines (sessions->camera +11.6 pp vs operational baseline, +1.1 pp vs last reported).

### Why the stop matches the math

The funnel is not the leak: half of sessions open the camera, half of camera sessions succeed, 83 sessions saw the paywall. The leak is the last step — 12 purchase_start sessions yielded 3 purchases (about 1 in 28 paywall viewers), and trials are unmeasurable-to-zero. Against roughly $225-280/week of ad spend at the campaign's recent pace (~11 installs per 3 days at $8.76 blended CPI), even crediting all 3 weekly purchases to ads puts spend around $75-93 per purchase against $4.99/mo or $29.99/yr price points. The weekly steering review now re-tests this verdict every Monday against fresh funnel + revenue figures.

Correction to the entry above (2026-10-20, user challenge — verified against the telemetry table row by row): "all-time purchases 5" counts purchase_success EVENTS in first-party telemetry, which is not the App Store Connect sales ledger. The 5 rows are: Oct 5 yearly (storekit format, pre-1.3 build), Oct 8 monthly (v1.3, storekit), Oct 13 monthly (v1.4, storekit), Oct 17 (LEGACY format — product id only, no storekit fields; least reliable as a sale), Oct 19 yearly (v1.5, storekit). The user sees 3 in his sales view — consistent with the three mid-window storekit sales, with the Oct 19 sale likely not yet posted in his report and the Oct 17 legacy row doubtful. Going forward, reports state both numbers separately: telemetry purchase_success events vs App Store Connect recorded sales, and ASC is the revenue ledger of record. The stop decision is unaffected — on 3 sales the economics are worse, not better.
