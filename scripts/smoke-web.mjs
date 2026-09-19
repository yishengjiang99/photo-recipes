#!/usr/bin/env node
/**
 * Local post-build smoke: assert dist/index.html references hashed assets that exist on disk.
 * Usage: node scripts/smoke-web.mjs   (expects dist/ already built)
 *        npm run build && node scripts/smoke-web.mjs
 */
import { readFileSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const dist = join(root, 'dist')
const indexPath = join(dist, 'index.html')

if (!existsSync(indexPath)) {
  console.error('smoke-web: dist/index.html missing — run npm run build first')
  process.exit(1)
}

const html = readFileSync(indexPath, 'utf8')
const refs = [...html.matchAll(/(?:src|href)="(\/assets\/[^"]+\.(?:js|css))"/g)].map((m) => m[1])

if (refs.length === 0) {
  console.error('smoke-web: no /assets/*.js or *.css references in dist/index.html')
  process.exit(1)
}

let failed = false
for (const ref of refs) {
  const file = join(dist, ref.slice(1)) // drop leading /
  if (!existsSync(file)) {
    console.error(`smoke-web: missing on disk: ${ref} → ${file}`)
    failed = true
  } else {
    console.log(`ok ${ref}`)
  }
}

if (failed) process.exit(1)
console.log(`smoke-web: ${refs.length} asset(s) present on disk`)
