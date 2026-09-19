import { CheckSquare, Lock, RotateCcw, Sparkles } from 'lucide-react'
import { useEffect, useState } from 'react'
import { useSubscription } from '../hooks/useSubscription'

interface ChecklistModeProps {
  presetId: string
  title: string
  steps: string[]
  equipment: string[]
}

export function ChecklistMode({
  presetId,
  title,
  steps,
  equipment,
}: ChecklistModeProps) {
  const storageKey = `photo-recipes:checklist:${presetId}`
  const [checked, setChecked] = useState<Record<string, boolean>>({})
  const { status, openPricing } = useSubscription()
  const pro = Boolean(status?.pro)

  useEffect(() => {
    try {
      const raw = localStorage.getItem(storageKey)
      if (raw) setChecked(JSON.parse(raw) as Record<string, boolean>)
      else setChecked({})
    } catch {
      setChecked({})
    }
  }, [storageKey])

  useEffect(() => {
    if (!pro) return
    localStorage.setItem(storageKey, JSON.stringify(checked))
  }, [checked, storageKey, pro])

  const toggle = (key: string) => {
    if (!pro) return
    setChecked((prev) => ({ ...prev, [key]: !prev[key] }))
  }

  const reset = () => setChecked({})

  const items = [
    ...equipment.map((label, i) => ({ key: `eq-${i}`, group: 'Gear', label })),
    ...steps.map((label, i) => ({
      key: `step-${i}`,
      group: 'Steps',
      label: `${i + 1}. ${label}`,
    })),
  ]

  const done = items.filter((i) => checked[i.key]).length
  const first = items[0]
  const rest = items.slice(1)

  if (!pro) {
    return (
      <section className="overflow-hidden rounded-2xl border border-border bg-surface">
        <div className="p-5 pb-0">
          <div className="mb-1 flex items-center gap-2 text-accent-soft">
            <CheckSquare className="h-4 w-4" />
            <span className="text-xs font-semibold uppercase tracking-wider">
              Field checklist
            </span>
          </div>
          <h3 className="font-display text-lg text-ink">{title}</h3>

          {first ? (
            <ul className="mt-4 space-y-2">
              <li className="rounded-xl bg-bg-elevated px-3 py-2.5 text-sm text-ink-secondary ring-1 ring-border">
                {first.label}
              </li>
            </ul>
          ) : null}

          {rest.length > 0 ? (
            <div className="relative mt-2 soft-gate-mask">
              <ul className="pointer-events-none select-none space-y-2 pb-8">
                {rest.slice(0, 5).map((item) => (
                  <li
                    key={item.key}
                    className="rounded-xl bg-bg-elevated/80 px-3 py-2.5 text-sm text-ink-tertiary ring-1 ring-border"
                  >
                    {item.label}
                  </li>
                ))}
              </ul>
            </div>
          ) : null}
        </div>

        <div className="flex flex-wrap items-center gap-3 border-t border-border bg-bg-elevated px-4 py-3 sm:px-5">
          <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-accent-muted ring-1 ring-accent/25">
            <Lock className="h-4 w-4 text-accent-soft" />
          </span>
          <p className="min-w-0 flex-1 text-sm text-ink-secondary">
            Interactive gear + step checklists with Pro
          </p>
          <button
            type="button"
            onClick={openPricing}
            className="inline-flex shrink-0 items-center gap-1.5 rounded-xl bg-accent px-3.5 py-2 text-sm font-semibold text-white hover:bg-accent-soft"
          >
            <Sparkles className="h-4 w-4" />
            Upgrade · 7-day trial
          </button>
        </div>
      </section>
    )
  }

  return (
    <section className="rounded-2xl border border-border bg-surface p-5">
      <div className="mb-4 flex items-start justify-between gap-3">
        <div>
          <div className="mb-1 flex items-center gap-2 text-accent-soft">
            <CheckSquare className="h-4 w-4" />
            <span className="text-xs font-semibold uppercase tracking-wider">
              Field checklist
            </span>
          </div>
          <h3 className="font-display text-lg text-ink">{title}</h3>
          <p className="mt-1 text-xs text-ink-tertiary">
            {done}/{items.length} complete · saved on this device
          </p>
        </div>
        <button
          type="button"
          onClick={reset}
          className="inline-flex items-center gap-1.5 rounded-lg bg-surface-2 px-2.5 py-1.5 text-xs text-ink-secondary ring-1 ring-border hover:text-ink"
        >
          <RotateCcw className="h-3.5 w-3.5" />
          Reset
        </button>
      </div>

      <div className="mb-3 h-1.5 overflow-hidden rounded-full bg-surface-2">
        <div
          className="h-full rounded-full bg-accent transition-all duration-300"
          style={{ width: `${items.length ? (done / items.length) * 100 : 0}%` }}
        />
      </div>

      <ul className="space-y-2">
        {items.map((item) => (
          <li key={item.key} className="checklist-item">
            <label className="flex cursor-pointer items-start gap-3 rounded-xl bg-bg-elevated/60 px-3 py-2.5 ring-1 ring-border transition hover:ring-border-strong">
              <input
                type="checkbox"
                checked={Boolean(checked[item.key])}
                onChange={() => toggle(item.key)}
                className="mt-0.5 h-4 w-4 rounded border-border-strong bg-surface text-accent focus:ring-accent/40"
              />
              <span
                className={`checklist-label text-sm leading-snug ${
                  checked[item.key] ? 'text-ink-tertiary' : 'text-ink'
                }`}
              >
                {item.label}
              </span>
            </label>
          </li>
        ))}
      </ul>
    </section>
  )
}
