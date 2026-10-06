# In-house telemetry (MySQL)

Privacy-first product / funnel analytics. **No third-party SDKs.** Clients POST allowlisted events to `POST /api/telemetry`. Persistence requires MySQL; without `MYSQL_*` the API still returns `202` and drops rows (`stored: false`).

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
