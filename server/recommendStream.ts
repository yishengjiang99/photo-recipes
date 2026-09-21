/**
 * Streaming Recommend — shared SSE contract for web + iOS.
 *
 * Events (text/event-stream):
 *   event: phase      data: {"phase":"started"|"sensing"|"thinking"|"writing"|"done"|"error"}
 *   event: status     data: {"message":"…"}
 *   event: reasoning  data: {"delta":"…"}   // optional, throttled
 *   event: content    data: {"delta":"…"}   // raw model text while JSON forms
 *   event: result     data: { same shape as POST /api/recommend success }
 *   event: error      data: {"error":"…","status"?:number}
 */
import { presets } from '../src/data/presets.ts'
import { shrinkVisionDataUrl } from './image.ts'
import {
  FALLBACK_MODEL,
  FAST_TEXT_TIMEOUT_MS,
  FAST_VISION_TIMEOUT_MS,
  PRIMARY_MODEL,
  VISION_MODELS,
  applyCreativeLookMessageOverride,
  buildFastSystemPrompt,
  buildFastUserContent,
  extractJsonObject,
  finalizeCreativeLookForClient,
  inferCreativeLookOverride,
  isApplyFiltersIntent,
  logRecommend,
  newRecommendCorrelationId,
  parseFastRecommendPayload,
  phoneTargetsFromPreset,
  promptFingerprint,
  redactDataUrls,
  type RecommendRequest,
  type RecommendResult,
} from './recommend.ts'

const XAI_BASE = 'https://api.x.ai/v1'

export type RecommendStreamPhase =
  | 'started'
  | 'sensing'
  | 'thinking'
  | 'writing'
  | 'done'
  | 'error'

export type RecommendStreamResultBody = {
  presetId: string
  recipeId: string
  reason: string
  teachWhy: string
  tips: string[]
  phoneTargets: RecommendResult['phoneTargets']
  coachOnly: RecommendResult['coachOnly']
  panCue?: RecommendResult['panCue']
  senseSummary?: string
  creativeLook?: RecommendResult['creativeLook']
  preset: RecommendResult['preset']
  model: string
  vision: boolean
}

export type RecommendStreamHandlers = {
  onPhase: (phase: RecommendStreamPhase) => void
  onStatus: (message: string) => void
  onReasoning?: (delta: string) => void
  onContent?: (delta: string) => void
  onResult: (result: RecommendStreamResultBody) => void
  onError: (error: string, status?: number) => void
}

function reasoningEffortFor(model: string): Record<string, string> {
  return model.includes('4.6') || model.includes('4.5') || model.includes('4.3')
    ? { reasoning_effort: 'low' }
    : {}
}

async function* iterXaiSseChunks(
  body: ReadableStream<Uint8Array>,
  signal?: AbortSignal,
): AsyncGenerator<Record<string, unknown>> {
  const reader = body.getReader()
  const decoder = new TextDecoder()
  let buf = ''
  try {
    while (true) {
      if (signal?.aborted) {
        throw Object.assign(new Error('Aborted'), { status: 499 })
      }
      const { done, value } = await reader.read()
      if (done) break
      buf += decoder.decode(value, { stream: true })
      const lines = buf.split('\n')
      buf = lines.pop() ?? ''
      for (const line of lines) {
        const trimmed = line.trim()
        if (!trimmed || trimmed.startsWith(':')) continue
        if (!trimmed.startsWith('data:')) continue
        const payload = trimmed.slice(5).trim()
        if (payload === '[DONE]') return
        try {
          yield JSON.parse(payload) as Record<string, unknown>
        } catch {
          /* skip */
        }
      }
    }
  } finally {
    try {
      reader.releaseLock()
    } catch {
      /* ignore */
    }
  }
}

function deltaFromChunk(chunk: Record<string, unknown>): {
  content?: string
  reasoning?: string
} {
  const choices = chunk.choices as
    | Array<{
        delta?: {
          content?: string | null
          reasoning_content?: string | null
        }
      }>
    | undefined
  const delta = choices?.[0]?.delta
  if (!delta) return {}
  return {
    content: typeof delta.content === 'string' ? delta.content : undefined,
    reasoning:
      typeof delta.reasoning_content === 'string'
        ? delta.reasoning_content
        : undefined,
  }
}

