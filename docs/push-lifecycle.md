# ProTune push engagement lifecycle

Status (2026-10-10 18:30 PT): **LIVE** for all eligible installs (`PUSH_LIFECYCLE_MODE=live`), legacy
come-shoot nudges **off** (`PUSH_EXP1_ENABLED=false`). Installs are only eligible once they run the 1.5
client (it links the push registration to the telemetry `anonId`); older builds receive no remote pushes.
Auto kill switch + daily monitor enabled (§7).
Supersedes the experiment memo in [`docs/biz/push-lifecycle.md`](biz/push-lifecycle.md) (Experiment 1 shoot briefs, retired 2026-10-06).

Code: `server/lifecycleSegments.ts` (rules), `server/lifecycleCopy.ts` (Grok copy + guardrails),
`server/lifecycleEngine.ts` (scheduler, caps, APNs, logging, report), routes in `server/push.ts`,
tests in `server/lifecycle.test.ts`. iOS: `Services/PushNotificationManager.swift`,
`Features/Settings/SettingsView.swift`, `Services/CameraRouter.swift`.

## 1. Audit (2026-10-10)

| Piece | State before this change |
|---|---|
| APNs key | Token auth `.p8`, key id `GAPGVZ7K2D`, team `83D36RPMUM`, on the droplet via `/etc/photo-recipes.env` (`APNS_*`). `/api/health` → `apnsEnv: true`. Not in GitHub secrets (not needed: deploy never touches it). |
| Entitlements | `PhotoRecipes.entitlements` (`aps-environment=development`) and `PhotoRecipesRelease.entitlements` (`production`). |
| Token registration | `POST /api/push/register` (+ `DELETE`), dual-written to `server/data/push-prefs.json` and MySQL `devices`/`push_tokens`. |
| Prefs | `GET/PUT /api/push/prefs` — opt-in, quiet hours (default 21:00–07:00 local), weekly cap, time zone. |
| Scheduler | `/etc/cron.d/photo-recipes-push-tick` → `POST /api/push/tick` every 10 min. **Live** (`PUSH_EXP1_ENABLED=true`): D1 return + evening "come shoot" nudges, static copy, ≤1/day, ≤3/week (free) / 5 (Pro). |
| Dead tokens | 410 / `Unregistered` pruned. `BadDeviceToken` was not. |
| iOS permission | Asked at a value moment: PostSaveCard "Remind me tomorrow" after the first saved optimized photo (never on launch / onboarding). |
| iOS local notifications | One D1 reminder + a **daily** 17:30 "Golden hour" repeat (exceeded a 3/week cap). |
| Tap handling | Every tap opened Auto Optimize; open tracked as `push_opened` without a send id. |
| Personalization | None. Push identity (guest cookie) was not linked to telemetry (`Analytics.anonId`), so no per-user signal. |
| Promotional consent (4.5.4) | Missing — no in-app opt-in for promotional pushes. |
| Kill switch / dry-run | Only the global `PUSH_EXP1_ENABLED` flag. |

## 2. Data used (first-party, anonymous)

The app already logs these to `telemetry_events` keyed by a random install id (`anon_id`). The
lifecycle reads **event names, times and one allowlisted token (`look_id`)** — never photos,
frames, voice, prompts or free text.

| Event | Used for |
|---|---|
| `session_start`, any event | install age (first seen), inactivity (last seen; `push_opened` excluded) |
| `capture_success` | captures last 7 days / total, "finished after abandoning" |
| `auto_optimize_success` | has the user felt the core feature |
| `optimize_capture_abandoned` | unfinished shot |
| `look_applied` (`look_id`) | favorite look (most used, 30 days) |
| `recipe_open` | recipe engagement |
| `paywall_view`, `purchase_success`, `free_quota_hit` | paywall-viewed-not-converted |

Linking: the iOS app now sends `anonId` with `/api/push/register` (additive field). Installs that
registered before this build show `no_activity_link` and get nothing from the lifecycle until
they update.

## 3. Segments and triggers

Evaluated every 10 minutes (same cron). One message per install per evaluation, highest
priority first. Each segment has a dedupe key; a key is never sent twice.

