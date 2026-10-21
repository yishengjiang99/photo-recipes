/**
 * Push lifecycle — Grok-written copy with guardrails, template fallback and caching.
 *
 * What goes to xAI: the app name, the segment goal, and coarse bucketed facts
 * (CopyFacts: tier, "1-3 captures last week", favorite look name, "away about a week").
 * Never: install ids, guest ids, device tokens, timestamps, photos, prompts, or free text.
 *
 * Every Grok draft must pass validateCopy(); otherwise the pre-approved template is used.
 * Drafts are cached by (segment, facts) so identical cohorts reuse one generation.
 */
import crypto from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import type { CopyFacts, SegmentId } from './lifecycleSegments.ts'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const CACHE_PATH_DEFAULT = path.resolve(__dirname, 'data/push-copy-cache.json')
const XAI_URL = 'https://api.x.ai/v1/chat/completions'
export const COPY_MODELS = [
  process.env.PUSH_COPY_MODEL?.trim() || 'grok-4.20-0309-non-reasoning',
  'grok-4.3',
]
const CACHE_TTL_MS = 14 * 24 * 60 * 60 * 1000
const GROK_TIMEOUT_MS = 15_000

export const LIMITS = { titleMax: 40, bodyMax: 140 }

/** Store facts the copy may state. Must match the live App Store offer (see docs/push-lifecycle.md). */
export const STORE_FACTS = {
  appName: 'ProTune',
  /** Paywall: "Pro unlocks unlimited Auto Optimize" + "7-day free trial" (ios/…/PaywallView.swift). */
  proBenefit: 'unlimited Auto Optimize',
  trialDays: 7,
  /** Prices are deliberately never put in pushes (they vary by storefront). */
}

export type Copy = { title: string; body: string }
export type CopyResult = Copy & {
  source: 'grok' | 'cache' | 'template'
  model?: string
  rejected?: string[]
}

const URGENCY =
  /\b(hurry|urgent|act now|last chance|limited[- ]time|don'?t miss|do not miss|expir\w*|ending soon|ends soon|only today|today only|now or never|final chance|before it'?s gone|running out|deadline|countdown|ASAP|immediately)\b/i
