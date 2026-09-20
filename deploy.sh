#!/usr/bin/env bash
# Deploy Photo Recipes (Vite SPA + Express/Grok API) to a remote Ubuntu server.
# Prefer: build locally → rsync dist + server-dist → nginx serves SPA, systemd runs API.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

DEPLOY_HOST="${DEPLOY_HOST:-}"
DEPLOY_USER="${DEPLOY_USER:-ubuntu}"
DEPLOY_PATH="${DEPLOY_PATH:-/var/www/photo-recipes}"
DEPLOY_SSH_PORT="${DEPLOY_SSH_PORT:-22}"
SERVER_NAME="${SERVER_NAME:-_}"
SKIP_BUILD="${SKIP_BUILD:-0}"
DRY_RUN="${DRY_RUN:-0}"

usage() {
  cat <<'USAGE'
Usage: ./deploy.sh [options]

Deploys Photo Recipes to a remote Ubuntu host:
  - Builds frontend + API bundle locally
  - rsyncs dist/, server-dist/, package files (never copies .env)
  - Installs Node 20 if missing, runs npm ci --omit=dev
  - Installs systemd unit photo-recipes.service (API on :8787)
  - Configures nginx to serve dist/ and proxy /api → 127.0.0.1:8787

Options / env vars:
  -H, --host HOST          Remote host (or DEPLOY_HOST)
  -u, --user USER          SSH user (default: ubuntu; DEPLOY_USER)
  -p, --path PATH          Remote app path (default: /var/www/photo-recipes; DEPLOY_PATH)
  -P, --port PORT          SSH port (default: 22; DEPLOY_SSH_PORT)
  -n, --server-name NAME   nginx server_name (default: _; SERVER_NAME)
      --skip-build         Skip local npm run build
      --dry-run            Print remote commands; still builds unless --skip-build
  -h, --help               Show this help

Secrets (manual on server — never auto-copied):
  Create /etc/photo-recipes.env owned by root, mode 640, readable by www-data:

    sudo tee /etc/photo-recipes.env <<'ENV'
    XAI_API_KEY=your_key_here
    PORT=8787
# MYSQL_HOST=
# MYSQL_USER=
# MYSQL_PASSWORD=
# MYSQL_DATABASE=
# TELEMETRY_READ_KEY=
    PUBLIC_BASE_URL=https://your.domain
    SESSION_SECRET=long-random-string
    ADMIN_PASSWORD=choose-a-strong-password
    STRIPE_SECRET_KEY=sk_live_…
    STRIPE_WEBHOOK_SECRET=whsec_…
    RESEND_API_KEY=re_…
    # Optional: RESEND_SEGMENT_ID=…  (waitlist / field-notes segment)
    ENV
    sudo chmod 640 /etc/photo-recipes.env
    sudo chown root:www-data /etc/photo-recipes.env
    sudo systemctl restart photo-recipes

  Stripe webhook URL: https://YOUR_DOMAIN/api/stripe-webhook

Examples:
  DEPLOY_HOST=1.2.3.4 ./deploy.sh
  ./deploy.sh -H recipes.example.com -u ubuntu -p /var/www/photo-recipes -n recipes.example.com
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -H|--host) DEPLOY_HOST="$2"; shift 2 ;;
    -u|--user) DEPLOY_USER="$2"; shift 2 ;;
    -p|--path) DEPLOY_PATH="$2"; shift 2 ;;
    -P|--port) DEPLOY_SSH_PORT="$2"; shift 2 ;;
    -n|--server-name) SERVER_NAME="$2"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$DEPLOY_HOST" ]]; then
  echo "Error: DEPLOY_HOST is required (or pass --host)." >&2
  usage >&2
  exit 1
fi

SSH=(ssh -p "$DEPLOY_SSH_PORT" -o StrictHostKeyChecking=accept-new "${DEPLOY_USER}@${DEPLOY_HOST}")
RSYNC_SSH="ssh -p ${DEPLOY_SSH_PORT} -o StrictHostKeyChecking=accept-new"

echo "==> Target: ${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_SSH_PORT} → ${DEPLOY_PATH}"
echo "==> nginx server_name: ${SERVER_NAME}"

if [[ "$SKIP_BUILD" != "1" ]]; then
  echo "==> Building frontend + API bundle locally…"
  npm run build
else
  echo "==> Skipping build (--skip-build)"
  [[ -d dist && -f server-dist/index.js ]] || {
    echo "Error: dist/ or server-dist/index.js missing; run without --skip-build" >&2
    exit 1
  }
