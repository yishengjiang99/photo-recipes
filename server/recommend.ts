import { presets } from '../src/data/presets.ts'
import type { RecipePreset } from '../src/types/index.ts'
import crypto from 'node:crypto'
import { shrinkVisionDataUrl } from './image.ts'
import { fetchWithTimeout } from './fetchTimeout.ts'

/** Library-only recipes: readable in the app, never picked by the recommender. */
const LIBRARY_ONLY_PRESET_IDS = new Set(['get-down-low'])
/** Presets the recommender may list and select. */
export const selectablePresets = presets.filter((p) => !LIBRARY_ONLY_PRESET_IDS.has(p.id))

const XAI_BASE = 'https://api.x.ai/v1'
/** Text Ask Grok models */
const PRIMARY_MODEL = 'grok-4'
const FALLBACK_MODEL = 'grok-3-mini'
/**
 * Vision coach path: prefer grok-4 (no high-reasoning tax). grok-4.6 defaults to
 * reasoning_effort=high and routinely exceeds our budget on night scenes — only use it
 * as fallback WITH reasoning_effort=low.
 * @see https://docs.x.ai/docs/guides/reasoning
 */
const VISION_MODELS = ['grok-4', 'grok-4.6'] as const
/** Hard cap on legacy tool rounds. If select_preset never succeeds, fail clearly. */
const MAX_ROUNDS = 4
/** Vision token cost vs quality — low is much faster for Auto Optimize / Recommend.
 * Image data URLs are held in memory only — never persisted.
 */
const VISION_IMAGE_DETAIL: 'auto' | 'low' | 'high' = 'low'
/**
 * Routing: non-empty message → tool-loop; empty message → fast one-shot (image-only AO).
 * RECOMMEND_TOOL_LOOP=1 forces tool-loop for empty-message AO (debug).
 * Text-only stays snappy; vision needs headroom (grok-4.6 often 12–35s on night scenes).
 * Nginx proxy_read_timeout is 120s — keep well under that.
 */
const FAST_TEXT_TIMEOUT_MS = 20_000
/** With reasoning_effort=low + thin JSON, vision should land in ~5–20s. */
const FAST_VISION_TIMEOUT_MS = 35_000
/** @deprecated use FAST_TEXT / FAST_VISION — kept for exports/tests */
const FAST_TIMEOUT_MS = FAST_VISION_TIMEOUT_MS

export interface RecommendLogContext {
  /** Short correlation id shared across one recommend request's log lines. */
  correlationId: string
  /** Truncated guest/anon id (never full if long). */
  guestIdShort?: string
  /** ios | web | android | server */
  platform?: string
}

export interface RecommendRequest {
  message: string
  favorites?: string[]
  /** data:image/...;base64,... — when set, uses vision model + multimodal user content */
  imageDataUrl?: string
  /** Optional structured-debug context from the HTTP layer. */
  log?: RecommendLogContext
}

/** Values a phone camera API can typically apply (AVFoundation / Camera2-style).
 * All keys optional/additive — older iOS builds ignore unknown keys.
 * Names match iOS Expert applyPhoneTargets contract (capability-gated on device).
 */
export type WhiteBalanceGains = {
  redGain?: number
  greenGain?: number
  blueGain?: number
}

export type WhiteBalanceTemperatureTint = {
  temperature?: number
  tint?: number
}

/** Preset name string, locked temperature/tint, or device RGB gains. */
export type WhiteBalanceTarget =
  | string
  | WhiteBalanceTemperatureTint
  | WhiteBalanceGains

export type TorchTarget = {
  mode: 'off' | 'on' | 'auto'
  /** Torch intensity 0…1 when mode is on (device-clamped). */
  level?: number
}

export type BracketTarget = {
  /** EV offsets for multi-capture / HDR burst, e.g. [-2, 0, 2]. */
  stops: number[]
  count?: number
}

export type MaxPhotoDimensions = {
  width: number
  height: number
}

/** V1 creative look pack — ORIGINAL ids only (never trademarked filter brand names). */
export const V1_CREATIVE_LOOK_IDS = [
  'crispCool',
  'warmGlow',
  'warmPop',
  'editorialRed',
  'softVintage',
  'monoInk',
  'goldenHour',
  'loFiPunch',
  'tealOrange',
  'blockbuster',
  'moodyFilm',
  'coolBlue',
  'softDream',
  'filmGrain',
] as const

/**
 * Selfie preset pack (front camera). Light + texture choices with a face-aware
 * still retouch on device — never reshaping or skin-tone changes.
 * Must match iOS `CreativeLookCatalog.selfieIds` (docs/selfie/selfie-presets-prompt.md).
 * Not part of the voice utterance matrix (LOOK_UTTERANCE_MATRIX covers V1 only).
 */
export const SELFIE_CREATIVE_LOOK_IDS = [
  'selfieNatural',
  'selfieGlow',
  'selfieStudio',
  'selfieLowLight',
  'selfiePortrait',
] as const

/** Every id the client can bake — V1 pack + selfie pack. Keep in sync with iOS `CreativeLookCatalog.allIds`. */
export const CREATIVE_LOOK_IDS = [...V1_CREATIVE_LOOK_IDS, ...SELFIE_CREATIVE_LOOK_IDS] as const

export type CreativeLookId = (typeof CREATIVE_LOOK_IDS)[number]

export type CreativeLook = {
  /** One of CREATIVE_LOOK_IDS (V1 enum). */
  id: CreativeLookId
  /**
   * Grade blend strength 0…1. Same grade on preview AND still when > 0; identity at 0.
   * Server default 0.55 when id present but intensity omitted/null.
   */
  intensity: number
}

/** Default intensity when creativeLook.id is present but intensity is omitted or null. */
export const CREATIVE_LOOK_DEFAULT_INTENSITY = 0.55


/**
 * Ordered utterance → CreativeLookId rules (first match wins).
 * More specific multi-word phrases before bare tokens to avoid collisions.
 */
export const CREATIVE_LOOK_OVERRIDE_RULES: ReadonlyArray<{
  re: RegExp
  id: CreativeLookId
}> = [
  // monoInk — B&W / mono (incl. "apply black and white filter")
  {
    re: /\b(?:apply\s+)?black\s*(?:and|&)\s*white(?:\s+filter)?\b|\bb\s*&\s*w\b|\bb\s+and\s+w\b|\bb\s*\/\s*w\b|\bbw\b|\bmono(?:chrome)?\b|\bmono\s*ink\b|make\s+it\s+black\s+and\s+white/i,
    id: 'monoInk',
  },
  { re: /\bwarm\s*pop\b/i, id: 'warmPop' },
  { re: /\bcrisp\s*cool\b/i, id: 'crispCool' },
  { re: /\beditorial\s*red\b/i, id: 'editorialRed' },
  { re: /\bsoft\s*vintage\b|\bvintage\s*look\b|\bvintage\b/i, id: 'softVintage' },
  { re: /\bgolden\s*hour\b/i, id: 'goldenHour' },
  { re: /\blo[\s-]?fi(?:\s*punch)?\b|\blofi\b/i, id: 'loFiPunch' },
  { re: /\bteal\s*(?:and|&)?\s*orange\b/i, id: 'tealOrange' },
  { re: /\bblockbuster\b|\bcinematic\b/i, id: 'blockbuster' },
  { re: /\bmoody\s*film\b|\bmoody\b/i, id: 'moodyFilm' },
  { re: /\bcool\s*blue\b|\bnight\s*grade\b/i, id: 'coolBlue' },
  { re: /\bsoft\s*dream\b|\bdreamy\b/i, id: 'softDream' },
  { re: /\bfilm\s*grain\b|\bgrainy\b|\badd\s+grain\b/i, id: 'filmGrain' },
  // warmGlow after warmPop; bare "warm" last among warm*
  { re: /\bwarm\s*glow\b|\bwarm\s*film\b|\bwarm\s*look\b|\bwarm\b/i, id: 'warmGlow' },
]

/** Canonical utterance → id pairs for unit tests (one+ per V1 look). */
export const LOOK_UTTERANCE_MATRIX: ReadonlyArray<{
  utterance: string
  id: CreativeLookId
}> = [
  { utterance: 'apply black and white filter', id: 'monoInk' },
  { utterance: 'black and white', id: 'monoInk' },
  { utterance: 'B&W', id: 'monoInk' },
  { utterance: 'b and w', id: 'monoInk' },
  { utterance: 'bw', id: 'monoInk' },
  { utterance: 'mono', id: 'monoInk' },
  { utterance: 'monochrome', id: 'monoInk' },
  { utterance: 'make it black and white', id: 'monoInk' },
  { utterance: 'mono ink', id: 'monoInk' },
  { utterance: 'warm pop', id: 'warmPop' },
  { utterance: 'warm glow', id: 'warmGlow' },
  { utterance: 'warm film', id: 'warmGlow' },
  { utterance: 'warm', id: 'warmGlow' },
  { utterance: 'crisp cool', id: 'crispCool' },
  { utterance: 'editorial red', id: 'editorialRed' },
  { utterance: 'soft vintage', id: 'softVintage' },
  { utterance: 'vintage look', id: 'softVintage' },
  { utterance: 'vintage', id: 'softVintage' },
  { utterance: 'golden hour', id: 'goldenHour' },
  { utterance: 'lo-fi', id: 'loFiPunch' },
  { utterance: 'lofi', id: 'loFiPunch' },
  { utterance: 'lo fi punch', id: 'loFiPunch' },
  { utterance: 'teal and orange', id: 'tealOrange' },
  { utterance: 'teal orange', id: 'tealOrange' },
  { utterance: 'teal & orange', id: 'tealOrange' },
  { utterance: 'blockbuster', id: 'blockbuster' },
  { utterance: 'cinematic', id: 'blockbuster' },
  { utterance: 'moody film', id: 'moodyFilm' },
  { utterance: 'moody', id: 'moodyFilm' },
  { utterance: 'cool blue', id: 'coolBlue' },
  { utterance: 'night grade', id: 'coolBlue' },
  { utterance: 'soft dream', id: 'softDream' },
  { utterance: 'dreamy', id: 'softDream' },
  { utterance: 'film grain', id: 'filmGrain' },
  { utterance: 'grainy', id: 'filmGrain' },
  { utterance: 'add grain', id: 'filmGrain' },
]

/** Deterministic look overrides from the latest user message (replaces any prior look intent). */
export function inferCreativeLookOverride(message: string): CreativeLook | undefined {
  const m = message.trim()
  if (!m) return undefined
  for (const rule of CREATIVE_LOOK_OVERRIDE_RULES) {
    if (rule.re.test(m)) {
      return { id: rule.id, intensity: CREATIVE_LOOK_DEFAULT_INTENSITY }
    }
  }
  return undefined
}

/**
 * Latest user message wins: if the note carries a named look intent (e.g. B&W → monoInk),
 * replace whatever creativeLook the model emitted (do not blend with a prior look).
 */
