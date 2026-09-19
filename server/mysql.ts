/**
 * Optional MySQL pool for in-house telemetry.
 * Graceful no-op when MYSQL_URL / MYSQL_HOST unset.
 */
import mysql from 'mysql2/promise'

let pool: mysql.Pool | null = null
let initAttempted = false

export function isMysqlConfigured(): boolean {
  const url = process.env.MYSQL_URL?.trim()
  if (url) return true
  return Boolean(process.env.MYSQL_HOST?.trim() && process.env.MYSQL_DATABASE?.trim())
}

export function getMysqlPool(): mysql.Pool | null {
  if (initAttempted) return pool
  initAttempted = true
  if (!isMysqlConfigured()) {
    pool = null
    return null
  }
  try {
    const url = process.env.MYSQL_URL?.trim()
    if (url) {
      pool = mysql.createPool(url)
    } else {
      pool = mysql.createPool({
        host: process.env.MYSQL_HOST!.trim(),
        port: Number(process.env.MYSQL_PORT || 3306),
        user: process.env.MYSQL_USER?.trim() || 'root',
        password: process.env.MYSQL_PASSWORD ?? '',
        database: process.env.MYSQL_DATABASE!.trim(),
        waitForConnections: true,
        connectionLimit: 4,
        enableKeepAlive: true,
      })
    }
  } catch (err) {
    console.warn(
      '[mysql] pool init failed — telemetry will no-op:',
      err instanceof Error ? err.message : err,
    )
    pool = null
  }
  return pool
}

export function mysqlHealthSnippet(): { mysql: boolean } {
  return { mysql: Boolean(getMysqlPool()) }
}
