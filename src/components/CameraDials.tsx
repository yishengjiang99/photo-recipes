import type { DialSettings } from '../types'
import { MODE_LABELS } from '../types'

interface CameraDialsProps {
  dials: DialSettings
  label?: string
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
        className={`relative flex h-24 w-24 items-center justify-center rounded-full bg-gradient-to-b from-zinc-800 to-zinc-950 shadow-inner ring-2 ${
          accent ? 'ring-rose-500/50' : 'ring-zinc-700'
        }`}
        style={{
          backgroundImage:
            'repeating-conic-gradient(from 0deg, #3f3f46 0deg 2deg, transparent 2deg 10deg)',
          backgroundBlendMode: 'overlay',
        }}
      >
        <div className="absolute inset-2 rounded-full bg-zinc-900/95 ring-1 ring-zinc-700/80" />
        <div className="relative z-10 max-w-[4.5rem] px-1 text-center">
          <p
            className={`font-mono text-sm font-semibold leading-tight ${
              accent ? 'text-rose-300' : 'text-zinc-100'
            }`}
          >
            {value}
          </p>
        </div>
        {/* pointer notch */}
        <span
          className={`absolute top-1 h-2 w-1 rounded-full ${
            accent ? 'bg-rose-400' : 'bg-zinc-500'
          }`}
        />
      </div>
      <p className="text-[10px] font-semibold uppercase tracking-widest text-zinc-500">
        {label}
      </p>
    </div>
  )
}

export function CameraDials({ dials, label = 'Recommended dials' }: CameraDialsProps) {
  const tiles: { label: string; value: string; accent?: boolean }[] = [
    { label: 'Mode', value: shortMode(dials.mode), accent: true },
  ]
  if (dials.aperture) tiles.push({ label: 'Aperture', value: dials.aperture })
  if (dials.shutter) tiles.push({ label: 'Shutter', value: dials.shutter })
  if (dials.iso) tiles.push({ label: 'ISO', value: dials.iso })
  if (dials.evBracket) tiles.push({ label: 'Bracket', value: dials.evBracket, accent: true })

  return (
    <section className="rounded-2xl border border-zinc-800 bg-zinc-900/40 p-5">
      <div className="mb-4 flex items-baseline justify-between gap-2">
        <h3 className="font-display text-lg text-zinc-100">{label}</h3>
        <span className="text-[10px] uppercase tracking-wider text-zinc-600">
          Educational · simulated
        </span>
      </div>
      <div className="flex flex-wrap justify-center gap-5 sm:gap-6">
        {tiles.map((t) => (
          <Dial key={t.label} {...t} />
        ))}
      </div>
      {dials.notes ? (
        <p className="mt-4 text-center text-sm text-zinc-400">{dials.notes}</p>
      ) : null}
      <p className="mt-2 text-center text-xs text-zinc-600">
        Full mode: {MODE_LABELS[dials.mode]}
      </p>
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
