import type { ReactNode } from 'react'
import { LegalShell } from '../components/LegalShell'

const SUPPORT_EMAIL = 'yisheng.jiang@gmail.com'
const LAST_UPDATED = 'September 19, 2026'

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section>
      <h2 className="mb-2 font-display text-xl text-ink">{title}</h2>
      <div className="space-y-3">{children}</div>
    </section>
  )
}

export function Privacy() {
  return (
    <LegalShell
      title="Privacy Policy"
      description={`Last updated ${LAST_UPDATED}. How Photo Recipes / Grepawk Photos handles your data.`}
      path="/privacy"
    >
      <p>
        This Privacy Policy describes how <strong className="text-ink">Photo Recipes</strong>{' '}
        (also branded as <strong className="text-ink">Grepawk Photos</strong> on iOS; together,
        the “Service”), operated at{' '}
        <a className="text-accent-soft hover:underline" href="https://photo.grepawk.com">
          https://photo.grepawk.com
        </a>
        , collects, uses, and shares information when you use our website, API, and iOS app.
      </p>
      <p>
        We design the Service to be privacy-first: photos you capture stay on your device unless
        you choose to send a frame for coaching; analytics use anonymous IDs; we do not embed
        third-party advertising or analytics SDKs.
      </p>

      <Section title="1. Who we are">
        <p>
          Contact for privacy and support:{' '}
          <a className="text-accent-soft hover:underline" href={`mailto:${SUPPORT_EMAIL}`}>
            {SUPPORT_EMAIL}
          </a>
          .
        </p>
      </Section>

      <Section title="2. Information we collect">
        <p>
          <strong className="text-ink">Camera & photos (device).</strong> The iOS app requests
          camera access to show a live viewfinder, apply field recipes / Auto Optimize settings,
          and capture photos. Captures are saved to your device Camera Roll (Photos library add
          permission). We do not upload full Camera Roll libraries or keep a cloud photo album.
        </p>
        <p>
          <strong className="text-ink">Optional image for coaching.</strong> If you use Field
          Coach, Photo Vision, Ask Grok with an image, or Auto Optimize’s vision step, a
          compressed probe/frame or photo you select may be sent to our servers and then to the
          xAI API solely to return recipe / dial recommendations. Images are processed for that
          request; we do not build a permanent photo archive or use your photos for advertising.
        </p>
        <p>
          <strong className="text-ink">Microphone & voice (optional).</strong> If you use voice
          input / dictation for scene description, the app may use the microphone. Audio may be
          sent to our speech-to-text endpoint (and/or on-device speech recognition where available)
          to produce text for coaching. We do not use voice data for advertising.
        </p>
        <p>
          <strong className="text-ink">Motion (iOS, optional).</strong> Motion sensors may be used
          on-device for a horizon level while shooting. Motion data is not sent for analytics.
        </p>
        <p>
          <strong className="text-ink">Local app data.</strong> Favorites, checklist progress, and
          similar preferences may be stored in browser <code className="text-ink">localStorage</code>{' '}
          or on-device storage. That data stays on your device unless a feature explicitly syncs it
          (most Free Peek state is local-only today).
        </p>
        <p>
          <strong className="text-ink">Subscription & billing.</strong>
        </p>
        <ul className="list-disc space-y-2 pl-5">
          <li>
            <strong className="text-ink">Web:</strong> Photo Recipes Pro is sold via Stripe
            Checkout. Stripe processes your payment details. We receive subscription status,
            customer/subscription identifiers, and the email Stripe associates with the purchase so
            we can unlock Pro (signed httpOnly cookies / entitlements). We do not store full card
            numbers on our servers.
          </li>
          <li>
            <strong className="text-ink">iOS:</strong> In-app purchases use Apple StoreKit / In-App
            Purchase. Apple processes payment. We verify receipts with Apple to unlock Pro. Manage
            or cancel iOS subscriptions in your Apple ID subscription settings.
          </li>
        </ul>
        <p>
          <strong className="text-ink">Email (optional).</strong> If you join the waitlist or field
          notes list on the marketing site, we store the email you submit (locally and/or via our
          email provider, Resend) to send product updates. You can ask us to remove it (see
          Contact).
        </p>
        <p>
          <strong className="text-ink">Telemetry (privacy-first).</strong> We run in-house product /
          funnel analytics. Clients may send allowlisted event names and non-sensitive properties to{' '}
          <code className="text-ink">POST /api/telemetry</code>. Events use an anonymous{' '}
          <code className="text-ink">anon_id</code> and short-lived <code className="text-ink">session_id</code>.
          We do <em>not</em> send photos, camera frames, GPS, names, emails, or tokens in telemetry
          props. We do <em>not</em> use third-party analytics/crash SDKs (no TelemetryDeck, Sentry,
          session replay, or ad trackers). The server may store an optional salted IP hash for abuse
          resistance.
        </p>
        <p>
          <strong className="text-ink">Technical logs.</strong> Our servers and host may automatically
          receive standard request metadata (e.g. IP address, user agent, timestamps) in access logs
          for security and reliability.
        </p>
      </Section>

      <Section title="3. How we use information">
        <ul className="list-disc space-y-2 pl-5">
          <li>Provide live camera coaching, Auto Optimize, Ask Grok / Photo Vision, and recipes</li>
          <li>Authenticate Pro entitlements (Stripe web or Apple IAP)</li>
          <li>Improve the product via aggregated, privacy-preserving funnel metrics</li>
          <li>Send optional waitlist / field-notes email if you opted in</li>
          <li>Prevent abuse, debug outages, and comply with law</li>
        </ul>
      </Section>

      <Section title="4. Sharing">
        <p>We share data only as needed to run the Service:</p>
        <ul className="list-disc space-y-2 pl-5">
          <li>
            <strong className="text-ink">xAI</strong> — for Ask Grok, vision recommend, STT, and
            related AI features when you use them
          </li>
          <li>
            <strong className="text-ink">Stripe</strong> — web payments and billing portal
          </li>
          <li>
            <strong className="text-ink">Apple</strong> — App Store / IAP billing and receipt
            verification
          </li>
          <li>
            <strong className="text-ink">Resend</strong> — if you submit an email to waitlist / field
            notes
          </li>
          <li>
            Hosting / infrastructure providers that process data under our instruction to serve the
            site and API
          </li>
        </ul>
        <p>We do not sell your personal information.</p>
      </Section>

      <Section title="5. Accounts, retention & deletion">
        <p>
          The Service does not require a traditional username/password account. Web Pro access is
          tied to Stripe checkout and browser cookies; iOS Pro is tied to your Apple ID purchases.
        </p>
        <p>
          <strong className="text-ink">Local data:</strong> clear site data in your browser, or
          delete the iOS app, to remove localStorage / on-device preferences.
        </p>
        <p>
          <strong className="text-ink">Subscriptions:</strong> cancel web Pro via Stripe billing
          portal (Manage billing in the app) or email us; cancel iOS Pro in Settings → Apple ID →
          Subscriptions.
        </p>
        <p>
          <strong className="text-ink">Email / entitlements deletion:</strong> email{' '}
          <a className="text-accent-soft hover:underline" href={`mailto:${SUPPORT_EMAIL}`}>
            {SUPPORT_EMAIL}
          </a>{' '}
          with the address used for Stripe or waitlist and we will delete or anonymize associated
          records we control, subject to legal/accounting retention (e.g. payment records held by
          Stripe/Apple).
        </p>
      </Section>

      <Section title="6. Children">
        <p>
          The Service is not directed to children under 13 (or the minimum age required in your
          jurisdiction). We do not knowingly collect personal information from children.
        </p>
      </Section>

      <Section title="7. International users">
        <p>
          Servers may be located in the United States or other regions where our hosting providers
          operate. By using the Service you understand your information may be processed in those
          locations.
        </p>
      </Section>

      <Section title="8. Changes">
        <p>
          We may update this policy from time to time. The “Last updated” date at the top will
          change. Continued use after changes means you accept the updated policy.
        </p>
      </Section>

      <Section title="9. Contact">
        <p>
          Questions or deletion requests:{' '}
          <a className="text-accent-soft hover:underline" href={`mailto:${SUPPORT_EMAIL}`}>
            {SUPPORT_EMAIL}
          </a>
          . More help:{' '}
          <a className="text-accent-soft hover:underline" href="/support">
            Support
          </a>
          .
        </p>
      </Section>
    </LegalShell>
  )
}
