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

export function Terms() {
  return (
    <LegalShell
      title="Terms of Use"
      description={`Last updated ${LAST_UPDATED}. Terms for Photo Recipes / Grepawk Photos.`}
      path="/terms"
    >
      <p>
        These Terms of Use (“Terms”) govern your access to and use of{' '}
        <strong className="text-ink">Photo Recipes</strong> /{' '}
        <strong className="text-ink">Grepawk Photos</strong> (the “Service”), including the website
        at{' '}
        <a className="text-accent-soft hover:underline" href="https://photo.grepawk.com">
          https://photo.grepawk.com
        </a>
        , related APIs, and the iOS app. By using the Service you agree to these Terms.
      </p>

      <Section title="1. The Service">
        <p>
          Photo Recipes provides educational field photography presets, live camera coaching, Auto
          Optimize (where available), Ask Grok / Photo Vision recommendations, and related tools.
          Recommendations and dial suggestions are informational. You remain responsible for camera
          settings, safe shooting, and the photos you capture.
        </p>
        <p>
          The Service is <strong className="text-ink">not affiliated</strong> with any book
          publisher or third-party photography brand unless explicitly stated. Product names and
          recipes are for educational reference.
        </p>
      </Section>

      <Section title="2. Eligibility">
        <p>
          You must be able to form a binding contract in your jurisdiction and meet any minimum age
          required by Apple or applicable law to use the App Store and in-app purchases.
        </p>
      </Section>

      <Section title="3. Free Peek and Pro">
        <p>
          Browsing recipes and limited Free Peek features (for example, a limited number of Auto
          Optimize or Ask Grok uses per day) may be available without payment. Paid features
          (“Photo Recipes Pro”) unlock additional capability as described in the product UI.
        </p>
        <ul className="list-disc space-y-2 pl-5">
          <li>
            <strong className="text-ink">Web:</strong> Pro is sold through Stripe Checkout
            (monthly or yearly plans, often with a free trial when offered). Billing is handled by
            Stripe. Manage or cancel via the in-app billing portal when available, or contact us.
          </li>
          <li>
            <strong className="text-ink">iOS:</strong> Pro is sold only through Apple In-App
            Purchase (StoreKit). Payment is charged to your Apple ID. Subscriptions renew unless
            canceled at least 24 hours before the end of the current period in your Apple ID
            subscription settings. We do not process iOS card details ourselves.
          </li>
        </ul>
        <p>
          Prices, trial length, and included features may change; the store listing or checkout
          page at purchase time controls. Refunds for App Store purchases are handled by Apple
          under Apple’s policies; web refunds may be requested by email and handled case-by-case
          subject to Stripe and applicable law.
        </p>
      </Section>

      <Section title="4. Acceptable use">
        <p>You agree not to:</p>
        <ul className="list-disc space-y-2 pl-5">
          <li>Abuse, overload, or disrupt the API or site (including scraping at harmful rates)</li>
          <li>Attempt to bypass Free Peek limits, paywalls, or entitlement checks</li>
          <li>Upload unlawful, harmful, or infringing content</li>
          <li>Reverse engineer the Service except as allowed by law</li>
          <li>Misrepresent the Service as affiliated with third parties it is not</li>
        </ul>
      </Section>

      <Section title="5. AI features">
        <p>
          Ask Grok, Photo Vision, speech-to-text, and Auto Optimize vision steps may send text
          and/or images you provide to third-party AI providers (including xAI) to generate
          recommendations. Outputs can be wrong or incomplete. Do not rely on them as professional
          advice. Do not submit content you are not allowed to share.
        </p>
      </Section>

      <Section title="6. Intellectual property">
        <p>
          The Service, branding, UI, and original content are owned by us or our licensors. You
          retain rights to photos you capture on your device. Feedback you send may be used to
          improve the product without obligation to you.
        </p>
      </Section>

      <Section title="7. Privacy">
        <p>
          Our{' '}
          <a className="text-accent-soft hover:underline" href="/privacy">
            Privacy Policy
          </a>{' '}
          explains how we handle data. By using the Service you also acknowledge that policy.
        </p>
      </Section>

      <Section title="8. Disclaimer of warranties">
        <p>
          THE SERVICE IS PROVIDED “AS IS” AND “AS AVAILABLE” WITHOUT WARRANTIES OF ANY KIND,
          EXPRESS OR IMPLIED, INCLUDING MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND
          NON-INFRINGEMENT. We do not warrant that recommendations will produce any particular
          photographic result or that the Service will be uninterrupted or error-free.
        </p>
      </Section>

      <Section title="9. Limitation of liability">
        <p>
          TO THE MAXIMUM EXTENT PERMITTED BY LAW, WE ARE NOT LIABLE FOR INDIRECT, INCIDENTAL,
          SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY LOSS OF PHOTOS, DATA, PROFITS, OR
          GOODWILL, ARISING FROM YOUR USE OF THE SERVICE. OUR TOTAL LIABILITY FOR ANY CLAIM
          RELATING TO THE SERVICE IS LIMITED TO THE GREATER OF (A) THE AMOUNTS YOU PAID US FOR PRO
          IN THE TWELVE MONTHS BEFORE THE CLAIM OR (B) USD $50.
        </p>
      </Section>

      <Section title="10. Termination">
        <p>
          You may stop using the Service at any time and cancel subscriptions as described above.
          We may suspend or terminate access for violation of these Terms or to protect the
          Service.
        </p>
      </Section>

      <Section title="11. Changes">
        <p>
          We may update these Terms by posting a new version with an updated date. Continued use
          after changes constitutes acceptance.
        </p>
      </Section>

      <Section title="12. Contact">
        <p>
          Questions:{' '}
          <a className="text-accent-soft hover:underline" href={`mailto:${SUPPORT_EMAIL}`}>
            {SUPPORT_EMAIL}
          </a>
          . Support page:{' '}
          <a className="text-accent-soft hover:underline" href="/support">
            /support
          </a>
          .
        </p>
      </Section>

      <Section title="13. Apple App Store notice">
        <p>
          If you downloaded the iOS app from the Apple App Store, you acknowledge that these Terms
          are between you and us, not Apple; Apple has no obligation to provide maintenance or
          support for the app except as required by law; in the event of a failure to conform to
          any applicable warranty, you may notify Apple for a refund of the purchase price (if any)
          as Apple’s sole warranty obligation; Apple is not responsible for product claims,
          consumer protection, or IP infringement claims relating to the app; and Apple and its
          subsidiaries are third-party beneficiaries of these Terms with the right to enforce them
          against you regarding the app.
        </p>
      </Section>
    </LegalShell>
  )
}