export function applyCreativeLookMessageOverride(
  message: string,
  look: CreativeLook | undefined,
): CreativeLook | undefined {
  const forced = inferCreativeLookOverride(message)
  if (forced) return forced
  return look
}

/** APPLY-FILTERS-style intents (logging / diagnostics only — does not force a look). */
const APPLY_FILTERS_LOOK_RE =
  /\b(apply\s+filters?|add\s+a\s+filter|put\s+a\s+filter\s+on|use\s+a\s+filter|apply\s+a\s+look|add\s+a\s+look|grade\s+this|color\s+grade|give\s+it\s+a\s+look|make\s+it\s+cinematic|make\s+it\s+moody|make\s+it\s+warm|film\s+look|teal\s+and\s+orange|add\s+grain)\b/i

/** True when the utterance looks like an APPLY-FILTERS ask (model should emit creativeLook). */
export function isApplyFiltersIntent(message: string): boolean {
  return APPLY_FILTERS_LOOK_RE.test(message.trim())
}

/** Redact vision data URLs / base64 blobs for safe structured logs. */
export function redactDataUrls(text: string): string {
  return text.replace(
    /data:(image\/[a-z0-9.+-]+);base64,[A-Za-z0-9+/=\s]+/gi,
    (match, mime: string) => {
      const comma = match.indexOf(',')
      const b64 = comma >= 0 ? match.slice(comma + 1).replace(/\s/g, '') : ''
      return `data:${mime};base64,<len=${b64.length}>`
    },
  )
}

export function newRecommendCorrelationId(): string {
  return crypto.randomUUID().replace(/-/g, '').slice(0, 12)
}

/** Truncate guest/anon ids for logs (keep recognizable short form). */
export function shortGuestId(id: string | undefined | null): string | undefined {
  if (!id) return undefined
  const s = id.trim()
  if (!s) return undefined
  if (s.length <= 10) return s
  return `${s.slice(0, 4)}…${s.slice(-4)}`
}

type RecommendLogPrefix = 'recommend' | 'creativeLook'

/**
 * Structured JSON log line for Recommend / creativeLook debug.
 * Never logs raw vision data URLs or API keys.
 */
export function logRecommend(
  prefix: RecommendLogPrefix,
  event: string,
  fields: Record<string, unknown> = {},
): void {
  const safe: Record<string, unknown> = { event }
  for (const [k, v] of Object.entries(fields)) {
    if (v === undefined) continue
    if (typeof v === 'string') {
      safe[k] = redactDataUrls(v).slice(0, 2000)
    } else {
      safe[k] = v
    }
  }
  console.info(`[${prefix}] ${JSON.stringify(safe)}`)
}

/** Fingerprint a prompt for logs (length + short sha) — never the full text with images. */
export function promptFingerprint(text: string): { len: number; sha8: string } {
  const redacted = redactDataUrls(text)
  const sha8 = crypto.createHash('sha256').update(redacted).digest('hex').slice(0, 8)
  return { len: redacted.length, sha8 }
}

/**
 * Apply message look override to both top-level creativeLook and phoneTargets.creativeLook.
 * Returns raw (pre-override) and final looks for structured logging.
 */
export function finalizeCreativeLookForClient(
  message: string,
  phoneTargets: PhoneTargets,
  topLevelLook?: CreativeLook,
): {
  phoneTargets: PhoneTargets
  creativeLook?: CreativeLook
  rawCreativeLook?: CreativeLook
  overrideMatched: boolean
} {
  const rawCreativeLook = topLevelLook ?? phoneTargets.creativeLook
  const forced = inferCreativeLookOverride(message)
  const creativeLook = applyCreativeLookMessageOverride(message, rawCreativeLook)
  if (!creativeLook) {
    return {
      phoneTargets,
      rawCreativeLook,
      overrideMatched: Boolean(forced),
    }
  }
  return {
    phoneTargets: { ...phoneTargets, creativeLook },
    creativeLook,
    rawCreativeLook,
    overrideMatched: Boolean(forced),
  }
}

const CREATIVE_LOOK_ID_SET = new Set<string>(CREATIVE_LOOK_IDS)

export interface PhoneTargets {
  /** Human / recipe shutter string, e.g. "1/60", "1/500". Keep alongside exposureDurationSec. */
  shutter?: string
  /**
   * Numeric exposure duration in seconds for setExposureModeCustom (e.g. 1/60 → 0.01667).
   * Prefer with iso when locking a custom pair; shutter string may still be present for UI.
   */
  exposureDurationSec?: number
  /** ISO as string ("100", "auto") or number. */
  iso?: string | number
  /** Exposure compensation as string ("+0.7") or number. */
  ev?: string | number
  whiteBalance?: WhiteBalanceTarget
  focusMode?: string
  /**
   * Multiplicative zoom factor for AVCaptureDevice.videoZoomFactor (1 = 1×, 2 = 2×).
   * Prefer cameraDevice for optical lens switch; zoom is digital / within-lens factor.
   * String forms like "2x" are accepted by the server and normalized to a number.
   */
  zoom?: number
  /**
   * Normalized viewfinder tap-to-focus point (0–1). Omit when focusMode alone is enough.
   * Spoken e.g. "lock focus on the rider" → focusMode locked + optional focusPoint.
   */
  focusPoint?: { x: number; y: number }
  /** Locked lens position 0…1 (setFocusModeLocked). */
  lensPosition?: number
  torch?: TorchTarget
  /** Photo output flash when supported. */
  flash?: 'off' | 'on' | 'auto'
  lowLightBoost?: boolean
  videoHDR?: boolean
  /** Optical camera switch vs digital zoom only. */
  cameraDevice?: 'ultraWide' | 'wide' | 'tele'
  /** Target fps; pair with preferFormatHint when useful. */
  frameRate?: number
  preferFormatHint?: string
  /** Multi-capture HDR / AE bracket plan for iOS burst. */
  bracket?: BracketTarget
  /** When true, iOS should re-trigger Auto Optimize on subject-area change. */
  monitorSubjectAreaChange?: boolean
  maxPhotoDimensions?: MaxPhotoDimensions
  /**
   * Preview-only LUT id. MUST NOT be sold as a capture magic filter —
   * capture settings (exposure/WB/focus/…) remain primary.
   */
  previewLUT?: string
  /**
   * P1 optional creative grade (ORIGINAL pack ids). Default: omit (none / identity).
   * Unlike previewLUT: same grade on preview AND still when intensity > 0; identity at 0.
   * Pipeline v1: CIFilter/CIColorMatrix procedural (optional .cube/Metal later — not required v1).
   * Capture settings remain PRIMARY. Never trademarked brand names / inspired-by in product UI.
   */
  creativeLook?: CreativeLook
  /**
   * P1 / OS-gated simulated aperture. If the device cannot apply it, put f-stop in coachOnly.aperture.
   * Never invent hardware aperture on fixed-aperture phones.
   */
  simulatedAperture?: number
}

/** Guidance the coach shows but the device does not auto-apply. */
export interface CoachOnly {
  aperture?: string
  nd?: string
  tripod?: boolean
  notes?: string
}

export interface PanCue {
  direction: 'left' | 'right' | 'either'
  note?: string
}

export interface SelectionPayload {
  presetId: string
  reason: string
  teachWhy: string
  tips: string[]
  phoneTargets: PhoneTargets
  coachOnly: CoachOnly
  panCue?: PanCue
  senseSummary?: string
  /**
   * One-release fallback mirror of phoneTargets.creativeLook (primary).
   * Prefer phoneTargets.creativeLook; top-level accepted for older client decode.
   */
  creativeLook?: CreativeLook
}

export interface RecommendResult {
  presetId: string
  reason: string
  teachWhy: string
  tips: string[]
  phoneTargets: PhoneTargets
  coachOnly: CoachOnly
  panCue?: PanCue
  senseSummary?: string
  /** Mirror of phoneTargets.creativeLook when present (one-release decode fallback). */
  creativeLook?: CreativeLook
  preset: RecipePreset
  model: string
  /**
   * Intentionally omitted: conversation history can contain image data URLs.
   * Vision is pass-through only — never return or persist message transcripts with photos.
   */
}

type ContentPart =
  | { type: 'text'; text: string }
  | { type: 'image_url'; image_url: { url: string; detail?: 'auto' | 'low' | 'high' } }

type ChatMessage = {
  role: 'system' | 'user' | 'assistant' | 'tool'
  content?: string | ContentPart[] | null
  tool_calls?: ToolCall[]
  tool_call_id?: string
  name?: string
}

type ToolCall = {
  id: string
  type: 'function'
  function: { name: string; arguments: string }
}

