/**
 * Push lifecycle — segment rules (pure, no I/O).
 *
 * Input: first-party anonymous telemetry events for ONE install (event name, time,
 * and allowlisted short tokens such as look_id) → bucketed ActivityFeatures → the single
 * highest-priority segment the install currently matches.
 *
 * Never reads photos, prompts, captions, or free text. See docs/push-lifecycle.md.
 */

export type Tier = 'free' | 'trial' | 'pro'

/** feature = about something the user started / how-to for the core feature (needs push permission).
 *  promotional = re-engagement, offers, announcements (also needs in-app marketing opt-in, Guideline 4.5.4). */
export type SegmentClass = 'feature' | 'promotional'

export type SegmentId =
  | 'unfinished_edit'
  | 'onboarding_d1'
  | 'onboarding_d3'
  | 'onboarding_d7'
  | 'paywall_not_converted'
  | 'new_feature'
  | 'inactive_7'
  | 'inactive_14'
  | 'winback_30'
  | 'weekly_tip'

export type TelemetryEventRow = {
  event: string
  at: Date
  /** allowlisted short token (look_id) or null */
  lookId?: string | null
}

export type ActivityFeatures = {
  firstSeenAt: Date | null
  lastSeenAt: Date | null
  daysSinceInstall: number | null
  hoursInactive: number | null
  daysInactive: number | null
  sessions7d: number
  captures7d: number
  capturesTotal: number
  aoSuccessTotal: number
  looksApplied30d: number
  recipeOpens30d: number
  paywallViews7d: number
  lastPaywallViewAt: Date | null
  purchasesTotal: number
  quotaHits7d: number
  lastAbandonAt: Date | null
  lastCaptureAt: Date | null
  favoriteLook: string | null
  tier: Tier
}

const H = 60 * 60 * 1000
const D = 24 * H

const LOOK_ID = /^[a-z0-9_-]{1,40}$/

export function featuresFromEvents(
  rows: TelemetryEventRow[],
  now: Date,
  tier: Tier,
  firstSeenOverride?: Date | null,
): ActivityFeatures {
  const t = now.getTime()
  let first: Date | null = firstSeenOverride ?? null
  let last: Date | null = null
  const f: ActivityFeatures = {
    firstSeenAt: null,
    lastSeenAt: null,
    daysSinceInstall: null,
    hoursInactive: null,
    daysInactive: null,
    sessions7d: 0,
    captures7d: 0,
    capturesTotal: 0,
    aoSuccessTotal: 0,
    looksApplied30d: 0,
    recipeOpens30d: 0,
    paywallViews7d: 0,
    lastPaywallViewAt: null,
    purchasesTotal: 0,
    quotaHits7d: 0,
    lastAbandonAt: null,
    lastCaptureAt: null,
    favoriteLook: null,
    tier,
  }
  const lookCounts = new Map<string, number>()
  for (const r of rows) {
    const at = r.at instanceof Date ? r.at : new Date(r.at)
    const ms = at.getTime()
    if (!Number.isFinite(ms) || ms > t + 5 * 60 * 1000) continue
    // Push opens are not "organic" activity — don't let them reset inactivity.
    if (r.event !== 'push_opened' && r.event !== 'notification_opened') {
      if (!last || ms > last.getTime()) last = at
    }
    if (!first || ms < first.getTime()) first = at
    const age = t - ms
    switch (r.event) {
      case 'session_start':
        if (age <= 7 * D) f.sessions7d++
        break
      case 'capture_success':
        f.capturesTotal++
        if (age <= 7 * D) f.captures7d++
        if (!f.lastCaptureAt || ms > f.lastCaptureAt.getTime()) f.lastCaptureAt = at
        break
      case 'auto_optimize_success':
        f.aoSuccessTotal++
        break
      case 'look_applied':
        if (age <= 30 * D) {
          f.looksApplied30d++
          const id = (r.lookId ?? '').trim().toLowerCase()
          if (LOOK_ID.test(id)) lookCounts.set(id, (lookCounts.get(id) ?? 0) + 1)
        }
        break
      case 'recipe_open':
        if (age <= 30 * D) f.recipeOpens30d++
        break
      case 'paywall_view':
        if (age <= 7 * D) f.paywallViews7d++
        if (!f.lastPaywallViewAt || ms > f.lastPaywallViewAt.getTime()) f.lastPaywallViewAt = at
        break
      case 'purchase_success':
        f.purchasesTotal++
        break
      case 'free_quota_hit':
        if (age <= 7 * D) f.quotaHits7d++
        break
      case 'optimize_capture_abandoned':
        if (!f.lastAbandonAt || ms > f.lastAbandonAt.getTime()) f.lastAbandonAt = at
        break
    }
  }
  f.firstSeenAt = first
  f.lastSeenAt = last
  if (first) f.daysSinceInstall = (t - first.getTime()) / D
  if (last) {
    f.hoursInactive = (t - last.getTime()) / H
    f.daysInactive = f.hoursInactive / 24
  }
  let best: string | null = null
  let bestN = 0
  for (const [id, n] of lookCounts) {
    if (n > bestN) {
      best = id
      bestN = n
    }
  }
  f.favoriteLook = best
  return f
}

