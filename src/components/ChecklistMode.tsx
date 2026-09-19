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
    ...steps.map((label, i) => ({ key: `step-${i}`, group: 'Steps', label: `${i + 1}. ${label}` })),
  ]

  const done = items.filter((i) => checked[i.key]).length

  if (!pro) {
    return (
      <section className="relative overflow-hidden rounded-2xl border border-zinc-800 bg-zinc-900/40 p-5">
        <div className="pointer-events-none select-none blur-[2px] opacity-50">
          <div className="mb-3 flex items-center gap-2 text-rose-400">
            <CheckSquare className="h-4 w-4" />
            <span className="text-xs font-semibold uppercase tracking-wider">
              Field checklist
            </span>
          </div>
          <h3 className="font-display text-lg text-zinc-100">{title}</h3>
          <ul className="mt-4 space-y-2">
            {items.slice(0, 4).map((item) => (
              <li
                key={item.key}
                className="rounded-xl bg-zinc-950/50 px-3 py-2.5 text-sm text-zinc-400 ring-1 ring-zinc-800"
              >
                {item.label}
              </li>
            ))}
          </ul>
        </div>
        <div className="absolute inset-0 flex items-center justify-center bg-zinc-950/70 p-6 backdrop-blur-[1px]">
          <div className="max-w-sm text-center">
            <span className="mx-auto mb-3 flex h-10 w-10 items-center justify-center rounded-xl bg-rose-500/20 ring-1 ring-rose-500/35">
              <Lock className="h-5 w-5 text-rose-300" />
            </span>
            <p className="font-display text-lg text-zinc-50">Field checklists are Pro</p>
            <p className="mt-1.5 text-sm text-zinc-400">
              Soft gate — you can still read steps above. Unlock interactive gear + step
              checklists with Photo Recipes Pro.
            </p>
            <button
              type="button"
              onClick={openPricing}
              className="mt-4 inline-flex items-center gap-1.5 rounded-xl bg-rose-500 px-4 py-2 text-sm font-semibold text-white hover:bg-rose-400"
            >
              <Sparkles className="h-4 w-4" />
              Upgrade · 7-day trial
            </button>
          </div>
        </div>
      </section>
    )
  }

  return (
    <section className="rounded-2xl border border-zinc-800 bg-zinc-900/40 p-5">
      <div className="mb-4 flex items-start justify-between gap-3">
        <div>
          <div className="mb-1 flex items-center gap-2 text-rose-400">
            <CheckSquare className="h-4 w-4" />
            <span className="text-xs font-semibold uppercase tracking-wider">
              Field checklist
            </span>
          </div>
          <h3 className="font-display text-lg text-zinc-100">{title}</h3>
          <p className="mt-1 text-xs text-zinc-500">
            {done}/{items.length} complete · saved on this device
          </p>
        </div>
        <button
          type="button"
          onClick={reset}
          className="inline-flex items-center gap-1.5 rounded-lg bg-zinc-800 px-2.5 py-1.5 text-xs text-zinc-400 ring-1 ring-zinc-700 hover:text-zinc-200"
        >
          <RotateCcw className="h-3.5 w-3.5" />
          Reset
        </button>
      </div>

      <div className="mb-3 h-1.5 overflow-hidden rounded-full bg-zinc-800">
        <div
          className="h-full rounded-full bg-rose-500 transition-all duration-300"
          style={{ width: `${items.length ? (done / items.length) * 100 : 0}%` }}
        />
      </div>

      <ul className="space-y-2">
        {items.map((item) => (
          <li key={item.key}>
            <label className="flex cursor-pointer items-start gap-3 rounded-xl bg-zinc-950/40 px-3 py-2.5 ring-1 ring-zinc-800/80 transition hover:ring-zinc-700">
              <input
                type="checkbox"
                checked={Boolean(checked[item.key])}
                onChange={() => toggle(item.key)}
                className="mt-0.5 h-4 w-4 rounded border-zinc-600 bg-zinc-900 text-rose-500 focus:ring-rose-500/40"
              />
              <span
                className={`text-sm leading-snug ${
                  checked[item.key] ? 'text-zinc-500 line-through' : 'text-zinc-300'
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