const tools = [
  {
    type: 'function' as const,
    function: {
      name: 'list_presets',
      description:
        'List all photography recipe presets in the app catalog with id, title, tags, short description, and key camera settings. Always call this (or get_preset_details) before selecting — never invent recipes outside this catalog.',
      parameters: {
        type: 'object',
        properties: {},
        additionalProperties: false,
      },
    },
  },
  {
    type: 'function' as const,
    function: {
      name: 'get_preset_details',
      description:
        'Get the full steps, tips, dials, gear, and when-to-use text for one preset by id. Use when you need more detail before finalizing.',
      parameters: {
        type: 'object',
        properties: {
          presetId: {
            type: 'string',
            description: 'Preset id from list_presets',
          },
        },
        required: ['presetId'],
        additionalProperties: false,
      },
    },
  },
  {
    type: 'function' as const,
    function: {
      name: 'select_preset',
      description:
        'Finalize Auto Optimize: pick exactly one catalog preset (keep current recipe or a better match) and emit phone-settable targets (AVFoundation levers: shutter/exposureDurationSec/iso/ev/WB/focus/lensPosition/zoom/cameraDevice/torch/flash/HDR/bracket/…), coach-only guidance, optional pan cue, and teachWhy. Aperture stays coachOnly (or simulatedAperture only if OS-gated). previewLUT is preview-only; creativeLook bakes the same grade on preview AND still when intensity > 0. Prefer phoneTargets.creativeLook; optional top-level creativeLook is a one-release fallback. If the user message includes a control tweak or APPLY-FILTERS / look ask (typed or spoken), phoneTargets MUST reflect that ask — including creativeLook when they want a filter/look applied. This ends the loop.',
      parameters: {
        type: 'object',
        properties: {
          presetId: {
            type: 'string',
            description: 'Exact preset id from the catalog (list_presets)',
          },
          reason: {
            type: 'string',
            description:
              'Coach-style explanation of why this recipe fits (shown in Ask / status depth). 1–3 short sentences.',
          },
          teachWhy: {
            type: 'string',
            description:
              'Short Teach mode one-liner (1–2 sentences). Field-manual tone — no model jargon.',
          },
          tips: {
            type: 'array',
            items: { type: 'string' },
            maxItems: 3,
            description: 'At most 3 short field tips tailored to this scene',
          },
          phoneTargets: {
            type: 'object',
            description:
              'Only values a phone camera API can apply (AVFoundation levers). All keys optional/additive; omit unsupported or unknown. Never put aperture here — use coachOnly.aperture (or simulatedAperture only if OS-gated). When the user asks for a control tweak, include matching keys. previewLUT is preview-only (never capture magic). creativeLook is a bakeable grade (preview+still when intensity>0); default omit (none); intensity optional (server defaults 0.55).',
            properties: {
              shutter: {
                type: 'string',
                description: 'Target shutter string for UI/recipe, e.g. "1/60", "1/500", "1/2". Keep even when exposureDurationSec is set.',
              },
              exposureDurationSec: {
                type: 'number',
                description:
                  'Exposure duration in seconds for setExposureModeCustom (e.g. 0.01667 for 1/60). Pair with iso for a custom exposure lock.',
              },
              iso: {
                description: 'Target ISO — string ("100", "400", "auto") or number',
                oneOf: [{ type: 'string' }, { type: 'number' }],
              },
              ev: {
                description: 'Exposure compensation — string ("+0.7", "0", "-1") or number',
                oneOf: [{ type: 'string' }, { type: 'number' }],
              },
              whiteBalance: {
                description:
                  'Preset string ("auto","daylight","cloudy","shade","tungsten") OR locked { temperature, tint } OR { redGain, greenGain, blueGain }',
                oneOf: [
                  { type: 'string' },
                  {
                    type: 'object',
                    properties: {
                      temperature: { type: 'number' },
                      tint: { type: 'number' },
                    },
                    additionalProperties: false,
                  },
                  {
                    type: 'object',
                    properties: {
                      redGain: { type: 'number' },
                      greenGain: { type: 'number' },
                      blueGain: { type: 'number' },
                    },
                    additionalProperties: false,
                  },
                ],
              },
              focusMode: {
                type: 'string',
                description: 'e.g. "continuous", "locked", "near", "infinity"',
              },
              zoom: {
                type: 'number',
                description:
                  'videoZoomFactor (1 = 1×, 2 = 2×). Prefer cameraDevice for optical lens switch.',
              },
              focusPoint: {
                type: 'object',
                description:
                  'Normalized tap-to-focus point (0–1). Use with focusMode when the user names a subject region; omit if focusMode alone is enough.',
                properties: {
                  x: {
                    type: 'number',
                    description: 'Horizontal position 0 (left) … 1 (right)',
                  },
                  y: {
                    type: 'number',
                    description: 'Vertical position 0 (top) … 1 (bottom)',
                  },
                },
                required: ['x', 'y'],
                additionalProperties: false,
              },
              lensPosition: {
                type: 'number',
                description: 'Locked lens position 0…1 (setFocusModeLocked)',
              },
              torch: {
                type: 'object',
                description: 'Torch / continuous light when device supports it',
                properties: {
                  mode: {
                    type: 'string',
                    enum: ['off', 'on', 'auto'],
                  },
                  level: {
                    type: 'number',
                    description: 'Intensity 0…1 when mode is on',
                  },
                },
                required: ['mode'],
                additionalProperties: false,
              },
              flash: {
                type: 'string',
                enum: ['off', 'on', 'auto'],
                description: 'Still-photo flash mode when PhotoOutput allows',
              },
              lowLightBoost: {
                type: 'boolean',
                description: 'Enable low-light boost when device supports it',
              },
              videoHDR: {
                type: 'boolean',
                description: 'Video HDR on/off when format supports it',
              },
              cameraDevice: {
                type: 'string',
                enum: ['ultraWide', 'wide', 'tele'],
                description: 'Optical camera switch (vs digital zoom only)',
              },
              frameRate: {
                type: 'number',
                description: 'Target fps (maps to min/max frame duration on active format)',
              },
              preferFormatHint: {
                type: 'string',
                description: 'Soft hint for activeFormat selection (e.g. "4k60", "1080p30")',
              },
              bracket: {
                type: 'object',
                description: 'Multi-capture HDR / AE bracket plan for iOS burst',
                properties: {
                  stops: {
                    type: 'array',
                    items: { type: 'number' },
                    minItems: 1,
                    maxItems: 9,
                    description: 'EV offsets, e.g. [-2, 0, 2]',
                  },
                  count: {
                    type: 'number',
                    description: 'Optional explicit frame count (defaults to stops.length)',
                  },
                },
                required: ['stops'],
                additionalProperties: false,
              },
              monitorSubjectAreaChange: {
                type: 'boolean',
                description:
                  'When true, iOS enables subject-area change monitoring and should re-trigger Auto Optimize on change',
              },
              maxPhotoDimensions: {
                type: 'object',
                description: 'Preferred max photo pixel dimensions when PhotoOutput supports it',
                properties: {
                  width: { type: 'number' },
                  height: { type: 'number' },
                },
                required: ['width', 'height'],
                additionalProperties: false,
              },
              previewLUT: {
                type: 'string',
                description:
                  'Preview-only LUT id. NEVER a capture magic filter — exposure/WB/focus remain primary.',
              },
              creativeLook: {
                type: 'object',
                description:
                  'Optional P1 creative grade (ORIGINAL pack ids / product names only e.g. Crisp Cool). Same grade on preview AND still when intensity > 0; identity at 0. Capture settings remain PRIMARY. intensity optional — server defaults 0.55 when omitted/null. REQUIRED when the user asks to apply a filter/look/grade (see APPLY-FILTERS intents). Otherwise default omit (none/identity) unless the scene clearly benefits (SUGGEST). Voice e.g. "warm film look" → warmGlow or moodyFilm; "apply filters" → pick best V1 id for the scene and emit creativeLook.',
                properties: {
                  id: {
                    type: 'string',
                    enum: [...CREATIVE_LOOK_IDS],
                    description: 'Creative look id (exact spelling). selfie* ids are front-camera selfie presets.',
                  },
                  intensity: {
                    type: 'number',
                    description:
                      'Grade blend 0…1 (preview+still bake). Optional; server defaults to 0.55 when omitted/null.',
                  },
                },
                required: ['id'],
                additionalProperties: false,
              },
              simulatedAperture: {
                type: 'number',
                description:
                  'P1 / OS-gated only. If unsupported, use coachOnly.aperture instead. Never fake hardware aperture.',
              },
            },
            additionalProperties: false,
          },
          coachOnly: {
            type: 'object',
            description:
              'Guidance shown to the photographer but NOT applied by the phone API (aperture, ND, tripod, free-form notes).',
            properties: {
              aperture: {
                type: 'string',
                description: 'e.g. "f/8", "f/11–f/16" — coach readout only on most phones',
              },
              nd: {
                type: 'string',
                description: 'ND filter advice, e.g. "3-stop ND" or "none"',
              },
              tripod: {
                type: 'boolean',
                description: 'True when a tripod is strongly recommended',
              },
              notes: {
                type: 'string',
                description: 'Other coach-only notes (brace, rear-curtain, etc.)',
              },
            },
            additionalProperties: false,
          },
          panCue: {
            type: 'object',
            description:
              'When a panning / motion-tracking recipe fits, tell the photographer which way to pan with the subject.',
            properties: {
              direction: {
                type: 'string',
                enum: ['left', 'right', 'either'],
                description: 'Primary pan direction relative to the photographer',
              },
              note: {
                type: 'string',
                description: 'Optional short cue, e.g. "Match subject speed left→right"',
              },
            },
            required: ['direction'],
            additionalProperties: false,
          },
          creativeLook: {
            type: 'object',
            description:
              'Optional one-release fallback mirror of phoneTargets.creativeLook. Prefer phoneTargets.creativeLook. Same shape { id, intensity? }; intensity defaults to 0.55 when omitted.',
            properties: {
              id: {
                type: 'string',
                enum: [...CREATIVE_LOOK_IDS],
              },
              intensity: { type: 'number', description: '0…1; optional, default 0.55' },
            },
            required: ['id'],
            additionalProperties: false,
          },
          senseSummary: {
            type: 'string',
            description:
              'One-line what you sensed (light / motion / subject). Status-ready, not chatty.',
          },
        },
        required: ['presetId', 'reason', 'teachWhy', 'phoneTargets', 'coachOnly'],
        additionalProperties: false,
      },
    },
  },
]

function truncate(s: string | undefined, n: number): string | undefined {
  if (!s) return undefined
  const t = s.trim()
  if (t.length <= n) return t
  return t.slice(0, n - 1).trimEnd() + '…'
}

/** Slim catalog row for list_presets — keep tokens low; details via get_preset_details. */
function summarizePreset(p: RecipePreset) {
  return {
    id: p.id,
    title: p.title,
    tags: p.tags,
    blurb: truncate(p.blurb, 120),
    keySettings: {
      mode: p.dials.mode,
      aperture: p.dials.aperture,
      shutter: p.dials.shutter,
      iso: p.dials.iso,
    },
  }
}

function asOptionalString(v: unknown): string | undefined {
  if (typeof v !== 'string') return undefined
  const t = v.trim()
  return t ? t : undefined
}

function parseZoom(raw: unknown): number | undefined | { error: string } {
  if (raw == null) return undefined
  if (typeof raw === 'number') {
    if (!Number.isFinite(raw) || raw <= 0) {
      return { error: 'phoneTargets.zoom must be a positive finite number (videoZoomFactor)' }
    }
    // Plausible phone range; iOS clamps further per device.
    if (raw < 0.5 || raw > 16) {
      return { error: 'phoneTargets.zoom out of range (use 0.5–16 as videoZoomFactor)' }
    }
    return raw
  }
  if (typeof raw === 'string') {
    const t = raw.trim().toLowerCase().replace(/×/g, 'x')
    const m = t.match(/^(\d+(?:\.\d+)?)\s*x?$/)
    if (!m) {
      return { error: 'phoneTargets.zoom string must look like "1", "2x", or "0.5"' }
    }
    const n = Number(m[1])
    if (!Number.isFinite(n) || n <= 0 || n < 0.5 || n > 16) {
      return { error: 'phoneTargets.zoom out of range (use 0.5–16 as videoZoomFactor)' }
    }
    return n
  }
  return { error: 'phoneTargets.zoom must be a number or string like "2x"' }
}

function parseFocusPoint(
  raw: unknown,
): { x: number; y: number } | undefined | { error: string } {
  if (raw == null) return undefined
  if (typeof raw !== 'object' || Array.isArray(raw)) {
    return { error: 'phoneTargets.focusPoint must be an object { x, y }' }
  }
  const o = raw as Record<string, unknown>
  const x = o.x
  const y = o.y
  if (typeof x !== 'number' || typeof y !== 'number' || !Number.isFinite(x) || !Number.isFinite(y)) {
    return { error: 'phoneTargets.focusPoint.x and .y must be finite numbers' }
  }
  if (x < 0 || x > 1 || y < 0 || y > 1) {
    return { error: 'phoneTargets.focusPoint.x/y must be in 0–1 (normalized viewfinder)' }
  }
  return { x, y }
}

