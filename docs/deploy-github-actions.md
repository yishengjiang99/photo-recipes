# GitHub Actions deploy (photo.grepawk.com)

**Primary** production deploy path. On push to `main` (web-affecting paths) or `workflow_dispatch`, workflow `.github/workflows/deploy-photo-grepawk.yml` builds and runs `./deploy.sh --skip-build`.

The CoS routine `auto-deploy-photo-grepawk-com` can remain as a **backup**; prefer Actions once secrets are set.

## Required secrets & variables

| Kind | Name | Value |
| --- | --- | --- |
| Secret | `DEPLOY_SSH_KEY` | Private SSH key (PEM) that can `ssh root@grepawk.com` |
| Secret (optional) | `DEPLOY_SSH_KNOWN_HOSTS` | `known_hosts` line(s) for `grepawk.com` |
| Variable | `DEPLOY_HOST` | `grepawk.com` |
| Variable | `DEPLOY_USER` | `root` |
| Variable | `SERVER_NAME` | `photo.grepawk.com` |

## One-time setup (`gh`)

From a machine whose key is already authorized on the server:

```bash
# Secret: private key (never commit this file)
gh secret set DEPLOY_SSH_KEY < ~/.ssh/id_ed25519 -R yishengjiang99/photo-recipes

# Optional: pin host key
ssh-keyscan -H grepawk.com | gh secret set DEPLOY_SSH_KNOWN_HOSTS -R yishengjiang99/photo-recipes

# Variables
gh variable set DEPLOY_HOST --body 'grepawk.com' -R yishengjiang99/photo-recipes
gh variable set DEPLOY_USER --body 'root' -R yishengjiang99/photo-recipes
gh variable set SERVER_NAME --body 'photo.grepawk.com' -R yishengjiang99/photo-recipes
```

## What the workflow does

1. `actions/checkout` + Node 20 + `npm ci` + `npm run build`
2. Installs `DEPLOY_SSH_KEY` as `~/.ssh/id_ed25519`
3. Runs `./deploy.sh --skip-build` with `DEPLOY_HOST` / `DEPLOY_USER` / `SERVER_NAME`
4. `deploy.sh` rsyncs `dist/`, `server-dist/`, package files, and `deploy/`; installs systemd + nginx; **reinstalls certbot TLS** when `/etc/letsencrypt/live/$SERVER_NAME` exists
5. Smoke: homepage + `/api/health` must succeed; HTML must keep `Cache-Control: no-cache` (from `deploy/nginx-photo-recipes.conf.template`)

## Manual trigger

```bash
gh workflow run deploy-photo-grepawk.yml -R yishengjiang99/photo-recipes
```

## Local / CoS backup

```bash
DEPLOY_HOST=grepawk.com DEPLOY_USER=root SERVER_NAME=photo.grepawk.com ./deploy.sh
```

See also `docs/deploy-auto.md`.


## Workflow file

Canonical path: `.github/workflows/deploy-photo-grepawk.yml`

If `git push` fails with *refusing to allow an OAuth App to create or update workflow … without `workflow` scope*, refresh auth then push:

```bash
gh auth refresh -h github.com -s workflow,repo
# then add and push .github/workflows/deploy-photo-grepawk.yml
```

Or create the file in the GitHub UI (Actions → New workflow / Add file) with the contents below.