| Priority | Segment | Class | Trigger | Goal / deep link | Dedupe |
|---|---|---|---|---|---|
| 10 | `unfinished_edit` | feature | `optimize_capture_abandoned` 2–48 h ago, no capture since, idle ≥2 h | Finish the shot → `auto-optimize` | per abandon day |
| 20 | `onboarding_d1` | feature | install age 1–2 d, idle ≥12 h | Try Auto Optimize → `auto-optimize` | once |
| 21 | `onboarding_d3` | feature | install age 3–4 d, idle ≥24 h | Try a creative look → `camera` | once |
| 22 | `onboarding_d7` | feature | install age 7–8 d, idle ≥48 h | Browse recipes → `recipes` | once |
| 30 | `paywall_not_converted` | promotional | free tier, never purchased, `paywall_view` 20–72 h ago | Honest Pro reminder + "eligible new subscribers get a 7-day free trial" → `paywall` (soft sheet) | once per 30 d |
| — | trial ending | — | **Not sent.** Apple already emails/notifies before renewal; trial users are excluded from the paywall segment. | — | — |
| 40 | `new_feature` | promotional | active ≤30 d, install ≥3 d; only announcements with `active: true` in `FEATURE_ANNOUNCEMENTS` (flip only after the feature is in the live App Store build) | Feature news → per announcement | once per feature |
| 50 | `inactive_7` | promotional | last seen 7–14 d (install ≥8 d) | One shot idea, favorite look if known → `camera` | per inactivity episode |
| 51 | `inactive_14` | promotional | last seen 14–30 d | One easy recipe → `recipes` | per episode |
| 52 | `winback_30` | promotional | last seen 30–45 d | Final gentle check-in; then silence | per episode |

Classes: **feature** pushes need iOS notification permission. **Promotional** pushes additionally
need *Settings → Notifications → Tips & offers* (off by default) — App Review Guideline 4.5.4.

## 4. Caps and safety

| Rule | Value |
|---|---|
| Per install | ≤1 push / 24 h and ≤3 / rolling 7 days, **combined** with the legacy come-shoot/D1 nudges (shared `sentThisWeek` / `lastNudgeAt`) |
| Time | only 10:00–20:00 and outside the user's quiet hours, in the install's own time zone |
| Dedupe | `(install, dedupeKey)` once ever |
| Per tick | ≤200 real sends |
| Opt-out | `pushOptIn=false` → nothing; marketing off → no promotional |
| Uninstall | APNs 410 / `Unregistered` / `BadDeviceToken` → token pruned everywhere |
| Kill switch | `PUSH_KILL_SWITCH=true` (env) or `POST /api/push/lifecycle/ops {"killSwitch":true}` (runtime). Stops lifecycle **and** legacy nudges. |
| Mode | `PUSH_LIFECYCLE_MODE` = `off` · `dry_run` (**default**) · `sandbox` (only Xcode-debug sandbox tokens) · `allowlist` (only guest ids in `PUSH_LIFECYCLE_ALLOWLIST`, e.g. your TestFlight phone) · `live`. Runtime ops can only downgrade the env mode. |

Dry-run and real send histories are stored separately (`push-lifecycle-state.dryrun.json` vs
`push-lifecycle-state.json`), so going live starts with clean dedupe/caps.

## 5. Copy: Grok + guardrails

`generateCopy(segment, goal, facts)`:

1. **Input to xAI** (model `grok-4.20-0309-non-reasoning`, fallback `grok-4.3`): segment goal, app
   facts, and coarse facts only — tier, captures last week as `0 / 1-3 / 4+`, used Auto Optimize
   yes/no, favorite look name, away-for bucket, feature fact. No ids, tokens, timestamps, photos or text.
2. **Guardrails** (`validateCopy`), any failure → retry / next model → **template fallback**:
   title ≤40, body ≤140, one line; no urgency/scarcity words; no prices, currency, %, discounts;
   no links/handles; no guilt or "since you last opened" surveillance tone; ≤1 emoji, ≤1 `!`, no
   shouting; "free"/"trial" only in the paywall segment and only as "eligible new subscribers… 7-day
   free trial"; paywall copy may name only the verified Pro benefit (unlimited Auto Optimize);
   no "new" outside feature announcements; no upsell outside the paywall segment.