function asIsoOrEv(raw: unknown, key: 'iso' | 'ev'): string | number | undefined | { error: string } {
  if (raw == null) return undefined
  if (typeof raw === 'number') {
    if (!Number.isFinite(raw)) return { error: `phoneTargets.${key} must be finite` }
    return raw
  }
  if (typeof raw === 'string') {
    const t = raw.trim()
    return t ? t : undefined
  }
  return { error: `phoneTargets.${key} must be a string or number` }
}

function parseWhiteBalance(
  raw: unknown,
): WhiteBalanceTarget | undefined | { error: string } {
  if (raw == null) return undefined
  if (typeof raw === 'string') {
    const t = raw.trim()
    return t ? t : undefined
  }
  if (typeof raw !== 'object' || Array.isArray(raw)) {
    return { error: 'phoneTargets.whiteBalance must be a string or object' }
  }
  const o = raw as Record<string, unknown>
  const hasTemp = 'temperature' in o || 'tint' in o
  const hasGains = 'redGain' in o || 'greenGain' in o || 'blueGain' in o
  if (hasTemp && hasGains) {
    return { error: 'phoneTargets.whiteBalance: use temperature/tint OR gains, not both' }
  }
  if (hasTemp) {
    const out: WhiteBalanceTemperatureTint = {}
    for (const k of ['temperature', 'tint'] as const) {
      if (o[k] == null) continue
      if (typeof o[k] !== 'number' || !Number.isFinite(o[k] as number)) {
        return { error: `phoneTargets.whiteBalance.${k} must be a finite number` }
      }
      out[k] = o[k] as number
    }
    if (out.temperature == null && out.tint == null) return undefined
    return out
  }
  if (hasGains) {
    const out: WhiteBalanceGains = {}
    for (const k of ['redGain', 'greenGain', 'blueGain'] as const) {
      if (o[k] == null) continue
      if (typeof o[k] !== 'number' || !Number.isFinite(o[k] as number)) {
        return { error: `phoneTargets.whiteBalance.${k} must be a finite number` }
      }
      const n = o[k] as number
      if (n < 0 || n > 8) {
        return { error: `phoneTargets.whiteBalance.${k} out of range (use 0–8)` }
      }
      out[k] = n
    }
    if (out.redGain == null && out.greenGain == null && out.blueGain == null) return undefined
    return out
  }
  return { error: 'phoneTargets.whiteBalance object needs temperature/tint or redGain/greenGain/blueGain' }
}

function parseTorch(raw: unknown): TorchTarget | undefined | { error: string } {
  if (raw == null) return undefined
  if (typeof raw !== 'object' || Array.isArray(raw)) {
    return { error: 'phoneTargets.torch must be an object { mode, level? }' }
  }
  const o = raw as Record<string, unknown>
  const mode = o.mode
  if (mode !== 'off' && mode !== 'on' && mode !== 'auto') {
    return { error: 'phoneTargets.torch.mode must be off|on|auto' }
  }
  if (o.level == null) return { mode }
  if (typeof o.level !== 'number' || !Number.isFinite(o.level)) {
    return { error: 'phoneTargets.torch.level must be a finite number' }
  }
  if (o.level < 0 || o.level > 1) {
    return { error: 'phoneTargets.torch.level must be in 0–1' }
  }
  return { mode, level: o.level }
}

function parseBracket(raw: unknown): BracketTarget | undefined | { error: string } {
  if (raw == null) return undefined
  if (typeof raw !== 'object' || Array.isArray(raw)) {
    return undefined
  }
  const o = raw as Record<string, unknown>
  if (!Array.isArray(o.stops) || o.stops.length < 1 || o.stops.length > 9) {
    return undefined
  }
  const stops: number[] = []
  for (const s of o.stops) {
    if (typeof s !== 'number' || !Number.isFinite(s)) {
      return undefined
    }
    if (s < -5 || s > 5) {
      return undefined
    }
    stops.push(s)
  }
  if (o.count == null) return { stops }
  if (typeof o.count !== 'number' || !Number.isFinite(o.count) || o.count < 1 || o.count > 9) {
    return undefined
  }
  return { stops, count: Math.round(o.count) }
}

function parseMaxPhotoDimensions(
  raw: unknown,
): MaxPhotoDimensions | undefined | { error: string } {
  if (raw == null) return undefined
  if (typeof raw !== 'object' || Array.isArray(raw)) {
    return { error: 'phoneTargets.maxPhotoDimensions must be { width, height }' }
  }
  const o = raw as Record<string, unknown>
  const w = o.width
  const h = o.height
  if (typeof w !== 'number' || typeof h !== 'number' || !Number.isFinite(w) || !Number.isFinite(h)) {
    return { error: 'phoneTargets.maxPhotoDimensions.width/height must be finite numbers' }
  }
  if (w < 1 || h < 1 || w > 20000 || h > 20000) {
    return { error: 'phoneTargets.maxPhotoDimensions out of range' }
  }
  return { width: Math.round(w), height: Math.round(h) }
}

function parseCreativeLook(
  raw: unknown,
  pathLabel = 'phoneTargets.creativeLook',
): CreativeLook | undefined | { error: string } {
  if (raw == null) return undefined
  if (typeof raw !== 'object' || Array.isArray(raw)) {
    return { error: `${pathLabel} must be an object { id, intensity? }` }
  }
  const o = raw as Record<string, unknown>
  const id = o.id
  if (typeof id !== 'string' || !CREATIVE_LOOK_ID_SET.has(id)) {
    return {
      error:
        `${pathLabel}.id must be one of the creative look pack (${CREATIVE_LOOK_IDS.join(', ')})`,
    }
  }
  // Omit / null → default 0.55; explicit number must be finite 0…1
  let intensity: number
  if (o.intensity == null) {
    intensity = CREATIVE_LOOK_DEFAULT_INTENSITY
  } else if (typeof o.intensity !== 'number' || !Number.isFinite(o.intensity)) {
    return { error: `${pathLabel}.intensity must be a finite number` }
  } else if (o.intensity < 0 || o.intensity > 1) {
    return { error: `${pathLabel}.intensity must be in 0–1` }
  } else {
    intensity = o.intensity
  }
  return { id: id as CreativeLookId, intensity }
}

export function parsePhoneTargets(raw: unknown): PhoneTargets | { error: string } {
  if (raw == null || typeof raw !== 'object' || Array.isArray(raw)) {
    return { error: 'phoneTargets must be an object' }
  }
  const o = raw as Record<string, unknown>
  const out: PhoneTargets = {}
  const shutter = asOptionalString(o.shutter)
  if (shutter) out.shutter = shutter

  if (o.exposureDurationSec != null) {
    if (typeof o.exposureDurationSec !== 'number' || !Number.isFinite(o.exposureDurationSec)) {
      return { error: 'phoneTargets.exposureDurationSec must be a finite number (seconds)' }
    }
    if (o.exposureDurationSec <= 0 || o.exposureDurationSec > 30) {
      return { error: 'phoneTargets.exposureDurationSec out of range (use >0…30s)' }
    }
    out.exposureDurationSec = o.exposureDurationSec
  }

  const iso = asIsoOrEv(o.iso, 'iso')
  if (iso && typeof iso === 'object' && 'error' in iso) return iso
  if (iso !== undefined && typeof iso !== 'object') out.iso = iso

  const ev = asIsoOrEv(o.ev, 'ev')
  if (ev && typeof ev === 'object' && 'error' in ev) return ev
  if (ev !== undefined && typeof ev !== 'object') out.ev = ev

  const whiteBalance = parseWhiteBalance(o.whiteBalance)
  if (whiteBalance && typeof whiteBalance === 'object' && 'error' in whiteBalance) {
    return whiteBalance
  }
  // String presets (e.g. "auto") are valid; only objects use the 'error' discriminant.
  if (whiteBalance !== undefined) {
    out.whiteBalance = whiteBalance as WhiteBalanceTarget
  }

  const focusMode = asOptionalString(o.focusMode)
  if (focusMode) out.focusMode = focusMode

  const zoom = parseZoom(o.zoom)
  if (zoom && typeof zoom === 'object' && 'error' in zoom) return zoom
  if (typeof zoom === 'number') out.zoom = zoom

  const focusPoint = parseFocusPoint(o.focusPoint)
  if (focusPoint && typeof focusPoint === 'object' && 'error' in focusPoint) {
    return focusPoint
  }
  if (focusPoint && 'x' in focusPoint) out.focusPoint = focusPoint

  if (o.lensPosition != null) {
    if (typeof o.lensPosition !== 'number' || !Number.isFinite(o.lensPosition)) {
      return { error: 'phoneTargets.lensPosition must be a finite number' }
    }
    if (o.lensPosition < 0 || o.lensPosition > 1) {
      return { error: 'phoneTargets.lensPosition must be in 0–1' }
    }
    out.lensPosition = o.lensPosition
  }

  const torch = parseTorch(o.torch)
  if (torch && typeof torch === 'object' && 'error' in torch) return torch
  if (torch && 'mode' in torch) out.torch = torch

  if (o.flash != null) {
    if (o.flash !== 'off' && o.flash !== 'on' && o.flash !== 'auto') {
      return { error: 'phoneTargets.flash must be off|on|auto' }
    }
    out.flash = o.flash
  }

  if (o.lowLightBoost != null) {
    if (typeof o.lowLightBoost !== 'boolean') {
      return { error: 'phoneTargets.lowLightBoost must be boolean' }
    }
    out.lowLightBoost = o.lowLightBoost
  }

  if (o.videoHDR != null) {
    if (typeof o.videoHDR !== 'boolean') {
      return { error: 'phoneTargets.videoHDR must be boolean' }
    }
    out.videoHDR = o.videoHDR
  }

  if (o.cameraDevice != null) {
    if (o.cameraDevice !== 'ultraWide' && o.cameraDevice !== 'wide' && o.cameraDevice !== 'tele') {
      return { error: 'phoneTargets.cameraDevice must be ultraWide|wide|tele' }
    }
    out.cameraDevice = o.cameraDevice
  }

  if (o.frameRate != null) {
    if (typeof o.frameRate !== 'number' || !Number.isFinite(o.frameRate)) {
      return { error: 'phoneTargets.frameRate must be a finite number' }
    }
    if (o.frameRate < 1 || o.frameRate > 240) {
      return { error: 'phoneTargets.frameRate out of range (use 1–240)' }
    }
    out.frameRate = o.frameRate
  }

  const preferFormatHint = asOptionalString(o.preferFormatHint)
  if (preferFormatHint) out.preferFormatHint = preferFormatHint

  const bracket = parseBracket(o.bracket)
  if (bracket && typeof bracket === 'object' && 'error' in bracket) return bracket
  if (bracket && 'stops' in bracket) out.bracket = bracket

  if (o.monitorSubjectAreaChange != null) {
    if (typeof o.monitorSubjectAreaChange !== 'boolean') {
      return { error: 'phoneTargets.monitorSubjectAreaChange must be boolean' }
    }
    out.monitorSubjectAreaChange = o.monitorSubjectAreaChange
  }

  const maxPhotoDimensions = parseMaxPhotoDimensions(o.maxPhotoDimensions)
  if (maxPhotoDimensions && typeof maxPhotoDimensions === 'object' && 'error' in maxPhotoDimensions) {
    return maxPhotoDimensions
  }
  if (maxPhotoDimensions && 'width' in maxPhotoDimensions) {
    out.maxPhotoDimensions = maxPhotoDimensions
  }

  const previewLUT = asOptionalString(o.previewLUT)
  if (previewLUT) out.previewLUT = previewLUT

  const creativeLook = parseCreativeLook(o.creativeLook)
  if (creativeLook && typeof creativeLook === 'object' && 'error' in creativeLook) {
    return creativeLook
  }
  if (creativeLook && 'id' in creativeLook) out.creativeLook = creativeLook

  if (o.simulatedAperture != null) {
    if (typeof o.simulatedAperture !== 'number' || !Number.isFinite(o.simulatedAperture)) {
      return { error: 'phoneTargets.simulatedAperture must be a finite number' }
    }
    if (o.simulatedAperture < 0.5 || o.simulatedAperture > 32) {
      return { error: 'phoneTargets.simulatedAperture out of range (use 0.5–32)' }
    }
    out.simulatedAperture = o.simulatedAperture
  }

  return out
}

