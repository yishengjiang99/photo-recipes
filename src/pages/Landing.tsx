import {
  Aperture,
  Camera,
  Check,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  Mic,
  Sparkles,
  BookOpen,
} from 'lucide-react'
import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { Seo } from '../components/Seo'
import { useSubscription } from '../hooks/useSubscription'
import { DEFAULT_DESCRIPTION, DEFAULT_TITLE, SITE_URL } from '../lib/site'

const HOW_STEPS = [
  {
    n: '1',
    title: 'Sense',
    body: 'Light, motion, and your scene note — viewfinder caption, voice, or type. A camera settings app that reads the field, not the feed.',
  },
  {
    n: '2',
    title: 'Reason',
    body: 'Matches a photography recipe and clamps to what your lens can do — landscape, panning, HDR, depth of field.',
  },
  {
    n: '3',
    title: 'Apply',
    body: 'Writes MODE / aperture / shutter / ISO — before→after chips you can trust. Auto Optimize camera dials for live capture.',
  },
  {
    n: '4',
    title: 'Verify',
    body: 'Soft pan cues if you need to reframe; then you’re ready to capture with a field photography checklist.',
  },
] as const

const FEATURES = [
  {
    overline: 'Live capture',
    title: 'Auto Optimize',
    body: 'One CTA runs the agent loop on the live viewfinder — auto optimize camera settings before you shoot.',
  },
  {
    overline: 'Craft',
    title: 'Recipe dials',
    body: 'Educational + live photography recipes — aperture rings you can override anytime.',
  },
  {
    overline: 'Framing',
    title: 'Direction cues',
    body: 'Quiet left/right chevrons when you should pan — not a game HUD. Built for panning photography settings in the field.',
  },
  {
    overline: 'Input',
    title: 'Voice + viewfinder note',
    body: 'Dictate or prefill From viewfinder; always editable. Ask “what settings for landscape” without leaving the shot.',
  },
  {
    overline: 'Coach',
    title: 'Ask / Photo Vision',
    body: 'Coach into a recipe when you’re stuck — HDR camera settings, depth of field settings, or motion. Free Peek quota applies.',
  },
  {
    overline: 'Funnel',
    title: 'Soft Pro funnel',
    body: 'Browse free; unlock unlimited optimize, manuals, and field photography checklists with Pro.',
  },
] as const