3. **Cache** (`push-copy-cache.json`, 14 days) by `(segment, facts)` — identical cohorts reuse one draft.
4. `PUSH_COPY_GROK=false` → templates only.

Store facts the copy may state are in `STORE_FACTS` / `APP_FACTS` (`lifecycleCopy.ts`) and must
match the live paywall (`$7.99/mo`, `$59.99/yr`, 7-day trial — prices are never put in pushes).

## 6. Payload, open tracking, KPIs

APNs payload: `aps.alert`, `thread-id: lifecycle`, `type: "lifecycle"`, `segment`, `sendId`, `deepLink`.
On tap the app logs `push_opened` / `notification_opened` with `send_id` + `campaign_id` (telemetry)
and `push_opened` with `sendId` (`/api/push/events`), then routes `photo-recipes://auto-optimize | camera | recipes | paywall`.

| KPI | Source | Target (first 4 weeks) |
|---|---|---|
| Open rate | opens with matching `sendId` / sends | ≥8% overall, ≥15% `unfinished_edit` |
| Return within 24 h | any telemetry event ≤24 h after send (`?kpi24h=1`) | ≥20% |
| Opt-out rate | `push_opt_out` + `push_marketing_opt_out` / sends | <2% per week; pause a segment above 5% |
| Paywall → purchase (paywall segment) | `paywall_from_push` → `purchase_success` | tracked, no target |

## 7. Ops

All endpoints need `X-Push-Cron-Secret`:

- `GET /api/push/lifecycle/report?days=14&kpi24h=1&cohort=1` — mode, audience, KPIs, last tick, recent decisions, telemetry cohort sizing.
- `POST /api/push/lifecycle/tick` — evaluate now (in dry_run, logs `would_send` only).
- `POST /api/push/lifecycle/ops` `{killSwitch, mode}` — runtime kill switch / downgrade.
- `POST /api/push/lifecycle/preview` `{segment, facts}` — generate copy without sending.

- `POST /api/push/lifecycle/guard` — evaluate the auto kill-switch guardrails now.

From GitHub (no SSH needed locally): **Actions → Push lifecycle report**: `report`, `monitor`,
`dry_run_tick` (only in dry_run), `live_tick` (only in live), `set_env` (PUSH_LIFECYCLE_MODE /
PUSH_EXP1_ENABLED in `/etc/photo-recipes.env`, backup kept, restart), `kill_switch_on`, `kill_switch_off`.

**Auto kill switch** (`autoGuard`, runs after every non-dry tick and from the daily monitor): turns
the runtime kill switch on and logs `lifecycle_auto_kill_switch` when, since go-live and within 7 days,
distinct installs sending `push_opt_out` / `push_marketing_opt_out` exceed **2%** of push-enabled
installs (minimum 2 installs, `PUSH_GUARD_MIN_OPTOUTS`), or when more than **20%** of real APNs
attempts in 24 h fail (minimum 10 attempts; 410/Unregistered/BadDeviceToken uninstalls excluded).
Clear it with `kill_switch_off` after review.

**Daily monitor**: the same workflow runs on a schedule at 10:00 PT (`monitor`): guard + report
(open rate, return within 24 h, opt-out rate, sends per segment) in the job summary and artifact.
The job fails (GitHub emails the owner) whenever the kill switch is on.

## 8. Going live (owner checklist)

1. Ship the iOS build with `anonId` registration + Tips & offers toggle (TestFlight → App Store).
2. Update App Store Connect → App Privacy if needed: Usage Data → Product Interaction is already
   declared for telemetry; confirm "used for: App Functionality, Analytics" covers notification targeting.
3. Run `dry_run_tick` + `report` for a few days; review copy and segment sizes.
4. Test on your TestFlight phone: put your guest id in `PUSH_LIFECYCLE_ALLOWLIST`, set
   `PUSH_LIFECYCLE_MODE=allowlist` in `/etc/photo-recipes.env`, restart.
5. Approve live: `PUSH_LIFECYCLE_MODE=live`, restart. Keep the kill switch handy.
6. Consider retiring the legacy come-shoot evening nudge (`PUSH_EXP1_ENABLED=false`) once the
   lifecycle is live — it sends static copy to every opted-in install and shares the same caps.
