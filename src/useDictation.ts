import { useCallback, useEffect, useRef, useState } from 'react'

const SAMPLE_RATE = 16000
const REFRESH_MS = 1500
const MAX_SECONDS = 180

export type MicStatus = 'idle' | 'loading' | 'listening' | 'finishing'

export const dictationSupported = () =>
  typeof AudioWorkletNode !== 'undefined' && Boolean(navigator.mediaDevices?.getUserMedia)

// Forwards raw mono frames to the main thread; the model needs Float32 @ 16kHz.
const CAPTURE_WORKLET = `
class Cap extends AudioWorkletProcessor {
  process(inputs) {
    const ch = inputs[0] && inputs[0][0]
    if (ch) this.port.postMessage(new Float32Array(ch))
    return true
  }
}
registerProcessor('cap', Cap)
`

function concat(chunks: Float32Array[], length: number) {
  const out = new Float32Array(length)
  let at = 0
  for (const c of chunks) {
    out.set(c, at)
    at += c.length
  }
  return out
}

/**
 * Whisper invents fluent sentences when fed silence, so never hand it a clip
 * that carries no speech. Measured against a muted mic and a quiet room.
 */
const SILENCE_RMS = 0.008

function loudEnough(audio: Float32Array) {
  let sum = 0
  for (let i = 0; i < audio.length; i++) sum += audio[i] * audio[i]
  return Math.sqrt(sum / audio.length) > SILENCE_RMS
}

/**
 * Dictation via Whisper running locally in a worker.
 *
 * The browser's Web Speech API was the obvious choice but it proxies audio to
 * Google's servers, which Chromium forks (Arc, Brave) cannot reach at all.
 * This runs on-device instead: no key, no network, no vendor.
 *
 * Whisper re-reads the whole clip on each pass rather than emitting deltas, so
 * `interim` is the current best transcript of everything said so far and it
 * self-corrects as context accumulates. `onFinal` fires once, on stop.
 */
export function useDictation(onFinal: (text: string) => void) {
  const [status, setStatus] = useState<MicStatus>('idle')
  const [progress, setProgress] = useState(0)
  const [interim, setInterim] = useState('')
  const [error, setError] = useState<string | null>(null)

  const workerRef = useRef<Worker | null>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const ctxRef = useRef<AudioContext | null>(null)
  const chunksRef = useRef<Float32Array[]>([])
  const lengthRef = useRef(0)
  const busyRef = useRef(false)
  const timerRef = useRef(null as number | null)
  const reqIdRef = useRef(0)
  const finalIdRef = useRef(-1)
  const finishingRef = useRef(false)
  const onFinalRef = useRef(onFinal)
  onFinalRef.current = onFinal

  const getWorker = useCallback(() => {
    if (workerRef.current) return workerRef.current
    const w = new Worker(new URL('./whisper.worker.ts', import.meta.url), {
      type: 'module',
    })
    w.onmessage = (e: MessageEvent) => {
      const msg = e.data
      if (msg.type === 'progress') setProgress(msg.pct)
      else if (msg.type === 'ready') setProgress(100)
      else if (msg.type === 'error') {
        setError(msg.message)
        setStatus('idle')
        busyRef.current = false
      } else if (msg.type === 'result') {
        busyRef.current = false
        // A pass launched before stop() covers less audio than the final one.
        // Showing it is fine; committing it would truncate the note.
        if (finishingRef.current && msg.id !== finalIdRef.current) {
          setInterim(msg.text)
          return
        }
        setInterim(msg.text)
        if (finishingRef.current) {
          finishingRef.current = false
          if (msg.text) onFinalRef.current(msg.text)
          setInterim('')
          setStatus('idle')
        }
      }
    }
    workerRef.current = w
    return w
  }, [])

  // Warm the model on mount so the first click isn't a cold 50MB wait.
  useEffect(() => {
    if (dictationSupported()) getWorker().postMessage({ type: 'load' })
  }, [getWorker])

  const transcribe = useCallback(
    (isFinal = false) => {
      // The final pass must run even if a rolling pass is still in flight.
      if ((busyRef.current && !isFinal) || !lengthRef.current) return
      const audio = concat(chunksRef.current, lengthRef.current)
      if (!loudEnough(audio)) {
        // Nothing was said. Finish cleanly rather than commit a hallucination.
        if (isFinal) {
          finishingRef.current = false
          setInterim('')
          setStatus('idle')
        }
        return
      }
      const id = ++reqIdRef.current
      if (isFinal) finalIdRef.current = id
      busyRef.current = true
      getWorker().postMessage({ type: 'transcribe', audio, id }, [audio.buffer])
    },
    [getWorker],
  )

  const teardown = useCallback(() => {
    if (timerRef.current) window.clearInterval(timerRef.current)
    timerRef.current = null
    streamRef.current?.getTracks().forEach((t) => t.stop())
    streamRef.current = null
    ctxRef.current?.close().catch(() => {})
    ctxRef.current = null
  }, [])

  const stop = useCallback(() => {
    if (status === 'idle') return
    teardown()
    if (!lengthRef.current) {
      setStatus('idle')
      setInterim('')
      return
    }
    // One last pass over the full clip, then commit it to the note.
    finishingRef.current = true
    setStatus('finishing')
    transcribe(true)
  }, [status, teardown, transcribe])

  const start = useCallback(async () => {
    setError(null)
    chunksRef.current = []
    lengthRef.current = 0
    setInterim('')
    setStatus('loading')
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true },
      })
      streamRef.current = stream
      const ctx = new AudioContext({ sampleRate: SAMPLE_RATE })
      ctxRef.current = ctx
      const url = URL.createObjectURL(
        new Blob([CAPTURE_WORKLET], { type: 'application/javascript' }),
      )
      await ctx.audioWorklet.addModule(url)
      URL.revokeObjectURL(url)

      const node = new AudioWorkletNode(ctx, 'cap')
      node.port.onmessage = (e: MessageEvent<Float32Array>) => {
        if (lengthRef.current >= SAMPLE_RATE * MAX_SECONDS) return
        chunksRef.current.push(e.data)
        lengthRef.current += e.data.length
      }
      ctx.createMediaStreamSource(stream).connect(node)
      // Keeps the worklet pulling without routing mic audio back to the speakers.
      node.connect(ctx.destination)

      setStatus('listening')
      timerRef.current = window.setInterval(transcribe, REFRESH_MS)
    } catch (err: any) {
      teardown()
      setStatus('idle')
      setError(
        err?.name === 'NotAllowedError'
          ? 'Microphone blocked. Allow it in the address bar, then try again.'
          : err?.name === 'NotFoundError'
            ? 'No microphone found.'
            : `Could not start the microphone: ${err?.message ?? err}`,
      )
    }
  }, [teardown, transcribe])

  const toggle = useCallback(() => {
    if (status === 'idle') start()
    else stop()
  }, [status, start, stop])

  useEffect(
    () => () => {
      teardown()
      workerRef.current?.terminate()
    },
    [teardown],
  )

  return {
    status,
    progress,
    interim,
    error,
    toggle,
    stop,
    recording: status === 'listening',
  }
}
