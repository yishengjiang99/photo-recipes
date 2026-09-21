import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { LegalShell } from '../components/LegalShell'

const SUPPORT_EMAIL = 'yisheng.jiang@gmail.com'

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section>
      <h2 className="mb-2 font-display text-xl text-ink">{title}</h2>
      <div className="space-y-3">{children}</div>
    </section>
  )
}

export function Support() {
  return (
    <LegalShell
      title="Support"
      description="Help for Grok Camera (Photo Recipes) — billing, camera, and Pro."
      path="/support"
    >
      <p>
        We’re happy to help with <strong className="text-ink">Grok Camera</strong> on iOS and the
        Photo Recipes website (Field Coach, Recommend, and Pro). Grepawk Photos may appear as a
        former or alternate name. For the fastest reply, email us directly.
      </p>

      <Section title="Contact">
        <p>
          Email:{' '}
          <a
            className="text-lg font-medium text-accent-soft hover:underline"
            href={`mailto:${SUPPORT_EMAIL}?subject=Grok%20Camera%20support`}
          >
            {SUPPORT_EMAIL}
          </a>
        </p>
        <p className="text-sm text-ink-tertiary">
          Please include your platform (web or iOS), roughly what you were doing, and — for billing
          — whether you subscribed via Stripe (web) or Apple (In-App Purchase).
        </p>
      </Section>

      <Section title="Common topics">
        <ul className="list-disc space-y-3 pl-5">
          <li>
            <strong className="text-ink">Camera permission.</strong> iOS Settings → Grok Camera →
            allow Camera. On the website, allow camera access in the browser for Field Coach live
            view, or upload a photo instead.
          </li>
          <li>
            <strong className="text-ink">Photos / Camera Roll.</strong> Captures save to your device
            Photos library. We don’t host a cloud gallery of your shots.
          </li>
          <li>
            <strong className="text-ink">Notifications (optional).</strong> If you opt in after a
            first capture, Grok Camera may send product push notifications. Turn them off anytime
            in iOS Settings → Grok Camera → Notifications.
          </li>
          <li>
            <strong className="text-ink">Pro on the web (Stripe).</strong> Use Manage billing in the
            app after checkout, or email us with the email used at Stripe Checkout. Cancel anytime;
            access continues through the paid period / trial rules shown at purchase.
          </li>
          <li>
            <strong className="text-ink">Pro on iOS (Apple IAP).</strong> Settings → [your name] →
            Subscriptions → Grok Camera Pro. Refunds and billing disputes for App Store purchases
            go through Apple.
          </li>
          <li>
            <strong className="text-ink">Free Peek limits.</strong> Free Peek includes limited daily
            Auto Optimize / Ask / Recommend uses. Pro removes those limits as described on the
            pricing section of the{' '}
            <Link className="text-accent-soft hover:underline" to="/">
              home page
            </Link>
            .
          </li>
          <li>
            <strong className="text-ink">Delete waitlist email / data request.</strong> Email us from
            the address you want removed. See also our{' '}
            <Link className="text-accent-soft hover:underline" to="/privacy">
              Privacy Policy
            </Link>
            .
          </li>
        </ul>
      </Section>

      <Section title="Legal">
        <p>
          <Link className="text-accent-soft hover:underline" to="/privacy">
            Privacy Policy
          </Link>
          {' · '}
          <Link className="text-accent-soft hover:underline" to="/terms">
            Terms of Use
          </Link>
        </p>
      </Section>

      <Section title="App Store Connect URLs">
        <p className="text-sm text-ink-tertiary">
          Canonical links for listing metadata (after this site is deployed):
        </p>
        <ul className="list-disc space-y-1 pl-5 text-sm">
          <li>
            Privacy:{' '}
            <a className="text-accent-soft hover:underline" href="https://photo.grepawk.com/privacy">
              https://photo.grepawk.com/privacy
            </a>
          </li>
          <li>
            Support:{' '}
            <a className="text-accent-soft hover:underline" href="https://photo.grepawk.com/support">
              https://photo.grepawk.com/support
            </a>
          </li>
          <li>
            Terms:{' '}
            <a className="text-accent-soft hover:underline" href="https://photo.grepawk.com/terms">
              https://photo.grepawk.com/terms
            </a>
          </li>
          <li>
            Marketing:{' '}
            <a className="text-accent-soft hover:underline" href="https://photo.grepawk.com/">
              https://photo.grepawk.com/
            </a>
          </li>
        </ul>
      </Section>
    </LegalShell>
  )
}
