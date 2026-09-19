/** Static before→after dial chips — marketing conversion beat (no live camera). */

const DIALS = [
  { label: 'Shutter', before: '1/500', after: '1/60' },
  { label: 'ISO', before: '100', after: '400' },
  { label: 'EV', before: '0', after: '−0.3' },
  { label: 'WB', before: 'Auto', after: 'Daylight' },
  { label: 'Focus', before: 'Cont.', after: 'Locked' },
] as const

export function LandingDialProof() {
  return (
    <div className="grid items-stretch gap-6 lg:grid-cols-2 lg:gap-10">
      {/* Faux viewfinder */}
      <div className="relative overflow-hidden rounded-2xl border border-border bg-surface ring-1 ring-border">
        <div className="absolute left-3 top-3 z-10 inline-flex items-center gap-1.5 rounded-full bg-bg/85 px-2.5 py-1 text-[11px] font-medium text-ink-secondary ring-1 ring-border backdrop-blur-sm">
          <span className="h-1.5 w-1.5 rounded-full bg-success" aria-hidden />
          Ready to capture
        </div>
        <img
          src="/phones-duo-iphone-android-camera.png"
          alt="Auto Optimize before and after — shutter, ISO, EV, WB, and focus dials on the live camera."
          width={900}
          height={680}
          className="h-full min-h-[220px] w-full object-cover object-center sm:min-h-[280px]"
          loading="lazy"
          decoding="async"
        />
        <div className="pointer-events-none absolute inset-x-0 bottom-0 bg-gradient-to-t from-bg/80 to-transparent px-4 pb-4 pt-10">
          <p className="text-xs text-ink-tertiary">Not a filter. Real capture settings.</p>
        </div>
      </div>

      {/* Chip stack */}
      <div className="flex flex-col justify-center">
        <ul className="space-y-2.5" aria-label="Before and after Auto Optimize settings">
          {DIALS.map((d) => (
            <li
              key={d.label}
              className="flex items-center gap-3 rounded-xl border border-border bg-surface px-3.5 py-2.5 sm:px-4"
            >
              <span className="w-16 shrink-0 text-xs font-semibold uppercase tracking-wide text-accent-soft sm:w-20">
                {d.label}
              </span>
              <span className="diff-before font-mono text-sm tabular-nums">{d.before}</span>
              <span className="text-ink-tertiary" aria-hidden>
                →
              </span>
              <span className="sr-only">to</span>
              <span className="diff-after font-mono text-sm tabular-nums">{d.after}</span>
            </li>
          ))}
        </ul>
        <p className="mt-3 rounded-xl border border-dashed border-border bg-bg-elevated px-3.5 py-2.5 text-xs text-ink-tertiary">
          Coach-only · aperture f/8 · ND · tripod
        </p>
        <p className="mt-3 text-xs text-ink-tertiary">Not a filter. Real capture settings.</p>
      </div>
    </div>
  )
}