const MONEY = /[$€£¥₹]|\b\d+\s?%|\b(discount|sale|deal|coupon|promo code|cheap|save \d+|half off|price drop)\b/i
const LINKS = /(https?:\/\/|www\.|\.com\b|@)/i
const GUILT = /\b(miss(es|ing)? you|we miss|lonely|abandon\w*|you forgot|don'?t leave|sad)\b/i
/** Don't make people feel watched: no "since you last opened", "two weeks away", etc. */
const WATCHED =
  /\b(since you last|you haven'?t (opened|used|been)|been (a|one|two|three|\d+) (days?|weeks?|months?)|(days?|weeks?|months?) away|while you were away|we noticed|we saw you)\b/i
const ABSOLUTE = /\b(guarantee\w*|best camera|perfect (photo|shot)s? every time|100%|always perfect|never fail)\b/i

/** Count emoji-ish symbols (pictographs). */
function emojiCount(s: string): number {
  return (s.match(/\p{Extended_Pictographic}/gu) ?? []).length
}

export function validateCopy(c: Copy, segment: SegmentId, facts: CopyFacts): string[] {
  const reasons: string[] = []
  const title = (c.title ?? '').trim()
  const body = (c.body ?? '').trim()
  const both = `${title} ${body}`
  if (!title) reasons.push('empty_title')
  if (!body) reasons.push('empty_body')
  if (title.length > LIMITS.titleMax) reasons.push('title_too_long')
  if (body.length > LIMITS.bodyMax) reasons.push('body_too_long')
  if (/[\r\n]/.test(both)) reasons.push('newline')
  if (URGENCY.test(both)) reasons.push('urgency')
  if (MONEY.test(both)) reasons.push('price_or_discount')
  if (LINKS.test(both)) reasons.push('link_or_handle')
  if (GUILT.test(both)) reasons.push('guilt')
  if (ABSOLUTE.test(both)) reasons.push('absolute_claim')
  if (WATCHED.test(both)) reasons.push('surveillance_tone')
  if ((both.match(/!/g) ?? []).length > 1) reasons.push('exclamation')
  if (/\b[A-Z]{4,}\b/.test(both.replace(/\bProTune\b/g, ''))) reasons.push('shouting')
  if (emojiCount(both) > 1) reasons.push('emoji')
  if (/\{|\}|\[|\]|<|>/.test(both)) reasons.push('markup')
  // "free" only as an honest trial mention in the paywall segment.
  const freeHits = both.match(/\bfree\b/gi) ?? []
  if (freeHits.length) {
    const trialOk =
      segment === 'paywall_not_converted' &&
      new RegExp(`\\b${STORE_FACTS.trialDays}[- ]day free trial\\b`, 'i').test(both) &&
      /\beligible|new subscribers?|if you'?re new\b/i.test(both)
    if (!trialOk) reasons.push('free_claim')
  }
  if (/\btrial\b/i.test(both) && segment !== 'paywall_not_converted') reasons.push('trial_mention')
  // Paywall copy may only name the one verified Pro benefit (no "all looks", "exclusive", …).
  if (segment === 'paywall_not_converted') {
    if (/\b(all|every|everything|exclusive|premium|looks?|recipes?|filters?|presets?|coach|ask|checklists?|no ads|ad-free)\b/i.test(both)) {
      reasons.push('unverified_pro_benefit')
    }
  }
  // Any "N-day" mention must be the real trial length.
  for (const m of both.matchAll(/\b(\d+)[- ]day\b/gi)) {
    if (Number(m[1]) !== STORE_FACTS.trialDays) reasons.push('wrong_trial_length')
  }
  if (/\bunlimited\b/i.test(both) && segment !== 'paywall_not_converted' && facts.tier === 'free') {
    reasons.push('unlimited_claim_for_free')
  }
  if (/\b(new|just launched|introducing)\b/i.test(both.replace(/\bnew subscribers?\b/gi, '')) && segment !== 'new_feature') {
    reasons.push('new_claim')
  }
  if (/\b(subscribe|upgrade|pro)\b/i.test(both.replace(/\bProTune\b/g, '')) && segment !== 'paywall_not_converted') {
    reasons.push('upsell_outside_paywall_segment')
  }
  return reasons
}

/** Pre-approved templates (also the fallback). Must pass validateCopy for every tier. */
export function templateCopy(segment: SegmentId, facts: CopyFacts): Copy {
  const look = facts.favoriteLook
  switch (segment) {
    case 'unfinished_edit':
      return { title: 'Your shot is still set up', body: 'Open the camera and Auto Optimize will pick up where you left off.' }
    case 'onboarding_d1':
      return facts.usedAutoOptimize
        ? { title: 'One tap, tuned settings', body: 'Point at any scene and tap Auto Optimize to dial in exposure and color for you.' }
        : { title: 'Try Auto Optimize', body: 'Point at any scene and tap Auto Optimize. ProTune tunes the settings in one tap.' }
    case 'onboarding_d3':
      return { title: 'Give your next shot a look', body: 'Film, black & white or warm tones: pick a look in the camera before you shoot.' }
    case 'onboarding_d7':
      return { title: 'Ideas for your next shoot', body: 'Browse photo recipes in the Library and load one straight into the camera.' }
    case 'paywall_not_converted':
      return {
        title: 'Still thinking about Pro?',
        body: `Pro unlocks unlimited Auto Optimize. Eligible new subscribers get a ${STORE_FACTS.trialDays}-day free trial.`,
      }
    case 'new_feature':
      return { title: 'Now in ProTune', body: (facts.announcement ?? 'A new camera feature is ready to try.').slice(0, LIMITS.bodyMax) }
    case 'inactive_7':
      return look
        ? { title: `A ${look} shot this week?`.slice(0, LIMITS.titleMax), body: `Your ${look} look is one tap away. Open the camera and try it on today's light.`.slice(0, LIMITS.bodyMax) }
        : { title: 'A shot idea for this week', body: 'Try Auto Optimize on a window-lit portrait. Soft side light works great.' }
    case 'inactive_14':
      return { title: 'An easy recipe to try', body: 'Pick a recipe in the Library and ProTune sets up the camera for it.' }
    case 'winback_30':
      return { title: 'Your camera presets are here', body: 'Whenever you are ready to shoot again, Auto Optimize is one tap away.' }
    case 'weekly_tip':
      return { title: 'A shot idea for this week', body: 'Point at a scene, tap Auto Optimize, then try a creative look on the next frame.' }
  }
}

type CacheEntry = Copy & { model: string; at: string }
type CacheFile = Record<string, CacheEntry>

function cachePath(): string {
  return process.env.PUSH_COPY_CACHE_PATH?.trim() || CACHE_PATH_DEFAULT
}

function readCache(): CacheFile {
  try {
    if (!fs.existsSync(cachePath())) return {}
    return JSON.parse(fs.readFileSync(cachePath(), 'utf8')) as CacheFile
  } catch {
    return {}
  }
}

function writeCache(c: CacheFile) {
  try {
    fs.mkdirSync(path.dirname(cachePath()), { recursive: true })
    const tmp = `${cachePath()}.${process.pid}.tmp`
    fs.writeFileSync(tmp, JSON.stringify(c, null, 2), 'utf8')
    fs.renameSync(tmp, cachePath())
  } catch (err) {
    console.warn('[lifecycle/copy] cache write failed', err instanceof Error ? err.message : err)
  }
}

export function copyCacheKey(segment: SegmentId, facts: CopyFacts): string {
  const canon = JSON.stringify([segment, facts.tier, facts.capturesLastWeek, facts.usedAutoOptimize, facts.favoriteLook, facts.awayFor, facts.announcement ?? null])
  return crypto.createHash('sha256').update(canon).digest('hex').slice(0, 24)
}

/** True statements about the shipping app the writer may rely on (keep in sync with the app). */
export const APP_FACTS = [
  'Auto Optimize works in the live camera: point at a scene, tap Auto Optimize, and ProTune tunes exposure and color before you take the photo. It does not edit photos you already took.',
  'Creative looks (film, black & white, warm tones and more) can be picked in the camera before shooting.',
  'The Library tab has photo recipes; opening one sets the camera up for that style.',
  'Pro unlocks unlimited Auto Optimize. Free users get a limited number per day.',
]

export function buildPrompt(segment: SegmentId, goal: string, facts: CopyFacts): { system: string; user: string } {
  const system = [
    `You write one iOS push notification for ${STORE_FACTS.appName}, an AI camera app that tunes iPhone camera settings (Auto Optimize) and offers creative looks and photo recipes.`,
    'Voice: warm, specific, calm, helpful. Plain English. Sound like a photographer friend, not an ad.',
    `Hard rules: title at most ${LIMITS.titleMax} characters; body at most ${LIMITS.bodyMax} characters; one line each.`,
    'No urgency or scarcity (no "hurry", "last chance", "limited time", "expires"). No guilt ("we miss you").',
    'No prices, currency, percentages, discounts or sales. No links. No hashtags. At most one emoji (prefer none). At most one exclamation mark.',
    'Do not invent features, results, numbers or offers. Only mention what the facts and goal state.',
    'Never mention free, trial, Pro, subscribing or upgrading unless the goal is explicitly about Pro.',
    'Do not say "new" unless the goal is a feature announcement.',
    'Do not refer to tracking, data, or how you know what the user did. Never mention how long they have been away or when they last opened the app.',
    'Every message must invite one concrete, doable action inside the app (e.g. tap Auto Optimize, pick a look, open a recipe).',
    'App facts you may rely on (do not claim anything beyond these):',
    ...APP_FACTS.map((f) => `- ${f}`),
    'Reply with JSON only: {"title": "...", "body": "..."}',
  ].join('\n')
  const user = JSON.stringify({ goal, facts })
  return { system, user }
}

let fetchImpl: typeof fetch = (...a) => fetch(...a)
export function setCopyFetchForTests(f: typeof fetch | null) {
  fetchImpl = f ?? ((...a) => fetch(...a))
}

async function callGrok(model: string, prompt: { system: string; user: string }): Promise<Copy> {
  const key = process.env.XAI_API_KEY?.trim()
  if (!key) throw new Error('no_xai_key')
  const ctrl = new AbortController()
  const timer = setTimeout(() => ctrl.abort(), GROK_TIMEOUT_MS)
  try {
    const res = await fetchImpl(XAI_URL, {
      method: 'POST',
      signal: ctrl.signal,
      headers: { authorization: `Bearer ${key}`, 'content-type': 'application/json' },
      body: JSON.stringify({
        model,
        temperature: 0.7,
        max_tokens: 200,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: prompt.system },
          { role: 'user', content: prompt.user },
        ],
      }),
    })
    if (!res.ok) throw new Error(`xai_http_${res.status}`)
    const json = (await res.json()) as { choices?: Array<{ message?: { content?: string } }> }
    const text = json.choices?.[0]?.message?.content ?? ''
    const m = text.match(/\{[\s\S]*\}/)
    if (!m) throw new Error('xai_no_json')
    const parsed = JSON.parse(m[0]) as Partial<Copy>
    return { title: String(parsed.title ?? '').trim(), body: String(parsed.body ?? '').trim() }
  } finally {
    clearTimeout(timer)
  }
}

