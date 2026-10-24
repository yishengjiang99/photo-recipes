/**
 * Optional MySQL pool for the FinalCap app's OWN database (admin usage section).
 * This is a different database from this app's telemetry pool (server/mysql.ts):
 * FinalCap's server keeps users / daily inference usage / chat interactions /
 * Apple transactions in the `finalcut` database on the same host.
 * Graceful no-op when FINALCUT_MYSQL_URL / FINALCUT_MYSQL_HOST+DATABASE unset.
 * Read-only use: finalcapUsage.ts only ever issues SELECTs against this pool.
 */
import mysql from 'mysql2/promise'

let pool: mysql.Pool | null = null
let initAttempted = false

export function isFinalcutMysqlConfigured(): boolean {
  const url = process.env.FINALCUT_MYSQL_URL?.trim()
  if (url) return true
  return Boolean(
    process.env.FINALCUT_MYSQL_HOST?.trim() &&
      process.env.FINALCUT_MYSQL_DATABASE?.trim(),
  )
}

export function getFinalcutMysqlPool(): mysql.Pool | null {
  if (initAttempted) return pool
  initAttempted = true
  if (!isFinalcutMysqlConfigured()) {
    pool = null
    return null
  }
  try {
    const url = process.env.FINALCUT_MYSQL_URL?.trim()
    if (url) {
      pool = mysql.createPool(url)
    } else {
      pool = mysql.createPool({
        host: process.env.FINALCUT_MYSQL_HOST!.trim(),
        port: Number(process.env.FINALCUT_MYSQL_PORT || 3306),
        user: process.env.FINALCUT_MYSQL_USER?.trim() || 'root',
        password: process.env.FINALCUT_MYSQL_PASSWORD ?? '',
        database: process.env.FINALCUT_MYSQL_DATABASE!.trim(),
        waitForConnections: true,
        connectionLimit: 2,
        enableKeepAlive: true,
      })
    }
  } catch (err) {
    console.warn(
      '[finalcap-mysql] pool init failed — FinalCap usage section will be empty:',
      err instanceof Error ? err.message : err,
    )
    pool = null
  }
  return pool
}
