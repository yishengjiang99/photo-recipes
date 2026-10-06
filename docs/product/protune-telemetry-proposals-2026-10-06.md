# ProTune — Telemetry product proposals (2026-10-06)

**Window:** 2026-09-19 → 2026-10-06 (MySQL `telemetry_events` + admin)  
**Sample:** small — treat as directional, not statistically conclusive  
**Source analysis:** camera/paywall/look/web funnels + DAU/WAU/D1  
**Related:** [telemetry.md](../telemetry.md) · [telemetry-funnels.md](../telemetry-funnels.md) · [biz/push-lifecycle.md](../biz/push-lifecycle.md)

---

## 1. Metrics snapshot

| Metric | Value | Note |
|---|---|---|
| DAU (7d) | **22** | distinct `anon_id` |
| WAU (7d) | **42** | |
| iOS openers (window) | **30** | app open → any event |
| → camera open | **17** | ~57% of openers |
| → optimize start | **8** | ~47% of camera openers |
| Purchases (30d) | **1** | yearly plan only plan that sold |
| D1 return | **~2.3%** | ~26/30 opens one-and-done |

### Funnel holes (ranked by lost users)

| Hole | Signal | Implication |
|---|---|---|
| Camera → Optimize | **9/17** camera openers never start Auto Optimize | Core value never felt |
| Session depth | **26/30** opens are one-and-done | No habit; paid UA would burn |
| Paywall timing | **12/22** paywall viewers never had a successful optimize | Asking before the “pop” |
| Look diversity | **goldenHour = 42/54** look suggestions; apply weak | Suggestion spam, low apply |
| Web → app | Landing **20** → camera CTA **3**; browser camera errors | Web is a leak, not a funnel |
| Instrumentation | Onboarding / ATT / recommend events blocked until allowlist fix (2026-10-06) | That funnel still dark |

---

## 2. Ranked recommendations (#1–#10)

Priority = expected lift × feasibility given current iOS + server. Numbers from §1.

### #1 — Make Auto Optimize unmissable on first camera open
**Why:** 9/17 never start. If Optimize is the product, half never touch it.  
**Do:** Bigger primary CTA; first-open coach mark; or auto-run once + clear Undo. Measure `camera_open → auto_optimize_start` within 30s.  
**Success:** ≥70% of first camera sessions start Optimize.  
**Status:** Proposed (not in current WIP pack).

