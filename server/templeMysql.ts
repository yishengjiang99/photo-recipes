/**
 * Optional MySQL pool for the Temple of the High Priestess game's OWN database
 * (admin Temple section). This is a different database from this app's telemetry
 * pool (server/mysql.ts) and from FinalCap's (server/finalcapMysql.ts): Temple's
 * server keeps devices / players / events / entitlements / saves in the `temple`
 * database on the same host.
 * Graceful no-op when TEMPLE_MYSQL_URL / TEMPLE_MYSQL_HOST+DATABASE unset.
 * Read-only use: templeUsage.ts only ever issues SELECTs against this pool.
 * The temple DB user is the same host-local user temple-api uses (socket auth
 * via /var/run/mysqld/mysqld.sock); set TEMPLE_MYSQL_SOCKET when the server
 * runs on the droplet, otherwise TEMPLE_MYSQL_HOST + PORT.
 */
import mysql from 'mysql2/promise'

let pool: mysql.Pool | null = null
let initAttempted = false

export function isTempleMysqlConfigured(): boolean {
  const url = process.env.TEMPLE_MYSQL_URL?.trim()
  if (url) return true
  return Boolean(
    process.env.TEMPLE_MYSQL_HOST?.trim() &&
      process.env.TEMPLE_MYSQL_DATABASE?.trim(),
  )
}

export function getTempleMysqlPool(): mysql.Pool | null {
  if (initAttempted) return pool
  initAttempted = true
  if (!isTempleMysqlConfigured()) {
    pool = null
    return null
  }
  try {
    const url = process.env.TEMPLE_MYSQL_URL?.trim()
    if (url) {
      pool = mysql.createPool(url)
    } else {
      pool = mysql.createPool({
        host: process.env.TEMPLE_MYSQL_HOST!.trim(),
        port: Number(process.env.TEMPLE_MYSQL_PORT || 3306),
        socketPath: process.env.TEMPLE_MYSQL_SOCKET?.trim() || undefined,
        user: process.env.TEMPLE_MYSQL_USER?.trim() || 'root',
        password: process.env.TEMPLE_MYSQL_PASSWORD ?? '',
        database: process.env.TEMPLE_MYSQL_DATABASE!.trim(),
        waitForConnections: true,
        connectionLimit: 2,
        enableKeepAlive: true,
      })
    }
  } catch (err) {
    console.warn(
      '[temple-mysql] pool init failed — Temple section will be empty:',
      err instanceof Error ? err.message : err,
    )
    pool = null
  }
  return pool
}
