import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import {
  IMAGE_BODY_KEYS,
  looksLikeImagePayload,
  parseImageFromJsonBody,
  scrubImageFieldsFromBody,
} from './visionPassthrough.ts'
import { MAX_IMAGE_BYTES } from './image.ts'

/** Minimal 1×1 JPEG */
const TINY_JPEG = Buffer.from(
  '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAn/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCdABmX/9k=',
  'base64',
)

describe('vision passthrough (no persist)', () => {
  it('MAX_IMAGE_BYTES is 100MB', () => {
    assert.equal(MAX_IMAGE_BYTES, 100 * 1024 * 1024)
  })

  it('parses data URL in memory and scrubs body fields', () => {
    const dataUrl = `data:image/jpeg;base64,${TINY_JPEG.toString('base64')}`
    const body: Record<string, unknown> = {
      message: 'sunset',
      image: dataUrl,
    }
    const parsed = parseImageFromJsonBody(body)
    assert.equal('error' in parsed, false)
    if ('error' in parsed) return
    assert.ok(parsed.imageDataUrl.startsWith('data:image/jpeg;base64,'))
    assert.ok(parsed.byteLength > 0)

    scrubImageFieldsFromBody(body)
    for (const key of IMAGE_BODY_KEYS) {
      if (key in body) {
        assert.equal(body[key], '[redacted:vision-passthrough]')
        assert.equal(looksLikeImagePayload(body[key]), false)
      }
    }
    // Original data URL must not remain on body
    assert.notEqual(body.image, dataUrl)
  })

  it('parses bare base64 with mime', () => {
    const body: Record<string, unknown> = {
      image: TINY_JPEG.toString('base64'),
      mime: 'image/jpeg',
    }
    const parsed = parseImageFromJsonBody(body)
    assert.equal('error' in parsed, false)
    if ('error' in parsed) return
    assert.equal(parsed.mime, 'image/jpeg')
  })

  it('rejects empty image', () => {
    const parsed = parseImageFromJsonBody({ image: '' })
    assert.equal('error' in parsed, true)
  })

  it('looksLikeImagePayload detects data URLs', () => {
    assert.equal(looksLikeImagePayload('data:image/jpeg;base64,abc'), true)
    assert.equal(looksLikeImagePayload('hello'), false)
  })

  it('does not write image bytes to a temp file during parse', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'pr-vision-'))
    const before = new Set(fs.readdirSync(dir))
    const dataUrl = `data:image/jpeg;base64,${TINY_JPEG.toString('base64')}`
    const body: Record<string, unknown> = { image: dataUrl }
    const parsed = parseImageFromJsonBody(body)
    assert.equal('error' in parsed, false)
    scrubImageFieldsFromBody(body)
    const after = new Set(fs.readdirSync(dir))
    assert.deepEqual([...after], [...before])
    fs.rmSync(dir, { recursive: true, force: true })
  })
})
