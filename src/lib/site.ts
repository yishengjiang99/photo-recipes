/** Public marketing / product URLs. */
export const SITE_URL: string =
  (import.meta.env.VITE_SITE_URL as string | undefined) || 'https://photo.grepawk.com'

/** Placeholder until TestFlight / store URL is wired. Documented in PR. */
export const TESTFLIGHT_URL = '#testflight'

/** App Store product page (Apple App Store marketing guidelines: badge links here). */
export const APP_STORE_URL =
  'https://apps.apple.com/us/app/ai-camera-auto-recipes/id6813991381'

export const OG_IMAGE_PATH = '/protune-og-1200x630.jpg'

/** Intrinsic size of the public OG image (1200×630, built from the App Store screenshots). */
export const OG_IMAGE_WIDTH = 1200
export const OG_IMAGE_HEIGHT = 630

/** Locked meta from docs/design-handoff-landing-v2.md §1 */
export const DEFAULT_TITLE =
  'ProTune AI Camera: Auto Shutter, ISO & Focus for iPhone'

export const DEFAULT_DESCRIPTION =
  'ProTune AI Camera for iPhone: tap Auto Optimize and it sets shutter, ISO, EV, white balance and focus for the scene. Real camera dials, no filters. Free to try.'

export const OG_IMAGE_ALT =
  'ProTune AI Camera on iPhone: Auto Optimize shows the shutter, ISO, EV, white balance and focus it applied.'

export const SITE_NAME = 'ProTune AI Camera'

/** Sister sites by the same developer (footer links). */
export const SISTER_SITES = [
  { href: 'https://grepawk.com/', label: 'FinalCap, a chat-to-edit AI video editor' },
  { href: 'https://music.grepawk.com/', label: 'AI Music Radar: turn what you hear into sheet music' },
] as const
