import { track } from '../lib/analytics'
import { APP_STORE_URL } from '../lib/site'

type AppStoreBadgeProps = {
  /** Where on the page — sent as telemetry `source`. */
  source: string
  /** Rendered badge height in px (Apple min 40px onscreen). */
  height?: 40 | 48 | 56
  className?: string
  onClick?: () => void
}

const heightClass = { 40: 'h-10', 48: 'h-12', 56: 'h-14' } as const

/**
 * Primary acquisition CTA (App Store first; browser camera is a secondary preview).
 * Official Apple badge artwork, unmodified per App Store marketing guidelines.
 */
export function AppStoreBadge({ source, height = 48, className = '', onClick }: AppStoreBadgeProps) {
  return (
    <a
      href={APP_STORE_URL}
      onClick={() => {
        track('landing_cta_appstore', { source })
        track('appstore_badge_click', { source })
        onClick?.()
      }}
      className={`inline-flex items-center justify-center ${className}`}
      aria-label="Download ProTune AI Camera on the App Store"
    >
      <img
        src="/download-on-the-app-store.svg"
        alt="Download on the App Store"
        width={(120 * height) / 40}
        height={height}
        className={`${heightClass[height]} w-auto`}
        loading="eager"
      />
    </a>
  )
}
