import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import type { Point, Shot, Stroke } from './types'
import { dictationSupported, useDictation } from './useDictation'
import { download, drawStrokes, exportName, renderShot } from './render'

function readFile(file: File): Promise<Shot> {
  return new Promise((res, rej) => {
    const reader = new FileReader()
    reader.onload = () => {
      const src = reader.result as string
      const img = new Image()
      img.onload = () =>
        res({
          id: crypto.randomUUID(),
          name: file.name,
          src,
          width: img.naturalWidth,
          height: img.naturalHeight,
          strokes: [],
          note: '',
        })
      img.onerror = rej
      img.src = src
    }
    reader.onerror = rej
    reader.readAsDataURL(file)
  })
}

export default function App() {
  const [shots, setShots] = useState<Shot[]>([])
  const [index, setIndex] = useState(0)
  const [dragging, setDragging] = useState(false)
  const [busy, setBusy] = useState(false)

  const shot = shots[index]

  const addFiles = useCallback(async (files: FileList | File[]) => {
    const images = Array.from(files).filter((f) => f.type.startsWith('image/'))
    if (!images.length) return
    const added = await Promise.all(images.map(readFile))
    setShots((prev) => {
      setIndex(prev.length)
      return [...prev, ...added]
    })
  }, [])

  const patch = useCallback(
    (id: string, fn: (s: Shot) => Shot) =>
      setShots((prev) => prev.map((s) => (s.id === id ? fn(s) : s))),
    [],
  )

  const appendNote = useCallback(
    (text: string) => {
      if (!shot || !text) return
      patch(shot.id, (s) => ({
        ...s,
        note: s.note ? `${s.note} ${text}` : text,
      }))
    },
    [shot, patch],
  )

  const { recording, interim, toggle, stop } = useDictation(appendNote)

  const undo = useCallback(() => {
    if (!shot) return
    patch(shot.id, (s) => ({ ...s, strokes: s.strokes.slice(0, -1) }))
  }, [shot, patch])

  const go = useCallback(
    (delta: number) => {
      stop()
      setIndex((i) => Math.min(shots.length - 1, Math.max(0, i + delta)))
    },
    [shots.length, stop],
  )

  const exportOne = useCallback(async (s: Shot, i: number) => {
    download(await renderShot(s), exportName(s, i))
  }, [])

  const exportAll = useCallback(async () => {
    setBusy(true)
    for (let i = 0; i < shots.length; i++) {
      await exportOne(shots[i], i)
      // Chrome throttles rapid programmatic downloads.
      await new Promise((r) => setTimeout(r, 350))
    }
    setBusy(false)
  }, [shots, exportOne])

  // --- keyboard ---------------------------------------------------------
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const typing =
        e.target instanceof HTMLElement &&
        (e.target.tagName === 'TEXTAREA' || e.target.tagName === 'INPUT')
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'z') {
        e.preventDefault()
        undo()
        return
      }
      if (typing) return
      if (e.key === 'ArrowRight') go(1)
      else if (e.key === 'ArrowLeft') go(-1)
      else if (e.key === ' ') {
        e.preventDefault()
        toggle()
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [go, toggle, undo])

  // --- window-level drop ------------------------------------------------
  useEffect(() => {
    const over = (e: DragEvent) => {
      e.preventDefault()
      setDragging(true)
    }
    const leave = (e: DragEvent) => {
      if (e.relatedTarget === null) setDragging(false)
    }
    const drop = (e: DragEvent) => {
      e.preventDefault()
      setDragging(false)
      if (e.dataTransfer?.files.length) addFiles(e.dataTransfer.files)
    }
    window.addEventListener('dragover', over)
    window.addEventListener('dragleave', leave)
    window.addEventListener('drop', drop)
    return () => {
      window.removeEventListener('dragover', over)
      window.removeEventListener('dragleave', leave)
      window.removeEventListener('drop', drop)
    }
  }, [addFiles])

  if (!shots.length) return <Dropzone dragging={dragging} onFiles={addFiles} />

  return (
    <div className="app">
      <header className="bar">
        <div className="brand">
          Redpen<span className="dot" />
        </div>
        <div className="counter">
          {index + 1} / {shots.length}
        </div>
        <div className="actions">
          <label className="ghost">
            Add
            <input
              type="file"
              accept="image/*"
              multiple
              hidden
              onChange={(e) => e.target.files && addFiles(e.target.files)}
            />
          </label>
          <button className="ghost" onClick={() => exportOne(shot, index)}>
            Export
          </button>
          <button className="primary" onClick={exportAll} disabled={busy}>
            {busy ? 'Exporting…' : `Download all (${shots.length})`}
          </button>
        </div>
      </header>

      <main className="stage">
        <NavButton dir={-1} disabled={index === 0} onClick={() => go(-1)} />
        <AnimatePresence mode="wait">
          <motion.div
            key={shot.id}
            className="canvasWrap"
            initial={{ opacity: 0, scale: 0.92 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 1.04 }}
            transition={{ type: 'spring', stiffness: 420, damping: 34, mass: 0.7 }}
          >
            <Sketchpad
              shot={shot}
              onStroke={(stroke) =>
                patch(shot.id, (s) => ({ ...s, strokes: [...s.strokes, stroke] }))
              }
            />
          </motion.div>
        </AnimatePresence>
        <NavButton
          dir={1}
          disabled={index === shots.length - 1}
          onClick={() => go(1)}
        />
      </main>

      <footer className="note">
        <button
          className={`mic ${recording ? 'on' : ''}`}
          onClick={toggle}
          title={dictationSupported() ? 'Dictate (Space)' : 'Not supported in this browser'}
          disabled={!dictationSupported()}
        >
          <MicIcon />
          {recording && <span className="pulse" />}
        </button>
        <div className="noteBody">
          <textarea
            value={shot.note}
            placeholder={
              dictationSupported()
                ? 'Hit the mic and talk. Or type here.'
                : 'Dictation needs Chrome or Safari. Type your note here.'
            }
            onChange={(e) =>
              patch(shot.id, (s) => ({ ...s, note: e.target.value }))
            }
          />
          {interim && <div className="interim">{interim}</div>}
        </div>
        <div className="hints">
          <span>
            <kbd>←</kbd>
            <kbd>→</kbd> move
          </span>
          <span>
            <kbd>Space</kbd> mic
          </span>
          <span>
            <kbd>⌘Z</kbd> undo
          </span>
        </div>
      </footer>

      <div className="film">
        {shots.map((s, i) => (
          <button
            key={s.id}
            className={`thumb ${i === index ? 'active' : ''}`}
            onClick={() => {
              stop()
              setIndex(i)
            }}
          >
            <img src={s.src} alt="" />
            {s.note.trim() && <span className="badge" />}
          </button>
        ))}
      </div>

      {dragging && <div className="dropVeil">Drop to add</div>}
    </div>
  )
}

