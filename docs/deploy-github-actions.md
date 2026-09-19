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
