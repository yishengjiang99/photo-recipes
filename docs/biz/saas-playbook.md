# Photo Recipes — SaaS / BD Playbook

Biz Dev recommendations for making Photo Recipes a durable SaaS. Grounded in product reality as of 2026-09-18 (repo README + live Stripe funnel).

## Product snapshot

- Soft funnel: Free Peek (browse + 1 Ask/day) → Pro via Stripe Checkout
- Pricing: **$7.99/mo** or **$59.99/yr** (primary CTA), 7-day trial
- ~5 book-derived technique recipes; Grok Ask is the hard paywall
- ICP: travel/landscape hobbyists + workshop alumni
- Position: **field technique assistant** (not filters / AI wrapper)
- North-star (Marketing): weekly activated Askers; kill/scale at W8

**Core constraint:** growth is gated by content depth + habit loop, not pricing polish.

---

## 1. Business model & packaging

### Keep (for now)

- Free Peek browse + 1 Ask/day → Pro is the right shape for hobbyists
- Yearly as primary CTA (~$5/mo effective) for cash + lower churn; monthly as safety valve
- 7-day trial is fine if checkout requires a card

### Change / add soon

| Package | Price | Who | Why |
|---|---|---|---|
| Pro (current) | $7.99/mo or $59.99/yr | Individual hobbyists | Core |
| Workshop Seat (B2B2C) | $3–5 / seat / event or $99–199 site license | Instructors | Highest ROI BD — they distribute |
| Club / Studio | $29–49/mo for 10–25 seats | Camera clubs | Expansion without enterprise sales |
| Lifetime founder (limited) | $149–199 one-time, first 100 | Early believers | Cash + testimonials; cap hard |

**Skip for 90 days:** Teams SSO, white-label OEM, family plans, freemium with ads.

**Packaging rule:** Pro unlocks (1) unlimited Ask, (2) field checklists, (3) photo→recipe when live, (4) favorites sync across devices. Anything that doesn’t drive weekly field use stays Free Peek.

**Legal/ops flag:** README notes educational transcription of a book. Before scale marketing, clarify rights or rewrite recipes in original voice. Licensing risk is a business-model risk.

---

## 2. Revenue path to $1k / $10k MRR

**Math (blended ARPU ~$6–8)**

- **$1k MRR** ≈ 125–170 paying users
- **$10k MRR** ≈ 1,250–1,700 paying users

### $0 → $1k (8–12 weeks if activation works)

1. **Activation rate** — % of Free Peek who Ask ≥2× in week 1 (north-star driver)
2. **Content surface** — need 25–40 technique recipes before paid channels work
3. **Workshop affiliate channel** — 10 instructors × 20 students × 15% trial convert → repeatable paid
4. **Reddit / technique SEO** — slow; compounds after content depth
5. **Micro-creator affiliate** — 20–30% recurring on yearly

### $1k → $10k

Only after W8 scale gate: paid creator/workshop pipeline + SEO + photo-upload as conversion spike.

**Do not buy Meta/Google ads until:** (a) ≥40 recipes, (b) trial→paid ≥40%, (c) month-2 retention ≥60%.

**Cash tip:** Push yearly hard in checkout and post-Ask paywall.

---

## 3. Partnerships & BD — pursue vs ignore

### Pursue hard (next 30–60 days)

1. Workshop instructors / alumni — co-branded field companion + 20–30% recurring + free Pro for instructor
2. Local camera clubs & Meetup photo groups — group codes / Club tier
3. Micro-creators 5k–80k (technique, not gear-unbox)
4. Photo retreat / national park workshop operators

### Pursue later

- Lens/filter accessory brands for affiliate bundles
- Camera-store demo iPads (ops-heavy)

### Ignore / deprioritize

- Big OEMs (Canon/Sony/Nikon) — 12–24 month cycles
- Filter apps / generative editors — wrong ICP
- Broad influencer giveaways with no technique angle
- App Store as primary before habit is proven

---

## 4. Retention / expansion after month 1

Photographers churn when the app isn’t in the bag on a shoot.

- Weekly “conditions” push (weather/season → recipe)
- Trip packs (“Coast weekend,” “City night”)
- Progress / streak on checklist completion
- Photo→recipe loop once vision ships
- New recipe cadence: 2–4/month to Pro first

**Instrument churn killers:** silent cancel after trial with 0 checklist uses; Askers who never open recipe detail; Pro with no open in 14 days.

---

## 5. Moat beyond “thin AI wrapper”

Grok recommend alone is **not** a moat. Build layers:

1. Proprietary technique graph (recipes ↔ conditions ↔ gear ↔ failure modes)
2. Field-proven corpus (checklist completions + consented before/after)
3. Distribution moat via workshops (instructors default to Photo Recipes)
4. Workflow lock-in (synced favorites, trip packs, camera profiles)
5. Brand position: field technique assistant — never drift into filters/AI art

Rewrite away from book-page transcription toward original structured recipes.

---

## 6. Ops: instrument, hire/contract, build vs buy

### Instrument this week

- Funnel: visit → recipe view → Ask → paywall → trial → paid → D7/D30 return
- North-star: weekly activated Askers
- Secondary: checklist_started/completed, recipes/user/week, trial→paid, Ask→paywall

### Build vs buy

| Need | Decision |
|---|---|
| Auth + cross-device sync | **Buy** (Clerk/Auth.js + DB) |
| Email/lifecycle | **Buy** (Resend + Loops/Customer.io) |
| Affiliates | **Buy** (Rewardful / promo codes v1) |
| Recipe CMS | **Build light** |
| Vision upload | **Build** (differentiator) |
| Community forum | **Don’t** |

### Hire/contract order

1. Founder: workshops BD + recipe expansion
2. Contract photographer-educator: 8–12 recipes/mo
3. Contract growth after W8 scale
4. No full-time eng until ~$3k+ MRR or clear bottleneck

---

## 7. Top 5 moves — next 30 days (ROI rank)

1. Expand catalog to ≥20 **original** recipes
2. Ship real accounts + sync favorites/checklists
3. Close 5 workshop/instructor design partners
4. Instrument north-star + trial funnel; write W8 gates
5. Photo→recipe MVP behind Pro

**Explicitly not in top 5:** OEM pitches, App Store, paid ads, community forum, redesign, third pricing tier.

---

## Bottom line

Photo Recipes can be a durable ~$8–12 ARPU hobbyist SaaS if it becomes the **default field companion for workshops and weekend shooters**. Right now the business is content- and habit-constrained, not pricing-constrained. Win the next 30 days on recipes + accounts + 5 instructor partners.

See also: [idea-dump.md](./idea-dump.md) for non-obvious packaging, BD, and retention experiments.