export type GenerateOpts = { useGrok?: boolean; now?: Date; bypassCache?: boolean }

/**
 * Grok → guardrails → cache; any failure or rejection → template. Never throws.
 * PUSH_COPY_GROK=false disables Grok entirely (templates only).
 */
export async function generateCopy(
  segment: SegmentId,
  goal: string,
  facts: CopyFacts,
  opts: GenerateOpts = {},
): Promise<CopyResult> {
  const now = opts.now ?? new Date()
  const useGrok = opts.useGrok ?? process.env.PUSH_COPY_GROK?.trim().toLowerCase() !== 'false'
  const key = copyCacheKey(segment, facts)
  if (!opts.bypassCache) {
    const cache = readCache()
    const hit = cache[key]
    if (hit && now.getTime() - Date.parse(hit.at) < CACHE_TTL_MS && validateCopy(hit, segment, facts).length === 0) {
      return { title: hit.title, body: hit.body, source: 'cache', model: hit.model }
    }
  }
  const rejected: string[] = []
  if (useGrok && process.env.XAI_API_KEY?.trim()) {
    const prompt = buildPrompt(segment, goal, facts)
    for (const model of COPY_MODELS) {
      for (let attempt = 0; attempt < 2; attempt++) {
        try {
          const draft = await callGrok(model, prompt)
          const reasons = validateCopy(draft, segment, facts)
          if (!reasons.length) {
            const cache = readCache()
            cache[key] = { ...draft, model, at: now.toISOString() }
            writeCache(cache)
            return { ...draft, source: 'grok', model, ...(rejected.length ? { rejected } : {}) }
          }
          rejected.push(`${model}:${reasons.join('+')}`)
        } catch (err) {
          rejected.push(`${model}:${err instanceof Error ? err.message : 'error'}`)
          break // transport error → next model
        }
      }
    }
  }
  return { ...templateCopy(segment, facts), source: 'template', ...(rejected.length ? { rejected } : {}) }
}
