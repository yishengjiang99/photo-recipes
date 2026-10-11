# Articles (photo.grepawk.com/articles)

Every article is one folder in `articles/`. The build turns this folder into:

- `/articles/<slug>`: a pre-rendered static page (no app JavaScript) with its own title, meta description,
  canonical, Open Graph/Twitter tags, Smart App Banner, `BlogPosting` + `BreadcrumbList` JSON-LD (with a
  `SoftwareApplication` reference to ProTune on the App Store), breadcrumbs, an App Store CTA at the top and
  the end, and links to the home page and the other articles.
- `/articles`: the index, with the featured article as the hero card (`CollectionPage` + `ItemList` JSON-LD).
- The home page feature card and the nav/footer link (from the featured article, via `src/generated/articles.ts`).
- `dist/sitemap.xml`: `public/sitemap.xml` plus `/articles` and every article with `<lastmod>`; the deploy's
  IndexNow step submits that file.

## Add an article

1. `cp -r articles/_template articles/<slug>` (lowercase-with-dashes; the slug is the URL).
2. Edit `articles/<slug>/article.html`: front matter between the `---` lines, then the HTML body.
   Remove `draft: true` when it's ready.
3. Put images in the same folder (`card.webp` 960x540 for cards, `og.jpg` 1200x630 for link previews).
4. `npm run build` (or `npm run articles` to refresh only the home page manifest), check `dist/articles/`,
   commit and push to `main`. The `Deploy photo.grepawk.com` workflow builds, deploys and submits the new URLs.

## Front matter

| key | required | notes |
| --- | --- | --- |
| `title` | yes | h1 and card title |
| `slug` | no | defaults to the folder name |
| `seoTitle` | no | `<title>`; ` \| ProTune AI Camera` is appended unless it mentions ProTune |
| `description` | yes | meta description, OG/Twitter, cards; keep it unique |
| `date` | yes | `YYYY-MM-DD`, `datePublished` |
| `updated` | no | `dateModified` and sitemap `lastmod` (defaults to `date`) |
| `author` | no | defaults to Yisheng Jiang |
| `eyebrow`, `readingTime` | no | small text above the h1 / in the byline |
| `heroImage`, `heroAlt` | no | card image (file in the folder or absolute URL) and alt text |
| `ogImage` | no | 1200x630 preview image; defaults to the site OG image |
| `featured` | no | `true`: first on /articles, home page card, nav/footer link |
| `navLabel`, `cardTitle`, `cardSummary` | no | nav/footer label and home page card copy |
| `draft` | no | `true` skips the article |

## Body rules

- One h1 per page: the build writes it from `title`; use `h2`/`h3` in the body. The build fails on a second h1,
  invalid JSON-LD, a duplicate title/description or a broken internal link.
- Wrap prose in `<div class="prose">` for the article typography.
- `<!-- include: file.html -->` inlines another file from the folder (used for the Photo School explainer).
  Keep embeds self-contained: scope CSS under one class, prefix ids, wrap scripts in an IIFE, and don't bind
  global keyboard shortcuts.
- Folders starting with `_` are ignored.

The generator is `scripts/prerender-articles.mjs`; nginx serves `/articles` and `/articles/<slug>` from
`dist/articles/**/index.html` (`deploy/nginx-photo-recipes.conf.template`).

## Photo School narration (voiceover)

`articles/photo-school/voiceover/` holds the narration script (`narration.json`: voice, model, per-chapter text
timed to the explainer's chapter durations) and `generate.py`, which calls ElevenLabs and writes
`narration.mp3` (one chapter-aligned track, -16 LUFS, mono 64 kbps) and `transcript.html` (included in the page as
the accessible transcript). Run it on the grepawk.com server, where the API key lives (`/etc/photo-recipes.env`);
the key is never committed or printed. Unchanged chapters reuse their previous take. Usage is in the script header;
the last run's numbers are in `voiceover/report.json`.

The player autoplays muted with a "Tap for sound" hint; the first tap on the player (play/pause, canvas, hint, Space or a
chapter) restarts that chapter with narration on (or turns it on when nothing is playing). The mp3 loads only then,
and uses the audio as its clock so seeking, pause and mute stay in sync.
