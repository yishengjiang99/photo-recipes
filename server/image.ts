/** Image helpers for vision recommend — never log raw bytes. */

export const ALLOWED_IMAGE_MIMES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
])

/** 25MB — matches nginx client_max_body_size + Express json limit (phone JPEG / HEIC re-encodes). */
export const MAX_IMAGE_BYTES = 25 * 1024 * 1024

const MIME_FROM_EXT: Record<string, string> = {
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
}

export function normalizeMime(raw: string | undefined | null): string | null {
  if (!raw) return null
  const mime = raw.split(';')[0]!.trim().toLowerCase()
  return ALLOWED_IMAGE_MIMES.has(mime) ? mime : null
}

export function mimeFromFilename(name: string | undefined): string | null {
  if (!name) return null
  const ext = name.split('.').pop()?.toLowerCase()
  if (!ext) return null
  const mime = MIME_FROM_EXT[ext]
  return mime && ALLOWED_IMAGE_MIMES.has(mime) ? mime : null
}

/**
 * Strip JPEG APP1 (EXIF) and other APPn segments except SOF/SOS/EOI payload.
 * PNG/WebP returned unchanged (canvas re-encode on client already strips metadata).
 */
export function stripJpegExif(buf: Buffer): Buffer {
  if (buf.length < 4 || buf[0] !== 0xff || buf[1] !== 0xd8) return buf
  const out: number[] = [0xff, 0xd8]
  let i = 2
  while (i < buf.length - 1) {
    if (buf[i] !== 0xff) {
      // Entropy-coded data after SOS — copy rest
      for (let j = i; j < buf.length; j++) out.push(buf[j]!)
      break
    }
    // Skip fill bytes
    while (i < buf.length && buf[i] === 0xff) i++
    if (i >= buf.length) break
    const marker = buf[i]!
    i++
    // Standalone markers
    if (marker === 0xd9) {
      out.push(0xff, 0xd9)
      break
    }
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
      out.push(0xff, marker)
      continue
    }
    if (i + 1 >= buf.length) break
    const len = (buf[i]! << 8) | buf[i + 1]!
    if (len < 2 || i + len > buf.length) break
    // Drop APP0–APP15 (0xE0–0xEF) and COM (0xFE)
    const drop = (marker >= 0xe0 && marker <= 0xef) || marker === 0xfe
    if (!drop) {
      out.push(0xff, marker)
      for (let j = i; j < i + len; j++) out.push(buf[j]!)
    }
    i += len
    if (marker === 0xda) {
      // SOS — copy rest including compressed data
      for (let j = i; j < buf.length; j++) out.push(buf[j]!)
      break
    }
  }
  return Buffer.from(out)
}

export function toDataUrl(mime: string, buf: Buffer): string {
  const cleaned = mime === 'image/jpeg' ? stripJpegExif(buf) : buf
  return `data:${mime};base64,${cleaned.toString('base64')}`
}

export function parseDataUrl(
  dataUrl: string,
): { mime: string; buffer: Buffer } | { error: string } {
  const m = /^data:(image\/[a-z0-9+.-]+);base64,([A-Za-z0-9+/=\s]+)$/i.exec(
    dataUrl.trim(),
  )
  if (!m) return { error: 'image must be a data URL (data:image/...;base64,...)' }
  const mime = normalizeMime(m[1]!)
  if (!mime) {
    return { error: 'Unsupported image type. Use JPEG, PNG, or WebP.' }
  }
  let buffer: Buffer
  try {
    buffer = Buffer.from(m[2]!.replace(/\s+/g, ''), 'base64')
  } catch {
    return { error: 'Invalid base64 image data' }
  }
  if (!buffer.length) return { error: 'Empty image data' }
  if (buffer.length > MAX_IMAGE_BYTES) {
    return { error: `Image too large (max ${MAX_IMAGE_BYTES / (1024 * 1024)}MB)` }
  }
  return { mime, buffer }
}
