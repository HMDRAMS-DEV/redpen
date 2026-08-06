import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react'
import type { Point, Shot, Stroke } from './types'
import { dictationSupported, useDictation } from './useDictation'
import { download, drawStrokes, exportName, renderShot } from './render'
import { makeZip } from './zip'

const isMac = /Mac|iP(hone|ad)/.test(navigator.platform || navigator.userAgent)
const MOD = isMac ? '⌘' : 'Ctrl'

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
  const [zoom, setZoom] = useState(false)
  const [entering, setEntering] = useState(false)

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

  const { recording, status, progress, interim, error, toggle, stop } =
    useDictation(appendNote)

  const undo = useCallback(() => {
    if (!shot) return
    patch(shot.id, (s) => ({ ...s, strokes: s.strokes.slice(0, -1) }))
  }, [shot, patch])

  const go = useCallback(
    (delta: number) => {
      stop()
      setZoom(false)
      setIndex((i) => Math.min(shots.length - 1, Math.max(0, i + delta)))
    },
    [shots.length, stop],
  )

  const jump = useCallback(
    (i: number) => {
      stop()
      setZoom(true)
      setIndex(i)
    },
    [stop],
  )

  // Stepping with arrows is a high-frequency action, so it only crossfades.
  // Tapping a thumbnail is deliberate and rare, so that one zooms.
  useEffect(() => {
    setEntering(true)
    let inner = 0
    // Two frames: one to paint the "before" state, one to transition out of it.
    const outer = requestAnimationFrame(() => {
      inner = requestAnimationFrame(() => setEntering(false))
    })
    return () => {
      cancelAnimationFrame(outer)
      cancelAnimationFrame(inner)
    }
  }, [index])

  const exportOne = useCallback(async (s: Shot, i: number) => {
    download(await renderShot(s), exportName(s, i))
  }, [])

  // One archive rather than N downloads — Chrome gates multi-file downloads
  // behind a permission prompt that is easy to miss and easy to deny.
  const exportAll = useCallback(async () => {
    if (busy) return
    setBusy(true)
    try {
      const entries = []
      for (let i = 0; i < shots.length; i++) {
        const blob = await renderShot(shots[i])
        entries.push({
          name: exportName(shots[i], i),
          data: new Uint8Array(await blob.arrayBuffer()),
        })
      }
      download(makeZip(entries), 'redpen.zip')
    } finally {
      setBusy(false)
    }
  }, [shots, busy])

  // --- keyboard ---------------------------------------------------------
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const mod = isMac ? e.metaKey : e.ctrlKey
      const typing =
        e.target instanceof HTMLElement &&
        (e.target.tagName === 'TEXTAREA' || e.target.tagName === 'INPUT')

      // Mic is modifier-based so it still works while typing the note.
      if (mod && e.key === 'Enter') {
        e.preventDefault()
        toggle()
        return
      }
      if (mod && e.key.toLowerCase() === 'd') {
        e.preventDefault()
        if (e.shiftKey) exportAll()
        else if (shot) exportOne(shot, index)
        return
      }
      if (mod && e.key.toLowerCase() === 'z') {
        e.preventDefault()
        undo()
        return
      }
      if (typing) return
      if (e.key === 'ArrowRight') go(1)
      else if (e.key === 'ArrowLeft') go(-1)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [go, toggle, undo, exportAll, exportOne, shot, index])

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
            Download <kbd>{MOD}D</kbd>
          </button>
          <button className="primary" onClick={exportAll} disabled={busy}>
            {busy ? 'Zipping…' : `Download all · ${shots.length}`}
            <kbd>{MOD}⇧D</kbd>
          </button>
        </div>
      </header>

      <main className="stage">
        <NavButton dir={-1} disabled={index === 0} onClick={() => go(-1)} />
        <div
          className="canvasWrap"
          data-entering={entering || undefined}
          data-zoom={zoom || undefined}
        >
          <Sketchpad
            shot={shot}
            onStroke={(stroke) =>
              patch(shot.id, (s) => ({ ...s, strokes: [...s.strokes, stroke] }))
            }
          />
        </div>
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
          // Never take focus, so the button can't swallow keys meant for the page.
          onMouseDown={(e) => e.preventDefault()}
          disabled={!dictationSupported()}
        >
          <MicIcon />
          {recording && <span className="pulse" />}
        </button>
        <div className="micLabel">
          <strong>
            {status === 'listening'
              ? 'Listening…'
              : status === 'loading'
                ? 'Starting…'
                : status === 'finishing'
                  ? 'Writing…'
                  : 'Talk'}
          </strong>
          <kbd>{MOD}⏎</kbd>
        </div>
        <div className="noteBody">
          <textarea
            value={shot.note}
            placeholder={
              dictationSupported()
                ? `Press ${MOD}⏎ and talk. Or type here.`
                : 'This browser has no microphone access. Type your note here.'
            }
            onChange={(e) =>
              patch(shot.id, (s) => ({ ...s, note: e.target.value }))
            }
          />
          {interim && <div className="interim">{interim}</div>}
          {progress > 0 && progress < 100 && (
            <div className="modelLoad">
              <span style={{ width: `${progress}%` }} />
              Downloading the speech model, once ever · {progress}%
            </div>
          )}
          {error && <div className="micError">{error}</div>}
        </div>
        <div className="hints">
          <span>
            <kbd>←</kbd>
            <kbd>→</kbd> move
          </span>
          <span>
            <kbd>{MOD}Z</kbd> undo
          </span>
        </div>
      </footer>

      <div className="film">
        {shots.map((s, i) => (
          <button
            key={s.id}
            className={`thumb ${i === index ? 'active' : ''}`}
            onClick={() => jump(i)}
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
      <span className="chev">{dir === -1 ? '‹' : '›'}</span>
      <kbd>{dir === -1 ? '←' : '→'}</kbd>
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

  // Abandon an in-flight stroke if the shot changes mid-drag.
  useEffect(() => {
    drawing.current = null
  }, [shot.id])

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
    <div className="zoneWrap">
      <div className="zoneMark">
        Redpen<span className="dot" />
      </div>
      <label className={`zone ${dragging ? 'hot' : ''}`}>
        <input
          type="file"
          accept="image/*"
          multiple
          hidden
          onChange={(e) => e.target.files && onFiles(e.target.files)}
        />
        <DropIcon />
        <p>Drag your screenshots here</p>
        <span className="or">
          or <u>click to choose files</u>
        </span>
        <small>PNG or JPG · drop as many as you want</small>
      </label>
      <p className="zoneTag">Circle what's broken. Say why. Download the whole set.</p>
    </div>
  )
}

function DropIcon() {
  return (
    <svg
      className="dropIcon"
      width="56"
      height="56"
      viewBox="0 0 48 48"
      fill="none"
      strokeWidth="2.5"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M9 29v6a6 6 0 0 0 6 6h18a6 6 0 0 0 6-6v-6" stroke="currentColor" />
      <path d="M24 6v21M15 19l9 9 9-9" stroke="var(--pen)" />
    </svg>
  )
}

function MicIcon() {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <rect x="9" y="2" width="6" height="11" rx="3" />
      <path d="M5 11a7 7 0 0 0 14 0M12 18v4" />
    </svg>
  )
}
