import { useCallback, useEffect, useRef, useState } from 'react'

type SpeechRecognition = any

const ERRORS: Record<string, string> = {
  'not-allowed': 'Microphone blocked. Allow it in the address bar, then try again.',
  'service-not-allowed': 'Microphone blocked by the browser or OS.',
  'audio-capture': 'No microphone found.',
  network:
    "Couldn't reach Google's speech servers, which this browser relies on. " +
    'Chromium forks (Arc, Brave) usually fail here — try Chrome. A VPN, ' +
    'firewall, or custom DNS will also block it.',
}

function getRecognition(): SpeechRecognition | null {
  const Ctor =
    (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition
  return Ctor ? new Ctor() : null
}

export const dictationSupported = () =>
  Boolean((window as any).SpeechRecognition || (window as any).webkitSpeechRecognition)

/**
 * Live dictation via the browser's Web Speech API.
 * `onFinal` fires with each committed chunk; `interim` is the in-flight guess.
 */
export function useDictation(onFinal: (text: string) => void) {
  const [recording, setRecording] = useState(false)
  const [interim, setInterim] = useState('')
  const [error, setError] = useState<string | null>(null)
  const recRef = useRef<SpeechRecognition | null>(null)
  const wantOnRef = useRef(false)
  const localRef = useRef(false)
  const retriedRef = useRef(false)
  const onFinalRef = useRef(onFinal)
  onFinalRef.current = onFinal

  // Chrome 138+ can run recognition on-device, which skips Google's servers
  // entirely — the only real cure for a `network` error. Probe once at mount so
  // start() stays synchronous inside the user gesture.
  useEffect(() => {
    const Ctor = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition
    if (!Ctor?.available) return
    let cancelled = false
    const opts = { langs: ['en-US'], processLocally: true }
    Ctor.available(opts)
      .then(async (status: string) => {
        if (status === 'downloadable' || status === 'downloading') {
          await Ctor.install(opts).catch(() => false)
          if (!cancelled) localRef.current = (await Ctor.available(opts)) === 'available'
        } else if (status === 'available' && !cancelled) {
          localRef.current = true
        }
      })
      .catch(() => {})
    return () => {
      cancelled = true
    }
  }, [])

  const stop = useCallback(() => {
    wantOnRef.current = false
    recRef.current?.stop()
    setRecording(false)
    setInterim('')
  }, [])

  const start = useCallback(() => {
    const rec = getRecognition()
    if (!rec) {
      setError('This browser has no speech recognition. Use Chrome, Edge, or Safari.')
      return
    }
    setError(null)
    rec.continuous = true
    rec.interimResults = true
    rec.lang = 'en-US'
    if (localRef.current) rec.processLocally = true

    rec.onresult = (e: any) => {
      let live = ''
      for (let i = e.resultIndex; i < e.results.length; i++) {
        const r = e.results[i]
        if (r.isFinal) onFinalRef.current(r[0].transcript.trim())
        else live += r[0].transcript
      }
      setInterim(live)
    }
    // Chrome ends the session on silence — restart while the user still wants it on.
    rec.onend = () => {
      if (wantOnRef.current) {
        try {
          rec.start()
        } catch {
          // Safari refuses to restart outside a user gesture; drop back to idle.
          wantOnRef.current = false
          setRecording(false)
        }
      } else {
        setRecording(false)
      }
    }
    rec.onerror = (e: any) => {
      // 'no-speech' and 'aborted' are routine; onend handles the restart.
      if (e.error === 'no-speech' || e.error === 'aborted') return
      // A single network blip is common on the first connection; retry once
      // before giving up on the user.
      if (e.error === 'network' && !retriedRef.current && wantOnRef.current) {
        retriedRef.current = true
        return
      }
      setError(ERRORS[e.error] ?? `Dictation error: ${e.error}`)
      wantOnRef.current = false
      setRecording(false)
      setInterim('')
    }

    recRef.current = rec
    wantOnRef.current = true
    retriedRef.current = false
    try {
      rec.start()
      setRecording(true)
    } catch {
      setError('Could not start the microphone. Reload and try again.')
      wantOnRef.current = false
    }
  }, [])

  const toggle = useCallback(() => {
    if (wantOnRef.current) stop()
    else start()
  }, [start, stop])

  useEffect(() => () => {
    wantOnRef.current = false
    recRef.current?.abort()
  }, [])

  return { recording, interim, error, toggle, stop }
}