export type FeatureAnnouncement = {
  id: string
  /** Only announcements explicitly set active are ever used. */
  active: boolean
  /** One-line, factual description fed to the copy writer (must be true in the shipping app). */
  fact: string
  deepLink: string
}

/**
 * Feature announcements. Inactive by default — flip `active` only once the feature is in
 * the App Store build users have (never for features still in review).
 */
export const FEATURE_ANNOUNCEMENTS: FeatureAnnouncement[] = [
  {
    id: 'selfie_pack_v1',
    active: false,
    fact: 'Selfie looks for the front camera: soft skin, under-eye smoothing and flattering light.',
    deepLink: 'photo-recipes://camera',
  },
]

export type SegmentDef = {
  id: SegmentId
  cls: SegmentClass
  /** What the push is trying to get the user to do (fed to the copy writer). */
  goal: string
  deepLink: string
  /** Lower = evaluated first. */
  priority: number
}

export const SEGMENTS: Record<SegmentId, SegmentDef> = {
  unfinished_edit: {
    id: 'unfinished_edit',
    cls: 'feature',
    goal: 'They started an Auto Optimize shot but left before capturing. Invite them to finish it.',
    deepLink: 'photo-recipes://auto-optimize',
    priority: 10,
  },
  onboarding_d1: {
    id: 'onboarding_d1',
    cls: 'feature',
    goal: 'Day 1 tip: point the camera at a scene and tap Auto Optimize to get tuned settings in one tap.',
    deepLink: 'photo-recipes://auto-optimize',
    priority: 20,
  },
  onboarding_d3: {
    id: 'onboarding_d3',
    cls: 'feature',
    goal: 'Day 3 tip: try a creative look (film, black & white, warm tones) on the next shot.',
    deepLink: 'photo-recipes://camera',
    priority: 21,
  },
  onboarding_d7: {
    id: 'onboarding_d7',
    cls: 'feature',
    goal: 'Day 7 tip: browse photo recipes in the Library for ideas for the next shoot.',
    deepLink: 'photo-recipes://recipes',
    priority: 22,
  },
  paywall_not_converted: {
    id: 'paywall_not_converted',
    cls: 'promotional',
    goal: 'They looked at ProTune Pro but did not subscribe. Honestly remind them what Pro adds (unlimited Auto Optimize) and that eligible new subscribers get a 7-day free trial. No pressure.',
    deepLink: 'photo-recipes://paywall',
    priority: 30,
  },
  new_feature: {
    id: 'new_feature',
    cls: 'promotional',
    goal: 'Tell them about a feature that is now in the app.',
    deepLink: 'photo-recipes://camera',
    priority: 40,
  },
  inactive_7: {
    id: 'inactive_7',
    cls: 'promotional',
    goal: 'They have not opened the app for about a week. Offer one concrete shot idea, ideally with their favorite look.',
    deepLink: 'photo-recipes://camera',
    priority: 50,
  },
  inactive_14: {
    id: 'inactive_14',
    cls: 'promotional',
    goal: 'Two weeks away. Suggest one easy photo recipe to try.',
    deepLink: 'photo-recipes://recipes',
    priority: 51,
  },
  winback_30: {
    id: 'winback_30',
    cls: 'promotional',
    goal: 'A month away; final gentle check-in. After this we stay quiet.',
    deepLink: 'photo-recipes://camera',
    priority: 52,
  },
  weekly_tip: {
    id: 'weekly_tip',
    cls: 'feature',
    goal: 'Default weekly tip for every install: suggest one concrete shot idea to try with Auto Optimize or a creative look.',
    deepLink: 'photo-recipes://camera',
    priority: 90,
  },
}

/** ISO-ish week bucket (UTC, Monday-based) for the default campaign dedupe key. */
function weekBucket(now: Date): string {
  const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()))
  d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() + 6) % 7))
  return d.toISOString().slice(0, 10)
}

/** Neutral features for installs with no telemetry link / no recent events. */
export function emptyFeatures(tier: Tier, firstSeenAt: Date | null, now: Date): ActivityFeatures {
  const dsi = firstSeenAt ? (now.getTime() - firstSeenAt.getTime()) / D : null
  return {
    firstSeenAt, lastSeenAt: null, daysSinceInstall: dsi, hoursInactive: null, daysInactive: null,
    sessions7d: 0, captures7d: 0, capturesTotal: 0, aoSuccessTotal: 0, looksApplied30d: 0, recipeOpens30d: 0,
    paywallViews7d: 0, lastPaywallViewAt: null, purchasesTotal: 0, quotaHits7d: 0, lastAbandonAt: null,
    lastCaptureAt: null, favoriteLook: null, tier,
  }
}

export type SegmentMatch = {
  segment: SegmentDef
  /** Dedupe key: the same key is never sent twice to the same install. */
  dedupeKey: string
  announcement?: FeatureAnnouncement
}

function day(d: Date): string {
  return d.toISOString().slice(0, 10)
}

