#!/usr/bin/env node
/**
 * Print funnel step counts using MYSQL_* env (same as API).
 * Usage: node scripts/funnel-report.mjs [--days 7]
 * Prints the CANONICAL funnel first (distinct session_id; stages sessions →
 * camera_open → auto_optimize_start → auto_optimize_success; trailing
 * complete days, America/Los_Angeles — see docs/telemetry-funnels.md),
 * then alternate cuts (raw counts / distinct anon_id, rolling window),
 * labelled as alternate. Alternate numbers are NOT comparable to canonical.
 */
import mysql from 'mysql2/promise'
import dotenv from 'dotenv'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
dotenv.config({ path: path.resolve(__dirname, '../.env') })

const days = Number(process.argv.includes('--days')
  ? process.argv[process.argv.indexOf('--days') + 1]
  : 7) || 7

function poolConfig() {
  if (process.env.MYSQL_URL?.trim()) return process.env.MYSQL_URL.trim()
  if (!process.env.MYSQL_HOST?.trim() || !process.env.MYSQL_DATABASE?.trim()) {
    console.error('MYSQL_URL or MYSQL_HOST+MYSQL_DATABASE required')
    process.exit(1)
  }
  return {
    host: process.env.MYSQL_HOST.trim(),
    port: Number(process.env.MYSQL_PORT || 3306),
    user: process.env.MYSQL_USER?.trim() || 'root',
    password: process.env.MYSQL_PASSWORD ?? '',
    database: process.env.MYSQL_DATABASE.trim(),
  }
}

const FUNNELS = {
  web_activation: [
    'landing_view',
    'landing_cta_camera',
    'camera_open',
    'auto_optimize_start',
    'auto_optimize_success',
  ],
  ios_capture: ['camera_open', 'auto_optimize_success', 'capture_success'],
  monetization: [
    'paywall_view',
    'paywall_plan_select',
    'purchase_start',
    'checkout_redirect',
    'purchase_success',
  ],
}

// PT helpers mirror server/telemetry.ts (canonicalFunnelWindow).
const PT = 'America/Los_Angeles'
function ptOffsetSec(tsSec) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: PT, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  }).formatToParts(new Date(tsSec * 1000))
  const v = (k) => Number(parts.find((x) => x.type === k)?.value)
  const wall = Date.UTC(v('year'), v('month') - 1, v('day'), v('hour'), v('minute'), v('second')) / 1000
  return Math.round((wall - Math.floor(tsSec)) / 60) * 60
}
function ptMidnightEpochSec(dayBucketSec) {
  const guess = dayBucketSec - ptOffsetSec(dayBucketSec)
  return dayBucketSec - ptOffsetSec(guess)
}
function canonicalWindow(windowDays, nowMs = Date.now()) {
  const nowSec = Math.floor(nowMs / 1000)
  const todayBucket = Math.floor((nowSec + ptOffsetSec(nowSec)) / 86400) * 86400
  const startBucket = todayBucket - windowDays * 86400
  return {
    startSec: ptMidnightEpochSec(startBucket),
    endSec: ptMidnightEpochSec(todayBucket),
    startDay: new Date(startBucket * 1000).toISOString().slice(0, 10),
    endDayExclusive: new Date(todayBucket * 1000).toISOString().slice(0, 10),
  }
}

const pool = mysql.createPool(poolConfig())
try {
  const w = canonicalWindow(days)
  const [[canonical]] = await pool.query(
    `SELECT
       COUNT(DISTINCT session_id) AS sessions,
       COUNT(DISTINCT IF(event = 'camera_open', session_id, NULL)) AS camera_open,
       COUNT(DISTINCT IF(event = 'auto_optimize_start', session_id, NULL)) AS auto_optimize_start,
       COUNT(DISTINCT IF(event = 'auto_optimize_success', session_id, NULL)) AS auto_optimize_success
     FROM telemetry_events
     WHERE session_id IS NOT NULL AND session_id <> ''
       AND created_at >= FROM_UNIXTIME(?) AND created_at < FROM_UNIXTIME(?)`,
    [w.startSec, w.endSec],
  )
  console.log('canonical (distinct session_id, trailing complete PT days)', {
    days,
    window: `${w.startDay} -> ${w.endDayExclusive} (exclusive, America/Los_Angeles)`,
    sessions: Number(canonical.sessions) || 0,
    camera_open: Number(canonical.camera_open) || 0,
    auto_optimize_start: Number(canonical.auto_optimize_start) || 0,
    auto_optimize_success: Number(canonical.auto_optimize_success) || 0,
  })
  console.log('alternate cuts below (raw counts / distinct anon_id, rolling window) — not comparable to canonical')
  const [[dau]] = await pool.query(
    `SELECT COUNT(DISTINCT anon_id) AS n FROM telemetry_events WHERE created_at >= (NOW(3) - INTERVAL 1 DAY)`,
  )
  const [[wau]] = await pool.query(
    `SELECT COUNT(DISTINCT anon_id) AS n FROM telemetry_events WHERE created_at >= (NOW(3) - INTERVAL 7 DAY)`,
  )
  console.log(JSON.stringify({ days, dau: dau.n, wau: wau.n }, null, 2))

  for (const [name, events] of Object.entries(FUNNELS)) {
    const ph = events.map(() => '?').join(',')
    const platformFilter = name === 'ios_capture' ? ` AND platform = 'ios'` : ''
    const [rows] = await pool.query(
      `SELECT event, COUNT(*) AS c, COUNT(DISTINCT anon_id) AS users
       FROM telemetry_events
       WHERE created_at >= (NOW(3) - INTERVAL ? DAY) AND event IN (${ph})${platformFilter}
       GROUP BY event`,
      [days, ...events],
    )
    const byEvent = Object.fromEntries(events.map((e) => [e, { c: 0, users: 0 }]))
    for (const r of rows) byEvent[r.event] = { c: Number(r.c), users: Number(r.users) }
    console.log(`${name} (alternate)`, byEvent)
  }
} finally {
  await pool.end()
}
