// Articles for photo.grepawk.com, generated from the articles/ folder (see articles/README.md).
//
//   node scripts/prerender-articles.mjs --manifest   writes src/generated/articles.ts (home page feature card, nav)
//   node scripts/prerender-articles.mjs              writes dist/articles/index.html, dist/articles/<slug>/index.html,
//                                                    copies each article's images, and writes dist/sitemap.xml
//                                                    (public/sitemap.xml + every article URL)
//
// Every article is one folder: articles/<slug>/article.html (front matter + HTML body) plus any files it uses.
// Folders starting with "_" (e.g. articles/_template) are ignored. Pages are plain static HTML: no app JS.
import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync, copyFileSync, statSync } from 'node:fs'
import { resolve, dirname, extname } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const srcDir = resolve(root, 'articles')
const dist = resolve(root, 'dist')
const SITE_URL = 'https://photo.grepawk.com'
const SITE_NAME = 'ProTune AI Camera'
const APP_STORE = 'https://apps.apple.com/app/id6813991381'
const APP_ID = '6813991381'
const DEFAULT_OG = '/protune-og-1200x630.jpg'
const TRUST = 'Free to try · Pro $7.99/mo or $59.99/yr · 7-day free trial'

const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
const ld = (o) => `<script type="application/ld+json">${JSON.stringify(o).replace(/</g, '\\u003c')}</script>`
const fmtDate = (d) => new Date(d + 'T12:00:00Z').toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric', timeZone: 'UTC' })

