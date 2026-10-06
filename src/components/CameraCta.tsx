import { Camera } from 'lucide-react'
import { Link } from 'react-router-dom'
import { track } from '../lib/analytics'

/** Opens the camera-first /app Field Coach (coach-only; no dial writes). */
export const CAMERA_HREF = '/app'

type CameraCtaProps = {
  label?: string
  className?: string
  fullWidth?: boolean
  size?: 'md' | 'lg'
  to?: string
  onClick?: () => void
  /** App Store badge is the primary landing action; browser preview defaults to secondary. */
  variant?: 'primary' | 'secondary'
}

const sizeClass = {
  md: 'min-h-11 gap-2 px-5 py-2.5 text-sm',
  lg: 'min-h-12 gap-2.5 px-6 py-3 text-base',
} as const

/**
 * Primary camera CTA for landing / marketing surfaces.
 * Opens web Field Coach live viewfinder — coach-only (no dial writes).
 */
export function CameraCta({
  label = 'Try the preview',
  className = '',
  fullWidth = false,
  size = 'md',
  to = CAMERA_HREF,
  onClick,
  variant = 'secondary',
}: CameraCtaProps) {
  const variantClass =
    variant === 'primary'
      ? 'bg-accent text-white shadow-[0_8px_24px_-12px_rgba(244,63,94,0.55)] hover:bg-accent-soft'
      : 'bg-transparent text-ink ring-1 ring-border hover:bg-surface'
  return (
    <Link
      to={to}
      onClick={() => {
        track('landing_cta_camera', { source: 'camera_cta', label })
        track('preview_cta_click', { label, variant })
        onClick?.()
      }}
      aria-label={`${label} — open Field Coach live viewfinder`}
      className={`inline-flex items-center justify-center rounded-full font-semibold transition ${variantClass} focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent ${sizeClass[size]} ${fullWidth ? 'w-full' : ''} ${className}`}
    >
      <Camera className={size === 'lg' ? 'h-5 w-5' : 'h-4 w-4'} strokeWidth={2} aria-hidden />
      {label}
    </Link>
  )
}
