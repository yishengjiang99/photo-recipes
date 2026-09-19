import type { DialSettings } from '../types'
import { MODE_LABELS } from '../types'

interface CameraDialsProps {
  dials: DialSettings
  label?: string
  /** When true, show web-coach badge (recommendations are not applied in-browser). */
  coachOnly?: boolean
}

function Dial({
  label,
  value,
  accent,
}: {
  label: string
  value: string
  accent?: boolean
}) {
  return (
    <div className="dial-animate flex flex-col items-center gap-2">
      <div
        className={`relative flex h-24 w-24 items-center justify-center rounded-full bg-gradient-to-b from-surface-2 to-bg shadow-inner ring-2 ${
          accent ? 'ring-border-strong' : 'ring-border'
        }`}
        style={{
          backgroundImage:
            'repeating-conic-gradient(from 0deg, #3f3f4a 0deg 2deg, transparent 2deg 10deg)',
          backgroundBlendMode: 'overlay',
        }}
      >
        <div className="absolute inset-2 rounded-full bg-surface/95 ring-1 ring-border" />
        <div className="relative z-10 max-w-[4.75rem] px-1 text-center">
          <p className="font-mono text-[0.9375rem] font-semibold leading-tight text-ink sm:text-base">
            {value}
          </p>
        </div>
        <span
          className={`absolute top-1 h-2 w-1 rounded-full ${
            accent ? 'bg-accent-soft' : 'bg-ink-tertiary'
          }`}
        />
      </div>
      <p className="text-[10px] font-semibold uppercase tracking-widest text-ink-tertiary">
        {label}
      </p>
    </div>
  )
}

export function CameraDials({
  dials,
  label = 'Recommended dials',
  coachOnly = false,
}: CameraDialsProps) {
  const tiles: { label: string; value: string; accent?: boolean }[] = [
    { label: 'Mode', value: shortMode(dials.mode), accent: true },
  ]
  if (dials.aperture) tiles.push({ label: 'Aperture', value: dials.aperture })
  if (dials.shutter) tiles.push({ label: 'Shutter', value: dials.shutter })
  if (dials.iso) tiles.push({ label: 'ISO', value: dials.iso })
  if (dials.evBracket)
    tiles.push({ label: 'Bracket', value: dials.evBracket, accent: true })

  return (
    <section className="rounded-2xl border border-border bg-surface-2 p-5">
      <div className="mb-4 flex flex-wrap items-baseline justify-between gap-2">
        <h3 className="font-display text-lg text-ink">{label}</h3>
        <div className="flex flex-wrap items-center gap-2">
          {coachOnly ? (
            <span className="rounded-full bg-vision/15 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-vision ring-1 ring-vision/30">
              Coach — not applied on web
            </span>
          ) : null}
          <span className="text-[10px] font-semibold uppercase tracking-wider text-ink-tertiary">
            Educational · simulated
          </span>
        </div>
      </div>
      <div className="grid grid-cols-2 justify-items-center gap-5 sm:flex sm:flex-wrap sm:justify-center sm:gap-6">
        {tiles.map((t) => (
          <Dial key={t.label} {...t} />
        ))}
      </div>
      {dials.notes ? (
        <p className="mt-4 text-center text-sm text-ink-secondary">{dials.notes}</p>
      ) : null}
      <p className="mt-2 text-center text-xs text-ink-tertiary">
        Full mode: {MODE_LABELS[dials.mode]}
      </p>
      {coachOnly ? (
        <p className="mt-2 text-center text-xs text-ink-tertiary">
          Web recommends dials only. The iOS app applies shutter / ISO / EV / WB / focus via Auto
          Optimize.
        </p>
      ) : null}
    </section>
  )
}

function shortMode(mode: DialSettings['mode']): string {
  switch (mode) {
    case 'aperture-priority':
      return 'A / Av'
    case 'shutter-priority':
      return 'S / Tv'
    case 'manual':
      return 'M'
    case 'phone-hdr':
      return 'HDR'
    default:
      return 'Auto'
  }
}