fi

echo "==> Preparing remote directory…"
if [[ "$DRY_RUN" == "1" ]]; then
  echo "[dry-run] ${SSH[*]} mkdir -p ${DEPLOY_PATH}"
else
  "${SSH[@]}" "sudo mkdir -p '${DEPLOY_PATH}' && sudo chown -R '${DEPLOY_USER}:${DEPLOY_USER}' '${DEPLOY_PATH}'"
fi

echo "==> Rsyncing release (excluding secrets, git, node_modules, src)…"
RSYNC_FLAGS=(-az --delete
  --exclude '.git'
  --exclude 'node_modules'
  --exclude '.env'
  --exclude '.env.*'
  --exclude 'src'
  --exclude 'public'
  --exclude '.vscode'
  --exclude '*.local'
  --exclude 'deploy.sh'
)

# Ship only what production needs
if [[ "$DRY_RUN" == "1" ]]; then
  echo "[dry-run] rsync ${RSYNC_FLAGS[*]} dist server-dist package.json package-lock.json deploy → ${DEPLOY_PATH}/"
else
  rsync "${RSYNC_FLAGS[@]}" \
    -e "$RSYNC_SSH" \
    dist/ \
    "${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_PATH}/dist/"

  rsync "${RSYNC_FLAGS[@]}" \
    -e "$RSYNC_SSH" \
    server-dist/ \
    "${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_PATH}/server-dist/"

  rsync -az -e "$RSYNC_SSH" \
    package.json package-lock.json \
    "${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_PATH}/"

  rsync -az -e "$RSYNC_SSH" \
    deploy/ \
    "${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_PATH}/deploy/"
fi

REMOTE_SCRIPT=$(cat <<REMOTE
set -euo pipefail
DEPLOY_PATH='${DEPLOY_PATH}'
SERVER_NAME='${SERVER_NAME}'
cd "\$DEPLOY_PATH"

echo '--> Ensuring Node 20…'
if ! command -v node >/dev/null 2>&1 || [[ "\$(node -v | sed 's/v//' | cut -d. -f1)" -lt 20 ]]; then
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl gnupg
  if [[ ! -f /etc/apt/sources.list.d/nodesource.list ]]; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  fi
  sudo apt-get install -y nodejs
fi
node -v
npm -v

echo '--> Ensuring nginx…'
if ! command -v nginx >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y nginx
fi

echo '--> npm ci --omit=dev…'
npm ci --omit=dev

echo '--> Writing systemd unit…'
TMP_UNIT=\$(mktemp)
sed -e "s|DEPLOY_PATH_PLACEHOLDER|\${DEPLOY_PATH}|g" \\
  "\${DEPLOY_PATH}/deploy/photo-recipes.service.template" > "\$TMP_UNIT"
sudo cp "\$TMP_UNIT" /etc/systemd/system/photo-recipes.service
rm -f "\$TMP_UNIT"

echo '--> Writing nginx site…'
TMP_NGX=\$(mktemp)
sed -e "s|DEPLOY_PATH_PLACEHOLDER|\${DEPLOY_PATH}|g" \\
    -e "s|SERVER_NAME_PLACEHOLDER|\${SERVER_NAME}|g" \\
  "\${DEPLOY_PATH}/deploy/nginx-photo-recipes.conf.template" > "\$TMP_NGX"
sudo cp "\$TMP_NGX" /etc/nginx/sites-available/photo-recipes
rm -f "\$TMP_NGX"
sudo ln -sfn /etc/nginx/sites-available/photo-recipes /etc/nginx/sites-enabled/photo-recipes
# Disable default site if it conflicts on :80
if [[ -L /etc/nginx/sites-enabled/default ]]; then
  sudo rm -f /etc/nginx/sites-enabled/default
fi
# Re-attach Let's Encrypt TLS if a cert already exists for this server_name
# (HTTP-only template would otherwise wipe certbot-managed 443 blocks)
if [[ -d "/etc/letsencrypt/live/\${SERVER_NAME}" ]] && command -v certbot >/dev/null 2>&1; then
  echo '--> Reinstalling TLS via certbot for '"\${SERVER_NAME}"'…'
  sudo certbot --nginx -d "\${SERVER_NAME}" --redirect --non-interactive --reinstall || \
    echo "WARNING: certbot reinstall failed; HTTPS may need manual fix"
fi

echo '--> Permissions for www-data…'
sudo chown -R www-data:www-data "\${DEPLOY_PATH}"
sudo chmod -R u=rwX,g=rX,o=rX "\${DEPLOY_PATH}"

if [[ ! -f /etc/photo-recipes.env ]]; then
  echo 'WARNING: /etc/photo-recipes.env missing.'
  echo 'Create it with XAI_API_KEY=… then: sudo systemctl restart photo-recipes'
  sudo tee /etc/photo-recipes.env >/dev/null <<'ENVSTUB'
# Photo Recipes production env — fill in XAI_API_KEY (do not commit)
XAI_API_KEY=
PORT=8787
ENVSTUB
  sudo chmod 640 /etc/photo-recipes.env
  sudo chown root:www-data /etc/photo-recipes.env
fi

echo '--> Enable & restart services…'
sudo systemctl daemon-reload
sudo systemctl enable photo-recipes
sudo systemctl restart photo-recipes
sudo nginx -t
sudo systemctl reload nginx

echo '--> Status'
sudo systemctl --no-pager --full status photo-recipes || true
curl -sS -m 5 http://127.0.0.1:8787/api/health || true
echo
echo 'Deploy complete.'
REMOTE
)

