#!/usr/bin/env bash
# Cron entry point: POST /api/push/tick (come-shoot / D1 push nudges).
# Installed by deploy.sh as /etc/cron.d/photo-recipes-push-tick (every 10 min).
# Reads PUSH_CRON_SECRET from /etc/photo-recipes.env without sourcing the whole file.
set -euo pipefail
ENV_FILE="${PHOTO_RECIPES_ENV:-/etc/photo-recipes.env}"
URL="${PUSH_TICK_URL:-http://127.0.0.1:8787/api/push/tick}"
SECRET="$(grep -E '^PUSH_CRON_SECRET=' "$ENV_FILE" | tail -1 | cut -d= -f2- | tr -d '\r' | sed -e 's/^"//' -e 's/"$//')"
if [[ -z "$SECRET" ]]; then
  echo "$(date -Is) push-tick: PUSH_CRON_SECRET missing in $ENV_FILE" >&2
  exit 1
fi
OUT="$(curl -sS -m 60 -X POST -H "X-Push-Cron-Secret: ${SECRET}" -w ' http=%{http_code}' "$URL" || true)"
echo "$(date -Is) ${OUT:0:600}"
