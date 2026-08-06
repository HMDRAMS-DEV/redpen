# Redpen

Drop app screenshots, circle what's broken, say why, download the set.

Built for reviewing mobile app builds: drag in a batch of screenshots, mark them up in red,
talk your feedback instead of typing it, and download each one as a single image with the
markup on the screenshot and the note rendered underneath — ready to paste into Linear,
Slack, or a ticket.

## How it works

| | |
|---|---|
| **Upload** | Drag screenshots anywhere on the page, or click to pick. Multiple at once. |
| **Mark up** | The cursor is a red pen over the image. Draw freehand. `⌘Z` undoes the last stroke. |
| **Dictate** | `⌘⏎`, or click the mic. Works while the cursor is in the note field. Text appears live and refines as you keep talking; it lands in the note when you stop. Editable by hand. |
| **Navigate** | `←` / `→`, the on-screen arrows, or the filmstrip. A red dot marks shots that already have a note. |
| **Download** | `⌘D` for the current shot, `⌘⇧D` for the whole set as `redpen.zip`. |

## Stack

Vite + React + TypeScript. No backend, no accounts, no uploads — every image stays
in the browser tab.

Dictation runs **Whisper locally**, on your machine, via `transformers.js`
(`onnx-community/whisper-base.en`, WebGPU when available and WASM otherwise). No
API key, no per-minute cost, and your audio never leaves the browser. The model
is a one-time ~50MB download that the browser then caches; a progress bar shows
it on first use.

The browser's built-in Web Speech API was the obvious choice and it does not
work: it proxies audio to Google's servers, and Chromium forks like Arc and
Brave ship without the required API key, so it fails with `network` every time.

## Develop

```sh
npm install
npm run dev
npm run build
```
