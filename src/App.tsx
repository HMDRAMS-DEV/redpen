import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react'
import type { Point, Shot, Stroke } from './types'
import { dictationSupported, useDictation } from './useDictation'
import { download, drawStrokes, exportName, renderShot } from './render'
import { makeZip } from './zip'

const isMac = /Mac|iP(hone|ad)/.test(navigator.platform || navigator.userAgent)
const MOD = isMac ? '⌘' : 'Ctrl'
const SOURCE_URL = 'https://github.com/HMDRAMS-DEV/redpen'
const DESKTOP_QUERY = '(min-width: 768px)'
const MAX_FILE_BYTES = 25 * 1024 * 1024
const MAX_IMAGE_PIXELS = 40_000_000
const IMAGE_TYPES = new Set(['image/png', 'image/jpeg', 'image/webp'])

function readFile(file: File): Promise<Shot> {
  return new Promise((res, rej) => {
    const reader = new FileReader()
    reader.onload = () => {
      const src = reader.result as string
      const img = new Image()
      img.onload = () => {
        if (img.naturalWidth * img.naturalHeight > MAX_IMAGE_PIXELS) {
          rej(new Error('Image dimensions are too large.'))
          return
        }
        res({
          id: crypto.randomUUID(),
          name: file.name,
          src,
          width: img.naturalWidth,
          height: img.naturalHeight,
          strokes: [],
          note: '',
        })
      }
      img.onerror = rej
      img.src = src
    }
    reader.onerror = rej
    reader.readAsDataURL(file)
  })
}

function useDesktopViewport() {
  const [desktop, setDesktop] = useState(() => window.matchMedia(DESKTOP_QUERY).matches)

  useEffect(() => {
    const query = window.matchMedia(DESKTOP_QUERY)
    const update = () => setDesktop(query.matches)
    query.addEventListener('change', update)
    return () => query.removeEventListener('change', update)
  }, [])

  return desktop
}

export default function App() {
  return useDesktopViewport() ? <Editor /> : <MobileNotice />
}

