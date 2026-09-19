/**
 * Minimal recipe chip catalog for pre-alarm briefs.
 * Mirror of top-level ids/titles from src/data/presets.ts — server-local so we
 * do not import Vite client modules. Keep in sync when presets change.
 */
export type RecipeChip = { id: string; title: string }

export const BRIEF_RECIPE_CHIPS: RecipeChip[] = [
  { id: 'sharp-front-to-back', title: 'Sharp from Front to Back' },
  { id: 'blur-moving-subjects', title: 'How to Blur Moving Subjects' },
  {
    id: 'panning-sharp-subject',
    title: 'Keep a Moving Subject Sharp, With Motion Blur in the Background',
  },
  {
    id: 'get-down-low',
    title: 'Shake Up Your Perspective by Getting Down Low',
  },
  {
    id: 'hdr-brights-darks',
    title: 'Capture all the Brights and Darks With HDR',
  },
]

/** Stable pick of 3 chips from guestId (deterministic, not random spam). */
export function pickRecipeChips(guestId: string, n = 3): RecipeChip[] {
  const list = BRIEF_RECIPE_CHIPS
  if (list.length <= n) return [...list]
  let h = 0
  for (let i = 0; i < guestId.length; i++) {
    h = (h * 31 + guestId.charCodeAt(i)) >>> 0
  }
  const start = h % list.length
  const out: RecipeChip[] = []
  for (let i = 0; i < n; i++) out.push(list[(start + i) % list.length]!)
  return out
}
