# ProTune AI Camera — App Privacy delta for lifecycle push (1.5)

Full current answers: [`app-privacy-1.2.md`](app-privacy-1.2.md). This file lists only what
changes for the lifecycle push build (1.5). Enter by hand: the public App Store Connect API has
**no App Privacy endpoint** (re-checked 2026-10-10; only the private web-session `/iris` API, which
rejected our API key). Editing App Privacy does not touch the 1.4 submission in review.

**App Store Connect → ProTune AI Camera → App Privacy → Edit → Data Types → Publish.**

## What 1.5 adds

- The app links its push registration to its anonymous telemetry id (`anonId`) so the server can
  choose notification tips from in-app event counts (docs/push-lifecycle.md).
- Optional in-app **"Tips & offers"** switch (off by default) for promotional pushes.
- A coarse, anonymous summary (tier, captures last week as 0 / 1-3 / 4+, favorite look) is sent
  to xAI to word notifications. No identifiers, photos, or prompts.

## Changes to make (everything else stays as in app-privacy-1.2.md)

| Data type | Change | Final purposes | Linked | Tracking |
|---|---|---|---|---|
| Device ID | add **Product Personalization** | Third-Party Advertising; Developer's Advertising or Marketing; Analytics; App Functionality; **Product Personalization** | Yes | Yes (unchanged, Meta) |
| Product Interaction | add **App Functionality** and **Product Personalization** | Developer's Advertising or Marketing; Analytics; **App Functionality**; **Product Personalization** | Yes | Yes (unchanged, Meta) |

No new data types. Resulting label is unchanged at the category level:
- **Data Used to Track You:** Identifiers, Purchases, Usage Data
- **Data Linked to You:** Identifiers, Purchases, Usage Data
- **Data Not Linked to You:** User Content, Diagnostics

The privacy policy (https://photo.grepawk.com/privacy, updated 2026-10-10) already discloses the
personalized notifications, the xAI summary and the Tips & offers opt-in.
