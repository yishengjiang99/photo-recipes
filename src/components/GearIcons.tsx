import {
  Aperture,
  Camera,
  Flashlight,
  Focus,
  Smartphone,
  Timer,
} from 'lucide-react'
import type { GearItem } from '../types'
import { GEAR_LABELS } from '../types'

const ICONS: Record<GearItem, typeof Camera> = {
  camera: Camera,
  phone: Smartphone,
  tripod: Focus,
  remote: Timer,
  flash: Flashlight,
  'wide-angle': Aperture,
}

export function GearIcons({
  gear,
  size = 'sm',
}: {
  gear: GearItem[]
  size?: 'sm' | 'md'
}) {
  const box = size === 'sm' ? 'h-7 w-7' : 'h-9 w-9'
  const icon = size === 'sm' ? 'h-3.5 w-3.5' : 'h-4.5 w-4.5'

  return (
    <ul className="flex flex-wrap gap-1.5" aria-label="Equipment">
      {gear.map((g) => {
        const Icon = ICONS[g]
        return (
          <li
            key={g}
            title={GEAR_LABELS[g]}
            className={`flex ${box} items-center justify-center rounded-lg bg-zinc-800/80 text-rose-400 ring-1 ring-zinc-700/80`}
          >
            <Icon className={icon} strokeWidth={1.75} aria-hidden />
            <span className="sr-only">{GEAR_LABELS[g]}</span>
          </li>
        )
      })}
    </ul>
  )
}
