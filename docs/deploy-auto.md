# Auto-deploy (photo.grepawk.com)

**Primary:** GitHub Actions workflow `.github/workflows/deploy-photo-grepawk.yml` (see `docs/deploy-github-actions.md`).

**Backup:** On merge to `main`, the Chief of Staff (CoS) routine `auto-deploy-photo-grepawk-com` can still deploy via `./deploy.sh` using the operator SSH key — useful if Actions secrets are unset.

## Target

| Env | Value |
| --- | --- |
| `DEPLOY_HOST` | `grepawk.com` |
| `DEPLOY_USER` | `root` |
| `SERVER_NAME` | `photo.grepawk.com` |

## Command

```bash
DEPLOY_HOST=grepawk.com DEPLOY_USER=root SERVER_NAME=photo.grepawk.com ./deploy.sh
```

Uses the operator SSH key (e.g. `~/.ssh/id_ed25519`). Do **not** put private keys in the workflow YAML; store them as the `DEPLOY_SSH_KEY` repository secret.

`deploy.sh` writes an HTTP nginx site from `deploy/nginx-photo-recipes.conf.template`, then reinstalls Let's Encrypt TLS with `certbot --nginx --reinstall` when `/etc/letsencrypt/live/$SERVER_NAME` already exists (so HTTPS is not wiped on each deploy). HTML keeps `Cache-Control: no-cache`.

## Verify

```bash
curl -sI https://photo.grepawk.com/ | head -20
curl -s https://photo.grepawk.com/api/health
```

Landing how-it-works cards should show Sense / Reason / Apply / Verify / Capture without step numbers.
