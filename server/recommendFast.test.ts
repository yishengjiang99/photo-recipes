import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import {
  buildCompactRecipeCatalog,
  extractJsonObject,
  parseFastRecommendPayload,
  selectablePresets,
  useRecommendToolLoop,
  shouldUseRecommendToolLoop,
} from './recommend.ts'
import { presets } from '../src/data/presets.ts'

describe('recommend fast path helpers', () => {
  it('default is not tool-loop', () => {
    delete process.env.RECOMMEND_TOOL_LOOP
    assert.equal(useRecommendToolLoop(), false)
  })

  it('RECOMMEND_TOOL_LOOP=1 enables legacy path', () => {
    process.env.RECOMMEND_TOOL_LOOP = '1'
    assert.equal(useRecommendToolLoop(), true)
    delete process.env.RECOMMEND_TOOL_LOOP
  })

  it('shouldUseRecommendToolLoop: non-empty → true, empty → false', () => {
    delete process.env.RECOMMEND_TOOL_LOOP
    assert.equal(shouldUseRecommendToolLoop({ message: 'apply filters' }), true)
    assert.equal(shouldUseRecommendToolLoop({ message: '' }), false)
  })

  it('compact catalog lists every selectable preset id + title', () => {
    const catalog = buildCompactRecipeCatalog()
    for (const p of selectablePresets) {
      assert.match(catalog, new RegExp(`- ${p.id}:`))
      assert.ok(catalog.includes(p.title))
    }
  })

  it('library-only get-down-low is never offered to the recommender', () => {
    assert.ok(presets.some((p) => p.id === 'get-down-low'))
    assert.ok(!selectablePresets.some((p) => p.id === 'get-down-low'))
    assert.doesNotMatch(buildCompactRecipeCatalog(), /get-down-low/)
  })

  it('extractJsonObject strips fences', () => {
    const raw = '```json\n{"tips":["a"],"recipeId":"hdr-brights-darks"}\n```'
    const obj = extractJsonObject(raw) as { tips: string[]; recipeId: string }
    assert.deepEqual(obj.tips, ['a'])
    assert.equal(obj.recipeId, 'hdr-brights-darks')
  })

  it('parseFastRecommendPayload accepts recipeId + phoneTargets', () => {
    const id = presets[0]!.id
    const r = parseFastRecommendPayload({
      tips: ['Brace the phone', 'Watch the horizon'],
      recipeId: id,
      phoneTargets: { shutter: '1/125', iso: 200, ev: '-0.3', focusMode: 'continuous' },
      reason: 'Bright daylight scene.',
    })
    assert.equal('error' in r, false)
    if ('error' in r) return
    assert.equal(r.presetId, id)
    assert.equal(r.phoneTargets.shutter, '1/125')
    assert.equal(r.phoneTargets.iso, 200)
    assert.equal(r.tips.length, 2)
  })

  it('parseFastRecommendPayload accepts phoneTarget + presetId aliases', () => {
    const id = presets[1]!.id
    const r = parseFastRecommendPayload({
      tips: ['Use a tripod'],
      presetId: id,
      phoneTarget: { shutter: '1/30', whiteBalance: 'daylight' },
    })
    assert.equal('error' in r, false)
    if ('error' in r) return
    assert.equal(r.presetId, id)
    assert.equal(r.phoneTargets.shutter, '1/30')
    assert.equal(r.phoneTargets.whiteBalance, 'daylight')
  })

  it('parseFastRecommendPayload rejects unknown recipeId', () => {
    const r = parseFastRecommendPayload({
      tips: ['x'],
      recipeId: 'not-a-real-recipe',
      phoneTargets: {},
    })
    assert.equal('error' in r, true)
  })

  it('parseFastRecommendPayload requires tips', () => {
    const r = parseFastRecommendPayload({
      recipeId: presets[0]!.id,
      phoneTargets: { iso: '100' },
    })
    assert.equal('error' in r, true)
  })
})