function parseCoachOnly(raw: unknown): CoachOnly | { error: string } {
  if (raw == null || typeof raw !== 'object' || Array.isArray(raw)) {
    return { error: 'coachOnly must be an object' }
  }
  const o = raw as Record<string, unknown>
  const out: CoachOnly = {}
  const aperture = asOptionalString(o.aperture)
  const nd = asOptionalString(o.nd)
  const notes = asOptionalString(o.notes)
  if (aperture) out.aperture = aperture
  if (nd) out.nd = nd
  if (notes) out.notes = notes
  if (typeof o.tripod === 'boolean') out.tripod = o.tripod
  return out
}

function parsePanCue(raw: unknown): PanCue | undefined | { error: string } {
  if (raw == null) return undefined
  if (typeof raw !== 'object' || Array.isArray(raw)) {
    return { error: 'panCue must be an object when provided' }
  }
  const o = raw as Record<string, unknown>
  const direction = o.direction
  if (direction !== 'left' && direction !== 'right' && direction !== 'either') {
    return { error: 'panCue.direction must be "left", "right", or "either"' }
  }
  const note = asOptionalString(o.note)
  return note ? { direction, note } : { direction }
}

function executeTool(
  name: string,
  argsJson: string,
): { result: unknown; selection?: SelectionPayload } {
  let args: Record<string, unknown> = {}
  try {
    args = argsJson ? (JSON.parse(argsJson) as Record<string, unknown>) : {}
  } catch {
    return { result: { error: 'Invalid JSON arguments' } }
  }

  if (name === 'list_presets') {
    return { result: { presets: selectablePresets.map(summarizePreset) } }
  }

  if (name === 'get_preset_details') {
    const id = String(args.presetId ?? '')
    const preset = presets.find((p) => p.id === id)
    if (!preset) {
      return {
        result: {
          error: `Unknown presetId "${id}". Use an id from list_presets.`,
        },
      }
    }
    return {
      result: {
        id: preset.id,
        title: preset.title,
        page: preset.page,
        tags: preset.tags,
        blurb: preset.blurb,
        whenToUse: preset.whenToUse,
        dials: preset.dials,
        steps: preset.steps,
        tips: preset.tips,
        gear: preset.gear,
        equipmentChecklist: preset.equipmentChecklist,
        phoneTip: preset.phoneTip,
        advancedTip: preset.advancedTip,
        subVariants: preset.subVariants?.map((v) => ({
          id: v.id,
          label: v.label,
          description: v.description,
          dials: v.dials,
          tips: v.tips,
        })),
      },
    }
  }

  if (name === 'select_preset') {
    const presetId = String(args.presetId ?? '')
    const reason = String(args.reason ?? '')
    const teachWhy = String(args.teachWhy ?? '')
    const tips = Array.isArray(args.tips)
      ? args.tips.map((t) => String(t)).filter(Boolean)
      : []
    const preset = selectablePresets.find((p) => p.id === presetId)
    if (!preset) {
      return {
        result: {
          error: `Cannot select unknown presetId "${presetId}". Call list_presets and pick a valid id.`,
        },
      }
    }
    if (!reason.trim()) {
      return { result: { error: 'reason is required' } }
    }
    if (!teachWhy.trim()) {
      return { result: { error: 'teachWhy is required (1–2 short sentences for Teach mode)' } }
    }
    if (tips.length > 3) {
      return { result: { error: 'tips: at most 3 short field tips' } }
    }

    const phoneTargets = parsePhoneTargets(args.phoneTargets)
    if ('error' in phoneTargets) {
      return { result: { error: phoneTargets.error } }
    }
    const coachOnly = parseCoachOnly(args.coachOnly)
    if ('error' in coachOnly) {
      return { result: { error: coachOnly.error } }
    }
    const panCue = parsePanCue(args.panCue)
    if (panCue && 'error' in panCue) {
      return { result: { error: panCue.error } }
    }

    // creativeLook: phoneTargets primary; top-level one-release fallback
    const topCreativeLook = parseCreativeLook(args.creativeLook, 'creativeLook')
    if (topCreativeLook && typeof topCreativeLook === 'object' && 'error' in topCreativeLook) {
      return { result: { error: topCreativeLook.error } }
    }
    if (!phoneTargets.creativeLook && topCreativeLook && 'id' in topCreativeLook) {
      phoneTargets.creativeLook = topCreativeLook
    }
    const creativeLook = phoneTargets.creativeLook

    const senseSummary = asOptionalString(args.senseSummary)
    const selection: SelectionPayload = {
      presetId,
      reason: reason.trim(),
      teachWhy: teachWhy.trim(),
      tips,
      phoneTargets,
      coachOnly,
      ...(panCue ? { panCue } : {}),
      ...(senseSummary ? { senseSummary } : {}),
      ...(creativeLook ? { creativeLook } : {}),
    }

    return {
      result: { ok: true, ...selection },
      selection,
    }
  }

  return { result: { error: `Unknown tool: ${name}` } }
}

async function callXai(
  apiKey: string,
  model: string,
  messages: ChatMessage[],
  toolChoice: 'auto' | 'required' | { type: 'function'; function: { name: string } } = 'auto',
): Promise<{ ok: true; data: Record<string, unknown> } | { ok: false; status: number; body: string }> {
  const res = await fetch(`${XAI_BASE}/chat/completions`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model,
      temperature: 0.3,
      messages,
      tools,
      // Prefer tools on early rounds so the model does not free-chat past the catalog.
      tool_choice: toolChoice,
    }),
  })

  const body = await res.text()
  if (!res.ok) {
    return { ok: false, status: res.status, body }
  }
  try {
    return { ok: true, data: JSON.parse(body) as Record<string, unknown> }
  } catch {
    return { ok: false, status: 502, body: 'Invalid JSON from xAI' }
  }
}

/** Copy-pasteable system prompt — keep in sync with docs/agentic-prompt-v2.md */
export function buildSystemPrompt(favorites?: string[], vision?: boolean): string {
  const favLine =
    favorites && favorites.length > 0
      ? `\nThe user has favorited these preset ids (prefer them only when they fit the scene equally well): ${favorites.join(', ')}.`
      : ''

  const senseLine = vision
    ? `SENSE (vision): Inspect the attached image plus any scene note. Infer light (direction/quality/contrast), motion, subject, depth cues, and dynamic range. Status-ready — think like a viewfinder caption, not a chat reply.`
    : `SENSE (text): Infer light, motion, subject, and depth from the photographer's scene note. Status-ready field notes only.`

  return `You are the Photo Recipes field assistant for Auto Optimize (Camera) and Ask / Photo Vision (web + iOS).
Primary job: analyze the scene from the viewfinder (image + optional note) → select one catalog recipe → emit phoneTargets for Auto Optimize to apply (AVFoundation levers: exposure/WB/focus/lens/zoom/cameraDevice/torch/flash/HDR/bracket/…).
Tone: darkroom field notes — quiet, concrete, instructor-at-your-shoulder. Never chatty. Never invent recipes.

LOOP (strict):
1. SENSE — ${senseLine}
2. REASON — Call list_presets once (slim catalog). Only get_preset_details if two candidates are close. Then select_preset promptly — do not re-list.
3. ACT / FINALIZE — Call select_preset with structured phoneTargets + coachOnly (+ panCue when motion/panning fits).
4. VERIFY (mental check before select_preset) — Targets match the recipe technique and any control ask in the note; exposure/ISO/EV/zoom/lens/torch ranges are phone-plausible; aperture/ND/tripod stay in coachOnly (simulatedAperture only if OS-gated); previewLUT is preview-only; creativeLook bakes preview+still when intensity>0 (default omit look; intensity defaults 0.55); panCue only for panning/motion recipes.

ALTERNATE INPUT (spoken / STT transcripts — secondary):
- When the user message is a voice transcript, treat it as another way into the same Sense → recommend → phoneTargets apply path (not Ask text-field-only).
- Even without picking a new recipe, you MUST still call tools and emit phoneTargets that match the ask — same apply path as Auto Optimize (AVCapture session).
- Map spoken intents → phoneTargets (and panCue / teachWhy when useful), e.g.:
  • "slower shutter for panning" → phoneTargets.shutter (e.g. "1/30") + panCue + teachWhy
  • "lock focus on the rider" → phoneTargets.focusMode "locked" (+ optional focusPoint {x,y} 0–1 if you can infer a region)
  • "zoom in a bit" / "go to 2x" → phoneTargets.zoom (videoZoomFactor number: 1 = 1×, 2 = 2×)
  • "pull EV down" → phoneTargets.ev; "daylight WB" → phoneTargets.whiteBalance
  • "switch to ultra-wide" → phoneTargets.cameraDevice "ultraWide"; "lock lens near" → lensPosition
  • "torch on low" → torch { mode: "on", level }; "flash off" → flash "off"
  • "bracket for HDR" → bracket { stops: [-2,0,2] }; "re-optimize if subject moves" → monitorSubjectAreaChange true
  • "warm film look" / "moody grade" / "teal orange" → creativeLook { id, intensity? } mapped to V1 pack (e.g. warmGlow, moodyFilm, tealOrange); intensity optional (server 0.55)
  • APPLY-FILTERS intents (text or STT) — MUST emit creativeLook (never omit / never empty):
      "apply filters" / "apply filter" / "add a filter" / "put a filter on" / "use a filter" /
      "apply a look" / "add a look" / "grade this" / "color grade" / "give it a look" /
      "make it cinematic" / "make it moody" / "make it warm" /
      "film look" / "teal and orange" / "add grain"
    → Still call list_presets + select_preset (keep current recipe if it fits). phoneTargets MUST include creativeLook { id, intensity? }.
    → Pick the best V1 id for the sensed scene (or the named look if they specified one). Default intensity omit → server 0.55.
    → Do NOT refuse or reply with coach-only text; the client auto-applies creativeLook on Recommend.
  • B&W (text or STT) — REQUIRED creativeLook.id = "monoInk" (intensity optional → 0.55):
      "black and white" / "B&W" / "b&w" / "bw" / "mono" / "monochrome" / "make it black and white"
    → Never omit; never emit a color look for these utterances.
  • LOOK OVERRIDE — each new user message / STT final **replaces** any prior creativeLook intent. Do not blend the previous look with the new ask; emit only the look that matches THIS message.
- When the intent is a control adjustment, phoneTargets MUST include the relevant keys (do not finalize with empty {} if they asked to change a settable control).

CRITICAL RULES:
- Catalog only: never invent preset ids, titles, or off-catalog recipes.
- If the user asks to apply a filter/look/grade (APPLY-FILTERS intents), creativeLook is REQUIRED on select_preset — pick a V1 pack id for the scene; never finalize without it.
- You MUST use tools.
- Even for text-only (no image), emit core phoneTargets (shutter/iso/ev/whiteBalance/focusMode) when the scene implies them — not only bracket. Do not free-form recommend without select_preset.
- phoneTargets = AVFoundation levers only (all optional; omit if unsupported): shutter, exposureDurationSec, iso, ev, whiteBalance (string|{temperature,tint}|{redGain,greenGain,blueGain}), focusMode, focusPoint, lensPosition, zoom, cameraDevice (ultraWide|wide|tele), torch {mode,level?}, flash, lowLightBoost, videoHDR, frameRate, preferFormatHint, bracket {stops,count?}, monitorSubjectAreaChange, maxPhotoDimensions, previewLUT (preview-only — NEVER a capture magic filter), creativeLook { id, intensity? 0–1 } (optional P1 bakeable grade from V1 pack — same on preview AND still when intensity>0; default omit/none/identity; intensity defaults 0.55; capture settings remain PRIMARY; product names only e.g. Crisp Cool), simulatedAperture (P1/OS-gated only). SUGGEST a V1 creativeLook when the story clearly benefits (golden hour→goldenHour/warmGlow; night city→coolBlue/moodyFilm; cinematic complementary→tealOrange; high-contrast drama→blockbuster; graphic B&W→monoInk; soft dreamy→softDream; grainy street→filmGrain); omit for neutral/documentary scenes.
- NEVER put hardware aperture in phoneTargets — use coachOnly.aperture (nd, tripod, notes stay coach-only). Prefer cameraDevice over zoom-only lens hints.
- coachOnly = aperture, nd, tripod, notes — shown to the photographer, NOT applied on device.
- teachWhy = 1–2 short sentences for Teach mode ("Why this?").
- tips = max 3 short field tips.
- panCue = optional { direction: left|right|either, note? } when the subject moves and panning helps.
- senseSummary = optional one-line status (light/motion/subject).
- Bounded loop: finish with select_preset promptly. Do not keep listing after you know the answer.
- Match technique to the scene (sunset + dark foreground → HDR/bracket; kid/cyclist running → panning/motion; full-frame sharpness → depth of field; fresh angle → get low).${favLine}`
}

