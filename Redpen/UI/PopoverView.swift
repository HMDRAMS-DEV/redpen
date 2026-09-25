import SwiftUI

/// Sits on the system menu material, so it reads like part of macOS. New screenshots come
/// first, then the review in progress, then ways to bring images in.
struct PopoverView: View {
    @Environment(ReviewStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Wordmark(size: 20)

            if let version = Updater.shared.available {
                UpdateTile(version: version)
            }

            if !store.pending.isEmpty {
                PendingTile()
            }

            if !store.shots.isEmpty {
                continueTile
            }

            let recent = store.captures.filter { capture in !store.pending.contains(capture) }.prefix(6)
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent screenshots")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach(Array(recent)) { capture in
                            Button { store.add(urls: [capture.url]) } label: {
                                CaptureThumb(url: capture.url, height: 58)
                            }
                            .buttonStyle(.plain)
                            .help("Mark up \(capture.url.lastPathComponent)")
                        }
                    }
                }
            }

            VStack(spacing: 0) {
                ActionRow(symbol: "photo.on.rectangle", title: "Choose from Photos") {
                    store.photoPickerRequested = true
                    store.requestEditor()
                }
                ActionRow(symbol: "folder", title: "Open images…") {
                    store.fileImporterRequested = true
                    store.requestEditor()
                }
                ActionRow(symbol: "doc.on.clipboard", title: "Paste image") {
                    if !store.paste() { store.show("No image on the clipboard.") }
                }
            }
            .padding(4)
            .tile()

            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var continueTile: some View {
        let marked = store.shots.filter(\.hasMarkup).count
        return Button { open(WindowID.editor) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Continue review").font(.system(size: 13, weight: .semibold))
                    Text("\(store.shots.count) \(store.shots.count == 1 ? "image" : "images") · \(marked) marked")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .contentShape(Rectangle())
            .tile()
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            voiceStatus
            Spacer()
            IconButton(symbol: "gearshape", help: "Settings") { open(WindowID.settings) }
            Menu {
                Button("Open Redpen") { open(WindowID.editor) }
                Button("Settings…") { open(WindowID.settings) }
                Button("Check for Updates…") { Updater.shared.check() }
                Divider()
                Button("Quit Redpen") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
            .help("More")
        }
    }

    @ViewBuilder private var voiceStatus: some View {
        if store.voice.engine == .superwhisper {
            Label("Voice: Superwhisper", systemImage: "waveform")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        } else if !store.voice.superwhisperInstalled {
            Link(destination: Voice.superwhisperSite) {
                Label("Try Superwhisper", systemImage: "waveform")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .help("Redpen works best with Superwhisper for dictation.")
        } else {
            Label("Voice: \(store.voice.engine.title)", systemImage: "waveform")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private func open(_ id: String) {
        openWindow(id: id)
        NSApp.activate()
    }
}

/// An update a background check found. Sparkle takes over from the button.
struct UpdateTile: View {
    let version: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.pen)
            VStack(alignment: .leading, spacing: 2) {
                Text("Update available")
                    .font(.system(size: 13, weight: .semibold))
                Text("Redpen \(version) is ready.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Update") { Updater.shared.check() }
                .buttonStyle(PillButtonStyle(compact: true))
        }
        .padding(10)
        .tile()
    }
}

/// New screenshots, stacked like a pile of pages, with one button to start marking them up.
struct PendingTile: View {
    @Environment(ReviewStore.self) private var store

    var body: some View {
        let count = store.pending.count
        HStack(spacing: 12) {
            ZStack {
                ForEach(Array(store.pending.prefix(3).enumerated().reversed()), id: \.element.id) { offset, capture in
                    CaptureThumb(url: capture.url, height: 40)
                        .frame(width: 56)
                        .rotationEffect(.degrees(Double(offset) * -5))
                        .offset(x: CGFloat(offset) * -4, y: CGFloat(offset) * -2)
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                }
            }
            .frame(width: 64, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(count == 1 ? "New screenshot" : "\(count) new screenshots")
                    .font(.system(size: 13, weight: .semibold))
                Text("Circle it, then say why.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Mark up") { store.addPending() }
                .buttonStyle(PillButtonStyle(compact: true))
            IconButton(symbol: "xmark", help: "Not now", size: 20) { store.dismissPending() }
        }
        .padding(10)
        .tile()
    }
}
