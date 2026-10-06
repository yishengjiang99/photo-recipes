# In-house telemetry (MySQL)

Privacy-first product / funnel analytics. **No third-party analytics SDKs** for this pipeline. Clients POST allowlisted events to `POST /api/telemetry`. (Separately, the iOS app 1.2+ embeds the AppsFlyer SDK for ad install attribution only; see [Ad attribution](#ad-attribution-ios-12) below.) Persistence requires MySQL; without `MYSQL_*` the API still returns `202` and drops rows (`stored: false`).

## Privacy rules

- Anonymous `anon_id` + short-lived `session_id` only (no accounts required).
- **Never** send photos, camera frames, base64, email, GPS, names, or tokens in `props`.
- Server strips blocked prop keys and oversized strings; optional `ip_hash` (salted SHA-256).
- Push Experiment 1 events stay on `PushAnalytics` → `/api/push/events` (unchanged allowlist).

## Env

| Variable | Purpose |
|----------|---------|
| `MYSQL_URL` | Full mysql2 URL (preferred) |
| `MYSQL_HOST` / `MYSQL_PORT` / `MYSQL_USER` / `MYSQL_PASSWORD` / `MYSQL_DATABASE` | Discrete connection |
| `TELEMETRY_READ_KEY` | Shared secret for `GET /api/telemetry/funnels` |
| `TELEMETRY_IP_SALT` | Optional salt for `ip_hash` (falls back to `SESSION_SECRET`) |

Production: put these in **`/etc/photo-recipes.env`** (systemd `EnvironmentFile=`). Never commit secrets.

## Migration

```bash
mysql "$MYSQL_DATABASE" < server/migrations/001_telemetry_events.sql
```

## Clients

- Web: `src/lib/analytics.ts` — `initAnalytics()` / `track(event, props)`
- iOS: `Analytics.shared.track` → `APIClient.postTelemetry`

## Funnels

See [telemetry-funnels.md](./telemetry-funnels.md). Ops:

```bash
curl -s -H "X-Telemetry-Read-Key: $TELEMETRY_READ_KEY" \
  "https://photo.grepawk.com/api/telemetry/funnels?days=7"
# or
node scripts/funnel-report.mjs --days 7
```

## Ad attribution (iOS 1.2+)

Added for X App Install ads. Everything below is in addition to (not part of) the in-house pipeline.

| Piece | Where | What it sends / stores |
|-------|-------|------------------------|
| SKAdNetwork 4 install registration | `ios/.../Services/Attribution.swift` | First launch only: `updatePostbackConversionValue(0, coarseValue: .low, lockWindow: false)`. Apple applies it to AdAttributionKit too. No identifiers. |
| `SKAdNetworkItems` | `Info.plist` | X (`9yg77x724h`, `n66cz3y3bx`) + AppsFlyer's SKAN partner list (152 IDs, from AppsFlyer's published sheet). Only matters if the app ever shows ads; harmless otherwise. |
| Postback copies | `Info.plist` `NSAdvertisingAttributionReportEndpoint` + `AdAttributionKit.AttributionCopyEndpoint` = `https://photo.grepawk.com` | Apple uses the registrable domain, so devices POST to `https://grepawk.com/.well-known/skadnetwork/report-attribution/` and `/.well-known/appattribution/report-attribution/`. |
| Postback receiver | `server/attribution.ts` (nginx block injected into the grepawk.com site by `deploy.sh`, also on photo.grepawk.com) | Logs one line to journald (`[attribution] postback …`), appends the raw body (incl. Apple signature) to `/var/lib/photo-recipes/attribution-postbacks.jsonl`, and inserts a `skan_postback` / `aak_postback` row in `telemetry_events` (summary fields only). Signatures are not verified yet. |
| AppsFlyer SDK | SPM `AppsFlyerFramework-Static` **7.0.2** (exact) | Only when the build has a dev key (`APPSFLYER_DEV_KEY` GitHub secret → build setting → `Info.plist` `AppsFlyerDevKey`). Install + launches, `first_auto_optimize` (once), `af_start_trial` (product, price, currency), `af_subscribe` (product, revenue, currency). Device IDs: IDFA only if ATT allowed, IDFV, AppsFlyer ID; IP → coarse location. |
| ATT prompt | `PhotoRecipesApp.swift` → `Attribution.requestTrackingAuthorizationAfter` | ~1 s after onboarding finishes (≈3 s after launch for users who onboarded earlier). Never on the first frame, never without a dev key. AppsFlyer `start()` waits up to 60 s for the answer (AppsFlyer 7 deprecated `waitForATTUserAuthorization`; same contract, done in the session-ready listener). Outcome → in-house event `att_prompt_result` (`status`). |

Ops:

```bash
ssh root@grepawk.com 'journalctl -u photo-recipes --since today | grep "\[attribution\]"'
ssh root@grepawk.com 'tail -n 5 /var/lib/photo-recipes/attribution-postbacks.jsonl'
```

Privacy: the policy at `/privacy` (src/pages/Privacy.tsx), `PrivacyInfo.xcprivacy`, and the App Store
label answers in [asc/app-privacy-1.2.md](./asc/app-privacy-1.2.md) must stay in sync.
