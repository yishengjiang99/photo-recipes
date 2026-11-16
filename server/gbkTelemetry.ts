/**
 * GBK Composer live telemetry for the admin dashboard, fetched server-to-server
 * from GBK's read-only GET /api/admin/telemetry (compose.grepawk.com) with the
 * shared GBK_ADMIN_READ_TOKEN (sent as x-gbk-admin-read; never logged or
 * returned). GBK isolates each section ({ error } per section), and this side
 * never throws: a timeout or HTTP failure comes back as { ok: false, error }.
 */
export function gbkAdminOrigin(): string {
  return (process.env.GBK_ADMIN_ORIGIN?.trim() || 'https://compose.grepawk.com').replace(/\/$/, '')
}

export type GbkTelemetryResult =
  | { ok: true; configured: true; data: Record<string, unknown> }
  | { ok: false; configured: boolean; error: string; status?: number }

export async function fetchGbkTelemetry(
  days: number,
  opts: { fetchImpl?: typeof fetch; timeoutMs?: number; token?: string; origin?: string } = {},
): Promise<GbkTelemetryResult> {
  const token = opts.token ?? process.env.GBK_ADMIN_READ_TOKEN?.trim() ?? ''
  if (!token) return { ok: false, configured: false, error: 'GBK_ADMIN_READ_TOKEN not set' }
  const f = opts.fetchImpl ?? fetch
  try {
    const res = await f(`${opts.origin ?? gbkAdminOrigin()}/api/admin/telemetry?days=${days}`, {
      headers: { 'x-gbk-admin-read': token, accept: 'application/json' },
      signal: AbortSignal.timeout(opts.timeoutMs ?? 8000),
    })
    if (!res.ok) return { ok: false, configured: true, status: res.status, error: `gbk responded ${res.status}` }
    return { ok: true, configured: true, data: (await res.json()) as Record<string, unknown> }
  } catch (err) {
    const e = err as Error
    return { ok: false, configured: true, error: e.name === 'TimeoutError' ? 'gbk timed out' : e.message || 'gbk fetch failed' }
  }
}
