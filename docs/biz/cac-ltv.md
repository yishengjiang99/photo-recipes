# CAC / LTV measurement plan

Biz Dev decision memo for Photo Recipes. Measure cost of acquisition and lifetime value with **stated assumptions** — no invented analytics. Unit economics must respect Stripe (web) vs StoreKit (iOS) fees.

**Status:** Proposed  
**Related:** [saas-playbook.md](./saas-playbook.md), [ios-push-monetization.md](./ios-push-monetization.md) (branch/docs as available), [push-lifecycle.md](./push-lifecycle.md)

---

## Definitions (lock these)

| Metric | Formula | Notes |
|---|---|---|
| **CAC** | (Ad spend + affiliate commissions + creator fees + attributable tool cost) ÷ **paying** starts in window | Do **not** divide by installs. Count **trial→paid** or first successful charge. |
| **LTV (cash)** | Sum of **net** revenue per cohort over time | Net of processor/store fees. |
| **LTV (model)** | ARPU_net × gross margin × (1 / monthly churn) | Early: prefer **90-day observed** cash LTV; extrapolate only with labeled assumptions. |
| **Payback** | CAC ÷ monthly net contribution per payer | Target **&lt; 3 months** while small. |

**Unit = paying subscriber** (Pro monthly or yearly). Free Peek / Auto Optimize users are **funnel**, not LTV until they pay.

### Shipped offer (do not contradict without explicit change)

Free Peek · 1 Auto Optimize/day · Pro **$7.99/mo** or **$59.99/yr** · **7-day** trial.

---

## Fee assumptions (update when contracts change)

| Surface | Gross → net (working assumption) |
|---|---|
| **Web (Stripe)** | ~2.9% + $0.30/tx → keep **~92–97%** of gross for planning |
| **iOS (App Store)** | **15–30%** Apple commission → keep **~70–85%** of gross |

Always report **gross and net** CAC/LTV; iOS can look fine on gross and fail on net.

### ARPU planning anchors (gross)

- Yearly: $59.99 / 12 ≈ **$5.00/mo** cash recognized for MRR-style views
- Monthly: **$7.99/mo**
- Blended ARPU depends on yearly mix — track mix, don’t invent it

**Churn:** unknown early → use **observed M1/M2 retention**. Do not invent a 5% churn number for board math.

---

## What to instrument

1. **Attribution path:** install / first open → `utm` or affiliate code → first Auto Optimize → paywall → trial → paid (Stripe **or** StoreKit).
2. **Cohorts:** week of **first pay**; split **web vs iOS** (fees + channels differ).
3. **Events:** `optimize_day1`, `trial_start`, `paid`, `renew`, `cancel`, `refund`.
4. **Spend ledger:** sheet (or Stripe Sigma later) — Meta/Reddit/creator/workshop costs tagged by campaign week.
5. **Blended + by-channel CAC** — never blended only.

Until volume is tiny: spreadsheet + Stripe / App Store Connect exports is enough. Do **not** build a warehouse first.

---

## Decision rules (when to adjust)

| Condition | Action |
|---|---|
| **CAC &gt; 0.3 × estimated LTV** (or payback &gt; 6 months) | Pause that channel; keep organic / workshop |
| **CAC &lt; 0.3 × LTV** and trial→paid ≥40% and M2 retain ≥60% | Scale that channel ~20–50%/week |
| **iOS CAC OK on gross, fails on net** | Cut iOS paid; prefer web or workshop seats |
| **Optimize-open from push/ads &lt;10%** | Creative/channel wrong — fix before more spend |
| **Refunds + cancels in trial week &gt;25%** | Offer/paywall problem — stop scaling |
| **n &lt; 30 payers in a channel** | Directional only — learn, don’t “optimize” |

**W8 kill/scale (with Marketing):** scale paid acquisition only if weekly activated Auto Optimizers + trial→paid clear agreed bars; otherwise workshops / SEO / affiliates only.

---

## 30-day rollout

| When | Work |
|---|---|
| **Week 1** | Cohort sheet (web/iOS), spend log, define “payer” |
| **Week 2** | Wire attribution on TestFlight + web checkout |
| **Week 3–4** | First channel CAC (workshop/affiliate cost counts even if $0 ads) |
| **Gate** | No Meta/Google scale until LTV proxy from **≥30 payers** and payback math above |

---

## First success / kill metrics

**Success:** Can compute **blended + top-channel CAC** and a **90-day net LTV proxy** for at least one payer cohort.

**Kill vanity:** Treating installs, downloads, or Free Peek opens as ROI.

---

## Owners

| Piece | Owner |
|---|---|
| Definitions, gates, this memo | Biz Dev |
| Stripe events / entitlements | Server Expert |
| StoreKit transactions / Trial | iOS Expert |
| Channel creative & spend ops | Marketing |
| Priority / W8 call | Chief of Staff + user |

## Anti-patterns

- CAC on installs
- LTV on gross App Store revenue without Apple cut
- Scaling ads before Optimize activation and trial→paid are healthy
- Dark-pattern urgency in acquisition creatives (trust &gt; short CAC)
