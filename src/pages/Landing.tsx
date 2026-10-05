import { Camera, Check, ChevronDown, X } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { CameraCta } from '../components/CameraCta'
import { LandingDialProof } from '../components/LandingDialProof'
import { LandingEmailCapture } from '../components/LandingEmailCapture'
import { Seo } from '../components/Seo'
import { useSubscription } from '../hooks/useSubscription'
import { DEFAULT_DESCRIPTION, DEFAULT_TITLE, SITE_URL, APP_STORE_URL } from '../lib/site'
import { track } from '../lib/analytics'

const TRUST_LINE =
  'Free Peek · 5 Auto Optimize/day · Pro $7.99/mo or $59.99/yr · 7-day trial'

const HOW_STEPS = [
  {
    title: 'Sense',
    body: 'Light, motion, subject — from the viewfinder note',
    status: 'Reading light…',
  },
  {
    title: 'Reason',
    body: 'Matches a field recipe; clamps to what the phone can set',
    status: 'Matching a recipe…',
  },
  {
    title: 'Apply',
    body: 'Writes shutter / ISO / EV / WB / focus',
    status: 'Applying shutter & ISO…',
  },
  {
    title: 'Verify',
    body: 'Soft pan ← → if you should reframe',
    status: 'Checking exposure…',
  },
  {
    title: 'Capture',
    body: 'You still press shutter',
    status: 'Ready to capture',
  },
] as const

const RECIPE_CARDS = [
  {
    title: 'Panning',
    body: 'Slow shutter + tracking cues — subject sharp, world streaks.',
  },
  {
    title: 'Depth of field',
    body: 'Focus strategy for front-to-back sharpness.',
  },
  {
    title: 'HDR / high contrast',
    body: 'Protect highlights; disciplined exposure targets.',
  },
  {
    title: 'Motion control',
    body: 'Freeze or blur on purpose — ISO and shutter paired.',
  },
] as const

const SETTABLE = [
  'Shutter / exposure duration',
  'ISO',
  'EV bias',
  'White balance',
  'Focus lock / POI',
  'Zoom / lens when available',
] as const

const COACH_ONLY = ['Aperture', 'ND filter', 'Tripod / support'] as const

const FAQ_ITEMS = [
  {
    q: 'Is this an AI filter app?',
    a: 'No — not a filter app. The iOS app writes dials via Auto Optimize; this site’s Field Coach recommends dials from your viewfinder or photo. Technique before the shutter, not filters after.',
  },
  {
    q: 'What does Auto Optimize change?',
    a: 'On iOS: shutter / exposure duration, ISO, EV, white balance, focus (zoom when available). Aperture, ND, and tripod stay coach-only. On this website, Field Coach only recommends dials — it does not apply them in the browser.',
  },
  {
    q: 'What’s free?',
    a: 'Free Peek: browse recipes · 5 Auto Optimize/day until Pro.',
  },
  {
    q: 'What’s in Pro?',
    a: 'Unlimited Auto Optimize, manual dials, Teach, checklists. $59.99/yr or $7.99/mo · 7-day trial.',
  },
  {
    q: 'iPhone and Android?',
    a: 'Designed for both; duo art shows Auto Optimize + dials.',
  },
  {
    q: 'Can I override the agent?',
    a: 'Yes — manual dials (Pro). Teach explains why.',
  },
  {
    q: 'Do I need an account?',
    a: 'Browse Free Peek without buying; Pro via Stripe (web) / IAP (iOS).',
  },
  {
    q: 'What are field notes?',
    a: 'Occasional craft emails — not a daily blast. Join via Get field notes.',
  },
  {
    q: 'Voice?',
    a: 'Optional dictate for a scene note on web Field Coach (recommend path). On iOS, voice can feed the same Auto Optimize apply path.',
  },
  {
    q: 'Publisher affiliation?',
    a: 'Educational presets inspired by field recipes — not affiliated with the publisher.',
  },
] as const

const PROOF_CHIPS = ['Shutter', 'ISO', 'EV', 'WB', 'Focus'] as const

