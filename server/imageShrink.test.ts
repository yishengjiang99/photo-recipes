import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import sharp from 'sharp'
import {
  parseDataUrl,
  shrinkVisionDataUrl,
  VISION_SHRINK_MAX_EDGE,
} from './image.ts'

describe('shrinkVisionDataUrl', () => {
  it('resizes long edge and returns jpeg data URL (in memory)', async () => {
    const buf = await sharp({
      create: {
        width: 2000,
        height: 1200,
        channels: 3,
        background: { r: 40, g: 80, b: 120 },
      },
    })
      .jpeg({ quality: 90 })
      .toBuffer()
    const input = `data:image/jpeg;base64,${buf.toString('base64')}`
    const out = await shrinkVisionDataUrl(input)
    assert.match(out, /^data:image\/jpeg;base64,/)
    const parsed = parseDataUrl(out)
    assert.equal('error' in parsed, false)
    if ('error' in parsed) return
    const meta = await sharp(parsed.buffer).metadata()
    assert.ok((meta.width ?? 0) <= VISION_SHRINK_MAX_EDGE)
    assert.ok((meta.height ?? 0) <= VISION_SHRINK_MAX_EDGE)
    assert.ok(parsed.buffer.length < buf.length)
  })
})
