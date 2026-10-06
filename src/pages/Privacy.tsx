import type { ReactNode } from 'react'
import { LegalShell } from '../components/LegalShell'

const SUPPORT_EMAIL = 'yisheng.jiang@gmail.com'
const LAST_UPDATED = 'October 6, 2026'

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
      description={`Last updated ${LAST_UPDATED}. How ProTune AI Camera (by Grepawk Photos) handles your data.`}
      path="/privacy"
    >
      <p>
        This Privacy Policy describes how <strong className="text-ink">ProTune AI Camera</strong> (the
        iOS app by <strong className="text-ink">Grepawk Photos</strong>; together,
        the “Service”), operated at{' '}
        <a className="text-accent-soft hover:underline" href="https://photo.grepawk.com">
          https://photo.grepawk.com
        </a>
        , collects, uses, and shares information when you use our website, API, and iOS app.
      </p>
      <p>
        We design the Service to be privacy-first: photos you capture stay on your device unless
        you choose to send a frame for Recommend / Apply look / Auto Optimize vision; our own
        analytics use anonymous guest IDs. Starting with iOS app version 1.2, the app includes
        <strong className="text-ink">Meta (Facebook) App Events</strong> for ad attribution, used
        only to measure which of our ads lead to installs and subscriptions (see “Ad attribution”
        below). We do not show ads in the app.
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
          permission). We do not sync your full Camera Roll or keep a cloud photo album.
        </p>
        <p>
          <strong className="text-ink">Recommend / Apply look / Auto Optimize vision.</strong> When
          you use Recommend, Apply look, Ask with an image, or Auto Optimize’s vision step, a
          compressed probe frame or a photo you select may be sent to our API and then to xAI for
          that request only, solely to return recipe / dial recommendations. We do not upload your
          full Camera Roll. Images are held in memory for that request (not written to our disk or
          database as a permanent archive); we do not use your photos for advertising.
        </p>
        <p>
          <strong className="text-ink">Microphone & voice (optional).</strong> If you use voice
          input / dictation for scene description, the app may use the microphone. Speech-to-text
          prefers on-device recognition first. Cloud STT (and related Recommend text) runs only as a
          fallback when on-device is unavailable or when you use a feature that needs it. We do not
          use voice data for advertising.
        </p>
        <p>
          <strong className="text-ink">Push notifications (optional, iOS).</strong> After you opt in
          (typically offered after a first capture path), we may register an APNs device token with
          your guest / anonymous id and related notification preferences so we can send product
          notifications you chose to receive. Push tokens and prefs are not sold. You can turn
          notifications off in iOS Settings at any time.
        </p>
        <p>
          <strong className="text-ink">Motion (iOS, optional).</strong> Motion sensors may be used
          on-device for a horizon level while shooting. Motion data is not sent for analytics.
        </p>
        <p>
          <strong className="text-ink">Guest / anonymous identifiers.</strong> The Service does not
          use a traditional login account. On the web we may set an httpOnly guest cookie; on iOS
          we use anonymous / guest ids. These identifiers support Free Peek quota, Pro entitlements,
          optional push delivery, and in-house telemetry — not a profile you sign into with a
          password.
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
            <strong className="text-ink">Web:</strong> ProTune AI Camera Pro is sold via Stripe
            Checkout. Stripe processes your payment details. We receive subscription status,
            customer/subscription identifiers, and the email Stripe associates with the purchase so
            we can unlock Pro (signed httpOnly cookies / entitlements). We do not store full card
            numbers on our servers.
          </li>
          <li>
            <strong className="text-ink">iOS:</strong> In-app purchases use Apple StoreKit / In-App
            Purchase. Apple processes payment. We verify receipts with Apple to unlock Pro. Manage
            or cancel iOS subscriptions in your Apple ID subscription settings (ProTune AI Camera Pro).
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
          <code className="text-ink">anon_id</code> / guest id and short-lived{' '}
          <code className="text-ink">session_id</code>. We do <em>not</em> send photos, camera
          frames, GPS, names, emails, or tokens in telemetry props. Apart from Meta App Events for ad
          attribution (below), we do <em>not</em> use third-party analytics/crash SDKs (no
          TelemetryDeck, Sentry, or session replay). The server may store an optional salted IP hash
          for abuse resistance.
        </p>
        <p>
          <strong className="text-ink">Ad attribution (iOS app 1.2 and later).</strong> We advertise
          the app (for example with App Install ads on X or Meta) and use{' '}
          <strong className="text-ink">Meta App Events</strong> to learn which ads lead to installs,
          free trials, and subscriptions. The Meta SDK in the app may send:
        </p>
        <ul className="list-disc space-y-2 pl-5">
          <li>
            <strong className="text-ink">Device identifiers:</strong> Apple’s advertising
            identifier (IDFA) <em>only if you allow tracking</em> in Apple’s “Allow … to track your
            activity” prompt, plus Meta’s anonymous app-instance identifier.
          </li>
          <li>
            <strong className="text-ink">Usage events:</strong> install / session signals
            (<code className="text-ink">activateApp</code>), and when you start a free trial or buy
            a subscription (product, price, and currency — never payment details).
          </li>
        </ul>
        <p>
          We use this only for advertising measurement: counting installs and subscriptions per ad
          campaign and deciding where to spend on ads. Device-level data is shared with Meta only if
          you allow tracking. We never send your photos, voice, or scene text to Meta or ad networks.
          Meta processes this data under its{' '}
          <a
            className="text-accent-soft hover:underline"
            href="https://www.facebook.com/privacy/policy/"
            target="_blank"
            rel="noreferrer"
          >
            privacy policy
          </a>
          .
        </p>
        <p>
          <strong className="text-ink">Your choices:</strong> you can decline the tracking prompt,
          or turn tracking off later in iOS Settings → Privacy &amp; Security → Tracking; the app
          works the same either way. When tracking is off, the IDFA is not available to us or Meta.
          The app also uses Apple’s SKAdNetwork / AdAttributionKit, which report installs to ad
          networks without any device identifier; we receive copies of those Apple-signed reports at
          grepawk.com and keep them for campaign measurement. To ask us to delete attribution data
          tied to your device, email us (see Contact).
        </p>
        <p>
          <strong className="text-ink">Technical logs.</strong> Our servers and host may automatically
          receive standard request metadata (e.g. IP address, user agent, timestamps) in access logs
          for security and reliability.
        </p>
      </Section>

      <Section title="3. How we use information">
        <ul className="list-disc space-y-2 pl-5">
          <li>
            Provide live camera coaching, Recommend / Apply look, Auto Optimize, Ask / Photo
            Vision, and recipes
          </li>
          <li>Authenticate Pro entitlements (Stripe web or Apple IAP)</li>
          <li>Enforce Free Peek quota and guest entitlements via guest / anon ids</li>
          <li>Deliver optional product push notifications when you opt in</li>
          <li>Improve the product via aggregated, privacy-preserving funnel metrics</li>
          <li>
            Measure which of our ads lead to installs, trials, and subscriptions (ad attribution)
            and prevent ad fraud (iOS app 1.2+)
          </li>
          <li>Send optional waitlist / field-notes email if you opted in</li>
          <li>Prevent abuse, debug outages, and comply with law</li>
        </ul>
      </Section>

      <Section title="4. Sharing">
        <p>We share data only as needed to run the Service:</p>
        <ul className="list-disc space-y-2 pl-5">
          <li>
            <strong className="text-ink">xAI</strong> — for Recommend / Apply look frames, Ask,
            vision, cloud STT fallback, and related AI features when you use them
          </li>
          <li>
            <strong className="text-ink">Apple</strong> — App Store / IAP billing and receipt
            verification; APNs to deliver push when you opt in
          </li>
          <li>
            <strong className="text-ink">Stripe</strong> — web payments and billing portal
          </li>
          <li>
            <strong className="text-ink">Resend</strong> — if you submit an email to waitlist / field
            notes
          </li>
          <li>
            <strong className="text-ink">Meta (Facebook)</strong> — App Events for ad attribution in
            the iOS app (1.2+): install / session signals and trial / purchase events (product, price,
            currency); IDFA only if you allow tracking
          </li>
          <li>
            <strong className="text-ink">Ad networks we advertise on (e.g. X)</strong> — attribution
            results for our campaigns via Apple SKAdNetwork / AdAttributionKit and Meta; device-level
            only if you allow tracking
          </li>
          <li>
            Hosting / infrastructure providers that process data under our instruction to serve the
            site and API
          </li>
        </ul>
        <p>
          We do not sell your personal information, including push tokens or guest ids. Sharing
          device identifiers with ad networks to measure our own ads may count as “sharing” or
          “targeted advertising” under some US state privacy laws; declining or turning off tracking
          (see “Your choices” above) opts you out.
        </p>
      </Section>

      <Section title="5. Accounts, retention & deletion">
        <p>
          The Service does not require a traditional username/password account. Web access uses an
          httpOnly guest cookie plus Stripe checkout cookies when you buy Pro; iOS uses anonymous /
          guest ids and Apple ID purchases for Pro.
        </p>
        <p>
          <strong className="text-ink">Local data:</strong> clear site data in your browser, or
          delete the iOS app, to remove localStorage / on-device preferences and local guest state.
        </p>
        <p>
          <strong className="text-ink">Subscriptions:</strong> cancel web Pro via Stripe billing
          portal (Manage billing in the app) or email us; cancel iOS Pro in Settings → Apple ID →
          Subscriptions.
        </p>
        <p>
          <strong className="text-ink">Push:</strong> disable notifications in iOS Settings, or
          delete the app, to stop delivery. Email us if you want server-side token / preference
          records removed.
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
