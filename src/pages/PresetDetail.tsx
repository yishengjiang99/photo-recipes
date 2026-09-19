import {
  ArrowLeft,
  Heart,
  Lightbulb,
  ListOrdered,
  Smartphone,
  Sparkles,
} from 'lucide-react'
import { useMemo, useState } from 'react'
import { Link, Navigate, useLocation, useParams } from 'react-router-dom'
import type { AiRecommendState } from '../components/FieldCoach'
import { CameraDials } from '../components/CameraDials'
import { ChecklistMode } from '../components/ChecklistMode'
import { presets } from '../data/presets'
import { useFavorites } from '../hooks/useFavorites'
import type { TechniqueTag } from '../types'
import { GEAR_LABELS, MODE_LABELS, TAG_LABELS } from '../types'

const CATEGORY_TINT: Record<TechniqueTag, string> = {
  'depth-of-field': '#5b8def',
  motion: '#f59e0b',
  hdr: '#a78bfa',
  composition: '#2dd4bf',
}

export function PresetDetail() {
  const { id } = useParams<{ id: string }>()
  const location = useLocation()
  const ai = (location.state as AiRecommendState | null)?.fromAsk
    ? (location.state as AiRecommendState)
    : null
  const preset = presets.find((p) => p.id === id)
  const { isFavorite, toggleFavorite } = useFavorites()
  const [variantId, setVariantId] = useState<string | 'base'>('base')

  const activeDials = useMemo(() => {
    if (!preset) return null
    if (variantId === 'base') return preset.dials
    return preset.subVariants?.find((v) => v.id === variantId)?.dials ?? preset.dials
  }, [preset, variantId])

  const activeVariantTips = useMemo(() => {
    if (!preset || variantId === 'base') return null
    return preset.subVariants?.find((v) => v.id === variantId)?.tips ?? null
  }, [preset, variantId])

  if (!preset || !activeDials) {
    return <Navigate to="/" replace />
  }

  const favorite = isFavorite(preset.id)

  return (
    <div className="text-left">
      <div className="mb-6 flex items-center justify-between gap-3">
        <Link
          to="/"
          className="inline-flex min-h-11 items-center gap-1.5 text-sm text-ink-secondary transition hover:text-ink"
        >
          <ArrowLeft className="h-4 w-4" />
          Library
        </Link>
        <button
          type="button"
          onClick={() => toggleFavorite(preset.id)}
          className={`inline-flex min-h-11 items-center gap-1.5 rounded-full px-3 py-1.5 text-sm ring-1 transition ${
            favorite
              ? 'bg-accent-muted text-accent-soft ring-accent/30'
              : 'bg-surface text-ink-secondary ring-border hover:text-ink'
          }`}
        >
          <Heart className={`h-4 w-4 ${favorite ? 'fill-accent text-accent' : ''}`} />
          {favorite ? 'Favorited' : 'Favorite'}
        </button>
      </div>

      <div className="mb-2 flex flex-wrap gap-1.5">
        {preset.tags.map((t) => (
          <span
            key={t}
            className="rounded-md px-2 py-0.5 text-[11px] font-semibold uppercase tracking-[0.08em] text-ink-secondary"
            style={{ backgroundColor: `${CATEGORY_TINT[t]}2e` }}
          >
            {TAG_LABELS[t]}
          </span>
        ))}
        <span className="rounded-md bg-surface-2 px-2 py-0.5 text-[11px] text-ink-tertiary">
          Book p.{preset.page}
        </span>
      </div>

      <h1 className="font-display text-3xl leading-tight text-ink sm:text-4xl">
        {preset.title}
      </h1>
      <p className="mt-3 text-base leading-relaxed text-ink-secondary">{preset.blurb}</p>

      {ai ? (
        <section className="mt-6 rounded-2xl border border-border bg-surface-2 p-4">
          <h2 className="mb-2 flex items-center gap-2 text-xs font-semibold uppercase tracking-wider text-accent-soft">
            <Sparkles className="h-3.5 w-3.5" />
            Grok picked this recipe
          </h2>
          <p className="text-sm leading-relaxed text-ink-secondary">{ai.reason}</p>
          {ai.tips.length > 0 ? (
            <ul className="mt-3 space-y-1.5">
              {ai.tips.map((tip) => (
                <li key={tip} className="flex gap-2 text-sm text-ink-secondary">
                  <span className="mt-2 h-1 w-1 shrink-0 rounded-full bg-accent" />
                  {tip}
                </li>
              ))}
            </ul>
          ) : null}
        </section>
      ) : null}

      <div className="mt-6 flex flex-wrap gap-2">
        {preset.gear.map((g) => (
          <span
            key={g}
            className="rounded-full border border-border bg-surface px-3 py-1.5 text-sm text-ink-secondary"
          >
            {GEAR_LABELS[g]}
          </span>
        ))}
      </div>

      <section className="mt-8">
        <h2 className="mb-2 flex items-center gap-2 text-sm font-semibold text-ink">
          <Sparkles className="h-4 w-4 text-accent-soft" />
          When to use
        </h2>
        <p className="text-sm leading-relaxed text-ink-secondary">{preset.whenToUse}</p>
      </section>

      {preset.subVariants && preset.subVariants.length > 0 ? (
        <section className="mt-8">
          <h2 className="mb-3 text-xs font-semibold uppercase tracking-wider text-ink-tertiary">
            Sub-settings on this recipe
          </h2>
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              onClick={() => setVariantId('base')}
              className={`rounded-full px-3.5 py-1.5 text-sm font-medium transition ${
                variantId === 'base'
                  ? 'bg-accent text-white'
                  : 'border border-border text-ink-secondary'
              }`}
            >
              Overview
            </button>
            {preset.subVariants.map((v) => (
              <button
                key={v.id}
                type="button"
                onClick={() => setVariantId(v.id)}
                className={`rounded-full px-3.5 py-1.5 text-sm font-medium transition ${
                  variantId === v.id
                    ? 'bg-accent text-white'
                    : 'border border-border text-ink-secondary'
                }`}
              >
                {v.label}
              </button>
            ))}
          </div>
          {variantId !== 'base' ? (
            <p className="mt-3 text-sm text-ink-secondary">
              {preset.subVariants.find((v) => v.id === variantId)?.description}
            </p>
          ) : null}
        </section>
      ) : null}

      <div className="mt-8">
        <CameraDials
          dials={activeDials}
          label={
            variantId === 'base'
              ? 'Recommended dials'
              : `${preset.subVariants?.find((v) => v.id === variantId)?.label ?? ''} dials`
          }
        />
      </div>

      <section className="mt-8">
        <h2 className="mb-3 flex items-center gap-2 font-display text-xl text-ink">
          <ListOrdered className="h-5 w-5 text-accent-soft" />
          Steps
        </h2>
        <ol className="space-y-3">
          {preset.steps.map((step, i) => (
            <li
              key={i}
              className="flex gap-3 rounded-xl border border-border bg-surface p-4"
            >
              <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-accent-muted font-mono text-sm font-semibold text-accent">
                {i + 1}
              </span>
              <p className="text-sm leading-relaxed text-ink">{step}</p>
            </li>
          ))}
        </ol>
      </section>

      <section className="mt-8 rounded-2xl border border-tip/25 bg-tip-bg p-5">
        <h2 className="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wider text-tip">
          <Lightbulb className="h-3.5 w-3.5" />
          Mode / aperture / shutter tips
        </h2>
        <ul className="space-y-2">
          {(activeVariantTips ?? preset.tips).map((tip) => (
            <li key={tip} className="flex gap-2 text-sm text-ink-secondary">
              <span className="mt-2 h-1 w-1 shrink-0 rounded-full bg-tip" />
              {tip}
            </li>
          ))}
        </ul>
        <p className="mt-4 text-xs text-ink-tertiary">
          Default mode: {MODE_LABELS[preset.dials.mode]}
        </p>
      </section>

      {preset.phoneTip ? (
        <section className="mt-4 flex gap-3 rounded-2xl border border-border bg-surface p-4">
          <Smartphone className="mt-0.5 h-5 w-5 shrink-0 text-ink-secondary" />
          <div>
            <h3 className="text-xs font-semibold uppercase tracking-wider text-ink-tertiary">
              Phone tip
            </h3>
            <p className="mt-1 text-sm leading-relaxed text-ink-secondary">
              {preset.phoneTip}
            </p>
          </div>
        </section>
      ) : null}

      {preset.advancedTip ? (
        <section className="mt-4 rounded-2xl border border-border bg-surface p-4">
          <h3 className="text-xs font-semibold uppercase tracking-wider text-ink-tertiary">
            Advanced
          </h3>
          <p className="mt-1 text-sm leading-relaxed text-ink-secondary">
            {preset.advancedTip}
          </p>
        </section>
      ) : null}

      <section className="mt-8">
        <h2 className="mb-3 text-xs font-semibold uppercase tracking-wider text-ink-tertiary">
          Equipment checklist
        </h2>
        <ul className="grid gap-2 sm:grid-cols-2">
          {preset.equipmentChecklist.map((item) => (
            <li
              key={item}
              className="rounded-xl bg-surface px-3 py-2.5 text-sm text-ink-secondary ring-1 ring-border"
            >
              {item}
            </li>
          ))}
        </ul>
      </section>

      <div className="mt-8">
        <ChecklistMode
          presetId={preset.id}
          title="Shoot mode"
          steps={preset.steps}
          equipment={preset.equipmentChecklist}
        />
      </div>
    </div>
  )
}