function FaqItem({ q, a }: { q: string; a: string }) {
  return (
    <details className="group border-b border-border py-4">
      <summary className="flex cursor-pointer list-none items-start justify-between gap-4 text-left text-base font-medium text-ink marker:content-none [&::-webkit-details-marker]:hidden">
        <span>{q}</span>
        <ChevronDown className="mt-1 h-4 w-4 shrink-0 text-ink-tertiary transition group-open:rotate-180" />
      </summary>
      <p className="mt-3 max-w-3xl text-sm leading-relaxed text-ink-secondary">{a}</p>
    </details>
  )
}

export function Landing() {
  const { openPricing } = useSubscription()

  useEffect(() => {
    track('landing_view', { source: 'marketing' })
  }, [])
  const [navOpen, setNavOpen] = useState(false)

  const jsonLd = useMemo(
    () => [
      {
        '@context': 'https://schema.org',
        '@type': 'SoftwareApplication',
        name: 'ProTune AI Camera',
        applicationCategory: 'PhotographyApplication',
        operatingSystem: 'iOS, Android, Web',
        description: DEFAULT_DESCRIPTION,
        url: SITE_URL,
        offers: [
          {
            '@type': 'Offer',
            name: 'Free Peek',
            price: '0',
            priceCurrency: 'USD',
          },
          {
            '@type': 'Offer',
            name: 'Pro yearly',
            price: '59.99',
            priceCurrency: 'USD',
          },
        ],
      },
      {
        '@context': 'https://schema.org',
        '@type': 'FAQPage',
        mainEntity: FAQ_ITEMS.map((item) => ({
          '@type': 'Question',
          name: item.q,
          acceptedAnswer: {
            '@type': 'Answer',
            text: item.a,
          },
        })),
      },
    ],
    [],
  )

  function startTrial() {
    openPricing()
  }

  function closeNav() {
    setNavOpen(false)
  }

  return (
    <div className="min-h-dvh bg-bg text-ink pb-[calc(4.5rem+env(safe-area-inset-bottom))] md:pb-0">
      <Seo title={DEFAULT_TITLE} description={DEFAULT_DESCRIPTION} path="/" jsonLd={jsonLd} />

      {/* Nav */}
      <header className="sticky top-0 z-30 border-b border-border/60 bg-bg/90 backdrop-blur-md">
        <div className="mx-auto flex max-w-[1120px] items-center justify-between gap-4 px-4 py-3 sm:px-6">
          <Link to="/" className="group flex items-center gap-2.5">
            <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-accent-muted ring-1 ring-accent/30">
              <Camera className="h-4 w-4 text-accent-soft" strokeWidth={1.75} />
            </span>
            <span className="font-display text-lg tracking-tight text-ink">ProTune AI Camera</span>
          </Link>

          <nav className="hidden items-center gap-6 text-sm text-ink-secondary md:flex" aria-label="Primary">
            <a href="#how" className="hover:text-ink">
              How
            </a>
            <a href="#recipes" className="hover:text-ink">
              Recipes
            </a>
            <a href="#pricing" className="hover:text-ink">
              Pricing
            </a>
            <a href="#notes" className="hover:text-ink">
              Notes
            </a>
          </nav>

          <div className="flex items-center gap-2">
            <CameraCta
              label="Open Camera"
              className="!min-h-9 !px-3.5 !py-1.5 !text-sm !shadow-none"
            />
            <button
              type="button"
              onClick={startTrial}
              className="hidden min-h-9 items-center rounded-full px-3 py-1.5 text-sm font-medium text-ink-secondary ring-1 ring-border hover:bg-surface sm:inline-flex"
            >
              Free trial
            </button>
            <button
              type="button"
              className="inline-flex h-9 w-9 items-center justify-center rounded-lg text-ink-secondary ring-1 ring-border md:hidden"
              aria-expanded={navOpen}
              aria-label={navOpen ? 'Close menu' : 'Open menu'}
              onClick={() => setNavOpen((v) => !v)}
            >
              {navOpen ? (
                <X className="h-4 w-4" />
              ) : (
                <span className="flex flex-col gap-1" aria-hidden>
                  <span className="block h-0.5 w-4 bg-ink-secondary" />
                  <span className="block h-0.5 w-4 bg-ink-secondary" />
                  <span className="block h-0.5 w-4 bg-ink-secondary" />
                </span>
              )}
            </button>
          </div>
        </div>

        {navOpen ? (
          <div className="border-t border-border px-4 py-3 md:hidden">
            <div className="flex flex-col gap-3 text-sm text-ink-secondary">
              <CameraCta label="Open Camera" fullWidth onClick={closeNav} />
              <Link
                to="/app/library"
                onClick={closeNav}
                className="inline-flex min-h-11 items-center justify-center rounded-full px-3 py-1.5 font-medium text-ink ring-1 ring-border"
              >
                Library
              </Link>
              <a href="#pricing" onClick={closeNav} className="py-1 hover:text-ink">
                Pricing
              </a>
              <a href="#notes" onClick={closeNav} className="py-1 hover:text-ink">
                Field notes
              </a>
            </div>
          </div>
        ) : null}
      </header>

      <main>
        {/* Hero */}
        <section className="landing-hero-glow">
          <div className="mx-auto grid max-w-[1120px] items-center gap-10 px-4 pb-14 pt-10 sm:px-6 sm:pt-14 lg:grid-cols-[0.42fr_0.58fr] lg:gap-12 lg:pb-20">
            <div className="text-left">
              <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-ink-tertiary">
                Field technique · iOS dials · web coach
              </p>
              <h1 className="font-display mt-3 max-w-[16ch] text-[clamp(2.15rem,4.2vw,3.25rem)] leading-[1.12] tracking-tight text-ink">
                Point at the shot — iOS Auto Optimize writes dials; web Field Coach recommends them
              </h1>
              <p className="mt-4 max-w-md text-base leading-relaxed text-ink-secondary sm:text-lg">
                On iPhone, Auto Optimize writes shutter, ISO, EV, white balance, and focus on the live
                camera. On this site, Field Coach reads your viewfinder or photo and recommends dials —
                it does not apply them in the browser. Not a filter app.
              </p>
              <p className="mt-2 text-sm italic text-ink-tertiary">Set the shot. Then take it.</p>
              <div className="mt-7 flex flex-col gap-3 min-[400px]:flex-row min-[400px]:flex-wrap min-[400px]:items-center">
                <CameraCta size="lg" fullWidth className="min-[400px]:!w-auto" />
                <a
                  href={APP_STORE_URL}
                  onClick={() => track('landing_cta_appstore', { source: 'hero' })}
                  className="inline-flex min-h-11 items-center justify-center min-[400px]:w-auto"
                  aria-label="Download on the App Store"
                >
                  {/* Official Apple badge artwork, unmodified per App Store marketing guidelines (min 40px onscreen). */}
                  <img
                    src="/download-on-the-app-store.svg"
                    alt="Download on the App Store"
                    width={120}
                    height={40}
                    className="h-10 w-auto"
                    loading="lazy"
                  />
                </a>
                <a
                  href="#notes"
                  onClick={() => track('landing_cta_waitlist', { source: 'hero' })}
                  className="inline-flex min-h-11 w-full items-center justify-center rounded-full px-5 py-2.5 text-sm font-medium text-ink-secondary hover:text-ink min-[400px]:w-auto"
                >
                  Join waitlist
                </a>
              </div>
              <p className="mt-3 text-xs text-ink-tertiary">{TRUST_LINE}</p>
            </div>

            <div className="relative mx-auto w-full max-w-xl lg:max-w-none">
              <img
                src="/phones-duo-iphone-android-camera.png"
                alt="ProTune AI Camera on iPhone and Android — Auto Optimize camera with recipe dials."
                width={1200}
                height={900}
                className="h-auto w-full rounded-xl object-contain shadow-[0_24px_60px_-24px_rgba(0,0,0,0.65)] ring-1 ring-border"
                fetchPriority="high"
                decoding="async"
              />
            </div>
          </div>
        </section>

        {/* Proof strip */}
        <section className="border-y border-border/50 py-5" aria-label="Settable dials">
          <div className="mx-auto flex max-w-[1120px] flex-wrap items-center justify-start gap-2 px-4 sm:justify-center sm:px-6">
            {PROOF_CHIPS.map((chip, i) => (
              <span
                key={chip}
                className="inline-flex items-center rounded-full border border-border bg-surface px-3 py-1 text-xs text-ink-secondary sm:text-sm"
              >
                <span className={i === 0 ? 'font-semibold text-accent-soft' : ''}>{chip}</span>
              </span>
            ))}
            <span className="hidden text-ink-tertiary sm:inline" aria-hidden>
              ·
            </span>
            <span className="text-xs text-ink-tertiary sm:text-sm">zoom when available</span>
            <span className="basis-full text-left text-xs text-ink-tertiary sm:basis-auto sm:ml-2">
              Coach-only: aperture · ND · tripod
            </span>
          </div>
        </section>

        {/* How it works */}
        <section id="how" className="scroll-mt-20 py-14 sm:py-20 lg:py-24">
          <div className="mx-auto max-w-[1120px] px-4 sm:px-6">
            <h2 className="font-display text-center text-3xl text-ink sm:text-4xl">
              Sense. Reason. Apply. Verify. Shoot.
            </h2>
            <p className="mx-auto mt-3 max-w-2xl text-center text-sm text-ink-secondary sm:text-base">
              One loop on the live viewfinder — status you can trust, dials you can override.
            </p>
            <ol className="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
              {HOW_STEPS.map((step) => (
                <li key={step.title} className="rounded-2xl border border-border bg-surface p-5 text-left">
                  <h3 className="font-display text-xl text-ink">{step.title}</h3>
                  <p className="mt-2 text-sm leading-relaxed text-ink-secondary">{step.body}</p>
                  <p className="mt-3 inline-flex rounded-full bg-bg-elevated px-2.5 py-1 font-mono text-[11px] text-ink-tertiary ring-1 ring-border">
                    {step.status}
                  </p>
                </li>
              ))}
            </ol>
          </div>
        </section>

        {/* Dial moment */}
        <section id="dials" className="scroll-mt-20 border-y border-border/50 bg-bg-elevated py-14 sm:py-20 lg:py-24">
          <div className="mx-auto max-w-[1120px] px-4 sm:px-6">
            <h2 className="font-display text-center text-3xl text-ink sm:text-4xl">
              Watch the dials move — then take the shot.
            </h2>
            <p className="mx-auto mt-3 max-w-2xl text-center text-sm text-ink-secondary sm:text-base">
              Before → after chips show exactly what Auto Optimize wrote. Tap through Teach anytime.
            </p>
            <div className="mt-10">
              <LandingDialProof />
            </div>
            <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
              <a
                href="#how"
                className="inline-flex min-h-10 items-center justify-center rounded-full px-4 py-2 text-sm font-semibold text-ink ring-1 ring-border hover:bg-surface"
              >
                See how it works
              </a>
              <button
                type="button"
                onClick={startTrial}
                className="inline-flex min-h-10 items-center justify-center rounded-full bg-accent px-4 py-2 text-sm font-semibold text-white hover:bg-accent-soft"
              >
                Start free trial
              </button>
            </div>
          </div>
        </section>

        {/* Settable vs coach-only */}
        <section className="py-14 sm:py-20 lg:py-24">
          <div className="mx-auto max-w-[1120px] px-4 sm:px-6">
            <h2 className="font-display text-center text-3xl text-ink sm:text-4xl">
              Honest about what the phone can write.
            </h2>
            <div className="mx-auto mt-10 grid max-w-3xl gap-4 sm:grid-cols-2">
              <article className="rounded-2xl border border-border bg-surface p-6 text-left">
                <h3 className="text-sm font-semibold uppercase tracking-[0.08em] text-accent-soft">
                  Agentic — iOS Auto Optimize sets
                </h3>
                <ul className="mt-4 space-y-2.5 text-sm text-ink-secondary">
                  {SETTABLE.map((item) => (
                    <li key={item} className="flex gap-2">
                      <Check className="mt-0.5 h-4 w-4 shrink-0 text-success" />
                      {item}
                    </li>
                  ))}
                </ul>
              </article>
              <article className="rounded-2xl border border-dashed border-border bg-bg-elevated p-6 text-left">
                <h3 className="text-sm font-semibold uppercase tracking-[0.08em] text-ink-tertiary">
                  Coach-only guidance
                </h3>
                <ul className="mt-4 space-y-2.5 text-sm text-ink-secondary">
                  {COACH_ONLY.map((item) => (
                    <li key={item} className="flex gap-2">
                      <span className="mt-0.5 h-4 w-4 shrink-0 text-center text-ink-tertiary" aria-hidden>
                        ·
                      </span>
                      {item}
                    </li>
                  ))}
                </ul>
              </article>
            </div>
          </div>
        </section>

        {/* Recipe teaser */}
        <section id="recipes" className="scroll-mt-20 border-t border-border/50 py-14 sm:py-20 lg:py-24">
          <div className="mx-auto max-w-[1120px] px-4 sm:px-6">
            <h2 className="font-display text-center text-3xl text-ink sm:text-4xl">
              Technique recipes, not LUTs.
            </h2>
            <p className="mx-auto mt-3 max-w-2xl text-center text-sm text-ink-secondary sm:text-base">
              Panning, HDR, depth of field, motion — dials, steps, and teach-why tips.
            </p>
            <div className="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              {RECIPE_CARDS.map((card) => (
                <Link
                  key={card.title}
                  to="/app/library"
                  className="rounded-2xl border border-border bg-surface p-5 text-left transition hover:border-border-strong hover:bg-surface-2"
                >
                  <h3 className="font-display text-xl text-ink">{card.title}</h3>
                  <p className="mt-2 text-sm leading-relaxed text-ink-secondary">{card.body}</p>
                </Link>
              ))}
            </div>
            <div className="mt-8 flex justify-center gap-3">
              <CameraCta />
              <Link
                to="/app/library"
                className="inline-flex min-h-11 items-center justify-center rounded-full px-5 py-2.5 text-sm font-semibold text-ink ring-1 ring-border hover:bg-surface"
              >
                Browse library
              </Link>
            </div>
          </div>
        </section>

        {/* Pricing */}
        <section id="pricing" className="scroll-mt-20 border-t border-border/50 py-14 sm:py-20 lg:py-24">
          <div className="mx-auto max-w-[1120px] px-4 sm:px-6">
            <h2 className="font-display text-center text-3xl text-ink sm:text-4xl">Free Peek vs Pro</h2>
            <div className="mx-auto mt-10 grid max-w-3xl gap-4 sm:grid-cols-2">
              <article className="rounded-2xl border border-border bg-surface p-6 text-left">
                <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-ink-tertiary">
                  Free Peek
                </p>
                <p className="mt-2 font-display text-3xl text-ink">$0</p>
                <ul className="mt-4 space-y-2 text-sm text-ink-secondary">
                  <li className="flex gap-2">
                    <Check className="h-4 w-4 shrink-0 text-success" /> Browse recipe library
                  </li>
                  <li className="flex gap-2">
                    <Check className="h-4 w-4 shrink-0 text-success" /> 5 Auto Optimize / day
                  </li>
                  <li className="flex gap-2">
                    <Check className="h-4 w-4 shrink-0 text-success" /> Teach mode teaser
                  </li>
                </ul>
                <Link
                  to="/app/library"
                  className="mt-6 inline-flex min-h-11 w-full items-center justify-center rounded-full text-sm font-semibold text-ink ring-1 ring-border hover:bg-surface-2"
                >
                  Browse library
                </Link>
              </article>

              <article className="relative rounded-2xl border border-accent/40 bg-surface p-6 text-left ring-1 ring-accent/20">
                <span className="absolute -top-2.5 right-4 rounded-full border border-accent/50 bg-accent-muted px-2.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-accent-soft">
                  Best value
                </span>
                <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-accent-soft">
                  Pro
                </p>
                <p className="mt-2 font-display text-3xl text-ink">
                  $59.99<span className="text-lg text-ink-tertiary">/yr</span>
                </p>
                <p className="mt-1 text-xs text-ink-tertiary">or $7.99/mo</p>
                <ul className="mt-4 space-y-2 text-sm text-ink-secondary">
                  <li className="flex gap-2">
                    <Check className="h-4 w-4 shrink-0 text-success" /> Browse + checklists
                  </li>
                  <li className="flex gap-2">
                    <Check className="h-4 w-4 shrink-0 text-success" /> Unlimited Auto Optimize
                  </li>
                  <li className="flex gap-2">
                    <Check className="h-4 w-4 shrink-0 text-success" /> Full manual dials + Teach
                  </li>
                </ul>
                <button
                  type="button"
                  onClick={startTrial}
                  className="mt-6 inline-flex min-h-11 w-full items-center justify-center rounded-full bg-accent text-sm font-semibold text-white hover:bg-accent-soft"
                >
                  Start 7-day trial
                </button>
                <p className="mt-3 text-center text-[11px] text-ink-tertiary">
                  Cancel anytime · Stripe on web · Apple IAP on iOS
                </p>
              </article>
            </div>
          </div>
        </section>

        {/* Get field notes */}
        <section id="notes" className="scroll-mt-20 border-t border-border/50 py-14 sm:py-20 lg:py-24">
          <div className="mx-auto grid max-w-[1120px] items-center gap-8 px-4 sm:px-6 lg:grid-cols-[0.45fr_0.55fr] lg:gap-12">
            <div className="text-left">
              <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-ink-tertiary">
                Field notes
              </p>
              <h2 className="font-display mt-2 text-3xl text-ink sm:text-4xl">Get field notes</h2>
              <p className="mt-3 max-w-md text-sm leading-relaxed text-ink-secondary sm:text-base">
                Occasional craft notes and launch updates — shutter discipline, not promo blasts.
                Unsubscribe anytime.
              </p>
              <p className="mt-3 text-xs text-ink-tertiary">No spam · No filter tips · Craft only</p>
            </div>
            <LandingEmailCapture />
          </div>
        </section>

        {/* FAQ */}
        <section id="faq" className="scroll-mt-20 border-t border-border/50 py-14 sm:py-20 lg:py-24">
          <div className="mx-auto max-w-[720px] px-4 sm:px-6">
            <h2 className="font-display text-center text-3xl text-ink sm:text-4xl">
              Questions before you head out.
            </h2>
            <div className="mt-8">
              {FAQ_ITEMS.map((item) => (
                <FaqItem key={item.q} q={item.q} a={item.a} />
              ))}
            </div>
          </div>
        </section>

        {/* Final CTA */}
        <section className="py-14 sm:py-20 lg:py-24">
          <div className="mx-auto max-w-[720px] px-4 text-center sm:px-6">
            <h2 className="font-display text-3xl text-ink sm:text-4xl">Go make the frame.</h2>
            <p className="mt-2 text-sm italic text-ink-tertiary">Set the shot. Then take it.</p>
            <div className="mt-7 flex flex-wrap items-center justify-center gap-3">
              <CameraCta size="lg" />
              <button
                type="button"
                onClick={startTrial}
                className="inline-flex min-h-11 items-center justify-center rounded-full px-5 py-2.5 text-sm font-semibold text-ink ring-1 ring-border hover:bg-surface"
              >
                Start free trial
              </button>
            </div>
            <p className="mt-3 text-xs text-ink-tertiary">{TRUST_LINE}</p>
            <a href="#notes" className="mt-5 inline-block text-sm text-ink-tertiary hover:text-ink">
              Get field notes
            </a>
          </div>
        </section>
      </main>

      {/* Sticky mobile camera CTA */}
      <div className="fixed inset-x-0 bottom-0 z-40 border-t border-border/70 bg-bg/95 px-4 pb-[max(0.75rem,env(safe-area-inset-bottom))] pt-3 backdrop-blur-md md:hidden">
        <CameraCta fullWidth size="lg" />
      </div>

      <footer className="border-t border-border py-10">
        <div className="mx-auto flex max-w-[1120px] flex-col gap-6 px-4 sm:flex-row sm:items-start sm:justify-between sm:px-6">
          <div className="text-left">
            <div className="flex items-center gap-2">
              <Camera className="h-4 w-4 text-accent-soft" />
              <span className="font-display text-lg text-ink">ProTune AI Camera</span>
            </div>
            <p className="mt-2 text-sm text-ink-tertiary">Field presets for live capture</p>
            <p className="mt-1 text-xs text-ink-tertiary">
              Educational · Not affiliated with the publisher
            </p>
          </div>
          <div className="flex flex-wrap gap-4 text-sm text-ink-tertiary">
            <a href="#how" className="hover:text-ink">
              How
            </a>
            <a href="#recipes" className="hover:text-ink">
              Recipes
            </a>
            <a href="#pricing" className="hover:text-ink">
              Pricing
            </a>
            <a href="#notes" className="hover:text-ink">
              Notes
            </a>
            <Link to="/privacy" className="hover:text-ink">
              Privacy
            </Link>
            <Link to="/terms" className="hover:text-ink">
              Terms
            </Link>
            <Link to="/support" className="hover:text-ink">
              Support
            </Link>
          </div>
        </div>
        <p className="mx-auto mt-8 max-w-[1120px] px-4 text-xs text-ink-tertiary sm:px-6">
          © {new Date().getFullYear()} ProTune AI Camera
        </p>
      </footer>
    </div>
  )
}