### #2 — Fix D1 retention before buying installs
**Why:** D1 ~2.3%; Push Exp 1 has **0 sends**. Paid UA would buy ghosts.  
**Do:** Post-capture delight (save + share sheet with before/after); golden-hour / “come shoot” local nudge after first success; real D1 push once APNs path works.  
**Success:** D1 ≥15% among users with ≥1 `auto_optimize_success`.  
**Status:** Partially covered by WIP push fix (#9).

### #3 — Soft paywall after first success; hard gate only on free quota  **[WIP]**
**Why:** 12/22 saw paywall without a successful optimize — selling before the demo.  
**Do:**  
- Soft: dismissible sheet / banner after first `auto_optimize_success` (value copy, no block).  
- Hard: full paywall only on `free_quota_hit` (next Optimize attempt when daily free exhausted).  
- Instrument `paywall_trigger` = `soft_post_success` | `hard_quota`.  
**Success:** Share of `paywall_view` with prior `auto_optimize_success` → ≥80%; purchase attempts concentrated on hard trigger.  
**Status:** **WIP — implementing in parallel with this doc.**

### #4 — Loosen first-day free; lean yearly
**Why:** Only purchased plan was yearly; free ceiling may choke the “feel” before upgrade.  
**Do:** First-day free ~**8–10** Optimizes (from ~5/day); keep monthly sparse in UI; yearly default / highlighted. Revisit after #3 ships.  
**Success:** ≥1 Optimize success before first hard paywall for ≥90% of free users who hit quota.  
**Status:** Proposed (config / StoreKit copy; after #3).

### #5 — Auto-apply top look + undo; stop goldenHour spam  **[WIP]**
**Why:** goldenHour 42/54 suggestions; apply weak → noise, not help.  
**Do:** After Optimize, auto-apply top look with visible Undo; diversify / cap goldenHour share; log `look_suggested` / `look_auto_applied` / `look_undone`.  
**Success:** Apply (incl. auto) ≥40% of suggestion sessions; goldenHour share of suggestions ≤30%.  
**Status:** **WIP — implementing in parallel.**

### #6 — Web: App Store badge first; demote in-browser camera
**Why:** Landing 20 → CTA 3; browser camera still errors.  
**Do:** Primary CTA = App Store / TestFlight; secondary “try in browser” behind fold or removed until mediaDevices path is solid.  
**Success:** CTA click → store open ≥50% of landing visitors on mobile Safari.  
**Status:** Proposed (web; separate from iOS WIP).

### #7 — Stay local-first on Optimize  **[WIP]**
**Why:** Sep cloud 504s; recent wins are local. Cloud is latency + failure mode for the moment that must feel instant.  
**Do:** Default path = on-device; cloud only as explicit fallback / secondary quality path with timeout + clear UI. Prefer local even when online.  
**Success:** p95 Optimize success latency on device path; cloud error rate no longer blocks first success.  
**Status:** **WIP — implementing in parallel.**

### #8 — Instrumentation hygiene
**Why:** Onboarding/ATT/recommend dark until allowlist fix; missing fields block cohorting.  
**Do:** Confirm new events land post-allowlist; add `paywall_trigger`, `free_quota_hit`; fill `app_version` on all client events.  
**Success:** Zero unknown critical events in 7d admin; `app_version` non-null ≥95%.  
**Status:** Allowlist fixed 2026-10-06; new events ride #3/#5.

### #9 — Kill or replace Push Exp 1  **[WIP]**
**Why:** Token present, **0 sends** — experiment is dead weight and blocks trust in push.  
**Do:** Fix APNs send path (“come shoot” / D1 after first success); kill Exp 1 if irreparable; replace with lifecycle from [push-lifecycle.md](../biz/push-lifecycle.md) (permission after first Optimize). Cap Free ≤3/week.  
**Success:** ≥1 successful `push_sent` → open → `camera_open` in internal cohort; revoke rate <5%.  
**Status:** **WIP — push fix in parallel.**

### #10 — Keep Recipe / Teach thin
**Why:** Usage concentrates on Camera + Optimize. Catalog depth is not the bottleneck.  
**Do:** No Recipe/Teach expansion until #1–#3 and D1 move. Protect camera chrome from feature creep.  
**Success:** Camera+Optimize remain ≥80% of meaningful sessions.  
**Status:** Guardrail (ongoing).

---

## 3. WIP (explicit — shipping in parallel)

Do **not** treat these as open proposals; they are already in flight as of 2026-10-06:

| # | Workstream | Intent | Verify in next TF |
|---|---|---|---|
| — | **Push fix** | Restore real send path; replace dead Exp 1; D1 / “come shoot” after first success | Token → `push_sent` → open → camera |
| **#3** | **Paywall soft → hard** | Soft after first Optimize success; hard only on free quota | `paywall_trigger` distribution |
| **#5** | **Auto-apply looks + undo** | Top look auto-applies; undo; less goldenHour | suggest / apply / undo events |
| **#7** | **Local-first Optimize** | On-device default; cloud fallback only | latency + success source props |

Owner context: iOS + server changes landing together; docs-only commit does not unblock TF.

---

## 4. Next TestFlight goals

Target build after WIP land (post build 51 attribution restore). Internal first.

| Goal | Pass criteria | Tied to |
|---|---|---|
| **G1** Optimize discoverability | First camera session: Optimize start ≥70% (n≥10 internal) | #1 (if included) or baseline coach |
| **G2** Soft/hard paywall | Soft shown after first success; hard only on quota; no hard before success | #3 |
| **G3** Looks | Auto-apply + undo visible; goldenHour ≤30% of suggestions in session logs | #5 |
| **G4** Local Optimize | Success without cloud when online; cloud timeout does not blank UI | #7 |
| **G5** Push smoke | Internal device: permission after Optimize → scheduled/test push opens camera | #9 |
| **G6** Events | `paywall_trigger`, `free_quota_hit`, `app_version` present in MySQL within 1h of TF use | #8 |

**Out of TF scope this cycle:** paid UA scale-up, Recipe/Teach expansion (#10), web App Store CTA (#6) unless bundled in same deploy.

**Hold App Store submit** until G2–G5 pass on internal + App Privacy filled from `docs/asc/app-privacy-1.2.md`. AppsFlyer Dev Key still missing on build 51 — cut a follow-up build when key lands if install ads need AppsFlyer.

---

## 5. Decision log

| Date (PT) | Decision |
|---|---|
| 2026-10-06 | Telemetry review → ship #3, #5, #7 + push fix; hold #1 as next candidate after TF |
| 2026-10-06 | 1.2 path: restore attribution + Meta (build 51); AppsFlyer runtime off until Dev Key |
| 2026-10-06 | User selected fix pack: push, paywall gate, #5, #7 |

---

## 6. One-liner

Stop selling and suggesting before the Optimize “pop”; make that moment local, automatic, and memorable — then soft-ask, hard-gate on quota, and only then spend on installs.
