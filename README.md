# Photo Recipes

A mobile-friendly web app of photography field presets, transcribed from pages of a “30 Recipes” photography book. Use it on location for steps, gear checklists, and educational camera dials — or ask Grok which recipe fits your scene.

## Stack

- Vite + React 19 + TypeScript
- Tailwind CSS v4
- React Router
- Express + tsx API (`server/`) with xAI Grok tool-calling
- Favorites & checklist progress in `localStorage`

## Presets (from book pages)

| Page | Recipe | Tags |
|------|--------|------|
| 28 | Sharp from Front to Back | Depth of field |
| 30 | How to Blur Moving Subjects | Motion (day / night sub-settings) |
| 32 | Keep a Moving Subject Sharp, With Motion Blur in the Background | Motion (panning + advanced flash) |
| 40 | Shake Up Your Perspective by Getting Down Low | Composition |
| 44 | Capture all the Brights and Darks With HDR | HDR (phone + camera methods) |

Preset data lives in `src/data/presets.ts` (shared with the API).

## Environment

Copy `.env.example` to `.env` and set your xAI key (never commit `.env`):

```bash
cp .env.example .env
# edit .env — set XAI_API_KEY=...
```

```
XAI_API_KEY=
```

The API reads `process.env.XAI_API_KEY` (and loads `.env` via dotenv). Without a key, `POST /api/recommend` returns **503**.

## Run locally (frontend + API)

```bash
cd /workspace/photo-recipes
npm install
npm run dev:all
```

- Web: [http://localhost:5173](http://localhost:5173) (Vite proxies `/api` → API)
- API: [http://localhost:8787](http://localhost:8787)

Or separately:

```bash
npm run dev:server          # API on :8787
npm run dev -- --host 0.0.0.0 --port 5173
```

### Example recommend request

```bash
curl -s http://localhost:8787/api/recommend \
  -H 'Content-Type: application/json' \
  -d '{"message":"sunset canyon with dark foreground","favorites":[]}'
```

Expected JSON shape: `{ "presetId", "reason", "tips", "preset" }`.

Health check (does not reveal the key):

```bash
curl -s http://localhost:8787/api/health
```

## Build

```bash
npm run build
npm run preview
```

## Features

- Preset library cards (title, blurb, gear icons, key settings)
- **Ask Grok** — describe a scene; agentic tool loop (`list_presets` / `get_preset_details` / `select_preset`) picks a catalog recipe
- Detail view: steps, tips, equipment, when-to-use, phone/advanced notes + AI reason banner
- Field checklist / step-by-step mode (persisted per preset)
- Simulated camera dials for recommended settings
- Filter by technique tags + favorites
- Dark photo-app aesthetic


## Deploy (Ubuntu + nginx + systemd)

Use `./deploy.sh` to build locally and publish to a remote Ubuntu host. nginx serves `dist/`; systemd runs the API on port **8787** with `/api` proxied.

```bash
chmod +x deploy.sh
DEPLOY_HOST=your.server.example ./deploy.sh
# or
./deploy.sh -H your.server.example -u ubuntu -p /var/www/photo-recipes -n your.server.example
```

| Variable / flag | Default | Meaning |
|-----------------|---------|---------|
| `DEPLOY_HOST` / `-H` | _(required)_ | SSH host |
| `DEPLOY_USER` / `-u` | `ubuntu` | SSH user |
| `DEPLOY_PATH` / `-p` | `/var/www/photo-recipes` | App directory on server |
| `DEPLOY_SSH_PORT` / `-P` | `22` | SSH port |
| `SERVER_NAME` / `-n` | `_` | nginx `server_name` |
| `--skip-build` | | Reuse existing `dist/` + `server-dist/` |
| `--dry-run` | | Print remote plan without applying |

**What gets synced:** `dist/`, `server-dist/`, `package.json`, `package-lock.json`, `deploy/` templates.  
**Never synced:** `.env`, `.env.*`, `node_modules`, `.git`, `src/`.

### Server secrets

Create `/etc/photo-recipes.env` on the host (deploy creates an empty stub if missing):

```bash
sudo tee /etc/photo-recipes.env <<'ENV'
XAI_API_KEY=your_key_here
PORT=8787
ENV
sudo chmod 640 /etc/photo-recipes.env
sudo chown root:www-data /etc/photo-recipes.env
sudo systemctl restart photo-recipes
```

### Remote services

- `photo-recipes.service` — `node server-dist/index.js` (EnvironmentFile=/etc/photo-recipes.env)
- nginx site `photo-recipes` — static SPA + `location /api/` → `http://127.0.0.1:8787`

```bash
sudo systemctl status photo-recipes
curl -s http://127.0.0.1:8787/api/health
```

Local production smoke test (after `npm run build`):

```bash
XAI_API_KEY=… npm start   # API on :8787; use vite preview or any static server for dist/
```

## License / attribution

Educational personal-use transcription of book recipes. Not affiliated with the book’s publisher or author.
