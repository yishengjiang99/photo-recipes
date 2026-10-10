// After `vite build`: SSR-build scripts/prerender-entry.tsx, render the public routes and write
//   /          -> dist/index.html   (the SPA shell used by every client-side route)
//   /privacy   -> dist/privacy.html, /terms -> dist/terms.html, /support -> dist/support.html
// plus dist/404.html. Each page gets its own title, description, canonical, OG/Twitter and JSON-LD.
// createRoot().render() in src/main.tsx replaces the static markup once JS runs.
import { build } from 'vite'
import react from '@vitejs/plugin-react'
import { readFileSync, writeFileSync, existsSync, rmSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const dist = resolve(root, 'dist')
const out = resolve(root, 'node_modules/.cache/prerender')
rmSync(out, { recursive: true, force: true })
await build({
  configFile: false,
  root,
  logLevel: 'warn',
  plugins: [react()],
  build: { ssr: resolve(root, 'scripts/prerender-entry.tsx'), outDir: out, emptyOutDir: true, minify: false },
  ssr: { noExternal: ['lucide-react'] },
})
const { render } = await import(pathToFileURL(resolve(out, 'prerender-entry.js')).href)
const SITE_URL = 'https://photo.grepawk.com'
const SITE_NAME = 'ProTune AI Camera'

const shell = readFileSync(resolve(dist, 'index.html'), 'utf8')
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
const escText = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;')

function headTags(h) {
  const url = SITE_URL + (h.path === '/' ? '/' : h.path)
  const img = h.image.startsWith('http') ? h.image : SITE_URL + h.image
  const tags = [
    `<title>${escText(h.title)}</title>`,
    `<meta name="description" content="${esc(h.description)}" />`,
    `<link rel="canonical" href="${esc(url)}" />`,
    `<meta property="og:type" content="website" />`,
    `<meta property="og:site_name" content="${esc(SITE_NAME)}" />`,
    `<meta property="og:title" content="${esc(h.title)}" />`,
    `<meta property="og:description" content="${esc(h.description)}" />`,
    `<meta property="og:url" content="${esc(url)}" />`,
    `<meta property="og:image" content="${esc(img)}" />`,
    `<meta property="og:image:type" content="image/jpeg" />`,
    `<meta property="og:image:width" content="1200" />`,
    `<meta property="og:image:height" content="630" />`,
    `<meta property="og:image:alt" content="${esc(h.imageAlt)}" />`,
    `<meta name="twitter:card" content="summary_large_image" />`,
    `<meta name="twitter:title" content="${esc(h.title)}" />`,
    `<meta name="twitter:description" content="${esc(h.description)}" />`,
    `<meta name="twitter:image" content="${esc(img)}" />`,
  ]
  if (h.jsonLd) tags.push(`<script type="application/ld+json" id="seo-jsonld">${JSON.stringify(h.jsonLd).replace(/</g, '\\u003c')}</script>`)
  return tags.join('\n    ')
}

const START = '<!-- head:start -->', END = '<!-- head:end -->'
if (!shell.includes(START) || !shell.includes(END)) throw new Error('index.html is missing the head:start/head:end markers')
if (!shell.includes('<div id="root"></div>')) throw new Error('index.html is missing <div id="root"></div>')

function page(url, { noindex = false } = {}) {
  const { html, head } = render(url)
  if (!head) throw new Error(`no <Seo> rendered for ${url}`)
  const h1 = (html.match(/<h1[\s>]/g) || []).length
  if (h1 !== 1) throw new Error(`${url}: expected exactly one <h1>, found ${h1}`)
  for (const m of html.matchAll(/(?:src|href)="(\/[^"#?]*)"/g)) {
    const p = m[1]
    if (/^\/(app|privacy|terms|support|admin|preset)(\/|$)/.test(p) || p === '/') continue
    if (!existsSync(resolve(dist, '.' + p))) throw new Error(`${url}: missing asset ${p}`)
  }
  let doc = shell.slice(0, shell.indexOf(START)) + START + '\n    ' + headTags(head) + (noindex ? '\n    <meta name="robots" content="noindex" />' : '') + '\n    ' + shell.slice(shell.indexOf(END))
  doc = doc.replace('<div id="root"></div>', `<div id="root">${html}</div>`)
  return doc
}

const routes = { '/': 'index.html', '/privacy': 'privacy.html', '/terms': 'terms.html', '/support': 'support.html' }
for (const [url, file] of Object.entries(routes)) {
  const doc = page(url)
  writeFileSync(resolve(dist, file), doc)
  console.log(`prerendered ${url} -> dist/${file} (${doc.length} bytes)`)
}

// Real 404 page (served by nginx with status 404): static, no app JS.
const notFound = `<!doctype html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<meta name="robots" content="noindex" />
<title>Page not found | ProTune AI Camera</title>
<link rel="icon" type="image/svg+xml" href="/favicon.svg" />
<style>body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#0c0c0f;color:#f4f4f5;font-family:system-ui,-apple-system,sans-serif;text-align:center;padding:1.5rem}a{color:#e0a812}p{opacity:.8}</style>
</head>
<body>
<main>
<h1>Page not found</h1>
<p>This page doesn't exist on photo.grepawk.com.</p>
<p><a href="/">ProTune AI Camera home</a> · <a href="/support">Support</a></p>
</main>
</body>
</html>
`
writeFileSync(resolve(dist, '404.html'), notFound)
console.log('wrote dist/404.html')
