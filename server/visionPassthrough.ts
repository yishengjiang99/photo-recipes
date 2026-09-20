/**
 * Vision image pass-through (Auto Optimize / Photo Vision / describe-scene).
 *
 * Contract:
 * - Accept JPEG/PNG/WebP from JSON (data URL / base64) or multipart field "image".
 * - Hold bytes ONLY in process memory for the lifetime of this HTTP request.
 * - Attach system/recipe prompts + XAI_API_KEY server-side, then forward to api.x.ai.
 * - Never write image bytes to disk, never INSERT into MySQL/JSON stores, never log raw bodies.
 * - After parse, scrub image fields off req.body / clear multipart buffer refs so accidental
 *   logging of req.body cannot leak base64 payloads.
 * - Failures still go through logApiError / optimize_error (message + status only).
 *
 * Multer MUST use memoryStorage() — never diskStorage — for these routes.
 */
import type { Request } from 'express'
import {
  MAX_IMAGE_BYTES,
  mimeFromFilename,
  normalizeMime,
  parseDataUrl,
  toDataUrl,
} from './image.ts'

/** Field names clients may use for the vision payload. */
export const IMAGE_BODY_KEYS = ['image', 'imageBase64', 'imageDataUrl'] as const

export type ParsedVisionImage =
  | { imageDataUrl: string; byteLength: number; mime: string }
  | { error: string }

/**
 * Parse an image from a JSON body into an in-memory data URL (EXIF stripped for JPEG).
 * Does not touch disk.
 */
export function parseImageFromJsonBody(
  body: Record<string, unknown>,
): ParsedVisionImage {
  const imageField = body.image ?? body.imageBase64 ?? body.imageDataUrl
  if (typeof imageField !== 'string' || !imageField.trim()) {
    return {
      error:
        'Provide an image (multipart field "image", or JSON image data URL / base64).',
    }
  }
  const raw = imageField.trim()
  if (raw.startsWith('data:')) {
    const parsed = parseDataUrl(raw)
    if ('error' in parsed) return { error: parsed.error }
    const imageDataUrl = toDataUrl(parsed.mime, parsed.buffer)
    return {
      imageDataUrl,
      byteLength: parsed.buffer.length,
      mime: parsed.mime,
    }
  }
  const mime =
    normalizeMime(typeof body.mime === 'string' ? body.mime : 'image/jpeg') ||
    'image/jpeg'
  try {
    const buffer = Buffer.from(raw.replace(/\s+/g, ''), 'base64')
    if (!buffer.length) return { error: 'Empty image data' }
    if (buffer.length > MAX_IMAGE_BYTES) {
      return {
        error: `Image too large (max ${MAX_IMAGE_BYTES / (1024 * 1024)}MB)`,
      }
    }
    return {
      imageDataUrl: toDataUrl(mime, buffer),
      byteLength: buffer.length,
      mime,
    }
  } catch {
    return { error: 'Invalid base64 image data' }
  }
}

/**
 * Convert a multipart file buffer (multer memoryStorage) into a data URL.
 * Caller should then releaseMultipartImageBuffer(req).
 */
export function dataUrlFromMultipartFile(file: {
  mimetype: string
  originalname: string
  buffer: Buffer
  size: number
}): ParsedVisionImage {
  const mime =
    normalizeMime(file.mimetype) || mimeFromFilename(file.originalname)
  if (!mime) {
    return { error: 'Unsupported image type. Use JPEG, PNG, or WebP.' }
  }
  if (file.size > MAX_IMAGE_BYTES || file.buffer.length > MAX_IMAGE_BYTES) {
    return {
      error: `Image too large (max ${MAX_IMAGE_BYTES / (1024 * 1024)}MB)`,
    }
  }
  return {
    imageDataUrl: toDataUrl(mime, file.buffer),
    byteLength: file.buffer.length,
    mime,
  }
}

/** Drop base64 / data-URL image fields from a parsed JSON body (mutates). */
export function scrubImageFieldsFromBody(
  body: Record<string, unknown> | null | undefined,
): void {
  if (!body || typeof body !== 'object') return
  for (const key of IMAGE_BODY_KEYS) {
    if (key in body) {
      body[key] = '[redacted:vision-passthrough]'
    }
  }
}

/**
 * Release multer's in-memory file buffer after we've copied it into a data URL.
 * Does not write anywhere — only drops the large Buffer reference for GC.
 */
export function releaseMultipartImageBuffer(req: Request): void {
  const file = req.file as Express.Multer.File | undefined
  if (!file) return
  // Replace with empty buffer so any late reference cannot retain the photo.
  ;(file as { buffer: Buffer }).buffer = Buffer.alloc(0)
  ;(file as { size: number }).size = 0
}

/**
 * True when a string looks like an embedded image payload (for tests / sanitizers).
 * Never log such strings.
 */
export function looksLikeImagePayload(value: unknown): boolean {
  if (typeof value !== 'string') return false
  if (/^data:image\//i.test(value)) return true
  // Long base64 blobs
  if (value.length >= 200 && /^[A-Za-z0-9+/=\s]+$/.test(value.slice(0, 400))) {
    return true
  }
  return false
}
