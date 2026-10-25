# ProTune steering packet — Monday, October 26, 2026

**Period covered:** Saturday Oct 18 – Friday Oct 24, 2026 (Pacific), the 7 most recent complete days before Oct 26. Today (Oct 25) is a partial day and is excluded, per the canonical funnel rule. Data pulled Oct 25, 2026. All telemetry is filtered to ProTune only (`app = 'photo-recipes'`); the telemetry table is shared with other apps and unfiltered reads are never used.

## 1. ProTune funnel (canonical, session-based)

| Stage | Sessions | Conversion |
|---|---|---|
| Sessions (any event) | 184 | — |
| Camera open | 105 | 57.1% of sessions |
| Auto-optimize start | 41 | 39.0% of camera sessions |
| Auto-optimize success | 54 | — (see note) |

Revenue stages, same window (distinct sessions): paywall view 44 → plan select 7 → purchase start 7 → **purchase success 3**. Paywall→purchase 6.8% (3/44); sessions→purchase 1.6% (3/184). Trial starts: **0** (still zero all-time).

Note on starts vs successes: successes (54) exceed starts (41) because older app versions emit success without a start event — a known instrumentation gap that is recovering under v1.6, not a conversion change.

Like-for-like context: the previous canonical window (Oct 17–23) read 182 sessions → 107 camera (58.8%) → 38 starts → 57 successes, with 3 purchases. This week is the same funnel at the same volume. Camera share is flat; nothing in the funnel moved materially.

## 2. Purchases — three ledgers, kept separate

### App Store Connect (ledger of record for iOS sales)
**3 purchases in the window**, all StoreKit in-app purchases:
- Mon Oct 19 — Yearly, app v1.5
- Tue Oct 20 — Monthly, app v1.6
- Thu Oct 23 — Yearly, app v1.6

All three buyers were new users. Read from the app's server-verified purchase records with their StoreKit source tags. App Store Connect's own posted figures are the system of record and can lag these by a day or more; the last row-level reconciliation against App Store Connect was the Oct 20 audit (3 posted + 1 then-pending at that date). Apple sends no per-sale email notices, and none arrived in the window.

### Stripe (web sales ledger)
**No completed Stripe purchase is recorded for the window.** One session started a web checkout (checkout_redirect) and did not complete it. A direct read of the Stripe account was not possible for this packet — the Stripe connection is not active in this environment — so this line rests on the app's own records, which is also where the one historical Stripe sale was identified. All-time Stripe sales: exactly 1, from before this window (Oct 20 audit). A completed web purchase does not appear in app telemetry, so telemetry can never prove a Stripe negative on its own; if the Stripe connection is restored, this line should be re-checked against it.

### Telemetry (event counts — not a sales ledger)
3 `purchase_success` events in 3 sessions in the window; 6 events all-time; `trial_start` 0 all-time. Telemetry counts events the app emitted, not money. It is shown only to corroborate the funnel and is never added to either sales ledger.

**Timing that matters for the verdict:** the campaign was stopped on Tue Oct 20 at 8:37 AM PT. Two of the week's three purchases (Oct 20 evening and Oct 23) landed *after* the stop, at $0 ad spend. The purchase rate without ads matches the rate during the final live window.

## 3. Campaign state — verified read-only (Oct 25, 2:00 PM PT)

- **Campaign** "ProTune AI Camera - Installs": **PAUSED** (configured and effective status both PAUSED).
- **Ad set** "ProTune - US iOS - Girl Transformation": configured ACTIVE, effective status **CAMPAIGN_PAUSED** — it cannot deliver while the campaign is paused. This matches how the Oct 20 stop was applied (campaign level).
- **Ads (5):** all effectively paused — 3 configured PAUSED; 2 configured ACTIVE but effective CAMPAIGN_PAUSED.
- **Spend:** Oct 18–20: $117.21 (the final live window, before the Oct 20 stop). **Oct 21–24: $0.00.** Total for the packet period: $117.21, all of it pre-stop.
- Nothing was restarted, edited, or unpaused in preparing this packet. Verification was read-only.

## 4. Verdict: KEEP STOPPED

The math, on this week's own numbers:

- Restarting costs **$40/day = $280/week** at the campaign's preserved budget.
- The funnel produced **3 purchases this week with $0 of ad spend**. If a restart merely matched that rate, cost per purchase would be **~$93**. Even if ads *doubled* purchases to 6/week, cost per purchase would be **~$47**.
- A purchase is worth: Yearly **$29.99** gross — $20.99 net after Apple's 30% (or $25.49 at the 15% rate). Monthly **$4.99** — $3.49 net per month at 30%.
- So one ad-bought customer must stay subscribed roughly **2 to 4.5 years on Yearly**, or **13 to 27 months on Monthly**, just to repay their acquisition cost. Trials — the usual bridge that makes subscription ads pencil out — remain at **zero all-time**, so there is no trial funnel for spend to amplify.
- The funnel itself is not the problem: 57% of sessions reach the camera and the product converts organically at ~3 purchases/week. The constraint is monetization (paywall→purchase 6.8%, no trials), and paid traffic does not change either number.

**Revisit triggers** (any one reopens the question at a future weekly review):
1. Trial starts appear and sustain above zero for a complete week.
2. Paywall→purchase conversion reaches 10%+ over a complete week.
3. A channel demonstrates cost per purchase at or below ~$25 (one Yearly net) before committing a weekly budget.

Until then, spend stays at $0 and the campaign stays paused with its lineup preserved for a one-switch restart.
