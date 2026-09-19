/** Public marketing / product URLs. Replace when canonical domain is final. */
export const SITE_URL: string =
  (import.meta.env.VITE_SITE_URL as string | undefined) || 'https://photorecipes.app'

/** Placeholder until TestFlight / store URL is wired. Documented in PR. */
export const TESTFLIGHT_URL = '#testflight'

export const OG_IMAGE_PATH = '/phones-duo-iphone-android-camera.png'

/** Locked meta from docs/design-handoff-landing-v2.md §1 */
export const DEFAULT_TITLE =
  'Photo Recipes — Auto Optimize shutter, ISO & focus'

export const DEFAULT_DESCRIPTION =
  'Point your phone at the shot — Auto Optimize writes shutter, ISO, EV, WB, and focus for live capture. Field recipes · Free Peek · Pro trial.'

export const OG_IMAGE_ALT =
  'Photo Recipes on iPhone and Android — before→after shutter and ISO dials (never aperture write).'
