/** Client-side image prep: resize longest edge, JPEG encode (strips EXIF). */

export const CLIENT_MAX_EDGE = 1280
export const CLIENT_MAX_BYTES = 4 * 1024 * 1024
export const ALLOWED_INPUT_TYPES = new Set([
  'image/jpeg',
  'image/jpg',
  'image/png',
  'image/webp',
])

export type CompressedImage = {
  dataUrl: string
  blob: Blob
  width: number
  height: number
  mime: 'image/jpeg'
}

function loadImage(file: Blob): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file)
    const img = new Image()
    img.onload = () => {
      URL.revokeObjectURL(url)
      resolve(img)
    }
    img.onerror = () => {
      URL.revokeObjectURL(url)
      reject(new Error('Could not decode image'))
    }
    img.src = url
  })
}

function canvasToJpegBlob(
  canvas: HTMLCanvasElement,
  quality: number,
): Promise<Blob> {
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (blob) => {
        if (!blob) reject(new Error('Failed to encode JPEG'))
        else resolve(blob)
      },
      'image/jpeg',
      quality,
    )
  })
}

function blobToDataUrl(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve(String(reader.result))
    reader.onerror = () => reject(new Error('Failed to read image'))
    reader.readAsDataURL(blob)
  })
}

/**
 * Compress an image file to JPEG ≤1280px longest edge, targeting under ~4MB.
 * Re-encoding via canvas strips EXIF / other metadata.
 */
export async function compressImageForUpload(file: File): Promise<CompressedImage> {
  const mime = (file.type || '').toLowerCase()
  if (mime && !ALLOWED_INPUT_TYPES.has(mime)) {
    throw new Error('Unsupported image type. Use JPEG, PNG, or WebP.')
  }
  // Empty type (some mobile browsers) — try decode anyway
  if (!mime) {
    const ext = file.name.split('.').pop()?.toLowerCase()
    if (ext && !['jpg', 'jpeg', 'png', 'webp'].includes(ext)) {
      throw new Error('Unsupported image type. Use JPEG, PNG, or WebP.')
    }
  }

  const img = await loadImage(file)
  const longest = Math.max(img.naturalWidth, img.naturalHeight)
  const scale = longest > CLIENT_MAX_EDGE ? CLIENT_MAX_EDGE / longest : 1
  const width = Math.max(1, Math.round(img.naturalWidth * scale))
  const height = Math.max(1, Math.round(img.naturalHeight * scale))

  const canvas = document.createElement('canvas')
  canvas.width = width
  canvas.height = height
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('Canvas not available')
  ctx.drawImage(img, 0, 0, width, height)

  let quality = 0.85
  let blob = await canvasToJpegBlob(canvas, quality)
  while (blob.size > CLIENT_MAX_BYTES && quality > 0.45) {
    quality -= 0.1
    blob = await canvasToJpegBlob(canvas, quality)
  }
  if (blob.size > CLIENT_MAX_BYTES) {
    throw new Error(
      `Image is still over ${CLIENT_MAX_BYTES / (1024 * 1024)}MB after compression. Try a smaller photo.`,
    )
  }

  const dataUrl = await blobToDataUrl(blob)
  return { dataUrl, blob, width, height, mime: 'image/jpeg' }
}
