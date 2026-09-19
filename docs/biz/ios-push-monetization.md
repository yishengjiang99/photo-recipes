# iOS push × TestFlight monetization (short)

Biz Dev notes for Experiment 1 (pre-alarm shoot brief). No agent-md. Pairs with `docs/biz/push-lifecycle.md`, server #23, iOS #22.

## Shipped offer (keep aligned)

| | |
|---|---|
| Free Peek | 1 Auto Optimize / day |
| Pro | $7.99/mo · $59.99/yr |
| Trial | 7-day free (StoreKit intro = `P1W` free on monthly + yearly) |
| Deep link | `photo-recipes://auto-optimize` (confirmed in iOS + `server/pushScheduler.ts`) |
| Recipe chips | `server/pushCatalog.ts` mirrors `src/data/presets.ts` ids |

## TestFlight / IAP rules that affect pushes

1. **Digital unlock = StoreKit only** on iOS. Pushes must not deep-link to web Stripe checkout for Pro / trial / any paid Optimize unlock.
2. **Sandbox:** TestFlight builds use StoreKit sandbox. Trial + subscribe flows are testable; real Apple proceeds only after App Store Connect + production certs.
3. **APNs:** Exp 1 stays **flag-off** until Ubuntu APNs certs/secrets — no fake “push live” marketing claims.
4. **Copy:** Lead with Auto Optimize / shoot brief. Never “speak.” Avoid StoreKit localization that still says only “Ask Grok” in paywall *from push* — Marketing/iOS can sync product strings separately.
5. **Apple fee:** Assume **15–30%** App Store cut on iOS MRR vs Stripe web. Yearly CTA still preferred; don’t invent Day Pass / Season Pass in push until StoreKit SKUs exist (`Products.storekit` today = monthly + yearly only).

## What Exp 1 pushes may / may not do

| OK | Not OK (yet) |
|---|---|
| Open Auto Optimize via `photo-recipes://auto-optimize` | “Buy Day Pass” / web checkout links |
| Entitlement-aware: Free vs trial vs Pro body text | Claiming unlimited Optimize while Free Peek |
| Soft trial CTA **in-app** after Optimize wall | Fake urgency, badge guilt, overnight spam |

## Net for Server / iOS

- URL scheme + chip catalog: **keep as implemented**.
- Monetization from push v1 = **activation → in-app paywall**, not IAP inside the notification.
- When APNs goes live: measure Optimize-open ≤2h (Biz success bar ≥25%); trial starts are secondary.

## Next packaging (only if asked)

Shoot-Day Pass / Season Pass need new StoreKit products + server entitlements before any push CTA.
