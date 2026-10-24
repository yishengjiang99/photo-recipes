/**
 * FinalCap usage for the admin dashboard — derived entirely from the FinalCap
 * server's own database (see server/finalcapMysql.ts). This is a SEPARATE data
 * source from this app's telemetry_events: FinalCap does not send client
 * telemetry events yet, so its numbers come from server-side records
 * (daily_inference_usage, chat_interactions, users, apple_transactions).
 * Never mix the two sources in one figure.
 *
 * Day keys are UTC dates: daily_inference_usage.usage_date is written by the
 * FinalCap server per UTC day, and chat days use DATE_FORMAT(created_at) as
 * stored (production DB session timezone is UTC).
 *
 * YouTube-audio fetches (POST /api/youtube-audio/fetch) are intentionally NOT
 * reported: the endpoint consumes inference access (counted in
 * daily_inference_usage) but no record distinguishes a fetch from any other
 * inference — chat_interactions metadata carries tool result counts, not tool
 * names — so there is no honest per-feature count to show.
 */
import type mysql from 'mysql2/promise'
import { getFinalcutMysqlPool, isFinalcutMysqlConfigured } from './finalcapMysql.ts'

export const FINALCAP_DEFAULT_DAYS = 30
export const FINALCAP_MAX_DAYS = 90

export function parseDaysParam(
  raw: unknown,
): { ok: true; days: number } | { ok: false } {
  if (raw === undefined || raw === null || raw === '') {
    return { ok: true, days: FINALCAP_DEFAULT_DAYS }
  }
  if (typeof raw !== 'string') return { ok: false }
  const t = raw.trim()
  if (!/^\d{1,3}$/.test(t)) return { ok: false }
  const n = Number.parseInt(t, 10)
  if (!Number.isFinite(n)) return { ok: false }
  return { ok: true, days: Math.min(FINALCAP_MAX_DAYS, Math.max(1, n)) }
}

/** Ascending list of the last `days` UTC date keys ('YYYY-MM-DD'), ending today. */
export function utcDayKeys(days: number, nowMs = Date.now()): string[] {
  const now = new Date(nowMs)
  const base = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate())
  const out: string[] = []
  for (let i = days - 1; i >= 0; i--) {
    out.push(new Date(base - i * 86_400_000).toISOString().slice(0, 10))
  }
  return out
}

export interface FinalcapDayUsage {
  day: string
  activeUsers: number
  inferences: number
}

export interface FinalcapChatDay {
  day: string
  human2ai: number
  ai2human: number
  error: number
  total: number
}

export interface FinalcapUsage {
  configured: boolean
  days: number
  timezone: string
  definitions: {
    dailyActive: string
    chat: string
    subscribers: string
  }
  dailyUsage: FinalcapDayUsage[]
  chatByDay: FinalcapChatDay[]
  totals: {
    registeredUsers: number
    /** Distinct user_id in apple_transactions, not revoked and not expired. */
    activeSubscribers: number
    /** users.has_subscription = 1 (the app's own flag; apple_transactions can lag it). */
    subscribersByUserFlag: number
    activeUsersInWindow: number
    inferencesInWindow: number
    chatInWindow: number
  }
  error?: string
}

const DEFINITIONS = {
  dailyActive:
    'Distinct user_id per usage_date in FinalCap daily_inference_usage; inferences = SUM(inference_count). Server-side edit/inference records (UTC days) — not client telemetry events.',
  chat:
    'Rows per day in FinalCap chat_interactions, split by interaction_type (human2ai = user message, ai2human = assistant reply, error).',
  subscribers:
    'Active subscribers = distinct user_id in apple_transactions with revoked_at IS NULL and (expires_at IS NULL OR expires_at > now). subscribersByUserFlag counts users.has_subscription = 1 instead.',
}

type Row = Record<string, unknown>
type QueryFn = (sql: string, params?: unknown[]) => Promise<[unknown, unknown]>

const num = (v: unknown): number => Number(v) || 0
const dayStr = (v: unknown): string =>
  v instanceof Date ? v.toISOString().slice(0, 10) : String(v ?? '').slice(0, 10)

function emptyUsage(days: number, keys: string[], configured: boolean): FinalcapUsage {
  return {
    configured,
    days,
    timezone: 'UTC',
    definitions: DEFINITIONS,
    dailyUsage: keys.map((day) => ({ day, activeUsers: 0, inferences: 0 })),
    chatByDay: keys.map((day) => ({ day, human2ai: 0, ai2human: 0, error: 0, total: 0 })),
    totals: {
      registeredUsers: 0,
      activeSubscribers: 0,
      subscribersByUserFlag: 0,
      activeUsersInWindow: 0,
      inferencesInWindow: 0,
      chatInWindow: 0,
    },
  }
}

