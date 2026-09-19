import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { parsePhoneTargets } from './recommend.ts'

function isError(r: ReturnType<typeof parsePhoneTargets>): r is { error: string } {
  return typeof r === 'object' && r !== null && 'error' in r
}

describe('parsePhoneTargets', () => {
  it('accepts empty object', () => {
    const r = parsePhoneTargets({})
    assert.equal(isError(r), false)
    assert.deepEqual(r, {})
  })

  it('accepts legacy-only keys', () => {
    const r = parsePhoneTargets({
      shutter: '1/60',
      iso: '100',
      ev: '+0.7',
      whiteBalance: 'auto',
      focusMode: 'locked',
      zoom: 2,
      focusPoint: { x: 0.5, y: 0.5 },
    })
    assert.equal(isError(r), false)
    if (isError(r)) return
    assert.equal(r.shutter, '1/60')
    assert.equal(r.iso, '100')
    assert.equal(r.ev, '+0.7')
    assert.equal(r.whiteBalance, 'auto')
    assert.equal(r.focusMode, 'locked')
    assert.equal(r.zoom, 2)
    assert.deepEqual(r.focusPoint, { x: 0.5, y: 0.5 })
  })

  it('accepts new in-range keys', () => {
    const r = parsePhoneTargets({
      exposureDurationSec: 1 / 60,
      lensPosition: 0.42,
      torch: { mode: 'on', level: 0.5 },
      flash: 'auto',
      lowLightBoost: true,
      videoHDR: false,
      cameraDevice: 'wide',
      frameRate: 30,
      preferFormatHint: '4k60',
      bracket: { stops: [-1, 0, 1], count: 3 },
      monitorSubjectAreaChange: true,
      maxPhotoDimensions: { width: 4032, height: 3024 },
      previewLUT: 'neutral',
      simulatedAperture: 1.8,
    })
    assert.equal(isError(r), false)
    if (isError(r)) return
    assert.equal(r.exposureDurationSec, 1 / 60)
    assert.equal(r.lensPosition, 0.42)
    assert.deepEqual(r.torch, { mode: 'on', level: 0.5 })
    assert.equal(r.flash, 'auto')
    assert.equal(r.lowLightBoost, true)
    assert.equal(r.videoHDR, false)
    assert.equal(r.cameraDevice, 'wide')
    assert.equal(r.frameRate, 30)
    assert.equal(r.preferFormatHint, '4k60')
    assert.deepEqual(r.bracket, { stops: [-1, 0, 1], count: 3 })
    assert.equal(r.monitorSubjectAreaChange, true)
    assert.deepEqual(r.maxPhotoDimensions, { width: 4032, height: 3024 })
    assert.equal(r.previewLUT, 'neutral')
    assert.equal(r.simulatedAperture, 1.8)
  })

  it('ignores unknown keys and keeps known keys', () => {
    const r = parsePhoneTargets({
      shutter: '1/125',
      iso: 200,
      totallyUnknown: 'nope',
      futureLever: { nested: true },
      aperture: 'f/1.8',
    })
    assert.equal(isError(r), false)
    if (isError(r)) return
    assert.equal(r.shutter, '1/125')
    assert.equal(r.iso, 200)
    assert.equal('totallyUnknown' in r, false)
    assert.equal('futureLever' in r, false)
    assert.equal('aperture' in r, false)
  })

  it('rejects lensPosition out of range', () => {
    const r = parsePhoneTargets({ lensPosition: 1.5 })
    assert.equal(isError(r), true)
    if (!isError(r)) return
    assert.match(r.error, /lensPosition/)
  })

  it('rejects exposureDurationSec of 0', () => {
    const r = parsePhoneTargets({ exposureDurationSec: 0 })
    assert.equal(isError(r), true)
    if (!isError(r)) return
    assert.match(r.error, /exposureDurationSec/)
  })

  it('rejects exposureDurationSec of 99', () => {
    const r = parsePhoneTargets({ exposureDurationSec: 99 })
    assert.equal(isError(r), true)
    if (!isError(r)) return
    assert.match(r.error, /exposureDurationSec/)
  })

  it('rejects bad torch.level', () => {
    const r = parsePhoneTargets({ torch: { mode: 'on', level: 1.5 } })
    assert.equal(isError(r), true)
    if (!isError(r)) return
    assert.match(r.error, /torch\.level/)
  })

  it('rejects bad bracket stops', () => {
    const tooFar = parsePhoneTargets({ bracket: { stops: [-6, 0, 6] } })
    assert.equal(isError(tooFar), true)
    if (!isError(tooFar)) return
    assert.match(tooFar.error, /bracket\.stops/)

    const empty = parsePhoneTargets({ bracket: { stops: [] } })
    assert.equal(isError(empty), true)
    if (!isError(empty)) return
    assert.match(empty.error, /bracket\.stops/)
  })

  it('does not require aperture on phoneTargets', () => {
    const r = parsePhoneTargets({
      shutter: '1/60',
      iso: 100,
      cameraDevice: 'ultraWide',
    })
    assert.equal(isError(r), false)
    if (isError(r)) return
    assert.equal('aperture' in r, false)
    assert.equal(r.shutter, '1/60')
    assert.equal(r.cameraDevice, 'ultraWide')
  })
})
