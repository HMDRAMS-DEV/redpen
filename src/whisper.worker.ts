/// <reference lib="webworker" />
import { pipeline } from '@huggingface/transformers'

// base.en is the smallest model that reliably gets product jargon right.
// Quantized decoder keeps the download near 50MB.
const MODEL = 'onnx-community/whisper-base.en'
const MODEL_REVISION = '51eefc0af78b103839eda9e7e4f4186acc6517fe'

type Pipe = (audio: Float32Array, opts?: object) => Promise<{ text: string }>

let pipe: Pipe | null = null
let loading: Promise<Pipe> | null = null

/** Weighted across files so the bar reflects bytes, not file count. */
function reportProgress() {
  const files = new Map<string, { loaded: number; total: number }>()
  return (e: any) => {
    if (e.status === 'progress' && e.total) {
      files.set(e.file, { loaded: e.loaded, total: e.total })
      let loaded = 0
      let total = 0
      for (const f of files.values()) {
        loaded += f.loaded
        total += f.total
      }
      if (total) {
        self.postMessage({ type: 'progress', pct: Math.round((loaded / total) * 100) })
      }
    }
  }
}

async function getPipe() {
  if (pipe) return pipe
  if (!loading) {
    loading = (async () => {
      let device: 'webgpu' | 'wasm' = 'wasm'
      if ((navigator as any).gpu) {
        try {
          device = (await (navigator as any).gpu.requestAdapter()) ? 'webgpu' : 'wasm'
        } catch {
          device = 'wasm'
        }
      }
      const p = (await pipeline('automatic-speech-recognition', MODEL, {
        revision: MODEL_REVISION,
        dtype: { encoder_model: 'fp32', decoder_model_merged: 'q8' },
        device,
        progress_callback: reportProgress(),
      })) as unknown as Pipe
      self.postMessage({ type: 'ready', device })
      pipe = p
      return p
    })()
  }
  return loading
}

self.onmessage = async (e: MessageEvent) => {
  const { type, audio, id } = e.data
  if (type === 'load') {
    try {
      await getPipe()
    } catch (err: any) {
      self.postMessage({ type: 'error', message: err?.message ?? 'Model failed to load' })
    }
    return
  }
  if (type === 'transcribe') {
    try {
      const p = await getPipe()
      const out = await p(audio, { chunk_length_s: 30, stride_length_s: 5 })
      self.postMessage({ type: 'result', id, text: (out.text ?? '').trim() })
    } catch (err: any) {
      self.postMessage({ type: 'error', message: err?.message ?? 'Transcription failed' })
    }
  }
}
