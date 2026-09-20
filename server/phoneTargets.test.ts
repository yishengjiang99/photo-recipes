import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { parsePhoneTargets, CREATIVE_LOOK_DEFAULT_INTENSITY } from './recommend.ts'

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
      creativeLook: { id: 'warmGlow', intensity: 0.65 },
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
    assert.deepEqual(r.creativeLook, { id: 'warmGlow', intensity: 0.65 })
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

  it('omits invalid bracket stops (soft-parse)', () => {
    // Out-of-range / empty stops are dropped — other fields still apply.
    const tooFar = parsePhoneTargets({
      shutter: '1/60',
      bracket: { stops: [-6, 0, 6] },
    })
    assert.equal(isError(tooFar), false)
    if (isError(tooFar)) return
    assert.equal(tooFar.shutter, '1/60')
    assert.equal('bracket' in tooFar, false)

    const empty = parsePhoneTargets({
      iso: 200,
      bracket: { stops: [] },
    })
    assert.equal(isError(empty), false)
    if (isError(empty)) return
    assert.equal(empty.iso, 200)
    assert.equal('bracket' in empty, false)
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

  it('accepts creativeLook with intensity 0 and 1', () => {
    const zero = parsePhoneTargets({ creativeLook: { id: 'monoInk', intensity: 0 } })
    assert.equal(isError(zero), false)
    if (isError(zero)) return
    assert.deepEqual(zero.creativeLook, { id: 'monoInk', intensity: 0 })

    const one = parsePhoneTargets({ creativeLook: { id: 'filmGrain', intensity: 1 } })
    assert.equal(isError(one), false)
    if (isError(one)) return
    assert.deepEqual(one.creativeLook, { id: 'filmGrain', intensity: 1 })
  })

  it('rejects unknown creativeLook.id', () => {
    const r = parsePhoneTargets({ creativeLook: { id: 'Clarendon', intensity: 0.5 } })
    assert.equal(isError(r), true)
    if (!isError(r)) return
    assert.match(r.error, /creativeLook\.id/)
  })

  it('rejects creativeLook.intensity out of range', () => {
    const high = parsePhoneTargets({ creativeLook: { id: 'tealOrange', intensity: 1.2 } })
    assert.equal(isError(high), true)
    if (!isError(high)) return
    assert.match(high.error, /creativeLook\.intensity/)

    const neg = parsePhoneTargets({ creativeLook: { id: 'tealOrange', intensity: -0.1 } })
    assert.equal(isError(neg), true)
    if (!isError(neg)) return
    assert.match(neg.error, /creativeLook\.intensity/)
  })

  it('omits creativeLook when absent (default none)', () => {
    const r = parsePhoneTargets({ shutter: '1/60' })
    assert.equal(isError(r), false)
    if (isError(r)) return
    assert.equal('creativeLook' in r, false)
  })

  it('defaults creativeLook.intensity to 0.55 when omitted or null', () => {
    assert.equal(CREATIVE_LOOK_DEFAULT_INTENSITY, 0.55)

    const omitted = parsePhoneTargets({ creativeLook: { id: 'crispCool' } })
    assert.equal(isError(omitted), false)
    if (isError(omitted)) return
    assert.deepEqual(omitted.creativeLook, { id: 'crispCool', intensity: 0.55 })

    const nulled = parsePhoneTargets({ creativeLook: { id: 'warmGlow', intensity: null } })
    assert.equal(isError(nulled), false)
    if (isError(nulled)) return
    assert.deepEqual(nulled.creativeLook, { id: 'warmGlow', intensity: 0.55 })
  })

  it('keeps explicit creativeLook.intensity including 0', () => {
    const r = parsePhoneTargets({ creativeLook: { id: 'tealOrange', intensity: 0 } })
    assert.equal(isError(r), false)
    if (isError(r)) return
    assert.deepEqual(r.creativeLook, { id: 'tealOrange', intensity: 0 })
  })
})

