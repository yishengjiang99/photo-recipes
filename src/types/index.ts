export type TechniqueTag =
  | 'hdr'
  | 'motion'
  | 'depth-of-field'
  | 'composition'

export type GearItem =
  | 'camera'
  | 'phone'
  | 'tripod'
  | 'remote'
  | 'flash'
  | 'wide-angle'

export type CameraMode =
  | 'aperture-priority'
  | 'shutter-priority'
  | 'manual'
  | 'auto'
  | 'phone-hdr'

export interface DialSettings {
  mode: CameraMode
  aperture?: string
  shutter?: string
  iso?: string
  evBracket?: string
  notes?: string
}

export interface SubVariant {
  id: string
  label: string
  description: string
  dials: DialSettings
  tips: string[]
}

export interface RecipePreset {
  id: string
  page: number
  title: string
  blurb: string
  whenToUse: string
  tags: TechniqueTag[]
  gear: GearItem[]
  dials: DialSettings
  steps: string[]
  tips: string[]
  equipmentChecklist: string[]
  subVariants?: SubVariant[]
  phoneTip?: string
  advancedTip?: string
}

export const TAG_LABELS: Record<TechniqueTag, string> = {
  hdr: 'HDR',
  motion: 'Motion',
  'depth-of-field': 'Depth of Field',
  composition: 'Composition',
}

export const GEAR_LABELS: Record<GearItem, string> = {
  camera: 'Camera',
  phone: 'Phone',
  tripod: 'Tripod',
  remote: 'Remote shutter',
  flash: 'Flash',
  'wide-angle': 'Wide-angle lens',
}

export const MODE_LABELS: Record<CameraMode, string> = {
  'aperture-priority': 'Aperture Priority (A/Av)',
  'shutter-priority': 'Shutter Priority (S/Tv)',
  manual: 'Manual (M)',
  auto: 'Auto',
  'phone-hdr': 'Phone HDR',
}
