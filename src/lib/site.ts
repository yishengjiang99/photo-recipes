/** Public marketing / product URLs. Replace when canonical domain is final. */
export const SITE_URL: string =
  (import.meta.env.VITE_SITE_URL as string | undefined) || 'https://photorecipes.app'

/** Placeholder until TestFlight / store URL is wired. Documented in PR. */
export const TESTFLIGHT_URL = '#testflight'

export const OG_IMAGE_PATH = '/phones-duo-iphone-android-camera.png'

export const DEFAULT_TITLE =
  'Photo Recipes — Camera settings app & photography recipes for the field'

export const DEFAULT_DESCRIPTION =
  'Camera settings app with photography recipes: Auto Optimize dials for landscape, panning, HDR, and depth of field. Field photography checklist · Free Peek · Pro trial.'
