# Push notification lifecycle

Biz Dev decision memo for Photo Recipes. Goal: engagement + durable Pro revenue without dark patterns. Core paywall moment: **Auto Optimize** (Free Peek = 1/day → Pro unlimited).

**Status:** Proposed  
**Recommended first experiment:** Pre-alarm shoot brief only (2 weeks)  
**Owner (spec):** Biz Dev · **Owner (impl):** Server Expert (+ iOS for APNs / permission UX)

---

## Principles

1. Calendar-tied to real shoots — not daily engagement spam.
2. Ask permission after first successful Auto Optimize, not on install.
3. Free Peek gets usefulness; Pro gets depth. No fake urgency or badge guilt.
4. Caps: ≤3 pushes/week Free Peek; ≤5/week Pro (user can raise in settings).
5. Quiet hours: no pushes 21:00–07:00 user local unless user set a shoot alarm inside that window.
6. Voice/STT never leads a push (“speak to optimize” banned).

**Shipped offer (do not contradict without explicit change request):** Free Peek · 1 Auto Optimize/day · Pro $7.99/mo or $59.99/yr · 7-day trial.

---

## Lifecycle by stage

### 1. Day 0 — permission

| Trigger | Copy intent | Deep link |
|---|---|---|
| After **first successful Auto Optimize** | “Get a brief before your next shoot?” | System permission + in-app prefs |
| Soft deny | No more asks until 3rd lifetime Optimize, then **one** retry | — |
| Hard deny / 2nd decline | Never re-prompt in-app; Settings deep link only if user opens notifications prefs | Settings |

### 2. Activation (D1–D7)

| When | Who | Intent | Paywall? |
|---|---|---|---|
| D1 evening | Opted-in, ≥1 Optimize | “Tomorrow’s light — reminder for Optimize?” | No |
| D3 | No Optimize since install | One craft tip + open viewfinder | No |
| D5 | Hit Free Peek wall (2nd Optimize attempt same day) | Trial or Shoot-Day Pass | **Yes** — only if they attempted Optimize |

### 3. Habit (ongoing)

| Type | Audience | Cadence | Notes |
|---|---|---|---|
| **Pre-alarm shoot brief** | User-set shoot window | Once per scheduled shoot (Fri/Sat typical) | 3 recipe chips + “Open Auto Optimize”. **Ship this first.** |
| Conditions / golden-hour | Opt-in weather | Max 2/week | Requires weather partner or coarse lat/lon; defer if not ready |
| Streak care | ≥2 weekend Optimizes in streak | On miss only | “Streak paused” + optional 24h Pass **once**; no guilt badges |

### 4. Monetization moments (priority order)

1. Soft wall after 2nd same-day Optimize attempt → trial / Day Pass (in-app; push only if already opted in).
2. Post-Optimize delight (~3s after success, in-app preferred): “Unlimited Optimize on Pro” — **≤1 push/week**.
3. Trial day 5: value recap (Optimizes used, checklists touched) → yearly CTA.
4. Win-back D14 quiet: one “new recipe for your last shoot type” → then **30 days silence**.

### 5. Churn / win-back

| Signal | Action |
|---|---|
| Pro, no open 10 days | One trip-pack push; no stack of discounts |
| Cancel intent | Offer pause 1 month or Season Pass before hard cancel (Server + Stripe/StoreKit owners) |

---

## Platform notes (Server / iOS)

| Surface | Notes |
|---|---|
| **iOS** | APNs via StoreKit-era app; permission UX + provisional? Prefer explicit after Optimize. Flag App Store Guideline 4.5.4 / IAP — pushes must not circumvent IAP or shame users into subscribe. |
| **Web** | Web Push optional later; not in v1 experiment. |
| **Entitlements** | Free Peek vs Pro vs trial must match Stripe **and** StoreKit; never promise Unlimited Optimize in a push if entitlement is Free. |
| **Fees** | Day Pass / trial CTAs: web → Stripe; iOS → StoreKit. Don’t deep-link iOS users to web checkout for digital unlock (IAP). |

---

## Data / events to instrument

- `push_permission_prompt_shown` / `accepted` / `denied`
- `push_sent` / `push_opened` (type, stage)
- `auto_optimize_started` within 2h of open (attribution)
- `paywall_from_push` → `trial_start` / `day_pass_purchase` / `subscribe`

No invented analytics — wire these before claiming lift.

---

## Experiment 1 (ship next)

**Name:** Pre-alarm shoot brief  
**Scope:** Users who set a shoot window + granted push. One brief before window; deep link to Auto Optimize.  
**Holdout:** 50% of eligible (if volume allows) or week-over-week before/after if n is tiny.  
**Duration:** 14 days  
**Primary success:** ≥25% of recipients open Auto Optimize within 2h of push.  
**Secondary:** Trial start rate in cohort vs control; unsubscribe / permission revoke rate &lt; 5% of recipients.  
**Kill:** Revoke &gt; 8% or Optimize-open &lt; 10% after 14 days.

---

## Out of scope for Server v1

- Weather/conditions pushes
- Full streak engine
- Web Push
- Marketing broadcast blasts

---

## Handoff checklist (Server Expert)

- [ ] User prefs: shoot window, quiet hours, cap, opt-in flags
- [ ] Token registration + APNs (coordinate iOS Expert)
- [ ] Scheduler for pre-alarm briefs
- [ ] Entitlement-aware copy (Free vs trial vs Pro)
- [ ] Event hooks listed above
- [ ] Feature flag for Experiment 1 + holdout

**Collaborators:** iOS (permission + APNs client), Marketing (final copy strings), Biz Dev (this spec).