if [[ "$DRY_RUN" == "1" ]]; then
  echo "[dry-run] remote script:"
  echo "$REMOTE_SCRIPT"
  echo "==> Dry run finished (no remote changes)."
  exit 0
fi

echo "==> Configuring remote host…"
"${SSH[@]}" "bash -s" <<<"$REMOTE_SCRIPT"

echo
echo "==> Post-deploy smoke (https://${SERVER_NAME})…"
SMOKE_BASE="https://${SERVER_NAME}"

echo "--> Health (wait for API after restart)"
HEALTH=""
for i in 1 2 3 4 5 6 7 8 9 10; do
  if HEALTH="$(curl -fsS -m 10 "${SMOKE_BASE}/api/health" 2>/dev/null)" && echo "$HEALTH" | grep -q ok; then
    break
  fi
  HEALTH=""
  sleep 1
done
if [[ -z "$HEALTH" ]] || ! echo "$HEALTH" | grep -q ok; then
  echo "SMOKE FAIL: /api/health did not become ok within ~10s: ${HEALTH:-'(empty/502)'}" >&2
  exit 1
fi
echo "    health ok: $HEALTH"

echo "--> Homepage + hashed assets"
HOME_HTML="$(curl -fsS -m 15 "${SMOKE_BASE}/")"
mapfile -t ASSET_URLS < <(printf '%s' "$HOME_HTML" | grep -oE '/assets/[^"'"'"' ]+\.(js|css)' | sort -u)
if [[ ${#ASSET_URLS[@]} -eq 0 ]]; then
  echo "SMOKE FAIL: no /assets/*.js or *.css found in homepage HTML" >&2
  exit 1
fi
for asset in "${ASSET_URLS[@]}"; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' -m 15 -fI "${SMOKE_BASE}${asset}" || true)"
  if [[ "$code" != "200" ]]; then
    echo "SMOKE FAIL: ${asset} → HTTP ${code} (expected 200)" >&2
    exit 1
  fi
  echo "    ${asset} → 200"
done

echo "--> TLS"
if command -v openssl >/dev/null 2>&1; then
  echo | openssl s_client -servername "${SERVER_NAME}" -connect "${SERVER_NAME}:443" 2>/dev/null \
    | openssl x509 -noout -subject -dates >/dev/null \
    || { echo "SMOKE FAIL: openssl TLS verify for ${SERVER_NAME}" >&2; exit 1; }
  echo "    openssl cert present for ${SERVER_NAME}"
fi
curl -fsSI -m 15 "${SMOKE_BASE}/" >/dev/null || {
  echo "SMOKE FAIL: curl TLS/HTTPS to ${SMOKE_BASE}/" >&2
  exit 1
}
CC="$(curl -sSI -m 15 "${SMOKE_BASE}/" | tr -d '\r' | grep -i '^cache-control:' || true)"
echo "    homepage Cache-Control: ${CC:-'(none)'}"
echo "$CC" | grep -qi 'no-cache' || echo "WARNING: homepage missing no-cache Cache-Control"

echo
echo "==> Done (smoke passed)."
echo "    App path : ${DEPLOY_PATH}"
echo "    API unit : photo-recipes.service (127.0.0.1:8787)"
echo "    Web      : nginx → ${DEPLOY_PATH}/dist , /api proxied"
echo "    Secrets  : edit /etc/photo-recipes.env on the server (never rsynced)"
