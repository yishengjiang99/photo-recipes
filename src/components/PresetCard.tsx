import { Heart } from 'lucide-react'
import { Link } from 'react-router-dom'
import type { RecipePreset, TechniqueTag } from '../types'
import { GEAR_LABELS, MODE_LABELS, TAG_LABELS } from '../types'

interface PresetCardProps {
  preset: RecipePreset
  favorite: boolean
  onToggleFavorite: (id: string) => void
}

const CATEGORY_RAIL: Record<TechniqueTag, string> = {
  'depth-of-field': '#5b8def',
  motion: '#f59e0b',
  hdr: '#a78bfa',
  composition: '#2dd4bf',
}

function categoryTint(tags: TechniqueTag[]): string {
  const primary = tags[0]
  return primary ? CATEGORY_RAIL[primary] : '#f43f5e'
}

export function PresetCard({ preset, favorite, onToggleFavorite }: PresetCardProps) {
  const tint = categoryTint(preset.tags)
  const keySetting =
    preset.dials.shutter ??
    preset.dials.aperture ??
    MODE_LABELS[preset.dials.mode]

  return (
    <article className="preset-card relative overflow-hidden rounded-2xl border border-border bg-surface">
      <span
        className="absolute inset-y-0 left-0 w-[3px]"
        style={{ backgroundColor: tint }}
        aria-hidden
      />
      <Link
        to={`/preset/${preset.id}`}
        className="block p-4 pl-5 text-left focus:outline-none focus-visible:ring-2 focus-visible:ring-accent/50 sm:p-5 sm:pl-6"
      >
        <div className="mb-3 flex items-start justify-between gap-3 pr-10">
          <div className="flex flex-wrap items-center gap-1.5">
            {preset.tags.map((t) => (
              <span
                key={t}
                className="rounded-md px-2 py-0.5 text-[11px] font-semibold uppercase tracking-[0.08em] text-ink-secondary"
                style={{ backgroundColor: `${CATEGORY_RAIL[t]}2e` }}
              >
                {TAG_LABELS[t]}
              </span>
            ))}
            <span className="text-[11px] text-ink-tertiary">p.{preset.page}</span>
          </div>
        </div>

        <h2 className="font-display text-[1.35rem] leading-snug text-ink sm:text-2xl">
          {preset.title}
        </h2>
        <p className="mt-2 line-clamp-2 text-sm leading-relaxed text-ink-secondary">
          {preset.blurb}
        </p>

        <div className="mt-4 flex flex-wrap items-end justify-between gap-3 border-t border-border pt-4">
          <div>
            <p className="text-[10px] font-semibold uppercase tracking-wider text-ink-tertiary">
              Key setting
            </p>
            <p className="font-mono text-base font-semibold text-ink sm:text-lg">
              {keySetting}
            </p>
          </div>
          <ul className="flex flex-wrap gap-1.5" aria-label="Equipment">
            {preset.gear.map((g) => (
              <li
                key={g}
                className="rounded-full border border-border bg-bg-elevated px-2.5 py-1 text-xs text-ink-secondary"
              >
                {GEAR_LABELS[g]}
              </li>
            ))}
          </ul>
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
        className="absolute right-3 top-3 inline-flex h-11 w-11 items-center justify-center rounded-full text-ink-tertiary transition hover:text-accent"
      >
        <Heart
          className={`h-4 w-4 ${favorite ? 'fill-accent text-accent' : ''}`}
          strokeWidth={2}
        />
      </button>
    </article>
  )
}