/** Ordered list of every segment the install matches right now (highest priority first). */
export function matchSegments(
  f: ActivityFeatures,
  now: Date,
  usedAnnouncements: ReadonlySet<string> = new Set(),
): SegmentMatch[] {
  const out: SegmentMatch[] = []
  const t = now.getTime()
  const S = SEGMENTS
  const inactiveH = f.hoursInactive ?? 0
  const dsi = f.daysSinceInstall

  // Unfinished: abandoned a shot 2–48h ago and no capture since.
  if (f.lastAbandonAt) {
    const age = t - f.lastAbandonAt.getTime()
    const capturedAfter = f.lastCaptureAt && f.lastCaptureAt.getTime() > f.lastAbandonAt.getTime()
    if (age >= 2 * H && age <= 48 * H && !capturedAfter && inactiveH >= 2) {
      out.push({ segment: S.unfinished_edit, dedupeKey: `unfinished_edit:${day(f.lastAbandonAt)}` })
    }
  }

  if (dsi !== null) {
    if (dsi >= 1 && dsi < 2 && inactiveH >= 12) {
      out.push({ segment: S.onboarding_d1, dedupeKey: 'onboarding_d1' })
    }
    if (dsi >= 3 && dsi < 4 && inactiveH >= 24) {
      out.push({ segment: S.onboarding_d3, dedupeKey: 'onboarding_d3' })
    }
    if (dsi >= 7 && dsi < 8 && inactiveH >= 48) {
      out.push({ segment: S.onboarding_d7, dedupeKey: 'onboarding_d7' })
    }
  }

  // Paywall viewed 20–72h ago, still free, never purchased. Trial users get Apple's own
  // renewal notice — we never send a "trial ending" push.
  if (f.tier === 'free' && f.purchasesTotal === 0 && f.lastPaywallViewAt) {
    const age = t - f.lastPaywallViewAt.getTime()
    if (age >= 20 * H && age <= 72 * H && inactiveH >= 12) {
      // At most one per 30 days: bucket by 30-day window of the view.
      const bucket = Math.floor(f.lastPaywallViewAt.getTime() / (30 * D))
      out.push({ segment: S.paywall_not_converted, dedupeKey: `paywall_not_converted:${bucket}` })
    }
  }

  // Feature announcement: recently active users (≤30d), not brand-new (≥3d), once per feature.
  if (dsi !== null && dsi >= 3 && f.daysInactive !== null && f.daysInactive <= 30 && inactiveH >= 24) {
    const ann = FEATURE_ANNOUNCEMENTS.find((a) => a.active && !usedAnnouncements.has(a.id))
    if (ann) {
      out.push({
        segment: { ...S.new_feature, deepLink: ann.deepLink },
        dedupeKey: `new_feature:${ann.id}`,
        announcement: ann,
      })
    }
  }

  const di = f.daysInactive
  if (di !== null && f.lastSeenAt && dsi !== null && dsi >= 8) {
    const episode = day(f.lastSeenAt)
    if (di >= 7 && di < 14) out.push({ segment: S.inactive_7, dedupeKey: `inactive_7:${episode}` })
    else if (di >= 14 && di < 30) out.push({ segment: S.inactive_14, dedupeKey: `inactive_14:${episode}` })
    else if (di >= 30 && di < 45) out.push({ segment: S.winback_30, dedupeKey: `winback_30:${episode}` })
  }

  // Default campaign: every install qualifies (Pro and active users included), once per week.
  out.push({ segment: S.weekly_tip, dedupeKey: `weekly_tip:${weekBucket(now)}` })
  return out.sort((a, b) => a.segment.priority - b.segment.priority)
}

/** Coarse, non-identifying facts the copy writer may use. No ids, no timestamps. */
export type CopyFacts = {
  tier: Tier
  capturesLastWeek: '0' | '1-3' | '4+'
  usedAutoOptimize: boolean
  favoriteLook: string | null
  awayFor: 'today' | 'a few days' | 'about a week' | 'two weeks' | 'a month' | null
  announcement?: string
}

export function prettyLook(id: string | null): string | null {
  if (!id || !LOOK_ID.test(id)) return null
  const words = id.split(/[_-]+/).filter(Boolean).slice(0, 3)
  if (!words.length) return null
  return words.map((w) => (w === 'bw' ? 'B&W' : w[0]!.toUpperCase() + w.slice(1))).join(' ')
}

export function copyFactsFor(f: ActivityFeatures, m: SegmentMatch): CopyFacts {
  const c = f.captures7d
  const di = f.daysInactive ?? 0
  return {
    tier: f.tier,
    capturesLastWeek: c === 0 ? '0' : c <= 3 ? '1-3' : '4+',
    usedAutoOptimize: f.aoSuccessTotal > 0,
    favoriteLook: prettyLook(f.favoriteLook),
    awayFor:
      di < 1 ? 'today' : di < 6 ? 'a few days' : di < 13 ? 'about a week' : di < 28 ? 'two weeks' : 'a month',
    ...(m.announcement ? { announcement: m.announcement.fact } : {}),
  }
}
