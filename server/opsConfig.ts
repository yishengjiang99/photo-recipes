/**
 * Runtime ops overrides for Free Peek (persisted JSON under server/data/).
 * Resolution: runtime override → env → hardcoded default.
 * Admin can PATCH without redeploy / env file edits.
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const DATA_DIR = path.resolve(__dirname, 'data')
const STORE_PATH = path.join(DATA_DIR, 'ops-config.json')

/** Default Free Peek Ask/Vision/Auto Optimize combined daily cap. */
export const DEFAULT_FREE_DAILY_LIMIT = 5
/** Default: free users may apply camera dials / phoneTargets. */
export const DEFAULT_FREE_PHONE_TARGETS_ENABLED = true

export type OpsConfigOverrides = {
  freeDailyLimit?: number
  freePhoneTargetsEnabled?: boolean
}

export type OpsConfigSource = 'override' | 'env' | 'default'

export type OpsConfigResolved = {
  freeDailyLimit: number
  freePhoneTargetsEnabled: boolean
  sources: {
    freeDailyLimit: OpsConfigSource
    freePhoneTargetsEnabled: OpsConfigSource
  }
  overrides: OpsConfigOverrides
  env: {
    FREE_DAILY_LIMIT: string | null
    FREE_PHONE_TARGETS_ENABLED: string | null
  }
}

function ensureDataDir() {
  if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true })
}

function readOverrides(): OpsConfigOverrides {
  ensureDataDir()
  try {
    if (!fs.existsSync(STORE_PATH)) return {}
    const raw = fs.readFileSync(STORE_PATH, 'utf8')
    const parsed = JSON.parse(raw) as Record<string, unknown>
    const out: OpsConfigOverrides = {}
    if (typeof parsed.freeDailyLimit === 'number' && Number.isFinite(parsed.freeDailyLimit)) {
      const n = Math.trunc(parsed.freeDailyLimit)
      if (n >= 0) out.freeDailyLimit = n
    }
    if (typeof parsed.freePhoneTargetsEnabled === 'boolean') {
      out.freePhoneTargetsEnabled = parsed.freePhoneTargetsEnabled
    }
    return out
  } catch {
    return {}
  }
}

function writeOverrides(overrides: OpsConfigOverrides) {
  ensureDataDir()
  const tmp = `${STORE_PATH}.${process.pid}.tmp`
  fs.writeFileSync(tmp, JSON.stringify(overrides, null, 2), 'utf8')
  fs.renameSync(tmp, STORE_PATH)
}

/** Test helper: wipe overrides file (or write empty). */
export function clearOpsConfigOverridesForTests() {
  ensureDataDir()
  if (fs.existsSync(STORE_PATH)) fs.unlinkSync(STORE_PATH)
}

/** Test helper: point at an isolated store path is not supported; use clear + patch. */
export function getOpsConfigStorePath(): string {
  return STORE_PATH
}

function parseNonNegInt(raw: string | undefined, fallback: number): number {
  if (raw === undefined || raw.trim() === '') return fallback
  const n = Number.parseInt(raw.trim(), 10)
  if (!Number.isFinite(n) || n < 0) return fallback
  return n
}

function parseBoolEnv(raw: string | undefined): boolean | undefined {
  if (raw === undefined || raw.trim() === '') return undefined
  const v = raw.trim().toLowerCase()
  if (v === '1' || v === 'true' || v === 'yes' || v === 'on') return true
  if (v === '0' || v === 'false' || v === 'no' || v === 'off') return false
  return undefined
}

export function getOpsConfigOverrides(): OpsConfigOverrides {
  return readOverrides()
}