function buildUserContent(req: RecommendRequest): string | ContentPart[] {
  const note = req.message.trim()
  const text = note
    ? `Scene note from the photographer:\n${note}\n\nSense the scene (image + note). Recommend the best catalog recipe and finalize with select_preset.`
    : 'Sense this photo. Recommend the best photography recipe from the catalog and finalize with select_preset.'

  if (!req.imageDataUrl) {
    return req.message.trim()
  }

  return [
    { type: 'text', text },
    {
      type: 'image_url',
      image_url: { url: req.imageDataUrl, detail: VISION_IMAGE_DETAIL },
    },
  ]
}

function isModelMissing(status: number, body: string): boolean {
  if (status === 404) return true
  const lower = body.toLowerCase()
  return (
    status === 400 &&
    (lower.includes('model') || lower.includes('not found') || lower.includes('does not exist'))
  )
}

async function recommendWithToolLoop(
  apiKey: string,
  req: RecommendRequest,
): Promise<RecommendResult> {
  const vision = Boolean(req.imageDataUrl)
  const timeoutMs = vision ? FAST_VISION_TIMEOUT_MS : FAST_TEXT_TIMEOUT_MS
  const cid = req.log?.correlationId ?? newRecommendCorrelationId()
  const lookOverride = inferCreativeLookOverride(req.message)
  if (!vision && !req.message.trim()) {
    throw Object.assign(new Error('Message or image is required'), { status: 400 })
  }

  const systemPrompt = buildSystemPrompt(req.favorites, vision)
  const userContent = buildUserContent(req)
  const sysFp = promptFingerprint(systemPrompt)
  const userTextForLog =
    typeof userContent === 'string'
      ? userContent
      : userContent
          .map((p) =>
            p.type === 'text'
              ? p.text
              : p.type === 'image_url'
                ? redactDataUrls(p.image_url.url)
                : '',
          )
          .join('\n')

  logRecommend('recommend', 'request_in', {
    correlationId: cid,
    guestId: req.log?.guestIdShort,
    platform: req.log?.platform,
    message: req.message,
    vision,
    path: 'tool-loop',
    applyFiltersIntent: isApplyFiltersIntent(req.message),
    creativeLookOverride: lookOverride ?? null,
    systemPromptLen: sysFp.len,
    systemPromptSha8: sysFp.sha8,
  })
  logRecommend('creativeLook', 'request_in', {
    correlationId: cid,
    message: req.message,
    override: lookOverride ?? null,
    applyFiltersIntent: isApplyFiltersIntent(req.message),
    path: 'tool-loop',
  })

  const messages: ChatMessage[] = [
    { role: 'system', content: systemPrompt },
    { role: 'user', content: userContent },
  ]

  const modelQueue = vision
    ? [...VISION_MODELS]
    : [PRIMARY_MODEL, FALLBACK_MODEL]
  let model = modelQueue[0]!
  let modelIndex = 0
  let selection: SelectionPayload | undefined
  let sawListOrDetails = false

  for (let round = 0; round < MAX_ROUNDS; round++) {
    // Early rounds: require a tool call so the model cannot skip the catalog.
    // After list/details, allow auto so it can choose select_preset vs more details.
    // Round 0: force list_presets (named) to skip free-chat + wasted rounds.
    // Round 1: require any tool if we still have not listed.
    // Later: auto so the model can select_preset.
    type ToolChoice =
      | 'auto'
      | 'required'
      | { type: 'function'; function: { name: string } }
    const toolChoice: ToolChoice =
      !selection && round === 0 && !sawListOrDetails
        ? { type: 'function', function: { name: 'list_presets' } }
        : !selection && !sawListOrDetails && round < 2
          ? 'required'
          : 'auto'

    const started = Date.now()
    logRecommend('recommend', 'xai_outbound', {
      correlationId: cid,
      path: 'tool-loop',
      model,
      round,
      toolChoice:
        typeof toolChoice === 'string' ? toolChoice : toolChoice.function.name,
      message: req.message,
      userText: userTextForLog.slice(0, 500),
      systemPromptLen: sysFp.len,
      systemPromptSha8: sysFp.sha8,
    })
    let response = await callXai(apiKey, model, messages, toolChoice)

    while (
      !response.ok &&
      isModelMissing(response.status, response.body) &&
      modelIndex < modelQueue.length - 1
    ) {
      modelIndex += 1
      model = modelQueue[modelIndex]!
      console.warn(`[recommend] model unavailable, falling back to ${model}`)
      response = await callXai(apiKey, model, messages, toolChoice)
    }

    // Some models reject tool_choice required / named function — retry once with auto.
    if (
      !response.ok &&
      toolChoice !== 'auto' &&
      (response.status === 400 || response.status === 422)
    ) {
      console.warn(
        `[recommend] tool_choice=${typeof toolChoice === 'string' ? toolChoice : toolChoice.function.name} rejected; retrying with auto`,
      )
      response = await callXai(apiKey, model, messages, 'auto')
    }

    if (!response.ok) {
      logRecommend('recommend', 'xai_error', {
        correlationId: cid,
        path: 'tool-loop',
        model,
        round,
        status: response.status,
        bodySnippet: redactDataUrls(response.body).slice(0, 400),
      })
      const visionHint = vision
        ? ' Vision models may be unavailable for this API key; try text Ask Grok or check xAI model access.'
        : ''
      const err = new Error(
        `xAI API error (${response.status}). Check model availability and API key.${visionHint}`,
      ) as Error & { status?: number; details?: string }
      err.status = response.status >= 400 && response.status < 600 ? response.status : 502
      // Never include image bytes; body may be truncated error JSON only
      err.details = response.body.slice(0, 500)
      throw err
    }

    const choices = response.data.choices as
      | Array<{ message?: ChatMessage; finish_reason?: string }>
      | undefined
    const finishReason = choices?.[0]?.finish_reason
    const usage = response.data.usage
    const toolCallsSummary = (choices?.[0]?.message?.tool_calls ?? []).map((tc) => ({
      name: tc.function.name,
      argsLen: tc.function.arguments?.length ?? 0,
    }))
    logRecommend('recommend', 'xai_response', {
      correlationId: cid,
      path: 'tool-loop',
      model,
      round,
      ms: Date.now() - started,
      finishReason: finishReason ?? null,
      toolCalls: toolCallsSummary,
      usage: usage ?? null,
      toolChoice:
        typeof toolChoice === 'string' ? toolChoice : toolChoice.function.name,
    })
    console.info(`[recommend] round=${round} model=${model} tool_choice=${typeof toolChoice === 'string' ? toolChoice : toolChoice.function.name} ${Date.now() - started}ms`)

    const assistant = choices?.[0]?.message
    if (!assistant) {
      throw Object.assign(new Error('Empty response from Grok'), { status: 502 })
    }

    messages.push({
      role: 'assistant',
      content: assistant.content ?? null,
      tool_calls: assistant.tool_calls,
    })

    const toolCalls = assistant.tool_calls
    if (!toolCalls || toolCalls.length === 0) {
      messages.push({
        role: 'user',
        content:
          'You must use tools. Call list_presets, then select_preset with a catalog id, teachWhy, phoneTargets (include shutter/ISO/EV/WB/focus/zoom/focusPoint when the user asked for those controls), and coachOnly. Do not invent recipes.',
      })
      continue
    }

    for (const tc of toolCalls) {
      if (tc.function.name === 'list_presets' || tc.function.name === 'get_preset_details') {
        sawListOrDetails = true
      }
      const { result, selection: sel } = executeTool(
        tc.function.name,
        tc.function.arguments,
      )
      messages.push({
        role: 'tool',
        tool_call_id: tc.id,
        name: tc.function.name,
        content: JSON.stringify(result),
      })
      if (sel) {
        const rawLook = sel.creativeLook ?? sel.phoneTargets.creativeLook
        logRecommend('creativeLook', 'xai_raw', {
          correlationId: cid,
          path: 'tool-loop',
          model,
          phoneTargetsCreativeLook: sel.phoneTargets.creativeLook ?? null,
          topLevelCreativeLook: sel.creativeLook ?? null,
          rawCreativeLook: rawLook ?? null,
        })
        const finalized = finalizeCreativeLookForClient(
          req.message,
          sel.phoneTargets,
          sel.creativeLook,
        )
        logRecommend('creativeLook', 'after_override', {
          correlationId: cid,
          path: 'tool-loop',
          model,
          rawCreativeLook: finalized.rawCreativeLook ?? null,
          finalCreativeLook: finalized.creativeLook ?? null,
          overrideMatched: finalized.overrideMatched,
        })
        if (finalized.creativeLook) {
          selection = {
            ...sel,
            creativeLook: finalized.creativeLook,
            phoneTargets: finalized.phoneTargets,
          }
        } else {
          selection = sel
        }
      }
    }

    if (selection) {
      const preset = presets.find((p) => p.id === selection!.presetId)!
      logRecommend('recommend', 'result', {
        correlationId: cid,
        path: 'tool-loop',
        model,
        presetId: selection.presetId,
        creativeLook: selection.creativeLook ?? selection.phoneTargets.creativeLook ?? null,
      })
      return {
        presetId: selection.presetId,
        reason: selection.reason,
        teachWhy: selection.teachWhy,
        tips: selection.tips,
        phoneTargets: selection.phoneTargets,
        coachOnly: selection.coachOnly,
        panCue: selection.panCue,
        senseSummary: selection.senseSummary,
        ...(selection.creativeLook ? { creativeLook: selection.creativeLook } : {}),
        preset,
        model,
        // Do not return `messages` — they embed the vision data URL (pass-through only).
      }
    }

    // Nudge toward finalize if we already listed and are burning rounds
    if (sawListOrDetails && round >= 2) {
      messages.push({
        role: 'user',
        content:
          'Finalize now: call select_preset with a valid catalog presetId, reason, teachWhy, phoneTargets matching any control ask in the note (shutter/ISO/EV/WB/focus/zoom/focusPoint), and coachOnly (and panCue if panning).',
      })
    }
  }

  throw Object.assign(
    new Error(
      'Grok did not call select_preset within the tool-call limit (max 5 rounds). Try again with a clearer scene note.',
    ),
    { status: 502 },
  )
}