export async function recommendWithGrokStream(
  apiKey: string,
  req: RecommendRequest,
  handlers: RecommendStreamHandlers,
  opts?: { signal?: AbortSignal },
): Promise<void> {
  const vision = Boolean(req.imageDataUrl)
  const timeoutMs = vision ? FAST_VISION_TIMEOUT_MS : FAST_TEXT_TIMEOUT_MS
  const cid = req.log?.correlationId ?? newRecommendCorrelationId()
  const lookOverride = inferCreativeLookOverride(req.message)
  if (!vision && !req.message.trim()) {
    handlers.onPhase('error')
    handlers.onError('Message or image is required', 400)
    return
  }

  handlers.onPhase('started')
  handlers.onStatus(vision ? 'Reading the scene…' : 'Listening to your note…')

  let imageDataUrl = req.imageDataUrl
  if (imageDataUrl) {
    handlers.onPhase('sensing')
    handlers.onStatus('Preparing the frame…')
    const before = imageDataUrl.length
    imageDataUrl = await shrinkVisionDataUrl(imageDataUrl, {
      maxEdge: 512,
      quality: 50,
    })
    console.info(
      `[recommend/stream] shrink in-memory ${before}→${imageDataUrl.length} chars`,
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
    path: 'fast-stream',
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
    path: 'fast-stream',
  })

  const messages = [
    {
      role: 'system' as const,
      content: systemPrompt,
    },
    {
      role: 'user' as const,
      content: userContent,
    },
  ]

  const modelQueue = vision
    ? [...VISION_MODELS]
    : [PRIMARY_MODEL, FALLBACK_MODEL]

  const ac = new AbortController()
  const onOuterAbort = () => ac.abort()
  opts?.signal?.addEventListener('abort', onOuterAbort, { once: true })
  const timer = setTimeout(() => ac.abort(), timeoutMs)

  let model = modelQueue[0]!
  let assembled = ''
  let sawReasoning = false
  let sawContent = false
  let lastReasoningEmit = 0
  let reasoningBuf = ''

  try {
    handlers.onPhase('thinking')
    handlers.onStatus('Grok is thinking…')

    let res: Response | null = null

      let errBody = ''
  for (let i = 0; i < modelQueue.length; i++) {
      model = modelQueue[i]!
      logRecommend('recommend', 'xai_outbound', {
        correlationId: cid,
        path: 'fast-stream',
        model,
        message: req.message,
        userText: userTextForLog.slice(0, 500),
        systemPromptLen: sysFp.len,
        systemPromptSha8: sysFp.sha8,
        stream: true,
      })
      try {
        res = await fetch(`${XAI_BASE}/chat/completions`, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${apiKey}`,
            'Content-Type': 'application/json',
            Accept: 'text/event-stream',
          },
          body: JSON.stringify({
            model,
            temperature: 0.2,
            max_tokens: 420,
            stream: true,
            response_format: { type: 'json_object' },
            messages,
            ...reasoningEffortFor(model),
          }),
          signal: ac.signal,
        })
      } catch (e) {
        if (ac.signal.aborted) {
          handlers.onPhase('error')
          handlers.onError('Recommend timed out — try again', 504)
          return
        }
        throw e
      }

      if (res.ok && res.body) break

      errBody = await res.text().catch(() => '')
      const missing =
        res.status === 404 ||
        (res.status === 400 && /model|not found|does not exist/i.test(errBody))
      if (missing && i < modelQueue.length - 1) {
        console.warn(`[recommend/stream] ${model} unavailable, trying next`)
        res = null
        continue
      }

      if (res.status === 400 || res.status === 422) {
        console.warn(
          '[recommend/stream] response_format rejected; retry without json_object',
        )
        res = await fetch(`${XAI_BASE}/chat/completions`, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${apiKey}`,
            'Content-Type': 'application/json',
            Accept: 'text/event-stream',
          },
          body: JSON.stringify({
            model,
            temperature: 0.2,
            max_tokens: 420,
            stream: true,
            messages,
            ...reasoningEffortFor(model),
          }),
          signal: ac.signal,
        })
        if (res.ok && res.body) break
      }

      logRecommend('recommend', 'xai_error', {
        correlationId: cid,
        path: 'fast-stream',
        model,
        status: res.status,
        bodySnippet: redactDataUrls(errBody || '').slice(0, 400),
      })
      handlers.onPhase('error')
      handlers.onError(
        `xAI API error (${res.status}). Check model availability and API key.`,
        res.status >= 400 && res.status < 600 ? res.status : 502,
      )
      return
    }

    if (!res?.body) {
      handlers.onPhase('error')
      handlers.onError('No stream body from xAI', 502)
      return
    }

    for await (const chunk of iterXaiSseChunks(res.body, ac.signal)) {
      const { content, reasoning } = deltaFromChunk(chunk)
      if (reasoning) {
        if (!sawReasoning) {
          sawReasoning = true
          handlers.onPhase('thinking')
          handlers.onStatus('Grok is reasoning…')
        }
        reasoningBuf += reasoning
        const now = Date.now()
        if (now - lastReasoningEmit > 200 && reasoningBuf) {
          handlers.onReasoning?.(reasoningBuf.slice(0, 240))
          reasoningBuf = ''
          lastReasoningEmit = now
        }
      }
      if (content) {
        if (!sawContent) {
          sawContent = true
          handlers.onPhase('writing')
          handlers.onStatus('Writing recipe tips…')
        }
        assembled += content
        handlers.onContent?.(content)
      }
    }

    if (reasoningBuf) handlers.onReasoning?.(reasoningBuf.slice(0, 240))

    if (!assembled.trim()) {
      handlers.onPhase('error')
      handlers.onError('Empty response from Grok', 502)
      return
    }

    let parsed: unknown
    try {
      parsed = extractJsonObject(assembled)
    } catch {
      handlers.onPhase('error')
      handlers.onError('Grok did not return valid JSON for Recommend', 502)
      return
    }

    const selection = parseFastRecommendPayload(parsed)
    if ('error' in selection) {
      handlers.onPhase('error')
      handlers.onError(selection.error, 502)
      return
    }

    const preset = presets.find((p) => p.id === selection.presetId)
    if (!preset) {
      handlers.onPhase('error')
      handlers.onError(`Unknown recipe ${selection.presetId}`, 502)
      return
    }

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
    logRecommend('recommend', 'xai_response', {
      correlationId: cid,
      path: 'fast-stream',
      model,
      finishReason: 'stream_done',
      assembledLen: assembled.length,
    })
    logRecommend('creativeLook', 'xai_raw', {
      correlationId: cid,
      path: 'fast-stream',
      model,
      phoneTargetsCreativeLook: phoneTargetsBase.creativeLook ?? null,
      topLevelCreativeLook: selection.creativeLook ?? null,
      rawCreativeLook: rawLook ?? null,
    })
    // Bugfix: stream path previously skipped applyCreativeLookMessageOverride,
    // so spoken B&W never forced monoInk on SSE clients.
    const finalized = finalizeCreativeLookForClient(
      req.message,
      phoneTargetsBase,
      selection.creativeLook,
    )
    logRecommend('creativeLook', 'after_override', {
      correlationId: cid,
      path: 'fast-stream',
      model,
      rawCreativeLook: finalized.rawCreativeLook ?? null,
      finalCreativeLook: finalized.creativeLook ?? null,
      overrideMatched: finalized.overrideMatched,
    })

    const result: RecommendStreamResultBody = {
      presetId: selection.presetId,
      recipeId: selection.presetId,
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
      vision,
    }

    logRecommend('recommend', 'result', {
      correlationId: cid,
      path: 'fast-stream',
      model,
      presetId: selection.presetId,
      creativeLook: finalized.creativeLook ?? null,
    })

    handlers.onStatus('Recipe ready')
    handlers.onResult(result)
    handlers.onPhase('done')
  } catch (e) {
    const ex = e as Error & { status?: number }
    if (ac.signal.aborted || /abort/i.test(ex.message || '')) {
      handlers.onPhase('error')
      handlers.onError('Recommend timed out — try again', 504)
      return
    }
    handlers.onPhase('error')
    handlers.onError(ex.message || 'Recommendation failed', ex.status)
  } finally {
    clearTimeout(timer)
    opts?.signal?.removeEventListener('abort', onOuterAbort)
  }
}

/** Write one SSE event. */
export function writeSse(
  res: { write: (chunk: string) => unknown },
  event: string,
  data: unknown,
) {
  res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`)
}
