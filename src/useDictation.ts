import { useCallback, useEffect, useRef, useState } from 'react'

type SpeechRecognition = any

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
  const recRef = useRef<SpeechRecognition | null>(null)
  const wantOnRef = useRef(false)
  const onFinalRef = useRef(onFinal)
  onFinalRef.current = onFinal

  const stop = useCallback(() => {
    wantOnRef.current = false
    recRef.current?.stop()
    setRecording(false)
    setInterim('')
  }, [])

  const start = useCallback(() => {
    const rec = getRecognition()
    if (!rec) return
    rec.continuous = true
    rec.interimResults = true
    rec.lang = 'en-US'

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
      if (wantOnRef.current) rec.start()
      else setRecording(false)
    }
    rec.onerror = (e: any) => {
      if (e.error === 'not-allowed' || e.error === 'service-not-allowed') {
        wantOnRef.current = false
        setRecording(false)
      }
    }

    recRef.current = rec
    wantOnRef.current = true
    rec.start()
    setRecording(true)
  }, [])

  const toggle = useCallback(() => {
    if (wantOnRef.current) stop()
    else start()
  }, [start, stop])

  useEffect(() => () => {
    wantOnRef.current = false
    recRef.current?.abort()
  }, [])

  return { recording, interim, toggle, stop }
}