// ---------- load ----------
function parseFrontMatter(text, file) {
  const m = text.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/)
  if (!m) throw new Error(`${file}: missing front matter (--- ... ---)`)
  const meta = {}
  for (const line of m[1].split(/\r?\n/)) {
    if (!line.trim() || line.trim().startsWith('#')) continue
    const i = line.indexOf(':')
    if (i < 0) throw new Error(`${file}: bad front matter line "${line}"`)
    const k = line.slice(0, i).trim(), v = line.slice(i + 1).trim().replace(/^(["'])(.*)\1$/, '$2')
    meta[k] = v === 'true' ? true : v === 'false' ? false : v
  }
  return { meta, body: text.slice(m[0].length) }
}

export function loadArticles() {
  if (!existsSync(srcDir)) return []
  const list = []
  for (const name of readdirSync(srcDir).sort()) {
    const dir = resolve(srcDir, name)
    if (name.startsWith('_') || name.startsWith('.') || !statSync(dir).isDirectory()) continue
    const file = resolve(dir, 'article.html')
    if (!existsSync(file)) throw new Error(`articles/${name}: missing article.html`)
    const { meta, body } = parseFrontMatter(readFileSync(file, 'utf8'), `articles/${name}/article.html`)
    for (const k of ['title', 'description', 'date']) if (!meta[k]) throw new Error(`articles/${name}: front matter needs "${k}"`)
    const slug = meta.slug || name
    if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(slug)) throw new Error(`articles/${name}: slug "${slug}" must be lowercase-with-dashes`)
    if (!/^\d{4}-\d{2}-\d{2}$/.test(meta.date)) throw new Error(`articles/${name}: date must be YYYY-MM-DD`)
    if (meta.draft === true) continue
    const html = body.replace(/<!--\s*include:\s*([\w.-]+)\s*-->/g, (_, f) => {
      const p = resolve(dir, f)
      if (!existsSync(p)) throw new Error(`articles/${name}: include ${f} not found`)
      return readFileSync(p, 'utf8')
    })
    const assetUrl = (f) => (!f ? '' : /^https?:|^\//.test(f) ? f : `/articles/${slug}/${f}`)
    list.push({
      dir, slug, html,
      title: meta.title,
      seoTitle: meta.seoTitle || meta.title,
      headline: meta.headline || meta.title,
      description: meta.description,
      date: meta.date,
      updated: meta.updated || meta.date,
      author: meta.author || 'Yisheng Jiang',
      eyebrow: meta.eyebrow || 'ProTune articles',
      readingTime: meta.readingTime || '',
      heroImage: assetUrl(meta.heroImage),
      heroAlt: meta.heroAlt || meta.title,
      ogImage: assetUrl(meta.ogImage) || DEFAULT_OG,
      featured: meta.featured === true,
      navLabel: meta.navLabel || '',
      cardTitle: meta.cardTitle || meta.title,
      cardSummary: meta.cardSummary || meta.description,
      url: `/articles/${slug}`,
    })
  }
  // Featured first, then newest first.
  list.sort((a, b) => (b.featured - a.featured) || b.date.localeCompare(a.date) || a.slug.localeCompare(b.slug))
  const seen = new Set()
  for (const a of list) { if (seen.has(a.slug)) throw new Error(`duplicate article slug ${a.slug}`); seen.add(a.slug) }
  return list
}

// ---------- shared pieces ----------
const CSS = `
@font-face{font-family:"DM Sans Fallback";src:local("Arial"),local("Liberation Sans"),local("Helvetica");size-adjust:101.4%}@font-face{font-family:"Instrument Serif Fallback";src:local("Times New Roman"),local("Liberation Serif"),local("Times");size-adjust:84.2%}
:root{color-scheme:dark;--bg:#0c0c0f;--bg2:#121216;--surface:#16161c;--surface2:#1e1e26;--border:#2a2a33;--ink:#f5f5f7;--ink2:#c4c4cc;--ink3:#8b8b96;--accent:#f43f5e;--accent-soft:#fb7185;--btn:#e11d48;--btn-hover:#be123c;--accent-muted:rgba(244,63,94,.14);--sans:"DM Sans","DM Sans Fallback",ui-sans-serif,system-ui,-apple-system,sans-serif;--display:"Instrument Serif","Instrument Serif Fallback",Georgia,serif}
*,*::before,*::after{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;min-height:100dvh;font-family:var(--sans);background:radial-gradient(ellipse 80% 50% at 50% -20%,rgba(244,63,94,.06),transparent),var(--bg);color:var(--ink);line-height:1.6;-webkit-font-smoothing:antialiased}
a{color:inherit}
img{max-width:100%;height:auto}
.skip{position:absolute;left:-9999px}.skip:focus{left:12px;top:12px;z-index:9;background:var(--surface);padding:8px 12px;border-radius:8px}
.w{max-width:1120px;margin:0 auto;padding:0 16px}
.wn{max-width:820px;margin:0 auto;padding:0 16px}
.hd{border-bottom:1px solid rgba(42,42,51,.6);background:rgba(12,12,15,.9)}
.hd-in{display:flex;align-items:center;justify-content:space-between;gap:12px;padding-top:12px;padding-bottom:12px;flex-wrap:wrap}
.brand{display:flex;align-items:center;gap:10px;text-decoration:none}
.brand-i{display:flex;width:36px;height:36px;align-items:center;justify-content:center;border-radius:12px;background:var(--accent-muted);box-shadow:inset 0 0 0 1px rgba(244,63,94,.3);color:var(--accent-soft)}
.brand-t{font-family:var(--display);font-size:1.15rem;letter-spacing:-.01em}
.nav{display:flex;gap:18px;font-size:.9rem;color:var(--ink2)}
.nav a{text-decoration:none;padding:6px 0}.nav a:hover,.nav a[aria-current=page]{color:var(--ink)}
.btn{display:inline-flex;align-items:center;justify-content:center;min-height:44px;padding:10px 20px;border-radius:999px;background:var(--btn);color:#fff;font-weight:600;font-size:.95rem;text-decoration:none;text-align:center;line-height:1.25}
.btn:hover{background:var(--btn-hover)}
.btn-sm{min-height:36px;padding:6px 14px;font-size:.875rem}
.btn-ghost{background:none;color:var(--ink);box-shadow:inset 0 0 0 1px var(--border)}.btn-ghost:hover{background:var(--surface)}
.crumbs ol{list-style:none;display:flex;flex-wrap:wrap;gap:6px;margin:0;padding:20px 0 0;font-size:.85rem;color:var(--ink3)}
.crumbs li+li::before{content:"›";margin-right:6px}
.crumbs a{text-decoration:none}.crumbs a:hover{color:var(--ink)}
.eyebrow{margin:28px 0 0;font-size:11px;font-weight:600;letter-spacing:.14em;text-transform:uppercase;color:var(--ink3)}
h1{font-family:var(--display);font-weight:400;font-size:clamp(2.1rem,5vw,3.4rem);line-height:1.08;letter-spacing:-.01em;margin:10px 0 0}
.dek{margin:14px 0 0;font-size:1.08rem;color:var(--ink2);max-width:62ch}
.byline{margin:12px 0 0;font-size:.85rem;color:var(--ink3)}
.cta{display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:12px 20px;margin:22px 0;padding:14px 16px;border:1px solid rgba(244,63,94,.35);border-radius:16px;background:var(--surface)}
.cta p{margin:0;font-size:.95rem;color:var(--ink2);flex:1 1 280px}.cta strong{color:var(--ink)}
.cta-end{display:block;text-align:center;padding:32px 20px;margin:48px 0 0}
.cta-end h2{font-family:var(--display);font-weight:400;font-size:clamp(1.7rem,3.6vw,2.3rem);line-height:1.15;margin:0}
.cta-end p{margin:10px auto 18px;max-width:52ch}
.cta-end .row{display:flex;flex-wrap:wrap;gap:12px;justify-content:center}
.small{font-size:.8rem;color:var(--ink3)}
.lede{font-size:1.05rem;color:var(--ink2);margin:0 0 22px}
.prose{margin-top:36px;color:var(--ink2);font-size:1.02rem}
.prose h2{font-family:var(--display);font-weight:400;color:var(--ink);font-size:clamp(1.55rem,3.2vw,2rem);line-height:1.15;margin:2.1em 0 .4em;scroll-margin-top:16px}
.prose p,.prose ul{margin:0 0 1em;max-width:70ch}.prose li{margin:.4em 0}.prose strong{color:var(--ink)}
.prose a{color:var(--accent-soft);text-underline-offset:2px}
.prose code{font-family:ui-monospace,"SF Mono",Menlo,monospace;font-size:.86em;background:var(--surface2);padding:1px 5px;border-radius:5px;color:var(--ink);word-break:break-word}
.more{margin:48px 0 0}.more h2{font-family:var(--display);font-weight:400;font-size:1.7rem;margin:0 0 14px}
.grid{display:grid;gap:16px;grid-template-columns:repeat(auto-fill,minmax(280px,1fr))}
.card{display:flex;flex-direction:column;border:1px solid var(--border);border-radius:16px;background:var(--surface);overflow:hidden;text-decoration:none}
.card:hover{border-color:#3f3f4a}
.card img{display:block;width:100%;aspect-ratio:16/9;object-fit:cover;background:#0e0f11}
.card-b{padding:16px 18px 18px}
.card-b h3,.card-b h2{font-family:var(--display);font-weight:400;font-size:1.4rem;line-height:1.2;margin:0;color:var(--ink)}
.card-b p{margin:8px 0 0;font-size:.92rem;color:var(--ink2)}
.tag{display:inline-block;margin-bottom:8px;font-size:10px;font-weight:600;letter-spacing:.12em;text-transform:uppercase;color:var(--accent-soft);border:1px solid rgba(244,63,94,.5);background:var(--accent-muted);border-radius:999px;padding:2px 10px}
.hero-card{display:grid;margin-top:28px;border-color:rgba(244,63,94,.4)}
@media(min-width:860px){.hero-card{grid-template-columns:1.15fr 1fr}.hero-card img{height:100%;aspect-ratio:auto;min-height:100%}.hero-card .card-b{padding:28px;display:flex;flex-direction:column;justify-content:center}.hero-card h2{font-size:2.1rem}}
.go{margin-top:14px;font-weight:600;color:var(--accent-soft);font-size:.95rem}
.ft{border-top:1px solid var(--border);margin-top:64px;padding:36px 0 40px;color:var(--ink3);font-size:.9rem}
.ft-in{display:flex;flex-wrap:wrap;justify-content:space-between;gap:20px}
.ft nav{display:flex;flex-wrap:wrap;gap:8px 18px}.ft a{text-decoration:none}.ft a:hover{color:var(--ink)}
.ft .brand-t{color:var(--ink)}
main{display:block}
.pse{margin:6px 0 0}.transcript{margin:12px 0 0;border:1px solid var(--border);border-radius:12px;background:var(--surface);padding:10px 16px;color:var(--ink2);font-size:.95rem}.transcript summary{cursor:pointer;color:var(--ink);font-weight:600;min-height:28px}.transcript ol{margin:10px 0 4px;padding-left:1.2em}.transcript li{margin:.45em 0}.transcript .ts{font-family:ui-monospace,Menlo,monospace;font-size:.8em;color:var(--ink3)}.transcript strong{color:var(--ink)}
@media(max-width:640px){.nav{order:3;width:100%;gap:16px}.hide-sm{display:none}}
`.replace(/\n/g, '')

const CAMERA_SVG = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3z"/><circle cx="12" cy="13" r="3"/></svg>'
const FONTS = 'https://fonts.googleapis.com/css2?family=DM+Sans:ital,opsz,wght@0,9..40,400;0,9..40,500;0,9..40,600;0,9..40,700;1,9..40,400&family=Instrument+Serif:ital@0;1&display=swap'

const softwareApp = () => ({
  '@type': 'SoftwareApplication',
  '@id': `${SITE_URL}/#app`,
  name: 'ProTune AI Camera',
  operatingSystem: 'iOS',
  applicationCategory: 'PhotographyApplication',
  url: APP_STORE,
  installUrl: APP_STORE,
  downloadUrl: APP_STORE,
  offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
})
const author = (name) => ({ '@type': 'Person', name, url: SITE_URL + '/' })
const breadcrumbLd = (items) => ({
  '@type': 'BreadcrumbList',
  itemListElement: items.map(([name, path], i) => ({ '@type': 'ListItem', position: i + 1, name, item: SITE_URL + path })),
})

function head({ title, description, path, image, imageAlt, type, jsonLd, extra = '' }) {
  const url = SITE_URL + path
  const img = image.startsWith('http') ? image : SITE_URL + image
  const imgType = /\.png$/i.test(img) ? 'image/png' : /\.webp$/i.test(img) ? 'image/webp' : 'image/jpeg'
  return `<!doctype html>
<html lang="en" class="dark">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<meta name="theme-color" content="#0c0c0f" />
<title>${esc(title)}</title>
<meta name="description" content="${esc(description)}" />
<link rel="canonical" href="${esc(url)}" />
<meta property="og:type" content="${type}" />
<meta property="og:site_name" content="${SITE_NAME}" />
<meta property="og:title" content="${esc(title)}" />
<meta property="og:description" content="${esc(description)}" />
<meta property="og:url" content="${esc(url)}" />
<meta property="og:image" content="${esc(img)}" />
<meta property="og:image:type" content="${imgType}" />
<meta property="og:image:width" content="1200" />
<meta property="og:image:height" content="630" />
<meta property="og:image:alt" content="${esc(imageAlt)}" />
${extra}<meta name="twitter:card" content="summary_large_image" />
<meta name="twitter:title" content="${esc(title)}" />
<meta name="twitter:description" content="${esc(description)}" />
<meta name="twitter:image" content="${esc(img)}" />
<meta name="twitter:image:alt" content="${esc(imageAlt)}" />
<meta name="apple-itunes-app" content="app-id=${APP_ID}" />
<link rel="icon" type="image/svg+xml" href="/favicon.svg" />
<link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png" />
<link rel="apple-touch-icon" href="/apple-touch-icon.png" />
<link rel="manifest" href="/site.webmanifest" />
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link rel="stylesheet" href="${FONTS}" media="print" onload="this.media='all'" />
<noscript><link rel="stylesheet" href="${FONTS}" /></noscript>
<style>${CSS}</style>
${ld({ '@context': 'https://schema.org', '@graph': jsonLd })}
</head>
<body>
<a class="skip" href="#main">Skip to content</a>`
}

function header(articles, current) {
  const feat = articles.find((a) => a.featured && a.navLabel)
  const cur = (p) => (p === current ? ' aria-current="page"' : '')
  return `
<header class="hd"><div class="w hd-in">
<a class="brand" href="/"><span class="brand-i">${CAMERA_SVG}</span><span class="brand-t">ProTune AI Camera</span></a>
<nav class="nav" aria-label="Primary"><a href="/">Home</a><a href="/articles"${cur('/articles')}>Articles</a>${feat ? `<a href="${feat.url}"${cur(feat.url)}>${esc(feat.navLabel)}</a>` : ''}</nav>
<a class="btn btn-sm" href="${APP_STORE}">Download ProTune<span class="hide-sm">&nbsp;on the App Store</span></a>
</div></header>`
}

function footer(articles) {
  const feat = articles.find((a) => a.featured && a.navLabel)
  return `
<footer class="ft"><div class="w ft-in">
<div><a class="brand" href="/"><span class="brand-i">${CAMERA_SVG}</span><span class="brand-t">ProTune AI Camera</span></a><p style="margin:10px 0 0">AI camera app for iPhone with field recipes.</p></div>
<nav aria-label="Footer"><a href="/">Home</a><a href="/articles">Articles</a>${feat ? `<a href="${feat.url}">${esc(feat.navLabel)}</a>` : ''}<a href="${APP_STORE}">ProTune on the App Store</a><a href="/privacy">Privacy</a><a href="/terms">Terms</a><a href="/support">Support</a></nav>
</div><p class="w" style="margin-top:20px">© 2026 ProTune AI Camera</p></footer>
</body>
</html>
`
}

const topCta = `<aside class="cta" aria-label="Get the app"><p><strong>ProTune AI Camera</strong> for iPhone sets shutter, ISO, EV, white balance and focus for the scene with one tap.</p><a class="btn" href="${APP_STORE}">Download ProTune on the App Store</a></aside>`
const endCta = `<aside class="cta cta-end" aria-label="Get the app"><h2>Try Auto Optimize on your iPhone</h2><p>Point at the scene, tap Auto Optimize, and ProTune writes real camera settings before you press the shutter.</p><div class="row"><a class="btn" href="${APP_STORE}">Download ProTune on the App Store</a><a class="btn btn-ghost" href="/">See how ProTune AI Camera works</a></div><p class="small" style="margin:14px 0 0">${TRUST}</p></aside>`

function card(a, { hero = false, eager = false, level = 'h3' } = {}) {
  const img = a.heroImage ? `<img src="${esc(a.heroImage)}" alt="${esc(a.heroAlt)}" width="960" height="540"${eager ? ' fetchpriority="high"' : ' loading="lazy"'} decoding="async" />` : ''
  return `<a class="card${hero ? ' hero-card' : ''}" href="${a.url}">${img}<div class="card-b">${a.featured ? '<span class="tag">Featured</span>' : ''}<${level}>${esc(a.title)}</${level}><p>${esc(a.description)}</p><p class="small" style="margin-top:10px">${esc(a.author)} · <time datetime="${a.date}">${fmtDate(a.date)}</time>${a.readingTime ? ' · ' + esc(a.readingTime) : ''}</p><span class="go">${hero ? 'Watch the explainer and read →' : 'Read the article →'}</span></div></a>`
}

// ---------- pages ----------
function articlePage(a, all) {
  const others = all.filter((x) => x.slug !== a.slug)
  const crumbs = [['Home', '/'], ['Articles', '/articles'], [a.navLabel || a.title, a.url]]
  const jsonLd = [
    {
      '@type': 'BlogPosting',
      '@id': `${SITE_URL}${a.url}#article`,
      headline: a.headline,
      name: a.title,
      description: a.description,
      image: [SITE_URL + (a.ogImage.startsWith('/') ? a.ogImage : '/' + a.ogImage)],
      datePublished: a.date,
      dateModified: a.updated,
      author: author(a.author),
      publisher: author(a.author),
      mainEntityOfPage: { '@type': 'WebPage', '@id': SITE_URL + a.url },
      url: SITE_URL + a.url,
      inLanguage: 'en',
      isPartOf: { '@type': 'Blog', '@id': `${SITE_URL}/articles#blog`, name: 'ProTune articles', url: `${SITE_URL}/articles` },
      about: softwareApp(),
    },
    breadcrumbLd(crumbs),
  ]
  const extra = `<meta property="article:published_time" content="${a.date}" />\n<meta property="article:modified_time" content="${a.updated}" />\n<meta property="article:author" content="${esc(a.author)}" />\n`
  return head({ title: /protune/i.test(a.seoTitle) ? a.seoTitle : `${a.seoTitle} | ${SITE_NAME}`, description: a.description, path: a.url, image: a.ogImage, imageAlt: a.heroAlt, type: 'article', jsonLd, extra })
    + header(all, a.url) + `
<main id="main" class="wn">
<nav class="crumbs" aria-label="Breadcrumb"><ol>${crumbs.map(([n, p], i) => i === crumbs.length - 1 ? `<li aria-current="page">${esc(n)}</li>` : `<li><a href="${p}">${esc(n)}</a></li>`).join('')}</ol></nav>
<article>
<header>
<p class="eyebrow">${esc(a.eyebrow)}</p>
<h1>${esc(a.headline)}</h1>
<p class="dek">${esc(a.description)}</p>
<p class="byline">By ${esc(a.author)} · <time datetime="${a.date}">${fmtDate(a.date)}</time>${a.readingTime ? ' · ' + esc(a.readingTime) : ''}</p>
</header>
${topCta}
${a.html.trim()}
${endCta}
</article>
<section class="more" aria-labelledby="more-h"><h2 id="more-h">${others.length ? 'More ProTune articles' : 'Keep reading'}</h2>
${others.length ? `<div class="grid">${others.map((o) => card(o)).join('')}</div>` : ''}
<p class="small" style="margin-top:14px;font-size:.95rem"><a href="/articles" style="color:var(--accent-soft)">All ProTune articles</a> · <a href="/" style="color:var(--accent-soft)">ProTune AI Camera home</a></p>
</section>
</main>` + footer(all)
}

function indexPage(all) {
  const [lead, ...rest] = all
  const title = 'Articles: Photography and iPhone Camera Settings | ProTune'
  const description = 'ProTune articles on the photography behind Auto Optimize: exposure, shutter and ISO, metering, white balance, light and composition for iPhone camera builders and photographers.'
  const crumbs = [['Home', '/'], ['Articles', '/articles']]
  const jsonLd = [
    {
      '@type': 'CollectionPage',
      '@id': `${SITE_URL}/articles#page`,
      name: 'ProTune articles',
      description,
      url: `${SITE_URL}/articles`,
      inLanguage: 'en',
      about: softwareApp(),
      mainEntity: {
        '@type': 'ItemList',
        itemListElement: all.map((a, i) => ({ '@type': 'ListItem', position: i + 1, url: SITE_URL + a.url, name: a.title })),
      },
    },
    breadcrumbLd(crumbs),
  ]
  return head({ title, description, path: '/articles', image: lead?.ogImage || DEFAULT_OG, imageAlt: lead?.heroAlt || 'ProTune AI Camera', type: 'website', jsonLd })
    + header(all, '/articles') + `
<main id="main" class="w">
<nav class="crumbs" aria-label="Breadcrumb"><ol><li><a href="/">Home</a></li><li aria-current="page">Articles</li></ol></nav>
<header>
<p class="eyebrow">ProTune articles</p>
<h1>Photography and camera settings, explained</h1>
<p class="dek">Notes from building <a href="/" style="color:var(--accent-soft)">ProTune AI Camera</a>: the photography behind each Auto Optimize decision, for photographers and camera builders.</p>
</header>
${topCta}
${lead ? card(lead, { hero: true, eager: true, level: 'h2' }) : '<p>No articles yet.</p>'}
${rest.length ? `<section class="more" aria-labelledby="all-h"><h2 id="all-h">All articles</h2><div class="grid">${rest.map((a) => card(a)).join('')}</div></section>` : ''}
${endCta}
</main>` + footer(all)
}

// ---------- outputs ----------
function writeManifest(all) {
  const items = all.map((a) => ({ slug: a.slug, url: a.url, title: a.title, cardTitle: a.cardTitle, cardSummary: a.cardSummary, navLabel: a.navLabel, image: a.heroImage, imageAlt: a.heroAlt, date: a.date, featured: a.featured }))
  const out = `// GENERATED by scripts/prerender-articles.mjs --manifest from articles/*/article.html. Do not edit by hand.
export type ArticleSummary = {
  slug: string
  url: string
  title: string
  cardTitle: string
  cardSummary: string
  navLabel: string
  image: string
  imageAlt: string
  date: string
  featured: boolean
}

export const ARTICLES: ArticleSummary[] = ${JSON.stringify(items, null, 2)}

export const FEATURED_ARTICLE: ArticleSummary | undefined = ARTICLES.find((a) => a.featured) ?? ARTICLES[0]
`
  const p = resolve(root, 'src/generated/articles.ts')
  mkdirSync(dirname(p), { recursive: true })
  if (!existsSync(p) || readFileSync(p, 'utf8') !== out) writeFileSync(p, out)
  console.log(`articles manifest: ${items.length} article(s) -> src/generated/articles.ts`)
}

function check(path, doc) {
  const h1 = (doc.match(/<h1[\s>]/g) || []).length
  if (h1 !== 1) throw new Error(`${path}: expected exactly one <h1>, found ${h1}`)
  for (const m of doc.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)) JSON.parse(m[1])
  for (const m of doc.matchAll(/(?:src|href)="(\/[^"#?]*)"/g)) {
    const p = m[1]
    if (/^\/(app|privacy|terms|support)?$/.test(p) || p === '/articles') continue
    const f = resolve(dist, '.' + p)
    if (!existsSync(f) && !existsSync(resolve(f, 'index.html'))) throw new Error(`${path}: broken internal link ${p}`)
  }
}

function writeSitemap(all) {
  const base = readFileSync(resolve(root, 'public/sitemap.xml'), 'utf8')
  const newest = all.reduce((m, a) => (a.updated > m ? a.updated : m), '0000-00-00')
  const urls = [['/articles', newest], ...all.map((a) => [a.url, a.updated])]
    .filter(([p]) => !base.includes(`<loc>${SITE_URL}${p}</loc>`))
    .map(([p, d]) => `  <url><loc>${SITE_URL}${p}</loc><lastmod>${d}</lastmod></url>`)
  const xml = all.length ? base.replace('</urlset>', urls.join('\n') + '\n</urlset>') : base
  writeFileSync(resolve(dist, 'sitemap.xml'), xml)
  console.log(`sitemap: dist/sitemap.xml (+${urls.length} article URL(s))`)
}

function build(all) {
  if (!existsSync(resolve(dist, 'index.html'))) throw new Error('dist/ missing: run vite build first')
  // copy article assets (everything in the folder except the source files)
  for (const a of all) {
    const out = resolve(dist, 'articles', a.slug)
    mkdirSync(out, { recursive: true })
    for (const f of readdirSync(a.dir)) {
      if (extname(f) === '.html' || extname(f) === '.md' || f.startsWith('.') || statSync(resolve(a.dir, f)).isDirectory()) continue
      copyFileSync(resolve(a.dir, f), resolve(out, f))
    }
  }
  const pages = [['/articles', resolve(dist, 'articles/index.html'), indexPage(all)], ...all.map((a) => [a.url, resolve(dist, 'articles', a.slug, 'index.html'), articlePage(a, all)])]
  for (const [, file, doc] of pages) { mkdirSync(dirname(file), { recursive: true }); writeFileSync(file, doc) }
  const titles = new Set(), descs = new Set()
  for (const [path, file, doc] of pages) {
    check(path, doc)
    const t = doc.match(/<title>([^<]*)<\/title>/)[1], d = doc.match(/<meta name="description" content="([^"]*)"/)[1]
    if (titles.has(t) || descs.has(d)) throw new Error(`${path}: title/description not unique`)
    titles.add(t); descs.add(d)
    console.log(`article page ${path} -> ${file.replace(root + '/', '')} (${doc.length} bytes)`)
  }
  writeSitemap(all)
}

const all = loadArticles()
writeManifest(all)
if (!process.argv.includes('--manifest')) build(all)
