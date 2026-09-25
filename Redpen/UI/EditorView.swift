import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// One screenshot at a time, big, with the set along the bottom.
struct EditorView: View {
    @Environment(ReviewStore.self) private var store
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var dropping = false

    var body: some View {
        @Bindable var store = store
        ZStack {
            Theme.canvas.ignoresSafeArea()
            if store.shots.isEmpty {
                EmptyStateView()
                    .transition(.opacity)
            } else {
                editor
                    .transition(.opacity)
            }
            if dropping {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.pen, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .background(Theme.penWash, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(Text("Drop to add").display(22).foregroundStyle(Theme.pen))
                    .padding(16)
                    .allowsHitTesting(false)
            }
            if let toast = store.toast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.canvas)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Theme.ink, in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 124)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.toast)
        .animation(.easeOut(duration: 0.2), value: store.shots.isEmpty)
        .frame(minWidth: 860, minHeight: 620)
        .background(shortcuts)
        .photosPicker(isPresented: $store.photoPickerRequested, selection: $photoItems, matching: .images)
        .fileImporter(isPresented: $store.fileImporterRequested, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { store.add(urls: urls) }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            photoItems = []
            Task {
                var data: [Data] = []
                for item in items {
                    if let loaded = try? await item.loadTransferable(type: Data.self) { data.append(loaded) }
                }
                store.add(imageData: data)
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $dropping) { providers in
            receive(providers)
            return true
        }
        // A menu bar app while you're not reviewing; a normal app with a Dock icon while you are.
        .onAppear { NSApp.setActivationPolicy(.regular) }
        .onDisappear {
            store.commitNote()
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            EditorBar()
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 10)

            if !store.pending.isEmpty {
                PendingTile()
                    .frame(width: 420)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack(spacing: 8) {
                IconButton(symbol: "chevron.left", help: "Previous (←)", size: 34) { store.step(-1) }
                    .opacity(store.index > 0 ? 1 : 0)
                if let shot = store.shot {
                    PageView(shot: shot)
                        .id(shot.id)
                        .transition(.opacity)
                }
                IconButton(symbol: "chevron.right", help: "Next (→)", size: 34) { store.step(1) }
                    .opacity(store.index < store.shots.count - 1 ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .animation(.easeOut(duration: 0.18), value: store.index)

            StatusLine()
                .frame(height: 30)

            Filmstrip()
                .padding(.bottom, 14)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.pending.isEmpty)
    }

    /// Keyboard shortcuts. Off while a note is being written, so the keys go to the note.
    private var shortcuts: some View {
        let writing = store.activeNoteID != nil
        let empty = store.shots.isEmpty
        return ZStack {
            Button("Previous") { store.step(-1) }.keyboardShortcut(.leftArrow, modifiers: []).disabled(writing)
            Button("Next") { store.step(1) }.keyboardShortcut(.rightArrow, modifiers: []).disabled(writing)
            Button("Undo") { store.undo() }.keyboardShortcut("z").disabled(writing || empty)
            Button("Copy") { store.copyCurrent() }.keyboardShortcut("c").disabled(writing || empty)
            Button("Copy All") { store.copyAll() }.keyboardShortcut("c", modifiers: [.command, .shift]).disabled(empty)
            Button("Save All") { store.saveAll() }.keyboardShortcut("s").disabled(empty)
            Button("Paste") {
                if !store.paste() { store.show("No image on the clipboard.") }
            }.keyboardShortcut("v").disabled(writing)
            Button("Open") { store.fileImporterRequested = true }.keyboardShortcut("o")
            Button("Talk") { store.toggleListening() }.keyboardShortcut(.return, modifiers: .command).disabled(!writing)
            Button("Remove") { if let shot = store.shot { store.remove(shot.id) } }
                .keyboardShortcut(.delete, modifiers: .command).disabled(writing || empty)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func receive(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in ReviewStore.shared.add(urls: [url]) }
                }
            } else {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in ReviewStore.shared.add(imageData: [data], name: "Dropped image") }
                }
            }
        }
    }
}

private struct EditorBar: View {
    @Environment(ReviewStore.self) private var store
    @State private var showHelp = false

