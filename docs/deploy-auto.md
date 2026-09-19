# Auto-deploy (photo.grepawk.com)

On merge to `main`, the Chief of Staff (CoS) routine deploys production via `./deploy.sh` — no GitHub Actions SSH secrets.

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

Uses the operator SSH key (e.g. `~/.ssh/id_ed25519`). Do **not** put private keys in `.github/workflows`.

`deploy.sh` writes an HTTP nginx site from `deploy/nginx-photo-recipes.conf.template`, then reinstalls Let's Encrypt TLS with `certbot --nginx --reinstall` when `/etc/letsencrypt/live/$SERVER_NAME` already exists (so HTTPS is not wiped on each deploy).

## Verify

```bash
curl -sI https://photo.grepawk.com/ | head -20
curl -s https://photo.grepawk.com/api/health
```

Landing how-it-works cards should show Sense / Reason / Apply / Verify / Capture without step numbers.
