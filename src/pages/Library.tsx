import { useMemo, useState } from 'react'
import { FieldCoach } from '../components/FieldCoach'
import { FilterBar } from '../components/FilterBar'
import { PresetCard } from '../components/PresetCard'
import { presets } from '../data/presets'
import { useFavorites } from '../hooks/useFavorites'
import type { TechniqueTag } from '../types'

export function Library() {
  const [filter, setFilter] = useState<TechniqueTag | 'all' | 'favorites'>('all')
  const { favorites, toggleFavorite, isFavorite } = useFavorites()

  const visible = useMemo(() => {
    let list = [...presets].sort((a, b) => a.page - b.page)
    if (filter === 'favorites') {
      list = list.filter((p) => favorites.includes(p.id))
    } else if (filter !== 'all') {
      list = list.filter((p) => p.tags.includes(filter))
    }
    return list
  }, [filter, favorites])

  return (
    <div>
      <div className="mb-6 text-left">
        <h1 className="font-display text-[1.75rem] text-ink sm:text-3xl">
          Recipe library
        </h1>
        <p className="mt-2 text-sm leading-relaxed text-ink-secondary">
          Shoot checklists + dials. Ask when you’re stuck.
        </p>
      </div>

      <FieldCoach />

      <FilterBar
        activeTag={filter}
        onChange={setFilter}
        favoritesCount={favorites.length}
      />

      <div className="mt-6 grid gap-4 lg:grid-cols-2">
        {visible.length === 0 ? (
          <p className="rounded-2xl border border-dashed border-border px-6 py-12 text-center text-sm text-ink-tertiary lg:col-span-2">
            {filter === 'favorites'
              ? 'No favorites yet — tap the heart on a recipe card.'
              : 'No presets match this filter.'}
          </p>
        ) : (
          visible.map((preset) => (
            <PresetCard
              key={preset.id}
              preset={preset}
              favorite={isFavorite(preset.id)}
              onToggleFavorite={toggleFavorite}
            />
          ))
        )}
      </div>
    </div>
  )
}
