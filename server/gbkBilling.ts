/**
 * GBK Composer billing funnel for the admin dashboard — read from the GBK
 * server's own SQLite databases on this host (/var/lib/gbk-composer):
 * analytics.sqlite `billing_daily` (day × event × surface × platform counts)
 * and shares.sqlite `billing_log` (per-account events). Written by GBK's
 * #118 BillingRecorder; money truth there is App Store Server Notifications
 * plus the /api/iap/apple intake (Stripe web money events are NOT in these
 * tables until the checkout service's webhook hop is wired).
 *
 * This is a SEPARATE data source from this panel's telemetry_events and from
 * the FinalCap sections above — never mix the figures. Day keys are UTC
 * (the recorder writes toISOString days). Soft-zero when the GBK files are
 * absent (e.g. a dev host): `available: false` and zeroed structures.
 */
import { DatabaseSync } from 'node:sqlite'
import { existsSync } from 'node:fs'
import { join } from 'node:path'
import { utcDayKeys } from './finalcapUsage.ts'

export function gbkComposerDataDir(): string {
  return process.env.GBK_COMPOSER_DATA_DIR?.trim() || '/var/lib/gbk-composer'
}

/** Events shown per day / in totals, in funnel order. */
export const GBK_BILLING_EVENTS = [
  'signup',
  'composition_created',
  'first_composition',
  'export',
  'share_published',
  'paywall_view',
  'paywall_dismiss',
  'checkout_start',
  'trial_start',
  'purchase',
  'renewal',
  'trial_convert',
  'cancel',
  'refund',
  'restore',
] as const

export interface GbkBillingDay {
  day: string
  counts: Record<string, number>
}

export interface GbkBillingStepRow {
  surface: string
  platform: string
  paywall_view: number
  checkout_start: number
  purchase: number
}

export interface GbkBillingRecent {
  ts: number
  account: string
  event: string
  plan: string
  surface: string
  platform: string
  detail: string
}

export interface GbkBillingReport {
  available: boolean
  days: number
  totals: Record<string, number>
  byDay: GbkBillingDay[]
  steps: { overall: Omit<GbkBillingStepRow, 'surface' | 'platform'>; bySurface: GbkBillingStepRow[] }
  recent: GbkBillingRecent[]
}

function zeroTotals(): Record<string, number> {
  return Object.fromEntries(GBK_BILLING_EVENTS.map((e) => [e, 0]))
}

export function fetchGbkBilling(days: number, dir: string = gbkComposerDataDir()): GbkBillingReport {
  const keys = utcDayKeys(days)
  const totals = zeroTotals()
  const byDay: GbkBillingDay[] = keys.map((day) => ({ day, counts: zeroTotals() }))
  const dayIndex = new Map(keys.map((k, i) => [k, i]))
  const steps = {
    overall: { paywall_view: 0, checkout_start: 0, purchase: 0 },
    bySurface: [] as GbkBillingStepRow[],
  }
  const recent: GbkBillingRecent[] = []
  const analyticsPath = join(dir, 'analytics.sqlite')
  if (!existsSync(analyticsPath)) {
    return { available: false, days, totals, byDay, steps, recent }
  }
  const since = keys[0]
  const adb = new DatabaseSync(analyticsPath, { readOnly: true })
  try {
    const rows = adb
      .prepare(
        'SELECT day, event, surface, platform, count FROM billing_daily WHERE day >= ? ORDER BY day',
      )
      .all(since) as unknown as Array<{
      day: string
      event: string
      surface: string
      platform: string
      count: number
    }>
    const stepMap = new Map<string, GbkBillingStepRow>()
    for (const r of rows) {
      if (r.event in totals) totals[r.event] += r.count
      const di = dayIndex.get(r.day)
      if (di !== undefined && r.event in byDay[di].counts) byDay[di].counts[r.event] += r.count
      if (r.event === 'paywall_view' || r.event === 'checkout_start' || r.event === 'purchase') {
        steps.overall[r.event] += r.count
        const key = `${r.surface}${r.platform}`
        let row = stepMap.get(key)
        if (!row) {
          row = { surface: r.surface, platform: r.platform, paywall_view: 0, checkout_start: 0, purchase: 0 }
          stepMap.set(key, row)
        }
        row[r.event] += r.count
      }
    }
    steps.bySurface = [...stepMap.values()].sort((a, b) => b.paywall_view - a.paywall_view)
  } finally {
    adb.close()
  }
  const sharesPath = join(dir, 'shares.sqlite')
  if (existsSync(sharesPath)) {
    const sdb = new DatabaseSync(sharesPath, { readOnly: true })
    try {
      const rows = sdb
        .prepare('SELECT ts, account, event, plan, surface, platform, detail FROM billing_log ORDER BY ts DESC LIMIT 25')
        .all() as unknown as GbkBillingRecent[]
      recent.push(...rows)
    } catch {
      /* billing_log absent on an older GBK deploy — aggregates above still stand */
    } finally {
      sdb.close()
    }
  }
  return { available: true, days, totals, byDay, steps, recent }
}