const FAQ_ITEMS = [
  {
    q: 'Is this an AI filter app?',
    a: 'No — Photo Recipes is a field technique coach and camera settings app. It applies real camera settings and photography recipes for capture, not filters or edits after the shot.',
  },
  {
    q: 'What does Auto Optimize do?',
    a: 'Sense → match a recipe → apply dials → verify (with optional pan cues) → you shoot. It sets exposure / focus / white-balance guidance for live capture — it does not paint filters onto a finished photo.',
  },
  {
    q: 'What’s free?',
    a: 'Free Peek lets you browse the recipe library. Agent / Ask runs and advanced manuals are limited (about 1 Auto Optimize or Ask per day) until Pro.',
  },
  {
    q: 'What’s included in Pro?',
    a: 'Unlimited Auto Optimize, Ask / Photo Vision, manual dials, and field checklists. $59.99/yr (best value) or $7.99/mo, with a 7-day trial.',
  },
  {
    q: 'Does it cover panning, HDR, and depth of field?',
    a: 'Yes — the skill library includes panning photography settings, HDR camera settings, depth of field settings, motion, and composition recipes with dials, steps, and teach-why tips.',
  },
  {
    q: 'iPhone and Android?',
    a: 'Designed for both. The marketing duo shows Auto Optimize on camera with recipe dials side by side.',
  },
  {
    q: 'Can I override the agent?',
    a: 'Yes — manual dials drawer (Pro). Teach mode explains why a recipe chose those settings so you learn for next time.',
  },
  {
    q: 'Do I need an account?',
    a: 'You can browse Free Peek without buying. Checkout for Pro trial uses Stripe; billing portal is available after you subscribe.',
  },
  {
    q: 'Is it affiliated with the book publisher?',
    a: 'Educational presets inspired by field recipes — not affiliated with the publisher.',
  },
] as const

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
  const [navOpen, setNavOpen] = useState(false)

  const jsonLd = useMemo(
    () => [
      {
        '@context': 'https://schema.org',
        '@type': 'SoftwareApplication',
        name: 'Photo Recipes',
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

  return (
    <div className="min-h-dvh bg-bg text-ink">
      <Seo title={DEFAULT_TITLE} description={DEFAULT_DESCRIPTION} path="/" jsonLd={jsonLd} />

      <header className="sticky top-0 z-30 border-b border-border/60 bg-bg/90 backdrop-blur-md">
        <div className="mx-auto flex max-w-[1120px] items-center justify-between gap-4 px-4 py-3 sm:px-6">
          <Link to="/" className="group flex items-center gap-2.5">
            <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-accent-muted ring-1 ring-accent/30">
              <Camera className="h-4 w-4 text-accent-soft" strokeWidth={1.75} />
            </span>
            <span className="font-display text-lg tracking-tight text-ink">Photo Recipes</span>
          </Link>

          <nav className="hidden items-center gap-6 text-sm text-ink-secondary md:flex" aria-label="Primary">
            <Link to="/app" className="hover:text-ink">
              Library
            </Link>
            <a href="#how-it-works" className="hover:text-ink">
              How it works
            </a>
            <a href="#pricing" className="hover:text-ink">
              Pricing
            </a>
            <a href="#faq" className="hover:text-ink">
              FAQ
            </a>
          </nav>

          <div className="flex items-center gap-2">
            <Link
              to="/app"
              className="hidden min-h-9 items-center rounded-full px-3 py-1.5 text-sm font-medium text-ink-secondary ring-1 ring-border hover:bg-surface sm:inline-flex"
            >
              Open app
            </Link>
            <button
              type="button"
              onClick={startTrial}
              className="inline-flex min-h-9 items-center rounded-full bg-accent px-3 py-1.5 text-sm font-semibold text-white hover:bg-accent-soft"
            >
              Start free trial
            </button>
            <button
              type="button"
              className="inline-flex h-9 w-9 items-center justify-center rounded-lg text-ink-secondary ring-1 ring-border md:hidden"
              aria-expanded={navOpen}
              aria-label="Open menu"
              onClick={() => setNavOpen((v) => !v)}
            >
              <span className="sr-only">Menu</span>
              <span className="flex flex-col gap-1" aria-hidden>
                <span className="block h-0.5 w-4 bg-ink-secondary" />
                <span className="block h-0.5 w-4 bg-ink-secondary" />
                <span className="block h-0.5 w-4 bg-ink-secondary" />
              </span>
            </button>
          </div>
        </div>

        {navOpen ? (
          <div className="border-t border-border px-4 py-3 md:hidden">
            <div className="flex flex-col gap-3 text-sm text-ink-secondary">
              <Link to="/app" onClick={() => setNavOpen(false)} className="hover:text-ink">
                Library
              </Link>
              <a href="#how-it-works" onClick={() => setNavOpen(false)} className="hover:text-ink">
                How it works
              </a>
              <a href="#pricing" onClick={() => setNavOpen(false)} className="hover:text-ink">
                Pricing
              </a>
              <a href="#faq" onClick={() => setNavOpen(false)} className="hover:text-ink">
                FAQ
              </a>
            </div>
          </div>
        ) : null}
      </header>

      <main>
        {/* Hero */}
        <section className="mx-auto grid max-w-[1120px] items-center gap-10 px-4 pb-16 pt-10 sm:px-6 sm:pt-14 lg:grid-cols-[0.42fr_0.58fr] lg:gap-12 lg:pb-24">
          <div className="text-left">
            <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-ink-tertiary">
              Field technique · live capture
            </p>
            <h1 className="font-display mt-3 text-[2.15rem] leading-[1.12] tracking-tight text-ink sm:text-5xl">
              Recipes that set your camera — not just your mood.
            </h1>
            <p className="mt-4 max-w-md text-base leading-relaxed text-ink-secondary sm:text-lg">
              Photo Recipes senses the scene, picks a field recipe, applies real dials, and coaches
              you to the shot. Agentic optimize. Manual override anytime.
            </p>
            <div className="mt-7 flex flex-wrap items-center gap-3">
              <button
                type="button"
                onClick={startTrial}
                className="inline-flex min-h-11 items-center justify-center rounded-full bg-accent px-5 py-2.5 text-sm font-semibold text-white hover:bg-accent-soft"
              >
                Start free trial
              </button>
              <Link
                to="/app"
                className="inline-flex min-h-11 items-center justify-center rounded-full px-5 py-2.5 text-sm font-semibold text-ink ring-1 ring-border hover:bg-surface"
              >
                Browse Free Peek
              </Link>
            </div>
            <p className="mt-3 text-xs text-ink-tertiary">
              7-day trial · Free Peek to browse · Cancel anytime
            </p>
          </div>

          <div className="relative mx-auto w-full max-w-xl lg:max-w-none">
            <img
              src="/phones-duo-iphone-android-camera.png"
              alt="Photo Recipes on iPhone and Android — Auto Optimize camera and recipe dials."
              width={1200}
              height={900}
              className="h-auto w-full object-contain"
              fetchPriority="high"
              decoding="async"
            />
          </div>
        </section>

        {/* How it works */}
        <section id="how-it-works" className="scroll-mt-20 border-t border-border/50 py-16 sm:py-20">
          <div className="mx-auto max-w-[1120px] px-4 sm:px-6">
            <h2 className="font-display text-center text-3xl text-ink sm:text-4xl">
              Sense. Apply. Verify. Shoot.
            </h2>
            <p className="mx-auto mt-3 max-w-2xl text-center text-sm text-ink-secondary sm:text-base">
              Auto Optimize runs a short field loop so your camera settings match the photography
              recipe — then you take the frame.
            </p>
            <ol className="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              {HOW_STEPS.map((step) => (
                <li
                  key={step.n}
                  className="rounded-2xl border border-border bg-surface p-5 text-left"
                >
                  <span className="font-mono text-xs font-semibold text-accent-soft">{step.n}</span>
                  <h3 className="mt-2 font-display text-xl text-ink">{step.title}</h3>
                  <p className="mt-2 text-sm leading-relaxed text-ink-secondary">{step.body}</p>
                </li>
              ))}
            </ol>
          </div>
        </section>

        {/* Features */}
        <section id="features" className="scroll-mt-20 py-16 sm:py-20">
          <div className="mx-auto max-w-[1120px] px-4 sm:px-6">
            <h2 className="font-display text-center text-3xl text-ink sm:text-4xl">
              Built for the field, not the feed.
            </h2>
            <p className="mx-auto mt-3 max-w-2xl text-center text-sm text-ink-secondary sm:text-base">
              A skill library of photography recipes — panning, HDR, depth of field, motion, and
              composition — with dials, steps, and teach-why tips.
            </p>
            <div className="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {FEATURES.map((f) => (
                <article
                  key={f.title}
                  className="rounded-2xl border border-border bg-surface p-5 text-left"
                >
                  <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-ink-tertiary">
                    {f.overline}
                  </p>
                  <h3 className="mt-2 text-base font-semibold text-ink">{f.title}</h3>
                  <p className="mt-2 text-sm leading-relaxed text-ink-secondary">{f.body}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        {/* Dual-phone deep-dive */}
        <section className="border-y border-border/50 bg-bg-elevated py-16 sm:py-20">
          <div className="mx-auto grid max-w-[1120px] items-center gap-10 px-4 sm:px-6 lg:grid-cols-2">
            <div className="order-2 lg:order-1">
              <img
                src="/iphone-duo-hero-web.png"
                alt="Photo Recipes dual iPhone screens showing recipe dials and Auto Optimize status."
                width={1100}
                height={800}
                className="mx-auto h-auto w-full max-w-md object-contain lg:max-w-none"
                loading="lazy"
                decoding="async"
              />
            </div>
            <div className="order-1 text-left lg:order-2">
              <h2 className="font-display text-3xl text-ink sm:text-4xl">
                An agent on your shoulder — dials you still control.
              </h2>
              <ul className="mt-6 space-y-4 text-sm text-ink-secondary">
                <li className="flex gap-3">
                  <Sparkles className="mt-0.5 h-4 w-4 shrink-0 text-accent-soft" />
                  <span>
                    <strong className="text-ink">Before → after settings</strong> — see MODE,
                    aperture, shutter, and ISO change as Auto Optimize applies the recipe.
                  </span>
                </li>
                <li className="flex gap-3">
                  <BookOpen className="mt-0.5 h-4 w-4 shrink-0 text-accent-soft" />
                  <span>
                    <strong className="text-ink">Teach mode</strong> — why this recipe for landscape,
                    HDR, or depth of field, so the next shoot sticks.
                  </span>
                </li>
                <li className="flex gap-3">
                  <Aperture className="mt-0.5 h-4 w-4 shrink-0 text-accent-soft" />
                  <span>
                    <strong className="text-ink">Manual override drawer</strong> — keep authorship;
                    the agent suggests, you decide.
                  </span>
                </li>
                <li className="flex gap-3">
                  <span className="mt-0.5 flex shrink-0 gap-0.5 text-accent-soft">
                    <ChevronLeft className="h-4 w-4" />
                    <ChevronRight className="h-4 w-4" />
                  </span>
                  <span>
                    <strong className="text-ink">Quiet pan L/R cues</strong> — reframe without a loud
                    HUD when panning photography settings call for it.
                  </span>
                </li>
                <li className="flex gap-3">
                  <Mic className="mt-0.5 h-4 w-4 shrink-0 text-accent-soft" />
                  <span>
                    <strong className="text-ink">Voice + From viewfinder</strong> — dictate the scene
                    note or pull caption text; always editable.
                  </span>
                </li>
              </ul>
            </div>
          </div>
        </section>

        {/* Pricing */}
        <section id="pricing" className="scroll-mt-20 py-16 sm:py-20">
          <div className="mx-auto max-w-[1120px] px-4 sm:px-6">
            <h2 className="font-display text-center text-3xl text-ink sm:text-4xl">
              Free Peek · Pro when you need the field open.
            </h2>
            <p className="mx-auto mt-3 max-w-xl text-center text-sm text-ink-secondary">
              Soft try the camera settings app. Upgrade for unlimited Auto Optimize and checklists.
            </p>

            <div className="mx-auto mt-10 grid max-w-3xl gap-4 sm:grid-cols-2">
              <article className="rounded-2xl border border-border bg-surface p-6 text-left">
                <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-ink-tertiary">
                  Free Peek
                </p>
                <p className="mt-2 font-display text-3xl text-ink">$0</p>
                <ul className="mt-4 space-y-2 text-sm text-ink-secondary">
                  <li className="flex gap-2">
                    <Check className="h-4 w-4 shrink-0 text-success" /> Browse photography recipes
                  </li>
                  <li className="flex gap-2">
                    <Check className="h-4 w-4 shrink-0 text-success" /> 1 Auto Optimize / Ask per day
                  </li>
                </ul>
                <Link
                  to="/app"
                  className="mt-6 inline-flex min-h-11 w-full items-center justify-center rounded-full text-sm font-semibold text-ink ring-1 ring-border hover:bg-surface-2"
                >
                  Browse Free Peek
                </Link>
              </article>

              <article className="rounded-2xl border border-accent/40 bg-surface p-6 text-left ring-1 ring-accent/20">
                <div className="flex items-center justify-between gap-2">
                  <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-accent-soft">
                    Pro · Best value
                  </p>
                  <span className="rounded-full bg-accent-muted px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-accent-soft">
                    7-day trial
                  </span>
                </div>
                <p className="mt-2 font-display text-3xl text-ink">
                  $59.99<span className="text-lg text-ink-tertiary">/yr</span>
                </p>
                <p className="mt-1 text-xs text-ink-tertiary">or $7.99/mo</p>
                <ul className="mt-4 space-y-2 text-sm text-ink-secondary">
                  <li className="flex gap-2">
                    <Check className="h-4 w-4 shrink-0 text-success" /> Unlimited Auto Optimize
                  </li>
                  <li className="flex gap-2">
                    <Check className="h-4 w-4 shrink-0 text-success" /> Manual dials + field checklists
                  </li>
                  <li className="flex gap-2">
                    <Check className="h-4 w-4 shrink-0 text-success" /> Ask / Photo Vision unlocked
                  </li>
                </ul>
                <button
                  type="button"
                  onClick={startTrial}
                  className="mt-6 inline-flex min-h-11 w-full items-center justify-center rounded-full bg-accent text-sm font-semibold text-white hover:bg-accent-soft"
                >
                  Start 7-day trial
                </button>
              </article>
            </div>
          </div>
        </section>

        {/* FAQ */}
        <section id="faq" className="scroll-mt-20 border-t border-border/50 py-16 sm:py-20">
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
        <section className="py-16 sm:py-24">
          <div className="mx-auto max-w-[720px] px-4 text-center sm:px-6">
            <h2 className="font-display text-3xl text-ink sm:text-4xl">Go make the frame.</h2>
            <div className="mt-7 flex flex-wrap items-center justify-center gap-3">
              <button
                type="button"
                onClick={startTrial}
                className="inline-flex min-h-11 items-center justify-center rounded-full bg-accent px-5 py-2.5 text-sm font-semibold text-white hover:bg-accent-soft"
              >
                Start free trial
              </button>
              <Link
                to="/app"
                className="inline-flex min-h-11 items-center justify-center rounded-full px-5 py-2.5 text-sm font-semibold text-ink ring-1 ring-border hover:bg-surface"
              >
                Open Free Peek
              </Link>
            </div>
            <p className="mt-3 text-xs text-ink-tertiary">
              7-day trial · Free Peek to browse · Cancel anytime
            </p>
          </div>
        </section>
      </main>

      <footer className="border-t border-border py-10">
        <div className="mx-auto flex max-w-[1120px] flex-col gap-6 px-4 sm:flex-row sm:items-start sm:justify-between sm:px-6">
          <div className="text-left">
            <div className="flex items-center gap-2">
              <Camera className="h-4 w-4 text-accent-soft" />
              <span className="font-display text-lg text-ink">Photo Recipes</span>
            </div>
            <p className="mt-2 text-sm text-ink-tertiary">Field presets for live capture</p>
            <p className="mt-1 text-xs text-ink-tertiary">
              Educational · Not affiliated with the publisher
            </p>
          </div>
          <div className="flex flex-wrap gap-4 text-sm text-ink-tertiary">
            <Link to="/app" className="hover:text-ink">
              Library
            </Link>
            <a href="#pricing" className="hover:text-ink">
              Pricing
            </a>
            <a href="#faq" className="hover:text-ink">
              FAQ
            </a>
            <span title="Privacy policy placeholder">Privacy</span>
            <span title="Terms placeholder">Terms</span>
          </div>
        </div>
        <p className="mx-auto mt-8 max-w-[1120px] px-4 text-xs text-ink-tertiary sm:px-6">
          © {new Date().getFullYear()} Photo Recipes
        </p>
      </footer>
    </div>
  )
}
