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
| **Dictate** | `⌘⏎`, or click the mic. Works while the cursor is in the note field. Live interim text shows as you talk; final text lands in the note. Editable by hand. |
| **Navigate** | `←` / `→`, the on-screen arrows, or the filmstrip. A red dot marks shots that already have a note. |
| **Download** | `⌘D` for the current shot, `⌘⇧D` for the whole set as `redpen.zip`. |

## Stack

Vite + React + TypeScript, no runtime dependencies beyond React. No backend, no accounts, no uploads — every image stays in the
browser tab. Dictation uses the browser's built-in Web Speech API (Chrome and Safari;
Firefox has no support and the mic button is disabled there).

## Develop

```sh
npm install
npm run dev
npm run build
```
