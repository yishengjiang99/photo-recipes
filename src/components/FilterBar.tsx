import { Heart, LayoutGrid } from 'lucide-react'
import type { TechniqueTag } from '../types'
import { TAG_LABELS } from '../types'

const ALL_TAGS: TechniqueTag[] = [
  'hdr',
  'motion',
  'depth-of-field',
  'composition',
]

interface FilterBarProps {
  activeTag: TechniqueTag | 'all' | 'favorites'
  onChange: (tag: TechniqueTag | 'all' | 'favorites') => void
  favoritesCount: number
}

export function FilterBar({ activeTag, onChange, favoritesCount }: FilterBarProps) {
  const chips: {
    id: TechniqueTag | 'all' | 'favorites'
    label: string
    icon?: typeof Heart
  }[] = [
    { id: 'all', label: 'All', icon: LayoutGrid },
    {
      id: 'favorites',
      label: `Favorites${favoritesCount ? ` (${favoritesCount})` : ''}`,
      icon: Heart,
    },
    ...ALL_TAGS.map((t) => ({
      id: t as TechniqueTag | 'all' | 'favorites',
      label: TAG_LABELS[t],
    })),
  ]

  return (
    <div
      className="-mx-1 flex flex-nowrap gap-2 overflow-x-auto px-1 pb-1 lg:flex-wrap"
      role="tablist"
      aria-label="Filter by technique"
    >
      {chips.map(({ id, label, icon: Icon }) => {
        const active = activeTag === id
        return (
          <button
            key={id}
            type="button"
            role="tab"
            aria-selected={active}
            onClick={() => onChange(id)}
            className={`inline-flex min-h-9 shrink-0 items-center gap-1.5 rounded-full px-3.5 py-1.5 text-sm font-medium transition ${
              active
                ? 'bg-accent text-white'
                : 'border border-border bg-transparent text-ink-secondary hover:border-border-strong hover:text-ink'
            }`}
          >
            {Icon ? <Icon className="h-3.5 w-3.5" strokeWidth={2} /> : null}
            {label}
          </button>
        )
      })}
    </div>
  )
}
