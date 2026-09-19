import { CheckSquare, RotateCcw } from 'lucide-react'
import { useEffect, useState } from 'react'

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
    localStorage.setItem(storageKey, JSON.stringify(checked))
  }, [checked, storageKey])

  const toggle = (key: string) => {
    setChecked((prev) => ({ ...prev, [key]: !prev[key] }))
  }

  const reset = () => setChecked({})

  const items = [
    ...equipment.map((label, i) => ({ key: `eq-${i}`, group: 'Gear', label })),
    ...steps.map((label, i) => ({ key: `step-${i}`, group: 'Steps', label: `${i + 1}. ${label}` })),
  ]

  const done = items.filter((i) => checked[i.key]).length

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
          <li key={item.key} className="checklist-item">
            <label className="flex cursor-pointer gap-3 rounded-xl bg-zinc-950/50 p-3 ring-1 ring-zinc-800/80 hover:ring-zinc-700">
              <input
                type="checkbox"
                checked={!!checked[item.key]}
                onChange={() => toggle(item.key)}
                className="mt-0.5 h-4 w-4 shrink-0 rounded border-zinc-600 bg-zinc-900 text-rose-500 focus:ring-rose-500/40"
              />
              <span>
                <span className="mb-0.5 block text-[10px] font-semibold uppercase tracking-wider text-zinc-600">
                  {item.group}
                </span>
                <span className="checklist-label text-sm leading-relaxed text-zinc-300">
                  {item.label}
                </span>
              </span>
            </label>
          </li>
        ))}
      </ul>
    </section>
  )
}