function Editor() {
  const [shots, setShots] = useState<Shot[]>([])
  const [index, setIndex] = useState(0)
  const [dragging, setDragging] = useState(false)
  const [busy, setBusy] = useState(false)
  const [zoom, setZoom] = useState(false)
  const [entering, setEntering] = useState(false)
  const [fileError, setFileError] = useState<string | null>(null)
  const [showGuide, setShowGuide] = useState(false)

  const shot = shots[index]

  const addFiles = useCallback(async (files: FileList | File[]) => {
    const selected = Array.from(files)
    const images = selected.filter(
      (file) => IMAGE_TYPES.has(file.type) && file.size <= MAX_FILE_BYTES,
    )
    if (images.length !== selected.length) {
      setFileError('Use PNG, JPEG, or WebP screenshots up to 25 MB each.')
    } else {
      setFileError(null)
    }
    if (!images.length) return
    let added: Shot[]
    try {
      added = await Promise.all(images.map(readFile))
    } catch {
      setFileError('One screenshot could not be opened or has unusually large dimensions.')
      return
    }
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

  const { recording, progress, interim, error, toggle, stop } =
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

  const remove = useCallback(
    (id: string) => {
      stop()
      setZoom(false)
      setShots((prev) => {
        const next = prev.filter((item) => item.id !== id)
        setIndex((current) => Math.min(current, Math.max(0, next.length - 1)))
        return next
      })
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
      if (e.key === 'Escape') {
        setShowGuide(false)
        return
      }
      if (e.key === 'ArrowRight') {
        e.preventDefault()
        go(1)
      } else if (e.key === 'ArrowLeft') {
        e.preventDefault()
        go(-1)
      }
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

  if (!shots.length) {
    return <Dropzone dragging={dragging} error={fileError} onFiles={addFiles} />
  }

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
          <ShortcutGuide open={showGuide} onToggle={() => setShowGuide((open) => !open)} />
          <label className="ghost">
            Add
            <input
              type="file"
              accept="image/png,image/jpeg,image/webp"
              multiple
              hidden
              onChange={(e) => e.target.files && addFiles(e.target.files)}
            />
          </label>
          <button className="ghost" onClick={() => exportOne(shot, index)}>
            Download
          </button>
          <button className="primary" onClick={exportAll} disabled={busy}>
            {busy ? 'Zipping…' : `Download all · ${shots.length}`}
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
          aria-label={recording ? 'Stop dictation' : 'Start dictation'}
          title={recording ? 'Stop dictation' : 'Start dictation'}
        >
          <MicIcon />
          {recording && <span className="pulse" />}
        </button>
        <div className="noteBody">
          <textarea
            aria-label={`Note for ${shot.name}`}
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
      </footer>

      <div className="film">
        {shots.map((s, i) => (
          <div key={s.id} className={`thumbSlot ${i === index ? 'active' : ''}`}>
            <button
              className="thumb"
              aria-label={`View ${s.name}`}
              onClick={() => jump(i)}
            >
              <img src={s.src} alt="" />
              {s.note.trim() && <span className="badge" />}
            </button>
            <button
              className="thumbDelete"
              aria-label={`Delete ${s.name}`}
              title={`Delete ${s.name}`}
              onClick={() => remove(s.id)}
            >
              <TrashIcon />
            </button>
          </div>
        ))}
      </div>

      <SourceLink className="cornerSource" />
      {dragging && <div className="dropVeil">Drop to add</div>}
      {fileError && <div className="fileToast" role="alert">{fileError}</div>}
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
    <button
      className="nav"
      aria-label={dir === -1 ? 'Previous image' : 'Next image'}
      onClick={onClick}
      disabled={disabled}
    >
      <span className="chev">{dir === -1 ? '‹' : '›'}</span>
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
  error,
  onFiles,
}: {
  dragging: boolean
  error: string | null
  onFiles: (f: FileList) => void
}) {
  return (
    <div className="zoneShell">
      <SourceLink className="cornerSource" />
      <label className={`zone ${dragging ? 'hot' : ''}`}>
        <input
          type="file"
          accept="image/png,image/jpeg,image/webp"
          multiple
          hidden
          onChange={(e) => e.target.files && onFiles(e.target.files)}
        />
        <div className="zoneMark">
          Redpen<span className="dot" />
        </div>
        <p className="zoneTag">Circle what's broken. Say why. Download the whole set.</p>
        <ShotStack />
        <div className="zoneCta">
          <strong>Drop your screenshots anywhere</strong>
          <span>
            or <u>click to choose</u> · PNG, JPEG, or WebP · up to 25 MB each
          </span>
        </div>
        {error && <div className="fileError" role="alert">{error}</div>}
      </label>
    </div>
  )
}

function ShortcutGuide({ open, onToggle }: { open: boolean; onToggle: () => void }) {
  return (
    <div className="guide">
      <button
        className="guideButton"
        aria-label="Keyboard shortcuts"
        aria-expanded={open}
        aria-controls="shortcut-guide"
        title="Keyboard shortcuts"
        onClick={onToggle}
      >
        <InfoIcon />
      </button>
      {open && (
        <div className="guideCard" id="shortcut-guide">
          <h2>Keyboard shortcuts</h2>
          <p>These work while the note field is focused.</p>
          <dl>
            <div><dt><kbd>←</kbd> <kbd>→</kbd></dt><dd>Move between images</dd></div>
            <div><dt><kbd>{MOD}⏎</kbd></dt><dd>Start or stop dictation</dd></div>
            <div><dt><kbd>{MOD}Z</kbd></dt><dd>Undo the last mark</dd></div>
            <div><dt><kbd>{MOD}D</kbd></dt><dd>Download this image</dd></div>
            <div><dt><kbd>{MOD}⇧D</kbd></dt><dd>Download the full set</dd></div>
          </dl>
        </div>
      )}
    </div>
  )
}

function SourceLink({ className = '' }: { className?: string }) {
  return (
    <a
      className={`sourceLink ${className}`.trim()}
      href={SOURCE_URL}
      target="_blank"
      rel="noreferrer"
      aria-label="View source code on GitHub"
      title="View source code on GitHub"
    >
      <GitHubIcon />
    </a>
  )
}

function MobileNotice() {
  return (
    <main className="mobileNotice">
      <div className="mobileMark">Redpen<span className="dot" /></div>
      <h1>Redpen is made for desktop.</h1>
      <p>Open it on a Mac or PC to mark up screenshots, dictate notes, and export the set.</p>
      <SourceLink className="cornerSource" />
    </main>
  )
}

/** The product's own metaphor as the illustration: marked-up screenshots. */
function ShotStack() {
  return (
    <div className="stack" aria-hidden="true">
      <span className="card c1" />
      <span className="card c2" />
      <span className="card c3">
        <i style={{ width: '62%' }} />
        <i style={{ width: '84%' }} />
        <i style={{ width: '44%' }} />
        <i style={{ width: '72%' }} />
        {/* Deliberately imperfect: it overshoots and crosses itself, the way a
            real pen does. A clean ellipse reads as a shape, not a mark. */}
        <svg className="scribble" viewBox="0 0 116 88" fill="none">
          <path
            d="M94 40c-3-14-19-24-37-23S23 29 21 45c-2 16 14 28 32 29 18 1 35-8 38-24 3-15-11-28-29-31C44 16 29 24 25 39"
            stroke="var(--pen)"
            strokeWidth="3.2"
            strokeLinecap="round"
          />
        </svg>
      </span>
    </div>
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

function InfoIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
      <circle cx="12" cy="12" r="9" />
      <path d="M12 11v6M12 7.5h.01" />
    </svg>
  )
}

function TrashIcon() {
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" aria-hidden="true">
      <path d="M4 7h16M9 7V4h6v3M7 7l1 13h8l1-13M10 11v5M14 11v5" />
    </svg>
  )
}

function GitHubIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path fillRule="evenodd" d="M12 2C6.477 2 2 6.59 2 12.253c0 4.53 2.865 8.374 6.84 9.73.5.094.682-.222.682-.493 0-.244-.009-.89-.014-1.747-2.782.62-3.369-1.376-3.369-1.376-.455-1.186-1.11-1.502-1.11-1.502-.908-.636.069-.623.069-.623 1.004.072 1.532 1.058 1.532 1.058.892 1.567 2.341 1.115 2.91.853.091-.663.349-1.115.635-1.371-2.221-.259-4.555-1.14-4.555-5.068 0-1.12.39-2.035 1.03-2.752-.103-.26-.447-1.302.098-2.714 0 0 .84-.276 2.75 1.05A9.34 9.34 0 0 1 12 6.953a9.3 9.3 0 0 1 2.504.345c1.909-1.326 2.747-1.05 2.747-1.05.547 1.412.203 2.454.1 2.714.64.717 1.028 1.632 1.028 2.752 0 3.938-2.338 4.806-4.566 5.06.359.318.679.947.679 1.908 0 1.378-.012 2.49-.012 2.828 0 .274.18.592.688.492C19.138 20.628 22 16.786 22 12.253 22 6.59 17.523 2 12 2Z" clipRule="evenodd" />
    </svg>
  )
}
