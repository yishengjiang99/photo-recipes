import { useEffect } from 'react'
import {
  DEFAULT_DESCRIPTION,
  DEFAULT_TITLE,
  OG_IMAGE_ALT,
  OG_IMAGE_HEIGHT,
  OG_IMAGE_PATH,
  OG_IMAGE_WIDTH,
  SITE_NAME,
  SITE_URL,
} from '../lib/site'

type SeoProps = {
  title?: string
  description?: string
  path?: string
  image?: string
  imageAlt?: string
  jsonLd?: Record<string, unknown> | Record<string, unknown>[]
}

function upsertMeta(attr: 'name' | 'property', key: string, content: string) {
  let el = document.head.querySelector(`meta[${attr}="${key}"]`) as HTMLMetaElement | null
  if (!el) {
    el = document.createElement('meta')
    el.setAttribute(attr, key)
    document.head.appendChild(el)
  }
  el.content = content
}

function upsertLink(rel: string, href: string) {
  let el = document.head.querySelector(`link[rel="${rel}"]`) as HTMLLinkElement | null
  if (!el) {
    el = document.createElement('link')
    el.rel = rel
    document.head.appendChild(el)
  }
  el.href = href
}

/** Filled during build-time prerendering (scripts/prerender.tsx); unused in the browser. */
export const ssrHead: { current: Required<Omit<SeoProps, 'jsonLd'>> & { jsonLd?: SeoProps['jsonLd'] } | null } = {
  current: null,
}

export function Seo({
  title = DEFAULT_TITLE,
  description = DEFAULT_DESCRIPTION,
  path = '/',
  image = OG_IMAGE_PATH,
  imageAlt = OG_IMAGE_ALT,
  jsonLd,
}: SeoProps) {
  if (import.meta.env.SSR) ssrHead.current = { title, description, path, image, imageAlt, jsonLd }
  useEffect(() => {
    const origin = SITE_URL.replace(/\/$/, '')
    const url = `${origin}${path}`
    const imageUrl = image.startsWith('http') ? image : `${origin}${image}`

    document.title = title
    upsertMeta('name', 'description', description)
    upsertMeta('property', 'og:title', title)
    upsertMeta('property', 'og:description', description)
    upsertMeta('property', 'og:type', 'website')
    upsertMeta('property', 'og:url', url)
    upsertMeta('property', 'og:site_name', SITE_NAME)
    upsertMeta('property', 'og:image', imageUrl)
    upsertMeta('property', 'og:image:width', String(OG_IMAGE_WIDTH))
    upsertMeta('property', 'og:image:height', String(OG_IMAGE_HEIGHT))
    upsertMeta('property', 'og:image:alt', imageAlt)
    upsertMeta('name', 'twitter:card', 'summary_large_image')
    upsertMeta('name', 'twitter:title', title)
    upsertMeta('name', 'twitter:description', description)
    upsertMeta('name', 'twitter:image', imageUrl)
    upsertLink('canonical', url)

    const scriptId = 'seo-jsonld'
    const existing = document.getElementById(scriptId)
    if (existing) existing.remove()
    if (jsonLd) {
      const script = document.createElement('script')
      script.id = scriptId
      script.type = 'application/ld+json'
      script.text = JSON.stringify(jsonLd)
      document.head.appendChild(script)
    }

    return () => {
      const s = document.getElementById(scriptId)
      if (s) s.remove()
    }
  }, [title, description, path, image, imageAlt, jsonLd])

  return null
}
