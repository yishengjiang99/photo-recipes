/**
 * fetch with AbortSignal timeout. On abort, throws Error with status 504.
 */
export async function fetchWithTimeout(
  url: string,
  init: RequestInit | undefined,
  ms: number,
): Promise<Response> {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), ms)
  try {
    return await fetch(url, {
      ...init,
      signal: controller.signal,
    })
  } catch (e) {
    if (
      e instanceof Error &&
      (e.name === 'AbortError' || e.message.includes('aborted'))
    ) {
      const err = new Error('Request timed out') as Error & { status?: number }
      err.status = 504
      throw err
    }
    throw e
  } finally {
    clearTimeout(timer)
  }
}