function NavButton({
  dir,
  disabled,
  onClick,
}: {
  dir: -1 | 1
  disabled: boolean
  onClick: () => void
}) {
  return (
    <button className="nav" onClick={onClick} disabled={disabled}>
      {dir === -1 ? '‹' : '›'}
    </button>
  )
}

/** Image + red-pen overlay. Draws freehand strokes in normalized coordinates. */
function Sketchpad({
  shot,
  onStroke,
}: {
  shot: Shot
  onStroke: (s: Stroke) => void
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const boxRef = useRef<HTMLDivElement>(null)
  const [size, setSize] = useState({ w: 0, h: 0 })
  const drawing = useRef<Point[] | null>(null)

  useLayoutEffect(() => {
    const el = boxRef.current
    if (!el) return
    const ro = new ResizeObserver(([entry]) => {
      const { width, height } = entry.contentRect
      setSize({ w: width, h: height })
    })
    ro.observe(el)
    return () => ro.disconnect()
  }, [])

  const paint = useCallback(
    (live?: Point[]) => {
      const canvas = canvasRef.current
      if (!canvas || !size.w) return
      const dpr = window.devicePixelRatio || 1
      canvas.width = size.w * dpr
      canvas.height = size.h * dpr
      const ctx = canvas.getContext('2d')!
      ctx.scale(dpr, dpr)
      ctx.clearRect(0, 0, size.w, size.h)
      const strokes = live ? [...shot.strokes, { points: live }] : shot.strokes
      drawStrokes(ctx, strokes, size.w, size.h, 3)
    },
    [shot.strokes, size],
  )

  useEffect(() => paint(), [paint])

  const toPoint = (e: React.PointerEvent): Point => {
    const r = e.currentTarget.getBoundingClientRect()
    return [(e.clientX - r.left) / r.width, (e.clientY - r.top) / r.height]
  }

  return (
    <div className="pad" ref={boxRef} style={{ aspectRatio: `${shot.width} / ${shot.height}` }}>
      <img src={shot.src} alt={shot.name} draggable={false} />
      <canvas
        ref={canvasRef}
        style={{ width: size.w, height: size.h }}
        onPointerDown={(e) => {
          e.currentTarget.setPointerCapture(e.pointerId)
          drawing.current = [toPoint(e)]
        }}
        onPointerMove={(e) => {
          if (!drawing.current) return
          drawing.current.push(toPoint(e))
          paint(drawing.current)
        }}
        onPointerUp={() => {
          const points = drawing.current
          drawing.current = null
          if (points && points.length > 1) onStroke({ points })
          else paint()
        }}
      />
    </div>
  )
}

function Dropzone({
  dragging,
  onFiles,
}: {
  dragging: boolean
  onFiles: (f: FileList) => void
}) {
  return (
    <label className={`zone ${dragging ? 'hot' : ''}`}>
      <input
        type="file"
        accept="image/*"
        multiple
        hidden
        onChange={(e) => e.target.files && onFiles(e.target.files)}
      />
      <div className="zoneMark">
        Redpen<span className="dot" />
      </div>
      <p>Drop your app screenshots here</p>
      <small>Circle what's broken. Say why. Export the whole set.</small>
    </label>
  )
}

function MicIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <rect x="9" y="2" width="6" height="11" rx="3" />
      <path d="M5 11a7 7 0 0 0 14 0M12 18v4" />
    </svg>
  )
}
