import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import {
  parsePhoneTargets,
  CREATIVE_LOOK_DEFAULT_INTENSITY,
  CREATIVE_LOOK_IDS,
  LOOK_UTTERANCE_MATRIX,
  inferCreativeLookOverride,
  applyCreativeLookMessageOverride,
  shouldUseRecommendToolLoop,
} from './recommend.ts'

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

describe('creativeLook message override (named looks / look replace)', () => {
  it('maps B&W utterances including apply black and white filter → monoInk', () => {
    for (const msg of [
      'apply black and white filter',
      'black and white',
      'B&W',
      'B&W please',
      'b and w',
      'b&w',
      'bw',
      'make it black and white',
      'mono',
      'monochrome look',
      'mono ink',
    ]) {
      const o = inferCreativeLookOverride(msg)
      assert.deepEqual(
        o,
        { id: 'monoInk', intensity: CREATIVE_LOOK_DEFAULT_INTENSITY },
        `expected monoInk for: ${msg}`,
      )
    }
  })

  it('LOOK_UTTERANCE_MATRIX: each V1 id has ≥1 utterance → expected id', () => {
    const seen = new Set<string>()
    for (const { utterance, id } of LOOK_UTTERANCE_MATRIX) {
      const o = inferCreativeLookOverride(utterance)
      assert.deepEqual(
        o,
        { id, intensity: CREATIVE_LOOK_DEFAULT_INTENSITY },
        `utterance "${utterance}" → expected ${id}, got ${o?.id}`,
      )
      seen.add(id)
    }
    for (const id of CREATIVE_LOOK_IDS) {
      assert.ok(seen.has(id), `missing matrix coverage for V1 id: ${id}`)
    }
  })

  it('does not force a look for generic apply-filters or shutter asks', () => {
    assert.equal(inferCreativeLookOverride('apply filters'), undefined)
    assert.equal(inferCreativeLookOverride('apply filter'), undefined)
    assert.equal(inferCreativeLookOverride('slower shutter'), undefined)
    assert.equal(inferCreativeLookOverride(''), undefined)
  })

  it('warm film / warm look force warmGlow (not undefined)', () => {
    assert.deepEqual(inferCreativeLookOverride('warm film look'), {
      id: 'warmGlow',
      intensity: CREATIVE_LOOK_DEFAULT_INTENSITY,
    })
    assert.deepEqual(inferCreativeLookOverride('warm pop'), {
      id: 'warmPop',
      intensity: CREATIVE_LOOK_DEFAULT_INTENSITY,
    })
  })

  it('replaces a prior look when the new message is B&W', () => {
    const replaced = applyCreativeLookMessageOverride('B&W', {
      id: 'warmGlow',
      intensity: 0.9,
    })
    assert.deepEqual(replaced, {
      id: 'monoInk',
      intensity: CREATIVE_LOOK_DEFAULT_INTENSITY,
    })
  })

  it('withCreativeLookOverride nest: override lands on phoneTargets.creativeLook + top-level', () => {
    const look = applyCreativeLookMessageOverride('apply black and white filter', {
      id: 'tealOrange',
      intensity: 0.6,
    })
    assert.deepEqual(look, {
      id: 'monoInk',
      intensity: CREATIVE_LOOK_DEFAULT_INTENSITY,
    })
    // Mirror what recommendFastOneShot / tool-loop do when nesting
    const phoneTargets = { shutter: '1/60', creativeLook: look }
    const top = look
    assert.equal(phoneTargets.creativeLook?.id, 'monoInk')
    assert.equal(top?.id, 'monoInk')
  })

  it('keeps model look when message has no named override', () => {
    const kept = applyCreativeLookMessageOverride('apply filters', {
      id: 'tealOrange',
      intensity: 0.6,
    })
    assert.deepEqual(kept, { id: 'tealOrange', intensity: 0.6 })
  })
})

describe('shouldUseRecommendToolLoop (message routing)', () => {
  it('non-empty message → tool-loop (STT / typed / APPLY-FILTERS)', () => {
    delete process.env.RECOMMEND_TOOL_LOOP
    assert.equal(shouldUseRecommendToolLoop({ message: 'apply black and white filter' }), true)
    assert.equal(shouldUseRecommendToolLoop({ message: 'B&W' }), true)
    assert.equal(shouldUseRecommendToolLoop({ message: '  warm glow  ' }), true)
    assert.equal(shouldUseRecommendToolLoop({ message: 'slower shutter' }), true)
  })

  it('empty / whitespace-only message → fast one-shot (image-only AO)', () => {
    delete process.env.RECOMMEND_TOOL_LOOP
    assert.equal(shouldUseRecommendToolLoop({ message: '' }), false)
    assert.equal(shouldUseRecommendToolLoop({ message: '   ' }), false)
  })

  it('RECOMMEND_TOOL_LOOP=1 forces tool-loop even for empty message', () => {
    process.env.RECOMMEND_TOOL_LOOP = '1'
    assert.equal(shouldUseRecommendToolLoop({ message: '' }), true)
    delete process.env.RECOMMEND_TOOL_LOOP
  })
})
