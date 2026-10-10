# Search Console — photo.grepawk.com

- The `grepawk.com` **Domain property** (DNS-verified) already covers `photo.grepawk.com`; no separate property is needed.
- Submit the sitemap in that property: `https://photo.grepawk.com/sitemap.xml` (lists `/`, `/privacy`, `/terms`, `/support`).
- `robots.txt` allows the site and disallows `/api/`, `/admin`, `/success`, `/app/success`.
- Unknown paths return a real `404` (`/404.html`, `noindex`); app routes (`/app/*`, `/admin`, `/success`, `/preset/*`) are client-rendered.
- `/`, `/privacy`, `/terms` and `/support` are pre-rendered at build time (`scripts/prerender.mjs`) with their own title, description, canonical, OG/Twitter tags and JSON-LD.
- The deploy workflow (`Deploy photo.grepawk.com`) snapshots every API route before and after deploy and fails if status codes or headers change, then checks HSTS, HTTP/2, gzip, caching, robots, sitemap, 404 and the single `<h1>`.