```yaml
# Deploy Photo Recipes web+API to https://photo.grepawk.com
#
# Required repository secret:
#   DEPLOY_SSH_KEY          — private SSH key that can SSH as DEPLOY_USER@DEPLOY_HOST
#
# Optional repository secret:
#   DEPLOY_SSH_KNOWN_HOSTS  — known_hosts lines for DEPLOY_HOST (else ssh-keyscan)
#
# Repository variables (Settings → Variables):
#   DEPLOY_HOST   = grepawk.com
#   DEPLOY_USER   = root
#   SERVER_NAME   = photo.grepawk.com
#
# See docs/deploy-github-actions.md for setup commands.
# Primary deploy path; CoS routine auto-deploy-photo-grepawk-com remains a backup
# (see docs/deploy-auto.md).

name: Deploy photo.grepawk.com

on:
  push:
    branches: [main]
    paths:
      - 'src/**'
      - 'server/**'
      - 'public/**'
      - 'package.json'
      - 'package-lock.json'
      - 'deploy/**'
      - 'deploy.sh'
      - 'index.html'
      - 'vite.config.*'
      - 'tsconfig*.json'
      - '.github/workflows/deploy-photo-grepawk.yml'
  workflow_dispatch:

concurrency:
  group: deploy-photo-grepawk
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node 20
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: npm

      - name: Install dependencies
        run: npm ci

      - name: Build frontend + API
        run: npm run build

      - name: Configure SSH
        env:
          DEPLOY_SSH_KEY: ${{ secrets.DEPLOY_SSH_KEY }}
          DEPLOY_SSH_KNOWN_HOSTS: ${{ secrets.DEPLOY_SSH_KNOWN_HOSTS }}
          DEPLOY_HOST: ${{ vars.DEPLOY_HOST }}
        run: |
          set -euo pipefail
          if [[ -z "${DEPLOY_SSH_KEY:-}" ]]; then
            echo "DEPLOY_SSH_KEY secret is required. See docs/deploy-github-actions.md" >&2
            exit 1
          fi
          if [[ -z "${DEPLOY_HOST:-}" ]]; then
            echo "DEPLOY_HOST variable is required (e.g. grepawk.com)." >&2
            exit 1
          fi
          mkdir -p ~/.ssh
          chmod 700 ~/.ssh
          printf '%s\n' "$DEPLOY_SSH_KEY" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          if [[ -n "${DEPLOY_SSH_KNOWN_HOSTS:-}" ]]; then
            printf '%s\n' "$DEPLOY_SSH_KNOWN_HOSTS" > ~/.ssh/known_hosts
          else
            ssh-keyscan -H "$DEPLOY_HOST" >> ~/.ssh/known_hosts 2>/dev/null || true
          fi
          chmod 600 ~/.ssh/known_hosts
          ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
            "${{ vars.DEPLOY_USER }}@${DEPLOY_HOST}" 'echo ssh-ok'

      - name: Deploy via deploy.sh
        env:
          DEPLOY_HOST: ${{ vars.DEPLOY_HOST }}
          DEPLOY_USER: ${{ vars.DEPLOY_USER }}
          SERVER_NAME: ${{ vars.SERVER_NAME }}
        run: |
          set -euo pipefail
          : "${DEPLOY_HOST:?DEPLOY_HOST variable required}"
          : "${DEPLOY_USER:?DEPLOY_USER variable required}"
          : "${SERVER_NAME:?SERVER_NAME variable required}"
          chmod +x ./deploy.sh
          # Build already done above; deploy.sh rsyncs, configures nginx,
          # reinstalls certbot TLS when a cert exists, then runs smoke checks
          # (including HTML no-cache Cache-Control via nginx template).
          ./deploy.sh --skip-build

      - name: Post-deploy smoke (explicit)
        env:
          SERVER_NAME: ${{ vars.SERVER_NAME }}
        run: |
          set -euo pipefail
          BASE="https://${SERVER_NAME}"
          echo "==> curl -fI ${BASE}/"
          curl -fsSI -m 20 "${BASE}/" | head -30
          echo "==> curl -f ${BASE}/api/health"
          HEALTH="$(curl -fsS -m 20 "${BASE}/api/health")"
          echo "$HEALTH"
          echo "$HEALTH" | grep -q ok
          CC="$(curl -sSI -m 15 "${BASE}/" | tr -d '\r' | grep -i '^cache-control:' || true)"
          echo "Cache-Control: ${CC:-'(none)'}"
          echo "$CC" | grep -qi 'no-cache'
```
