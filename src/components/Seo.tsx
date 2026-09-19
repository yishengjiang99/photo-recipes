import { useEffect } from 'react'
import { DEFAULT_DESCRIPTION, DEFAULT_TITLE, OG_IMAGE_PATH, SITE_URL } from '../lib/site'

type SeoProps = {
  title?: string
  description?: string
  path?: string
  image?: string
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

export function Seo({
  title = DEFAULT_TITLE,
  description = DEFAULT_DESCRIPTION,
  path = '/',
  image = OG_IMAGE_PATH,
  jsonLd,
}: SeoProps) {
  useEffect(() => {
    const url = `${SITE_URL.replace(/\/$/, '')}${path}`
    const imageUrl = image.startsWith('http')
      ? image
      : `${SITE_URL.replace(/\/$/, '')}${image}`

    document.title = title
    upsertMeta('name', 'description', description)
    upsertMeta('property', 'og:title', title)
    upsertMeta('property', 'og:description', description)
    upsertMeta('property', 'og:type', 'website')
    upsertMeta('property', 'og:url', url)
    upsertMeta('property', 'og:image', imageUrl)
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
  }, [title, description, path, image, jsonLd])

  return null
}