/**
 * Env-only legacy switch (empty-message AO debug). Prefer shouldUseRecommendToolLoop(req).
 * Non-empty spoken/typed messages always use the tool loop regardless of this flag.
 */
export function useRecommendToolLoop(): boolean {
  return process.env.RECOMMEND_TOOL_LOOP === '1'
}

/**
 * Product routing: non-empty req.message (STT / typed Scene Ask / APPLY-FILTERS)
 * → recommendWithToolLoop. Empty message → fast one-shot (image-only Auto Optimize).
 * RECOMMEND_TOOL_LOOP=1 still forces tool-loop for empty-message AO (debug).
 */
export function shouldUseRecommendToolLoop(
  req: Pick<RecommendRequest, 'message'>,
): boolean {
  if (typeof req.message === 'string' && req.message.trim().length > 0) return true
  return useRecommendToolLoop()
}

/** Compact catalog for one-shot prompt (id + short title/when). */
export function buildCompactRecipeCatalog(): string {
  return selectablePresets
    .map((p) => {
      const when = truncate(p.whenToUse, 90) || truncate(p.blurb, 80) || ''
      return `- ${p.id}: ${p.title}${when ? ` — ${when}` : ''}`
    })
    .join('\n')
}

export function buildFastSystemPrompt(favorites?: string[], vision?: boolean): string {
  const favLine =
    favorites && favorites.length > 0
      ? `\nPrefer these favorited ids only when they fit equally well: ${favorites.join(', ')}.`
      : ''
  const sense = vision
    ? 'Look at the image (and any note). Infer light, motion, subject, and dynamic range in one beat.'
    : "Infer light, motion, subject, and depth from the photographer's scene note."
  const catalog = buildCompactRecipeCatalog()

  return `You are Photo Recipes field coach — ONE-SHOT, latency-critical.
${sense} Pick exactly ONE catalog recipe. Do NOT invent recipes. Do NOT emit phone camera JSON.
Tone: darkroom field notes — quiet, concrete.

CATALOG (pick recipeId from this list only):
${catalog}${favLine}

Return ONLY a JSON object:
{
  "recipeId": "<exact catalog id>",
  "tips": ["short tip", "..."],   // 1–3 tips, required
  "reason": "1–2 sentences why this recipe",
  "teachWhy": "1 sentence technique lesson",
  "senseSummary": "one-line light/motion/subject"
}

Rules:
- recipeId MUST be an exact id from CATALOG.
- tips required (1–3), each under 12 words.
- No phoneTargets, no bracket, no tools, no markdown.
`
}

export function buildFastUserContent(req: RecommendRequest): string | ContentPart[] {
  const note = req.message.trim()
  const text = note
    ? `Scene note from the photographer:\n${note}\n\nSense the scene and reply with the JSON object only.`
    : 'Sense this photo and reply with the JSON object only (recipeId + tips + reason).'

  if (!req.imageDataUrl) {
    return text
  }
  return [
    { type: 'text', text },
    {
      type: 'image_url',
      image_url: { url: req.imageDataUrl, detail: VISION_IMAGE_DETAIL },
    },
  ]
}

/** Strip optional ```json fences and parse. */
export function extractJsonObject(raw: string): unknown {
  let s = raw.trim()
  const fence = /^```(?:json)?\s*([\s\S]*?)```$/i.exec(s)
  if (fence) s = fence[1]!.trim()
  // If model prepended prose, take outermost {…}
  if (!s.startsWith('{')) {
    const start = s.indexOf('{')
    const end = s.lastIndexOf('}')
    if (start >= 0 && end > start) s = s.slice(start, end + 1)
  }
  return JSON.parse(s) as unknown
}

/**
 * Normalize one-shot model JSON → SelectionPayload fields.
 * Accepts recipeId|presetId and phoneTarget|phoneTargets aliases.
 */

/** Map catalog dials → a light PhoneTargets shell (web coach + iOS apply fallback). */
export function phoneTargetsFromPreset(preset: RecipePreset): PhoneTargets {
  const d = preset.dials ?? {}
  const out: PhoneTargets = {}
  const iso = typeof d.iso === 'string' ? d.iso : undefined
  if (iso && /\d/.test(iso)) {
    const n = Number(String(iso).replace(/[^0-9.]/g, ''))
    if (Number.isFinite(n) && n > 0) out.iso = Math.round(n)
  }
  const shutter = typeof d.shutter === 'string' ? d.shutter : undefined
  if (shutter && /\d/.test(shutter) && !/auto|bracket/i.test(shutter)) {
    out.shutter = shutter.split(/[·•|]/)[0]!.trim()
  }
  const notes = typeof d.notes === 'string' ? d.notes : ''
  if (/tripod/i.test(notes) || /tripod/i.test(String(d.shutter ?? ''))) {
    // coachOnly carries tripod; nothing to set on phoneTargets
  }
  if (typeof d.evBracket === 'string' && /−|\+|\d/.test(d.evBracket)) {
    // HDR recipes: suggest a simple ±2 bracket when the book says so
    if (/−2|\-2/.test(d.evBracket) && /\+2/.test(d.evBracket)) {
      out.bracket = { stops: [-2, 0, 2] }
    }
  }
  return out
}

export function parseFastRecommendPayload(raw: unknown): SelectionPayload | { error: string } {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    return { error: 'Model response must be a JSON object' }
  }
  const args = raw as Record<string, unknown>

  const recipeIdRaw =
    asOptionalString(args.recipeId) ||
    asOptionalString(args.presetId) ||
    ''
  const tips = Array.isArray(args.tips)
    ? args.tips.map((t) => String(t)).filter(Boolean).slice(0, 3)
    : []
  if (tips.length === 0) {
    return { error: 'tips: at least one short field tip is required' }
  }

  let presetId = recipeIdRaw
  let preset = selectablePresets.find((p) => p.id === presetId)
  if (presetId && !preset) {
    return {
      error: `Unknown recipeId "${presetId}". Use an id from the catalog.`,
    }
  }
  if (!preset) {
    // Soft fallback: a general-purpose recipe so apply path still has a preset shell.
    preset =
      presets.find((p) => p.id === 'sharp-front-to-back') ?? presets[0]
    if (!preset) return { error: 'Recipe catalog is empty' }
    presetId = preset.id
  }

  const reason =
    asOptionalString(args.reason) ||
    `Matched ${preset.title} for this scene.`
  const teachWhy =
    asOptionalString(args.teachWhy) ||
    `Use ${preset.title} technique for this light and subject.`

  const phoneRaw =
    args.phoneTargets !== undefined
      ? args.phoneTargets
      : args.phoneTarget !== undefined
        ? args.phoneTarget
        : {}
  let phoneTargets: PhoneTargets = {}
  const parsedPhone = parsePhoneTargets(phoneRaw)
  if ('error' in parsedPhone) {
    // Thin coach path: never fail the whole recommend on optional dial JSON.
    console.warn('[recommend] soft-drop phoneTargets:', parsedPhone.error)
    phoneTargets = {}
  } else {
    phoneTargets = parsedPhone
  }

  const coachRaw = args.coachOnly !== undefined ? args.coachOnly : {}
  let coachOnly: CoachOnly = {}
  const parsedCoach = parseCoachOnly(coachRaw)
  if ('error' in parsedCoach) {
    console.warn('[recommend] soft-drop coachOnly:', parsedCoach.error)
    coachOnly = {}
  } else {
    coachOnly = parsedCoach
  }

  const panCue = parsePanCue(args.panCue)
  if (panCue && 'error' in panCue) {
    return { error: panCue.error }
  }

  const topCreativeLook = parseCreativeLook(args.creativeLook, 'creativeLook')
  if (topCreativeLook && typeof topCreativeLook === 'object' && 'error' in topCreativeLook) {
    return { error: topCreativeLook.error }
  }
  if (!phoneTargets.creativeLook && topCreativeLook && 'id' in topCreativeLook) {
    phoneTargets.creativeLook = topCreativeLook
  }
  const creativeLook = phoneTargets.creativeLook
  const senseSummary = asOptionalString(args.senseSummary)

  return {
    presetId,
    reason: reason.trim(),
    teachWhy: teachWhy.trim(),
    tips,
    phoneTargets,
    coachOnly,
    ...(panCue ? { panCue } : {}),
    ...(senseSummary ? { senseSummary } : {}),
    ...(creativeLook ? { creativeLook } : {}),
  }
}

