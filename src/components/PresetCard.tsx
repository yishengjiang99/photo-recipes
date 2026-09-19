import { Heart } from 'lucide-react'
import { Link } from 'react-router-dom'
import type { RecipePreset } from '../types'
import { MODE_LABELS, TAG_LABELS } from '../types'
import { GearIcons } from './GearIcons'

interface PresetCardProps {
  preset: RecipePreset
  favorite: boolean
  onToggleFavorite: (id: string) => void
}

export function PresetCard({ preset, favorite, onToggleFavorite }: PresetCardProps) {
  return (
    <article className="preset-card relative overflow-hidden rounded-2xl border border-zinc-800/90 bg-zinc-900/60">
      <Link to={`/preset/${preset.id}`} className="block p-5 text-left focus:outline-none focus-visible:ring-2 focus-visible:ring-rose-500/60">
        <div className="mb-3 flex items-start justify-between gap-3">
          <div className="flex flex-wrap gap-1.5">
            {preset.tags.map((t) => (
              <span
                key={t}
                className="rounded-md bg-rose-500/10 px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wide text-rose-300"
              >
                {TAG_LABELS[t]}
              </span>
            ))}
            <span className="rounded-md bg-zinc-800 px-2 py-0.5 text-[11px] text-zinc-500">
              p.{preset.page}
            </span>
          </div>
        </div>

        <h2 className="font-display text-xl leading-snug text-zinc-50 sm:text-[1.35rem]">
          {preset.title}
        </h2>
        <p className="mt-2 line-clamp-2 text-sm leading-relaxed text-zinc-400">
          {preset.blurb}
        </p>

        <div className="mt-4 flex flex-wrap items-center gap-3 border-t border-zinc-800/80 pt-4">
          <GearIcons gear={preset.gear} />
          <div className="ml-auto text-right">
            <p className="text-[10px] uppercase tracking-wider text-zinc-600">Key setting</p>
            <p className="font-mono text-xs text-zinc-300">
              {preset.dials.shutter ?? preset.dials.aperture ?? MODE_LABELS[preset.dials.mode]}
            </p>
          </div>
        </div>
      </Link>

      <button
        type="button"
        aria-label={favorite ? 'Remove from favorites' : 'Add to favorites'}
        aria-pressed={favorite}
        onClick={(e) => {
          e.preventDefault()
          onToggleFavorite(preset.id)
        }}
        className="absolute right-3 top-3 rounded-full bg-zinc-950/70 p-2 text-zinc-500 backdrop-blur transition hover:text-rose-400"
      >
        <Heart
          className={`h-4 w-4 ${favorite ? 'fill-rose-500 text-rose-500' : ''}`}
          strokeWidth={2}
        />
      </button>
    </article>
  )
}