export function resolveOpsConfig(): OpsConfigResolved {
  const overrides = readOverrides()
  const envLimitRaw = process.env.FREE_DAILY_LIMIT?.trim() || null
  const envDialsRaw = process.env.FREE_PHONE_TARGETS_ENABLED?.trim() || null

  let freeDailyLimit: number
  let freeDailyLimitSource: OpsConfigSource
  if (overrides.freeDailyLimit !== undefined) {
    freeDailyLimit = overrides.freeDailyLimit
    freeDailyLimitSource = 'override'
  } else if (envLimitRaw !== null) {
    freeDailyLimit = parseNonNegInt(envLimitRaw, DEFAULT_FREE_DAILY_LIMIT)
    freeDailyLimitSource = 'env'
  } else {
    freeDailyLimit = DEFAULT_FREE_DAILY_LIMIT
    freeDailyLimitSource = 'default'
  }

  let freePhoneTargetsEnabled: boolean
  let freePhoneTargetsSource: OpsConfigSource
  if (overrides.freePhoneTargetsEnabled !== undefined) {
    freePhoneTargetsEnabled = overrides.freePhoneTargetsEnabled
    freePhoneTargetsSource = 'override'
  } else {
    const fromEnv = parseBoolEnv(envDialsRaw ?? undefined)
    if (fromEnv !== undefined) {
      freePhoneTargetsEnabled = fromEnv
      freePhoneTargetsSource = 'env'
    } else {
      freePhoneTargetsEnabled = DEFAULT_FREE_PHONE_TARGETS_ENABLED
      freePhoneTargetsSource = 'default'
    }
  }

  return {
    freeDailyLimit,
    freePhoneTargetsEnabled,
    sources: {
      freeDailyLimit: freeDailyLimitSource,
      freePhoneTargetsEnabled: freePhoneTargetsSource,
    },
    overrides,
    env: {
      FREE_DAILY_LIMIT: envLimitRaw,
      FREE_PHONE_TARGETS_ENABLED: envDialsRaw,
    },
  }
}

export function getFreeDailyLimitFromOps(): number {
  return resolveOpsConfig().freeDailyLimit
}

export function getFreePhoneTargetsEnabled(): boolean {
  return resolveOpsConfig().freePhoneTargetsEnabled
}

export type PatchOpsConfigResult =
  | { ok: true; config: OpsConfigResolved }
  | { ok: false; error: string; details?: string }

/**
 * Validate and merge PATCH body into persisted overrides.
 * Pass `null` for a key to clear that override (fall back to env/default).
 */
export function patchOpsConfig(body: unknown): PatchOpsConfigResult {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    return { ok: false, error: 'invalid_body', details: 'Expected JSON object' }
  }
  const input = body as Record<string, unknown>
  const next = { ...readOverrides() }

  if ('freeDailyLimit' in input) {
    const v = input.freeDailyLimit
    if (v === null) {
      delete next.freeDailyLimit
    } else if (typeof v === 'number' && Number.isFinite(v) && Number.isInteger(v) && v >= 0) {
      next.freeDailyLimit = v
    } else if (typeof v === 'string' && v.trim() !== '') {
      const n = Number.parseInt(v.trim(), 10)
      if (!Number.isFinite(n) || !Number.isInteger(n) || n < 0) {
        return {
          ok: false,
          error: 'invalid_freeDailyLimit',
          details: 'freeDailyLimit must be an integer ≥ 0 (0 = no free peeks)',
        }
      }
      next.freeDailyLimit = n
    } else {
      return {
        ok: false,
        error: 'invalid_freeDailyLimit',
        details: 'freeDailyLimit must be an integer ≥ 0 (0 = no free peeks)',
      }
    }
  }

  if ('freePhoneTargetsEnabled' in input) {
    const v = input.freePhoneTargetsEnabled
    if (v === null) {
      delete next.freePhoneTargetsEnabled
    } else if (typeof v === 'boolean') {
      next.freePhoneTargetsEnabled = v
    } else if (v === 'true' || v === 'false') {
      next.freePhoneTargetsEnabled = v === 'true'
    } else {
      return {
        ok: false,
        error: 'invalid_freePhoneTargetsEnabled',
        details: 'freePhoneTargetsEnabled must be a boolean',
      }
    }
  }

  writeOverrides(next)
  return { ok: true, config: resolveOpsConfig() }
}