async function callXaiJson(
  apiKey: string,
  model: string,
  messages: ChatMessage[],
  timeoutMs: number,
): Promise<{ ok: true; data: Record<string, unknown> } | { ok: false; status: number; body: string }> {
  let res: Response
  try {
    res = await fetchWithTimeout(
      `${XAI_BASE}/chat/completions`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model,
          temperature: 0.2,
          max_tokens: 420,
          response_format: { type: 'json_object' },
          messages,
          // grok-4.6 defaults to reasoning_effort=high (often 30–60s). Force low on coach path.
          ...(model.includes('4.6') || model.includes('4.5') || model.includes('4.3')
            ? { reasoning_effort: 'low' }
            : {}),
        }),
      },
      timeoutMs,
    )
  } catch (e) {
    const ex = e as Error & { status?: number }
    if (ex.status === 504) {
      return { ok: false, status: 504, body: 'Recommend timed out' }
    }
    throw e
  }

  const body = await res.text()
  if (!res.ok) {
    return { ok: false, status: res.status, body }
  }
  try {
    return { ok: true, data: JSON.parse(body) as Record<string, unknown> }
  } catch {
    return { ok: false, status: 502, body: 'Invalid JSON from xAI' }
  }
}

async function recommendFastOneShot(
  apiKey: string,
  req: RecommendRequest,
): Promise<RecommendResult> {
  const vision = Boolean(req.imageDataUrl)
  const timeoutMs = vision ? FAST_VISION_TIMEOUT_MS : FAST_TEXT_TIMEOUT_MS
  const cid = req.log?.correlationId ?? newRecommendCorrelationId()
  const lookOverride = inferCreativeLookOverride(req.message)
  if (!vision && !req.message.trim()) {
    throw Object.assign(new Error('Message or image is required'), { status: 400 })
  }

  let imageDataUrl = req.imageDataUrl
  if (imageDataUrl) {
    const before = imageDataUrl.length
    imageDataUrl = await shrinkVisionDataUrl(imageDataUrl, { maxEdge: 512, quality: 50 })
    console.info(
      `[recommend] fast shrink in-memory ${before}→${imageDataUrl.length} chars (data URL)`,
    )
  }

  const systemPrompt = buildFastSystemPrompt(req.favorites, vision)
  const userContent = buildFastUserContent({ ...req, imageDataUrl })
  const sysFp = promptFingerprint(systemPrompt)
  const userTextForLog =
    typeof userContent === 'string'
      ? userContent
      : userContent
          .map((p) =>
            p.type === 'text'
              ? p.text
              : p.type === 'image_url'
                ? redactDataUrls(p.image_url.url)
                : '',
          )
          .join('\n')

  logRecommend('recommend', 'request_in', {
    correlationId: cid,
    guestId: req.log?.guestIdShort,
    platform: req.log?.platform,
    message: req.message,
    vision,
    path: 'fast',
    applyFiltersIntent: isApplyFiltersIntent(req.message),
    creativeLookOverride: lookOverride ?? null,
    systemPromptLen: sysFp.len,
    systemPromptSha8: sysFp.sha8,
  })
  logRecommend('creativeLook', 'request_in', {
    correlationId: cid,
    message: req.message,
    override: lookOverride ?? null,
    applyFiltersIntent: isApplyFiltersIntent(req.message),
    path: 'fast',
  })

  const messages: ChatMessage[] = [
    { role: 'system', content: systemPrompt },
    {
      role: 'user',
      content: userContent,
    },
  ]

  const modelQueue = vision
    ? [...VISION_MODELS]
    : [PRIMARY_MODEL, FALLBACK_MODEL]
  let model = modelQueue[0]!
  let modelIndex = 0

  const started = Date.now()
  logRecommend('recommend', 'xai_outbound', {
    correlationId: cid,
    path: 'fast',
    model,
    message: req.message,
    userText: userTextForLog.slice(0, 500),
    systemPromptLen: sysFp.len,
    systemPromptSha8: sysFp.sha8,
  })
  let response = await callXaiJson(apiKey, model, messages, timeoutMs)

  while (
    !response.ok &&
    isModelMissing(response.status, response.body) &&
    modelIndex < modelQueue.length - 1
  ) {
    modelIndex += 1
    model = modelQueue[modelIndex]!
    console.warn(`[recommend] fast model unavailable, falling back to ${model}`)
    response = await callXaiJson(apiKey, model, messages, timeoutMs)
  }

  // Some models reject response_format — retry once without it.
  if (!response.ok && (response.status === 400 || response.status === 422)) {
    console.warn('[recommend] response_format rejected; retrying without json_object')
    let res: Response
    try {
      res = await fetchWithTimeout(
        `${XAI_BASE}/chat/completions`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${apiKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            model,
            temperature: 0.2,
            max_tokens: 420,
            messages,
            ...(model.includes('4.6') || model.includes('4.5') || model.includes('4.3')
              ? { reasoning_effort: 'low' }
              : {}),
          }),
        },
        timeoutMs,
      )
    } catch (e) {
      const ex = e as Error & { status?: number }
      if (ex.status === 504) {
        throw Object.assign(new Error('Recommend timed out — try again'), {
          status: 504,
        })
      }
      throw e
    }
    const body = await res.text()
    if (!res.ok) {
      response = { ok: false, status: res.status, body }
    } else {
      try {
        response = { ok: true, data: JSON.parse(body) as Record<string, unknown> }
      } catch {
        response = { ok: false, status: 502, body: 'Invalid JSON from xAI' }
      }
    }
  }

  if (!response.ok) {
    logRecommend('recommend', 'xai_error', {
      correlationId: cid,
      path: 'fast',
      model,
      status: response.status,
      bodySnippet: redactDataUrls(response.body).slice(0, 400),
    })
    if (response.status === 504) {
      throw Object.assign(new Error('Recommend timed out — try again'), {
        status: 504,
      })
    }
    const visionHint = vision
      ? ' Vision models may be unavailable for this API key; try text Ask or check xAI model access.'
      : ''
    const err = new Error(
      `xAI API error (${response.status}). Check model availability and API key.${visionHint}`,
    ) as Error & { status?: number; details?: string }
    err.status = response.status >= 400 && response.status < 600 ? response.status : 502
    err.details = response.body.slice(0, 500)
    throw err
  }

  const choices = response.data.choices as
    | Array<{ message?: ChatMessage; finish_reason?: string }>
    | undefined
  logRecommend('recommend', 'xai_response', {
    correlationId: cid,
    path: 'fast',
    model,
    ms: Date.now() - started,
    finishReason: choices?.[0]?.finish_reason ?? null,
    usage: response.data.usage ?? null,
  })
  console.info(
    `[recommend] fast=1 model=${model} ${Date.now() - started}ms`,
  )

  const content = choices?.[0]?.message?.content
  const contentStr =
    typeof content === 'string'
      ? content
      : Array.isArray(content)
        ? content
            .map((p) => (p && typeof p === 'object' && 'text' in p ? String((p as { text?: string }).text ?? '') : ''))
            .join('')
        : ''
  if (!contentStr.trim()) {
    throw Object.assign(new Error('Empty response from Grok'), { status: 502 })
  }

  let parsed: unknown
  try {
    parsed = extractJsonObject(contentStr)
  } catch {
    throw Object.assign(new Error('Grok did not return valid JSON for Recommend'), {
      status: 502,
    })
  }

  const selection = parseFastRecommendPayload(parsed)
  if ('error' in selection) {
    throw Object.assign(new Error(selection.error), { status: 502 })
  }

  const preset = presets.find((p) => p.id === selection.presetId)!
  const phoneTargetsBase =
    selection.phoneTargets && Object.keys(selection.phoneTargets).length > 0
      ? selection.phoneTargets
      : phoneTargetsFromPreset(preset)
  const coachOnly =
    selection.coachOnly && Object.keys(selection.coachOnly).length > 0
      ? selection.coachOnly
      : {
          ...(typeof preset.dials?.notes === 'string'
            ? { notes: preset.dials.notes }
            : {}),
          ...(/tripod/i.test(String(preset.dials?.notes ?? '')) ||
            /tripod/i.test(String(preset.dials?.shutter ?? ''))
            ? { tripod: true }
            : {}),
        }
  const rawLook = selection.creativeLook ?? phoneTargetsBase.creativeLook
  logRecommend('creativeLook', 'xai_raw', {
    correlationId: cid,
    path: 'fast',
    model,
    phoneTargetsCreativeLook: phoneTargetsBase.creativeLook ?? null,
    topLevelCreativeLook: selection.creativeLook ?? null,
    rawCreativeLook: rawLook ?? null,
  })
  const finalized = finalizeCreativeLookForClient(
    req.message,
    phoneTargetsBase,
    selection.creativeLook,
  )
  logRecommend('creativeLook', 'after_override', {
    correlationId: cid,
    path: 'fast',
    model,
    rawCreativeLook: finalized.rawCreativeLook ?? null,
    finalCreativeLook: finalized.creativeLook ?? null,
    overrideMatched: finalized.overrideMatched,
  })
  logRecommend('recommend', 'result', {
    correlationId: cid,
    path: 'fast',
    model,
    presetId: selection.presetId,
    creativeLook: finalized.creativeLook ?? null,
  })
  return {
    presetId: selection.presetId,
    reason: selection.reason,
    teachWhy: selection.teachWhy,
    tips: selection.tips,
    phoneTargets: finalized.phoneTargets,
    coachOnly,
    panCue: selection.panCue,
    senseSummary: selection.senseSummary,
    ...(finalized.creativeLook ? { creativeLook: finalized.creativeLook } : {}),
    preset,
    model,
  }
}

/**
 * Recommend routing:
 * - Non-empty message (STT / typed / APPLY-FILTERS) → agentic recommendWithToolLoop
 * - Empty message (image-only Auto Optimize shutter) → recommendFastOneShot
 * - RECOMMEND_TOOL_LOOP=1 forces tool-loop even for empty-message AO (debug)
 */
export async function recommendWithGrok(
  apiKey: string,
  req: RecommendRequest,
): Promise<RecommendResult> {
  if (shouldUseRecommendToolLoop(req)) {
    return recommendWithToolLoop(apiKey, req)
  }
  return recommendFastOneShot(apiKey, req)
}

export {
  VISION_MODELS,
  PRIMARY_MODEL,
  FALLBACK_MODEL,
  MAX_ROUNDS,
  VISION_IMAGE_DETAIL,
  FAST_TIMEOUT_MS,
  FAST_TEXT_TIMEOUT_MS,
  FAST_VISION_TIMEOUT_MS,
  tools,
}
