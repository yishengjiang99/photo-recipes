/** Public marketing / product URLs. */
export const SITE_URL: string =
  (import.meta.env.VITE_SITE_URL as string | undefined) || 'https://photo.grepawk.com'

/** Placeholder until TestFlight / store URL is wired. Documented in PR. */
export const TESTFLIGHT_URL = '#testflight'

export const OG_IMAGE_PATH = '/phones-duo-iphone-android-camera.png'

/** Intrinsic size of public OG image (phones-duo; 1280×720). */
export const OG_IMAGE_WIDTH = 1280
export const OG_IMAGE_HEIGHT = 720

/** Locked meta from docs/design-handoff-landing-v2.md §1 */
export const DEFAULT_TITLE =
  'ProTune AI Camera — Auto Optimize shutter, ISO & focus'

export const DEFAULT_DESCRIPTION =
  'Point your phone at the shot — Auto Optimize writes shutter, ISO, EV, WB, and focus for live capture. Field recipes · Free Peek · Pro trial.'

export const OG_IMAGE_ALT =
  'ProTune AI Camera on iPhone and Android — before→after shutter and ISO dials (never aperture write).'

export const SITE_NAME = 'ProTune AI Camera'
