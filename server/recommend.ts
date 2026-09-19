import { presets } from '../src/data/presets.ts'
import type { RecipePreset } from '../src/types/index.ts'

const XAI_BASE = 'https://api.x.ai/v1'
const PRIMARY_MODEL = 'grok-4'
const FALLBACK_MODEL = 'grok-3-mini'
const MAX_ROUNDS = 5

export interface RecommendRequest {
  message: string
  favorites?: string[]
}

export interface RecommendResult {
  presetId: string
  reason: string
  tips: string[]
  preset: RecipePreset
  messages?: unknown[]
}

type ChatMessage = {
  role: 'system' | 'user' | 'assistant' | 'tool'
  content?: string | null
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
        'Get the full steps, tips, dials, gear, and when-to-use text for one preset by id.',
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
        'Finalize your recommendation by selecting exactly one preset from the catalog. Call this when you have chosen the best match for the user scene.',
      parameters: {
        type: 'object',
        properties: {
          presetId: {
            type: 'string',
            description: 'Exact preset id from the catalog',
          },
          reason: {
            type: 'string',
            description:
              'Clear coach-style explanation of why this recipe fits the scene',
          },
          tips: {
            type: 'array',
            items: { type: 'string' },
            description: 'Optional short field tips tailored to the scene',
          },
        },
        required: ['presetId', 'reason'],
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

function executeTool(
  name: string,
  argsJson: string,
): { result: unknown; selection?: { presetId: string; reason: string; tips: string[] } } {
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
    return {
      result: { ok: true, presetId, reason, tips },
      selection: { presetId, reason, tips },
    }
  }

  return { result: { error: `Unknown tool: ${name}` } }
}

async function callXai(
  apiKey: string,
  model: string,
  messages: ChatMessage[],
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
      tool_choice: 'auto',
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

function buildSystemPrompt(favorites?: string[]): string {
  const favLine =
    favorites && favorites.length > 0
      ? `\nThe user has favorited these preset ids (prefer them only when they fit the scene equally well): ${favorites.join(', ')}.`
      : ''

  return `You are a photography field coach for the Photo Recipes web app.
Your job is to recommend exactly ONE recipe from the app's catalog for the user's scene description.

CRITICAL RULES:
- You MUST use tools. Never invent recipes, titles, or ids outside the catalog.
- First call list_presets (and optionally get_preset_details) to inspect the catalog.
- Then call select_preset with a valid presetId, a clear reason, and optional tips.
- Do not answer with free-form recipe advice without calling select_preset.
- Match technique to the scene (e.g. sunset with dark foreground → HDR; kid running → motion/panning; landscapes needing full sharpness → depth of field; fresh angle → get low).${favLine}`
}

export async function recommendWithGrok(
  apiKey: string,
  req: RecommendRequest,
): Promise<RecommendResult> {
  const messages: ChatMessage[] = [
    { role: 'system', content: buildSystemPrompt(req.favorites) },
    { role: 'user', content: req.message.trim() },
  ]

  let model = PRIMARY_MODEL
  let selection: { presetId: string; reason: string; tips: string[] } | undefined

  for (let round = 0; round < MAX_ROUNDS; round++) {
    let response = await callXai(apiKey, model, messages)

    if (!response.ok && response.status === 404 && model === PRIMARY_MODEL) {
      model = FALLBACK_MODEL
      response = await callXai(apiKey, model, messages)
    }

    if (!response.ok) {
      const err = new Error(
        `xAI API error (${response.status}). Check model availability and API key.`,
      ) as Error & { status?: number; details?: string }
      err.status = response.status >= 400 && response.status < 600 ? response.status : 502
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
      // Nudge the model to use tools
      messages.push({
        role: 'user',
        content:
          'You must use tools. Call list_presets, then select_preset with a catalog id. Do not invent recipes.',
      })
      continue
    }

    for (const tc of toolCalls) {
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
        tips: selection.tips,
        preset,
        messages,
      }
    }
  }

  throw Object.assign(
    new Error('Grok did not call select_preset within the tool-call limit.'),
    { status: 502 },
  )
}