    var body: some View {
        HStack(spacing: 10) {
            Wordmark(size: 22)
            Text("\(store.index + 1) of \(store.shots.count)")
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.muted)
                .padding(.leading, 6)
            Spacer()
            VoiceChip()
            IconButton(symbol: "questionmark.circle", help: "How it works", size: 30) { showHelp.toggle() }
                .popover(isPresented: $showHelp, arrowEdge: .bottom) { HelpCard() }
            Menu {
                Button("Choose from Photos…") { store.photoPickerRequested = true }
                Button("Open Images…") { store.fileImporterRequested = true }
                Button("Paste Image") { if !store.paste() { store.show("No image on the clipboard.") } }
                if !store.captures.isEmpty {
                    Divider()
                    Button("Latest Screenshot") { store.add(urls: [store.captures[0].url]) }
                }
                Divider()
                Button("Start Over", role: .destructive) { store.clear() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
            .help("Add images")
            IconButton(symbol: "square.and.arrow.down", help: "Save all as PNG (⌘S)", size: 30) { store.saveAll() }
            Button("Copy") { store.copyCurrent() }
                .buttonStyle(PillButtonStyle(prominent: false))
                .help("Copy this image (⌘C)")
            Button(store.shots.count > 1 ? "Copy all · \(store.shots.count)" : "Copy all") { store.copyAll() }
                .buttonStyle(PillButtonStyle())
                .help("Copy every image, ready to paste into a chat (⇧⌘C)")
        }
        .frame(height: 40)
    }
}

/// Which voice is on, and a live cue while it listens.
private struct VoiceChip: View {
    @Environment(ReviewStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let listening = store.voice.isListening
        Button {
            openWindow(id: WindowID.settings)
        } label: {
            Label(listening ? "Listening" : store.voice.engine.title,
                  systemImage: store.voice.engine == .typing ? "keyboard" : "waveform")
                .font(.system(size: 12, weight: .semibold))
                .symbolEffect(.variableColor.iterative, isActive: listening)
                .foregroundStyle(listening ? Theme.pen : Theme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(listening ? Theme.penWash : Theme.quietWash, in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Voice settings")
        .animation(.easeOut(duration: 0.2), value: listening)
    }
}

/// One line under the page that says what to do next.
private struct StatusLine: View {
    @Environment(ReviewStore.self) private var store

    var body: some View {
        Group {
            if let error = store.voice.error {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(Theme.pen)
            } else if store.activeNoteID != nil {
                Text(writingHint).foregroundStyle(Theme.muted)
            } else if store.shot?.hasMarkup == false {
                Text(store.voice.engine == .typing
                     ? "Circle anything, then type why. Click anywhere to leave a note."
                     : "Circle anything, then say why. Click anywhere to leave a note.")
                    .foregroundStyle(Theme.muted)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .lineLimit(1)
        .contentTransition(.opacity)
        .animation(.easeOut(duration: 0.2), value: store.activeNoteID)
    }

    private var writingHint: String {
        guard store.voice.isListening else { return "Return to finish · ⌘⏎ to talk" }
        switch store.voice.engine {
        case .superwhisper: return "Talk, then stop Superwhisper as usual. Your words land in the note."
        default: return "Talk. It finishes when you pause, or press Return."
        }
    }
}

private struct Filmstrip: View {
    @Environment(ReviewStore.self) private var store

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(store.shots.enumerated()), id: \.element.id) { position, shot in
                        FilmThumb(shot: shot, selected: position == store.index) { store.select(position) }
                            .id(shot.id)
                    }
                    Button { store.fileImporterRequested = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 56, height: 64)
                            .background(Theme.quietWash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Add images (⌘O)")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .frame(minWidth: 0)
            }
            .frame(maxWidth: .infinity)
            .onChange(of: store.index) { _, index in
                guard store.shots.indices.contains(index) else { return }
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(store.shots[index].id, anchor: .center) }
            }
        }
    }
}

private struct FilmThumb: View {
    @Environment(ReviewStore.self) private var store
    let shot: Shot
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let width = min(max(64 * shot.size.width / max(shot.size.height, 1), 40), 120)
        Button(action: action) {
            Image(decorative: shot.image, scale: 1)
                .resizable()
                .interpolation(.medium)
                .scaledToFill()
                .frame(width: width, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selected ? Theme.ink : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1)
                )
                .overlay(alignment: .topTrailing) {
                    if shot.hasMarkup {
                        Circle().fill(Theme.pen).frame(width: 8, height: 8)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                            .padding(5)
                    }
                }
                .opacity(selected || hovering ? 1 : 0.72)
                .scaleEffect(selected ? 1 : 0.94)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            if hovering {
                Button { store.remove(shot.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Theme.ink.opacity(0.8), in: Circle())
                }
                .buttonStyle(.plain)
                .offset(x: -6, y: -6)
                .help("Remove")
            }
        }
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selected)
        .contextMenu {
            Button("Copy") { store.select(store.shots.firstIndex { $0.id == shot.id } ?? 0); store.copyCurrent() }
            Button("Remove", role: .destructive) { store.remove(shot.id) }
        }
        .accessibilityLabel(shot.name)
    }
}

private struct HelpCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mark it like a teacher").display(17)
            VStack(alignment: .leading, spacing: 6) {
                line("Circle anything", "Your loop becomes a clean red circle, and it starts listening.")
                line("Talk", "Your words appear beside the circle in red.")
                line("Click anywhere", "Leave a note right there.")
                line("Talk for a while", "Long notes move under the image, numbered, so a model reads them easily.")
            }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                row("← →", "Move between images")
                row("⏎", "Finish the note")
                row("⌘⏎", "Talk into the note")
                row("⌘Z", "Undo")
                row("⌘C", "Copy this image")
                row("⇧⌘C", "Copy all")
                row("⌘S", "Save all as PNG")
                row("⌘V", "Paste an image")
            }
        }
        .padding(18)
        .frame(width: 320)
    }

    private func line(_ title: String, _ detail: String) -> some View {
        (Text(title).fontWeight(.semibold) + Text("  ") + Text(detail).foregroundStyle(.secondary))
            .font(.system(size: 12))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ keys: String, _ action: String) -> some View {
        GridRow {
            Text(keys).font(.system(size: 12, weight: .semibold).monospaced()).foregroundStyle(.secondary)
            Text(action).font(.system(size: 12))
        }
    }
}
