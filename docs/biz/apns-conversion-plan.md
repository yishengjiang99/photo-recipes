# APNs as conversion mechanism — optimized plan

Biz Dev. Builds on [push-lifecycle.md](./push-lifecycle.md) (PR #19 / branch `docs/push-lifecycle`), [ios-push-monetization.md](./ios-push-monetization.md), Exp 1 server #23 + iOS #22 (merged), and [cac-ltv.md](./cac-ltv.md).

**Status:** Implement next  
**Owner (spec):** Biz Dev · **Owner (impl):** Server Expert (+ iOS for client/APNs sandbox)

---

## What already exists

| Piece | State |
|---|---|
| Pre-alarm shoot brief scheduler, prefs, caps, quiet hours, 50% holdout | **Shipped** (`server/pushScheduler.ts`, `pushPrefs`, routes) |
| Recipe chips + `photo-recipes://auto-optimize` | **Shipped** |
| iOS permission-after-Optimize + client | **Merged** (#22) |
| Push event allowlist → `/api/push/events` | **Shipped** |
| `PUSH_EXP1_ENABLED` flag (default off) | **Shipped** |
| **Live APNs HTTP/2 send** | **Not wired** — `server/apns.ts` stubs even when `APNS_*` is set |
| Lifecycle / monetization memos | On branch PR #19; not all on `main` yet |

**Bottleneck for conversion:** credentials + **real APNs provider**. Without send, Exp 1 cannot move trial/paid.

---

## Conversion job (not “engagement”)

APNs is a **cheap activation → paywall** channel (CAC ≈ ops cost). Every notification must advance one step:

```
permission
  → scheduled brief open
    → Auto Optimize within 2h
      → Free Peek wall (2nd Optimize same day)  OR  Pro habit
        → in-app trial / yearly paywall (StoreKit on iOS)
          → paid
```

**Rule:** Notification never sells IAP. It only opens **Auto Optimize**. Conversion happens **in-app** after intent (wall / trial day 5). No Stripe links from iOS push.

---

## Optimized sequence (narrower than full lifecycle)

### Phase 0 — Unblock send (this sprint) ← **Server**

1. Wire **live APNs** (JWT + HTTP/2) behind `APNS_*`; keep stub if unset.
2. Sandbox vs production host from token `environment`.
3. Ubuntu: document `/etc/photo-recipes.env` keys (`APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, `APNS_P8_PATH` or `APNS_P8_CONTENTS`, `PUSH_EXP1_ENABLED`, `PUSH_CRON_SECRET`).
4. Cron tick already exists — verify systemd timer calls it.
5. **Do not** enable `PUSH_EXP1_ENABLED=true` in prod until sandbox end-to-end works on TestFlight.

**Exit:** TestFlight device receives one pre-alarm (or manual trigger) → tap → Auto Optimize.

### Phase 1 — Conversion experiment (flag on, 14 days)

**Only** `pre_alarm_shoot_brief` (no D1/D3 tip spam, no weather, no streak).

| Metric | Target | Kill |
|---|---|---|
| `push_opened` → `auto_optimize_started` ≤2h | ≥25% of sends | &lt;10% |
| Permission revoke among recipients | &lt;5% | &gt;8% |
| `paywall_from_push` → `trial_start` (secondary) | Lift vs holdout | Flat + high revoke |

Holdout stays **50%**. Attribute with existing push events; join to telemetry `purchase_success` when available ([telemetry-funnels.md](../telemetry-funnels.md)).

### Phase 2 — Conversion nudges (only if Phase 1 hits primary)

Add **one** of these (A/B, not both at once):

| ID | Trigger | Push job | Deep link |
|---|---|---|---|
| **W1** | Free Peek, opted-in, hit day quota (2nd Optimize attempt) | “Tomorrow’s shoot — brief ready” / soft trial context in **body only** | `photo-recipes://auto-optimize` (paywall stays in-app) |
| **T5** | StoreKit trialing, day 5, &lt;3 Optimizes in trial | Value recap → open camera | `photo-recipes://auto-optimize` |

Still **no** Day Pass / web checkout in payload until StoreKit SKU exists.

### Explicitly deferred

Weather/conditions, streak guilt, Web Push, marketing blasts, Day Pass in notification, agent-md edits.

---

## Entitlement-aware copy (server payload)

| Tier | Title/body intent |
|---|---|
| `free` | Shoot brief + open Optimize (never “unlimited”) |
| `trial` | Brief + “trial · Optimize ready” |
| `pro` | Brief only (retention, not paywall) |

Caps: Free ≤3/week, Pro ≤5/week; quiet 21:00–07:00 local unless shoot start is inside quiet.

---

## Server implement checklist (ordered)

- [ ] **P0** Real APNs send path in `server/apns.ts` (replace deferred no-op when creds present)
- [ ] **P0** Env + deploy notes for Ubuntu secrets; sandbox TestFlight proof
- [ ] **P0** Manual/admin “send test brief” endpoint or cron dry-run with force flag (dev-only / secret-gated)
- [ ] **P1** Confirm cron + `PUSH_EXP1_ENABLED` runbook; metrics from `push-events.jsonl` / MySQL if dual-written
- [ ] **P1** Dashboard or script: send → open → optimize≤2h → trial_start by treatment vs holdout
- [ ] **P2** (gate) Implement **W1** or **T5** behind separate flag `PUSH_EXP2_*`

**iOS collaborator:** sandbox/prod token environment accuracy; permission UX already after first Optimize — don’t re-prompt.

**Biz success bar for “APNs works as conversion”:** Phase 1 primary metric + non-zero attributed `trial_start` from treatment within 14 days of flag-on (directional if n small; don’t scale spend on push alone).

---

## Anti-patterns

- Enabling flag before live APNs proven on a device
- Monetization URL in the payload
- Daily spam “engagement” pushes that dilute permission
- Counting installs or sends as conversion success
