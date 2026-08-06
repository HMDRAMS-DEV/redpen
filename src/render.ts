import type { Shot, Stroke } from './types'

const PEN = '#ff2d2d'

export function drawStrokes(
  ctx: CanvasRenderingContext2D,
  strokes: Stroke[],
  w: number,
  h: number,
  lineWidth: number,
) {
  ctx.strokeStyle = PEN
  ctx.lineWidth = lineWidth
  ctx.lineCap = 'round'
  ctx.lineJoin = 'round'
  for (const s of strokes) {
    if (s.points.length < 2) continue
    ctx.beginPath()
    ctx.moveTo(s.points[0][0] * w, s.points[0][1] * h)
    for (let i = 1; i < s.points.length; i++) {
      ctx.lineTo(s.points[i][0] * w, s.points[i][1] * h)
    }
    ctx.stroke()
  }
}

function wrap(ctx: CanvasRenderingContext2D, text: string, maxW: number) {
  const lines: string[] = []
  for (const para of text.split('\n')) {
    if (!para.trim()) {
      lines.push('')
      continue
    }
    let line = ''
    for (const word of para.split(/\s+/)) {
      const next = line ? `${line} ${word}` : word
      if (ctx.measureText(next).width > maxW && line) {
        lines.push(line)
        line = word
      } else {
        line = next
      }
    }
    lines.push(line)
  }
  return lines
}

function loadImage(src: string) {
  return new Promise<HTMLImageElement>((res, rej) => {
    const img = new Image()
    img.onload = () => res(img)
    img.onerror = rej
    img.src = src
  })
}

/** Composites screenshot + red markup, with the dictated note rendered below it. */
export async function renderShot(shot: Shot): Promise<Blob> {
  const img = await loadImage(shot.src)
  const w = shot.width
  const h = shot.height

  const pad = Math.round(w * 0.06)
  const fontSize = Math.max(18, Math.round(w * 0.036))
  const lineHeight = Math.round(fontSize * 1.45)
  const penWidth = Math.max(3, Math.round(w * 0.008))

  // Measure the note first so the canvas can be sized in one pass.
  const measure = document.createElement('canvas').getContext('2d')!
  measure.font = `${fontSize}px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif`
  const note = shot.note.trim()
  const lines = note ? wrap(measure, note, w) : []
  const textBlock = lines.length ? lines.length * lineHeight + pad : 0

  const canvas = document.createElement('canvas')
  canvas.width = w + pad * 2
  canvas.height = pad + h + textBlock + pad
  const ctx = canvas.getContext('2d')!

  ctx.fillStyle = '#ffffff'
  ctx.fillRect(0, 0, canvas.width, canvas.height)

  ctx.drawImage(img, pad, pad, w, h)
  ctx.strokeStyle = 'rgba(0,0,0,0.12)'
  ctx.lineWidth = 1
  ctx.strokeRect(pad + 0.5, pad + 0.5, w - 1, h - 1)

  ctx.save()
  ctx.translate(pad, pad)
  drawStrokes(ctx, shot.strokes, w, h, penWidth)
  ctx.restore()

  if (lines.length) {
    ctx.fillStyle = '#111111'
    ctx.font = `${fontSize}px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif`
    ctx.textBaseline = 'top'
    let y = pad + h + pad
    for (const line of lines) {
      ctx.fillText(line, pad, y)
      y += lineHeight
    }
  }

  return new Promise<Blob>((res) =>
    canvas.toBlob((b) => res(b!), 'image/png'),
  )
}

export function download(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}

export function exportName(shot: Shot, i: number) {
  const base = shot.name.replace(/\.[^.]+$/, '').replace(/[^\w-]+/g, '-')
  return `redpen-${String(i + 1).padStart(2, '0')}-${base}.png`
}
