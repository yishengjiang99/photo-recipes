import { presets } from '../src/data/presets.ts'
import type { RecipePreset } from '../src/types/index.ts'

const XAI_BASE = 'https://api.x.ai/v1'
/** Text Ask Grok models */
const PRIMARY_MODEL = 'grok-4'
const FALLBACK_MODEL = 'grok-3-mini'
/**
 * Vision + tools: grok-4.6 (current xAI frontier with image input + function calling).
 * Falls back to grok-4 if grok-4.6 is unavailable (404).
 * @see https://docs.x.ai/developers/grok-4-6
 */
const VISION_MODELS = ['grok-4.6', 'grok-4'] as const
/** Hard cap on tool rounds. If select_preset never succeeds, fail clearly. */
const MAX_ROUNDS = 5

export interface RecommendRequest {
  message: string
  favorites?: string[]
  /** data:image/...;base64,... — when set, uses vision model + multimodal user content */
  imageDataUrl?: string
}

/** Values a phone camera API can typically apply (AVFoundation / Camera2-style).
 * All keys optional/additive — older iOS builds ignore unknown keys.
 */
export interface PhoneTargets {
  shutter?: string
  iso?: string
  /** Exposure compensation, e.g. "+0.7" or "-1" */
  ev?: string
  whiteBalance?: string
  focusMode?: string
  /**
   * Multiplicative zoom factor for AVCaptureDevice.videoZoomFactor (1 = 1×, 2 = 2×).
   * Clients may also map discrete values to lens switch (e.g. 0.5 ultra-wide, 1 wide, 2 tele).
   * String forms like "2x" are accepted by the server and normalized to a number.
   */
  zoom?: number
  /**
   * Normalized viewfinder tap-to-focus point (0–1). Omit when focusMode alone is enough.
   * Spoken e.g. "lock focus on the rider" → focusMode locked + optional focusPoint.
   */
  focusPoint?: { x: number; y: number }
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
  preset: RecipePreset
  model: string
  messages?: unknown[]
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
        'Finalize Auto Optimize: pick exactly one catalog preset (keep current recipe or a better match) and emit phone-settable targets (shutter/ISO/EV/WB/focus/zoom/focusPoint), coach-only guidance, optional pan cue, and teachWhy. If the user message includes a control tweak (typed or spoken transcript), phoneTargets MUST reflect that ask. This ends the loop.',
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
              'Only values a phone camera API can apply (shutter, iso, ev, whiteBalance, focusMode, zoom, focusPoint). When the user asks for a control tweak, include the keys that match. Omit keys you cannot set.',
            properties: {
              shutter: {
                type: 'string',
                description: 'Target shutter, e.g. "1/60", "1/500", "1/2"',
              },
              iso: {
                type: 'string',
                description: 'Target ISO, e.g. "100", "400", "auto"',
              },
              ev: {
                type: 'string',
                description: 'Exposure compensation, e.g. "+0.7", "0", "-1"',
              },
              whiteBalance: {
                type: 'string',
                description: 'e.g. "auto", "daylight", "cloudy", "shade", "tungsten"',
              },
              focusMode: {
                type: 'string',
                description: 'e.g. "continuous", "locked", "near", "infinity"',
              },
              zoom: {
                type: 'number',
                description:
                  'Multiplicative zoom factor for videoZoomFactor (1 = 1×, 2 = 2×). Clients may map to lens switch (0.5 UW, 1 wide, 2 tele).',
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

function summarizePreset(p: RecipePreset) {
  return {
    id: p.id,
    title: p.title,
    page: p.page,
    tags: p.tags,
    description: p.blurb,
    whenToUse: p.whenToUse,
    keySettings: {
      mode: p.dials.mode,
      aperture: p.dials.aperture,
      shutter: p.dials.shutter,
      iso: p.dials.iso,
      evBracket: p.dials.evBracket,
      notes: p.dials.notes,
    },
    gear: p.gear,
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

function parsePhoneTargets(raw: unknown): PhoneTargets | { error: string } {
  if (raw == null || typeof raw !== 'object' || Array.isArray(raw)) {
    return { error: 'phoneTargets must be an object' }
  }
  const o = raw as Record<string, unknown>
  const out: PhoneTargets = {}
  const shutter = asOptionalString(o.shutter)
  const iso = asOptionalString(o.iso)
  const ev = asOptionalString(o.ev)
  const whiteBalance = asOptionalString(o.whiteBalance)
  const focusMode = asOptionalString(o.focusMode)
  if (shutter) out.shutter = shutter
  if (iso) out.iso = iso
  if (ev) out.ev = ev
  if (whiteBalance) out.whiteBalance = whiteBalance
  if (focusMode) out.focusMode = focusMode

  const zoom = parseZoom(o.zoom)
  if (zoom && typeof zoom === 'object' && 'error' in zoom) return zoom
  if (typeof zoom === 'number') out.zoom = zoom

  const focusPoint = parseFocusPoint(o.focusPoint)
  if (focusPoint && typeof focusPoint === 'object' && 'error' in focusPoint) {
    return focusPoint
  }
  if (focusPoint && 'x' in focusPoint) out.focusPoint = focusPoint

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
    return { result: { presets: presets.map(summarizePreset) } }
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
    const preset = presets.find((p) => p.id === presetId)
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
  toolChoice: 'auto' | 'required' = 'auto',
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
Primary job: analyze the scene from the viewfinder (image + optional note) → select one catalog recipe → emit phoneTargets for Auto Optimize to apply (shutter/ISO/EV/WB/focus[/zoom]).
Tone: darkroom field notes — quiet, concrete, instructor-at-your-shoulder. Never chatty. Never invent recipes.

LOOP (strict):
1. SENSE — ${senseLine}
2. REASON — Call list_presets. Optionally get_preset_details for 1–2 candidates. Pick exactly ONE catalog id (keep the current recipe if it already fits, or switch to a better catalog match).
3. ACT / FINALIZE — Call select_preset with structured phoneTargets + coachOnly (+ panCue when motion/panning fits).
4. VERIFY (mental check before select_preset) — Targets match the recipe technique and any control ask in the note; shutter/ISO/EV/zoom are phone-plausible; aperture/ND/tripod stay in coachOnly; panCue only for panning/motion recipes.

ALTERNATE INPUT (spoken / STT transcripts — secondary):
- When the user message is a voice transcript, treat it as another way into the same Sense → recommend → phoneTargets apply path (not Ask text-field-only).
- Even without picking a new recipe, you MUST still call tools and emit phoneTargets that match the ask — same apply path as Auto Optimize (AVCapture session).
- Map spoken intents → phoneTargets (and panCue / teachWhy when useful), e.g.:
  • "slower shutter for panning" → phoneTargets.shutter (e.g. "1/30") + panCue + teachWhy
  • "lock focus on the rider" → phoneTargets.focusMode "locked" (+ optional focusPoint {x,y} 0–1 if you can infer a region)
  • "zoom in a bit" / "go to 2x" → phoneTargets.zoom (videoZoomFactor number: 1 = 1×, 2 = 2×)
  • "pull EV down" → phoneTargets.ev; "daylight WB" → phoneTargets.whiteBalance
- When the intent is a control adjustment, phoneTargets MUST include the relevant keys (do not finalize with empty {} if they asked to change shutter/ISO/EV/WB/focus/zoom).

CRITICAL RULES:
- Catalog only: never invent preset ids, titles, or off-catalog recipes.
- You MUST use tools. Do not free-form recommend without select_preset.
- phoneTargets = only what a phone camera API can apply: shutter, iso, ev, whiteBalance, focusMode, zoom, focusPoint.
- coachOnly = aperture, nd, tripod, notes — shown to the photographer, NOT applied on device.
- teachWhy = 1–2 short sentences for Teach mode ("Why this?").
- tips = max 3 short field tips.
- panCue = optional { direction: left|right|either, note? } when the subject moves and panning helps.
- senseSummary = optional one-line status (light/motion/subject).
- Bounded loop: finish with select_preset promptly. Do not keep listing after you know the answer.
- Match technique to the scene (sunset + dark foreground → HDR; kid/cyclist running → panning/motion; full-frame sharpness → depth of field; fresh angle → get low).${favLine}`
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
      image_url: { url: req.imageDataUrl, detail: 'high' },
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

export async function recommendWithGrok(
  apiKey: string,
  req: RecommendRequest,
): Promise<RecommendResult> {
  const vision = Boolean(req.imageDataUrl)
  if (!vision && !req.message.trim()) {
    throw Object.assign(new Error('Message or image is required'), { status: 400 })
  }

  const messages: ChatMessage[] = [
    { role: 'system', content: buildSystemPrompt(req.favorites, vision) },
    { role: 'user', content: buildUserContent(req) },
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
    const toolChoice: 'auto' | 'required' =
      !selection && !sawListOrDetails && round < 2 ? 'required' : 'auto'

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

    // Some models reject tool_choice:"required" — retry once with auto.
    if (
      !response.ok &&
      toolChoice === 'required' &&
      (response.status === 400 || response.status === 422)
    ) {
      console.warn('[recommend] tool_choice=required rejected; retrying with auto')
      response = await callXai(apiKey, model, messages, 'auto')
    }

    if (!response.ok) {
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
        selection = sel
      }
    }

    if (selection) {
      const preset = presets.find((p) => p.id === selection!.presetId)!
      return {
        presetId: selection.presetId,
        reason: selection.reason,
        teachWhy: selection.teachWhy,
        tips: selection.tips,
        phoneTargets: selection.phoneTargets,
        coachOnly: selection.coachOnly,
        panCue: selection.panCue,
        senseSummary: selection.senseSummary,
        preset,
        model,
        messages,
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

export { VISION_MODELS, PRIMARY_MODEL, FALLBACK_MODEL, MAX_ROUNDS, tools }
