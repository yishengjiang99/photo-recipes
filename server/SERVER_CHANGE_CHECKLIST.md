# Server change checklist

Required for any PR that touches `server/**` (or shared API contracts used by the API).

## Must stay green

1. **`npm run test:server`** — includes unit tests **and** the push register E2E (`server/pushRegister.e2e.test.ts`):
   - `GET /api/push/prefs` mints `pr_guest` and returns `tokenCount`
   - `POST /api/push/register` with a mock 64-hex token bumps `tokenCount` to ≥ 1
   - Re-register is idempotent; invalid tokens return 400
2. **CI workflow `Server CI`** runs on PRs/pushes that change `server/**`, `scripts/e2e-push-register.mjs`, or this checklist — do not merge red.
3. If you change push registration, devices, `push_tokens`, or prefs read shape, update `server/pushRegister.e2e.test.ts` in the **same PR**.

## Optional / deploy

- Against a running API: `BASE_URL=https://photo.grepawk.com npm run e2e:push`
- Deploy workflow may run the same smoke post-deploy when `server/**` ships.

## Out of scope for this gate

- Live APNs requires `APNS_*` on the host; unit tests mock HTTP/2 (no Apple calls in CI). Delivery is wired in `server/apns.ts` (HTTP/2 + JWT); keep `PUSH_EXP1_ENABLED=false` until TestFlight sandbox proof via `POST /api/push/test-send`.
- `PUSH_CRON_SECRET` (X-Push-Cron-Secret) can trigger APNs sends via `/api/push/tick` and `/api/push/test-send` — treat as **blast capability**; rotate immediately if leaked.
- iOS client changes (covered by TestFlight workflow separately)
