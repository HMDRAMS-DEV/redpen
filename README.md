# Redpen

Redpen is a desktop screenshot-review tool. Drop in app screenshots, draw directly on them, type or dictate feedback, then download each marked-up image or the whole set as a ZIP.

**[Try Redpen](https://redpen.ramihmd.com)**

## What it does

- Imports PNG, JPEG, and WebP screenshots locally in the browser.
- Draws freehand red annotations without changing the original files.
- Transcribes microphone audio with Whisper on the visitor's device.
- Renders each screenshot, annotation, and note into a portable PNG.
- Downloads the complete review as a store-only ZIP archive.

Use the info button in the app for keyboard shortcuts. Arrow keys move between screenshots even while the note field is focused.

## Privacy and architecture

Redpen has no backend, accounts, analytics, or upload endpoint. Screenshots, annotations, notes, and microphone frames stay in the browser tab.

Dictation runs in a Web Worker with [`@huggingface/transformers`](https://github.com/huggingface/transformers.js) and `onnx-community/whisper-base.en`. The browser downloads model/runtime assets from Hugging Face and jsDelivr, then caches them. Audio is not sent to an application server and there is no per-use model API charge.

The app is intentionally desktop-only. Mobile screens receive a short notice instead of initializing the editor or speech model.

## Run locally

Requires Node.js 22.12 or newer.

```sh
npm ci
npm run dev
```

Then open the local URL printed by Vite.

## Verify

```sh
npm run lint
npm test
npm run build
npm audit
```

The browser tests use Playwright. Install its Chromium runtime once if needed:

```sh
npx playwright install chromium
```

## Stack

React 19, TypeScript, Vite, Transformers.js, Canvas, Web Audio, and Playwright. Production is a static Vercel deployment with an enforced content security policy.

## License

[MIT](LICENSE)