export async function fetchFinalcapUsage(
  days: number,
  poolArg?: mysql.Pool | null,
  nowMs = Date.now(),
): Promise<FinalcapUsage> {
  const windowDays = Math.min(FINALCAP_MAX_DAYS, Math.max(1, Math.floor(days)))
  const keys = utcDayKeys(windowDays, nowMs)
  const first = keys[0]!
  const last = keys[keys.length - 1]!
  const pool = poolArg === undefined ? getFinalcutMysqlPool() : poolArg
  if (!pool) return emptyUsage(windowDays, keys, isFinalcutMysqlConfigured())
  const query = pool.query.bind(pool) as unknown as QueryFn

  try {
    const [usageRows] = (await query(
      `SELECT DATE_FORMAT(usage_date, '%Y-%m-%d') AS day,
              COUNT(DISTINCT user_id) AS users,
              COALESCE(SUM(inference_count), 0) AS inferences
       FROM daily_inference_usage
       WHERE usage_date >= ? AND usage_date <= ?
       GROUP BY usage_date
       ORDER BY usage_date ASC`,
      [first, last],
    )) as [Row[]]
    const [chatRows] = (await query(
      `SELECT DATE_FORMAT(created_at, '%Y-%m-%d') AS day,
              interaction_type AS type,
              COUNT(*) AS n
       FROM chat_interactions
       WHERE created_at >= ? AND created_at < DATE_ADD(?, INTERVAL 1 DAY)
       GROUP BY day, interaction_type
       ORDER BY day ASC`,
      [first, last],
    )) as [Row[]]
    const [[userTotal]] = (await query(
      `SELECT COUNT(*) AS n FROM users`,
    )) as [Row[]]
    const [[subTx]] = (await query(
      `SELECT COUNT(DISTINCT user_id) AS n FROM apple_transactions
       WHERE revoked_at IS NULL AND (expires_at IS NULL OR expires_at > UTC_TIMESTAMP())`,
    )) as [Row[]]
    const [[subFlag]] = (await query(
      `SELECT COUNT(*) AS n FROM users WHERE has_subscription = 1`,
    )) as [Row[]]
    const [[activeWindow]] = (await query(
      `SELECT COUNT(DISTINCT user_id) AS n FROM daily_inference_usage
       WHERE usage_date >= ? AND usage_date <= ?`,
      [first, last],
    )) as [Row[]]

    const usageByDay = new Map<string, { users: number; inferences: number }>()
    for (const r of usageRows ?? []) {
      usageByDay.set(dayStr(r.day), { users: num(r.users), inferences: num(r.inferences) })
    }
    const chatByDayMap = new Map<string, { human2ai: number; ai2human: number; error: number }>()
    for (const r of chatRows ?? []) {
      const day = dayStr(r.day)
      const entry = chatByDayMap.get(day) ?? { human2ai: 0, ai2human: 0, error: 0 }
      const type = String(r.type ?? '')
      if (type === 'human2ai' || type === 'ai2human' || type === 'error') {
        entry[type] += num(r.n)
      }
      chatByDayMap.set(day, entry)
    }

    const dailyUsage = keys.map((day) => {
      const v = usageByDay.get(day)
      return { day, activeUsers: v?.users ?? 0, inferences: v?.inferences ?? 0 }
    })
    const chatByDay = keys.map((day) => {
      const v = chatByDayMap.get(day) ?? { human2ai: 0, ai2human: 0, error: 0 }
      return { day, ...v, total: v.human2ai + v.ai2human + v.error }
    })

    return {
      configured: true,
      days: windowDays,
      timezone: 'UTC',
      definitions: DEFINITIONS,
      dailyUsage,
      chatByDay,
      totals: {
        registeredUsers: num(userTotal?.n),
        activeSubscribers: num(subTx?.n),
        subscribersByUserFlag: num(subFlag?.n),
        activeUsersInWindow: num(activeWindow?.n),
        inferencesInWindow: dailyUsage.reduce((s, d) => s + d.inferences, 0),
        chatInWindow: chatByDay.reduce((s, d) => s + d.total, 0),
      },
    }
  } catch (err) {
    console.warn(
      '[admin] finalcap usage query failed:',
      err instanceof Error ? err.message : err,
    )
    return { ...emptyUsage(windowDays, keys, true), error: 'query_failed' }
  }
}
