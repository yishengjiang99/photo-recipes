# Push verify (come-shoot / D1)

## Root cause (fixed)
Push Exp 1 required a `shootWindow`, but iOS only sent `pushOptIn` + timezone → **0 shoot windows → 0 sends**.

## What ships now
1. **Server come-shoot / D1 nudge** (`runComeShootNudgeTick`) — no shootWindow. Cron `/api/push/tick` runs come-shoot first, then Exp1.
2. **iOS local notifications** after Allow — D1 at next ~18:00 + daily golden-hour 17:30.
3. Exp1 still works if a user later sets a shoot window.

## Device verify (tester: yisheng.jiang@gmail.com)
1. Install latest TestFlight build with these iOS changes.
2. Capture a photo or run Auto Optimize once → Allow notifications when prompted.
3. Confirm local schedule: Settings → Notifications → ProTune → pending locals, or wait until 17:30 / next 18:00.
4. Server remote nudge (ops):
   ```bash
   curl -sS -X POST https://photo.grepawk.com/api/push/test-send \
     -H "Content-Type: application/json" \
     -H "X-Push-Cron-Secret: $PUSH_CRON_SECRET" \
     -H "X-Push-Test-Allow-Production: 1" \
     -d '{"guestId":"<guest>","title":"Come shoot","body":"Test nudge — open Auto Optimize."}'
   ```
5. Tap notification → should open Auto Optimize (`photo-recipes://auto-optimize`).

## Cron
Host must call `POST /api/push/tick` with `X-Push-Cron-Secret` every ~5–15 min while `PUSH_EXP1_ENABLED=true`. Evening window for come-shoot: **16:30–19:00** user local.
