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
import type { AiRecommendState } from '../components/AskGrok'
import { CameraDials } from '../components/CameraDials'
import { ChecklistMode } from '../components/ChecklistMode'
import { GearIcons } from '../components/GearIcons'
import { presets } from '../data/presets'
import { useFavorites } from '../hooks/useFavorites'
import { GEAR_LABELS, MODE_LABELS, TAG_LABELS } from '../types'

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
          className="inline-flex items-center gap-1.5 text-sm text-zinc-400 transition hover:text-zinc-100"
        >
          <ArrowLeft className="h-4 w-4" />
          Library
        </Link>
        <button
          type="button"
          onClick={() => toggleFavorite(preset.id)}
          className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-sm ring-1 transition ${
            favorite
              ? 'bg-rose-500/15 text-rose-300 ring-rose-500/30'
              : 'bg-zinc-900 text-zinc-400 ring-zinc-800 hover:text-zinc-200'
          }`}
        >
          <Heart className={`h-4 w-4 ${favorite ? 'fill-rose-400' : ''}`} />
          {favorite ? 'Favorited' : 'Favorite'}
        </button>
      </div>

      <div className="mb-2 flex flex-wrap gap-1.5">
        {preset.tags.map((t) => (
          <span
            key={t}
            className="rounded-md bg-rose-500/10 px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wide text-rose-300"
          >
            {TAG_LABELS[t]}
          </span>
        ))}
        <span className="rounded-md bg-zinc-800 px-2 py-0.5 text-[11px] text-zinc-500">
          Book p.{preset.page}
        </span>
      </div>

      <h1 className="font-display text-3xl leading-tight text-zinc-50 sm:text-4xl">
        {preset.title}
      </h1>
      <p className="mt-3 text-base leading-relaxed text-zinc-400">{preset.blurb}</p>

      {ai ? (
        <section className="mt-6 rounded-2xl border border-rose-500/30 bg-rose-500/10 p-4 ring-1 ring-rose-500/20">
          <h2 className="mb-2 flex items-center gap-2 text-xs font-semibold uppercase tracking-wider text-rose-300">
            <Sparkles className="h-3.5 w-3.5" />
            Grok picked this recipe
          </h2>
          <p className="text-sm leading-relaxed text-zinc-200">{ai.reason}</p>
          {ai.tips.length > 0 ? (
            <ul className="mt-3 space-y-1.5">
              {ai.tips.map((tip) => (
                <li key={tip} className="flex gap-2 text-sm text-zinc-300">
                  <span className="mt-2 h-1 w-1 shrink-0 rounded-full bg-rose-400" />
                  {tip}
                </li>
              ))}
            </ul>
          ) : null}
        </section>
      ) : null}

      <div className="mt-6 flex flex-wrap items-center gap-4 rounded-2xl border border-zinc-800 bg-zinc-900/40 p-4">
        <GearIcons gear={preset.gear} size="md" />
        <div className="text-sm text-zinc-400">
          {preset.gear.map((g) => GEAR_LABELS[g]).join(' · ')}
        </div>
      </div>

      {/* When to use */}
      <section className="mt-8">
        <h2 className="mb-2 flex items-center gap-2 text-xs font-semibold uppercase tracking-wider text-rose-400">
          <Sparkles className="h-3.5 w-3.5" />
          When to use
        </h2>
        <p className="text-sm leading-relaxed text-zinc-300">{preset.whenToUse}</p>
      </section>

      {/* Sub-variants */}
      {preset.subVariants && preset.subVariants.length > 0 ? (
        <section className="mt-8">
          <h2 className="mb-3 text-xs font-semibold uppercase tracking-wider text-zinc-500">
            Sub-settings on this recipe
          </h2>
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              onClick={() => setVariantId('base')}
              className={`rounded-full px-3.5 py-1.5 text-sm font-medium transition ${
                variantId === 'base'
                  ? 'bg-rose-500 text-white'
                  : 'bg-zinc-900 text-zinc-400 ring-1 ring-zinc-800'
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
                    ? 'bg-rose-500 text-white'
                    : 'bg-zinc-900 text-zinc-400 ring-1 ring-zinc-800'
                }`}
              >
                {v.label}
              </button>
            ))}
          </div>
          {variantId !== 'base' ? (
            <p className="mt-3 text-sm text-zinc-400">
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

      {/* Steps */}
      <section className="mt-8">
        <h2 className="mb-3 flex items-center gap-2 font-display text-xl text-zinc-100">
          <ListOrdered className="h-5 w-5 text-rose-400" />
          Steps
        </h2>
        <ol className="space-y-3">
          {preset.steps.map((step, i) => (
            <li
              key={i}
              className="flex gap-3 rounded-xl border border-zinc-800/80 bg-zinc-900/30 p-4"
            >
              <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-rose-500/15 font-mono text-sm font-semibold text-rose-300">
                {i + 1}
              </span>
              <p className="text-sm leading-relaxed text-zinc-300">{step}</p>
            </li>
          ))}
        </ol>
      </section>

      {/* Tips */}
      <section className="mt-8 rounded-2xl border border-zinc-800 bg-zinc-900/40 p-5">
        <h2 className="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wider text-amber-400/90">
          <Lightbulb className="h-3.5 w-3.5" />
          Mode / aperture / shutter tips
        </h2>
        <ul className="space-y-2">
          {(activeVariantTips ?? preset.tips).map((tip) => (
            <li key={tip} className="flex gap-2 text-sm text-zinc-300">
              <span className="mt-2 h-1 w-1 shrink-0 rounded-full bg-amber-400/80" />
              {tip}
            </li>
          ))}
        </ul>
        <p className="mt-4 text-xs text-zinc-600">
          Default mode: {MODE_LABELS[preset.dials.mode]}
        </p>
      </section>

      {preset.phoneTip ? (
        <section className="mt-4 flex gap-3 rounded-2xl border border-sky-500/20 bg-sky-500/5 p-4">
          <Smartphone className="mt-0.5 h-5 w-5 shrink-0 text-sky-400" />
          <div>
            <h3 className="text-xs font-semibold uppercase tracking-wider text-sky-400">
              Phone tip
            </h3>
            <p className="mt-1 text-sm leading-relaxed text-zinc-300">{preset.phoneTip}</p>
          </div>
        </section>
      ) : null}

      {preset.advancedTip ? (
        <section className="mt-4 rounded-2xl border border-violet-500/20 bg-violet-500/5 p-4">
          <h3 className="text-xs font-semibold uppercase tracking-wider text-violet-300">
            Advanced
          </h3>
          <p className="mt-1 text-sm leading-relaxed text-zinc-300">{preset.advancedTip}</p>
        </section>
      ) : null}

      {/* Equipment checklist summary */}
      <section className="mt-8">
        <h2 className="mb-3 text-xs font-semibold uppercase tracking-wider text-zinc-500">
          Equipment checklist
        </h2>
        <ul className="grid gap-2 sm:grid-cols-2">
          {preset.equipmentChecklist.map((item) => (
            <li
              key={item}
              className="rounded-xl bg-zinc-900/50 px-3 py-2.5 text-sm text-zinc-300 ring-1 ring-zinc-800"
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
