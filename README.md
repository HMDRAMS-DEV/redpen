# Redpen

A menu bar app for marking up screenshots the way a teacher marks a page. Circle anything and say why. Your words appear beside the circle in red pen. Then paste the set into a chat with a model.

**[Download for Mac](https://github.com/HMDRAMS-DEV/redpen/releases/latest)** · [redpen.ramihmd.com](https://redpen.ramihmd.com)

Requires macOS 15 or later. Signed with a Developer ID and notarized by Apple.

## How it works

- **Circle anything.** A rough loop becomes a clean red-pen circle. Redpen starts listening straight away, and the transcript is written beside the circle, outside it.
- **Click anywhere** to leave a note at that spot. Click a note to edit it.
- **Talk for a while.** Notes over 90 characters move under the image, numbered to match a circled number on the image. The exported PNG gets taller to fit them, so a model reads them as plain text.
- **Lines, ticks, and crosses** stay as you drew them, just smoothed. They don't open a note.
- **One image at a time**, with the set in a carousel along the bottom. Use ← and → to move between images.

## Getting images in

- **Screenshots.** Redpen finds your screenshots through Spotlight's `kMDItemIsScreenCapture` tag, wherever they're saved. New ones turn the menu bar loop red, circling how many are waiting, and after a burst Redpen sends one notification asking if you want to mark them up. You can turn this off in Settings. The first screen and Settings ask for notification permission, and link to Focus settings, where you can add Redpen to a Focus's allowed apps so the notification gets through.
- **iPhone and iPad screenshots.** If you allow Photos access, Redpen also finds screenshots that reach this Mac through iCloud Photos, copies them to its cache, and asks about them the same way.
- **Photos.** The system Photos picker, which needs no library permission. Library access is only for finding iCloud screenshots.
- **Files.** Open, drop on the window or the Dock icon, use Open With, or press ⌘V.

## Voice

| Engine | What happens |
|---|---|
| **Superwhisper** (default when installed) | Redpen opens `superwhisper://record` when you circle or click, and keeps focus on the note. Stop recording with your Superwhisper shortcut, or press ⌘⏎ (Redpen sends `superwhisper://stop`). Superwhisper pastes the transcript into the note, and Redpen finishes the note a moment later. |
| **Mac dictation** | Apple's speech recognizer, on this Mac when supported. The note finishes when you pause. |
| **Type only** | No listening. |

If Superwhisper isn't installed, the first screen, the popover, and Settings link to [superwhisper.com](https://superwhisper.com).

## Export

- **Copy** (⌘C) puts the marked-up PNG on the clipboard as image data and as a file, so it pastes into ChatGPT, Claude, or Slack.
- **Copy all** (⇧⌘C) copies every image as files.
- **Save all** (⌘S) writes `redpen-01-name.png` and so on to a folder you choose.

## Build

Requirements: macOS 15 or later, Xcode 16 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
xcodebuild -project Redpen.xcodeproj -scheme Redpen -destination 'platform=macOS' test
open Redpen.xcodeproj   # then Run
```

To render the editor, the empty state, the popover, and a sample export to PNGs for design review:

```sh
TEST_RUNNER_REDPEN_SNAPSHOTS=1 xcodebuild -project Redpen.xcodeproj -scheme Redpen -destination 'platform=macOS' test -only-testing:RedpenTests/SnapshotRender
```

The images land in `$TMPDIR/RedpenSnapshots`.

`scripts/make-dmg.sh` builds Release and writes `site/downloads/Redpen.dmg`. It signs with the HMDFV Inc. Developer ID; `scripts/release.sh` notarizes it. The app icon is drawn by `scripts/render-icon.swift`.

Redpen isn't sandboxed, because it reads screenshots wherever macOS saves them and opens Superwhisper's deep links.

## Updates and releases

Both the app and the site use [Sparkle](https://sparkle-project.org). The app reads `site/appcast.xml` from the website once a day. An update found right after launch opens Sparkle's window; one found later waits as an "Update available" tile in the popover. **Check for Updates…** is in the popover's ⋯ menu and in Settings.

To ship a release, bump `CFBundleShortVersionString` and `CFBundleVersion` in `project.yml`, commit, then run:

```sh
scripts/release.sh "What changed, in a sentence or two."
```

It builds the disk image, notarizes it when a `ramihmd-notary` notarytool profile exists, signs it for Sparkle, creates the GitHub release, adds the release to `site/appcast.xml`, commits, pushes, and deploys the site. The Sparkle signing key lives in the login keychain; back it up with `generate_keys -x` (the tool is in Xcode's SourcePackages at `artifacts/sparkle/Sparkle/bin`).

## Site

`site/` is the landing page at redpen.ramihmd.com, a static Vercel deployment. Deploy from `site/` with `vercel deploy --prod`.

The earlier browser version of Redpen lives in git history before this commit.

## Code map

Under `Redpen/`:


- `Model/Ink.swift`: turns a raw stroke into a circle or a smoothed line.
- `Model/Markup.swift`: note placement, the notes panel, drawing, and PNG export. The editor and the export share it.
- `Store/ReviewStore.swift`: images, the pen, the active note, new screenshots, and copying.
- `Voice/Voice.swift`: Superwhisper deep links and Apple speech.
- `Capture/ScreenshotWatcher.swift`: the Spotlight query for screenshots.
- `Capture/PhotosWatcher.swift`: screenshots from other devices, through iCloud Photos.

## License

[MIT](LICENSE)
