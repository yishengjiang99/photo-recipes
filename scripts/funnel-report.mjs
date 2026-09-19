#!/usr/bin/env node
/**
 * Print funnel step counts using MYSQL_* env (same as API).
 * Usage: node scripts/funnel-report.mjs [--days 7]
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

const pool = mysql.createPool(poolConfig())
try {
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
    console.log(name, byEvent)
  }
} finally {
  await pool.end()
}
