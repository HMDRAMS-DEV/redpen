import AppKit
import ImageIO
import Observation
import UniformTypeIdentifiers
import UserNotifications

enum Keys {
    static let voiceEngine = "voiceEngine"
    static let askOnScreenshot = "askOnScreenshot"
    static let welcomed = "welcomed"
}

enum WindowID {
    static let editor = "editor"
    static let settings = "settings"
}

/// The review in progress: the screenshots, the pen, the note being written, and the new
/// screenshots waiting to be marked up.
@MainActor
@Observable
final class ReviewStore {
    static let shared = ReviewStore()

    var shots: [Shot] = []
    var index = 0
    /// The note shown as a live text field.
    private(set) var activeNoteID: Note.ID?
    /// The stroke under the pen, in image pixels.
    private(set) var liveStroke: [CGPoint] = []
    let voice: Voice

    /// Screenshots from the last few days, newest first.
    private(set) var captures: [ScreenshotWatcher.Capture] = []
    /// Screenshots taken since launch that you haven't added or dismissed.
    private(set) var pending: [ScreenshotWatcher.Capture] = []
    /// Bumped to ask the menu bar label, which is always alive, to open the editor window.
    private(set) var editorRequests = 0
    var photoPickerRequested = false
    var fileImporterRequested = false
    var toast: String?

    private let watcher = ScreenshotWatcher()
    private var handled: Set<URL> = []
    private let launched = Date.now
    private var noticeTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var commitTask: Task<Void, Never>?
    private var started = false
    /// Whether the active note is new, and its text when it opened, so a note that ends
    /// empty or unchanged leaves no undo step behind.
    private var session: (isNew: Bool, original: String)?

    var shot: Shot? { shots.indices.contains(index) ? shots[index] : nil }
    var activeNote: Note? { shot?.notes.first { $0.id == activeNoteID } }

    init(preview: [Shot] = [], voice: Voice = Voice()) {
        shots = preview
        self.voice = voice
    }

    func start() {
        guard !started else { return }
        started = true
        UserDefaults.standard.register(defaults: [Keys.askOnScreenshot: true])
        watcher.onChange = { [weak self] in self?.capturesChanged($0) }
        watcher.start()
    }

    func requestEditor() {
        editorRequests += 1
    }

    // MARK: Adding screenshots

    func add(urls: [URL]) {
        let added = urls.compactMap { url -> Shot? in
            guard let image = Self.load(CGImageSourceCreateWithURL(url as CFURL, nil)) else { return nil }
            return Shot(name: url.lastPathComponent, image: image)
        }
        handled.formUnion(urls)
        pending.removeAll { handled.contains($0.url) }
        append(added, failed: urls.count - added.count)
    }

    func add(imageData: [Data], name: String = "Photo") {
        let added = imageData.compactMap { data in
            Self.load(CGImageSourceCreateWithData(data as CFData, nil)).map { Shot(name: name, image: $0) }
        }
        append(added, failed: imageData.count - added.count)
    }

    /// Adds an image from the clipboard. Returns false when there isn't one.
    @discardableResult
    func paste() -> Bool {
        let board = NSPasteboard.general
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: [UTType.image.identifier]]) as? [URL], !urls.isEmpty {
            add(urls: urls)
            return true
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = board.data(forType: type) {
                add(imageData: [data], name: "Pasted image")
                return true
            }
        }
        return false
    }

    private func append(_ added: [Shot], failed: Int) {
        if failed > 0 { show(failed == 1 ? "One image couldn't be opened." : "\(failed) images couldn't be opened.") }
        guard !added.isEmpty else { return }
        commitNote()
        shots.append(contentsOf: added)
        index = shots.count - added.count
        requestEditor()
    }

    /// Downscales very large photos; screenshots come through at full size.
    private static func load(_ source: CGImageSource?) -> CGImage? {
        guard let source else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 5120,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: New screenshots

    func addPending() {
        add(urls: pending.reversed().map(\.url))
    }

    func dismissPending() {
        handled.formUnion(pending.map(\.url))
        pending = []
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["screenshots"])
    }

    private func capturesChanged(_ found: [ScreenshotWatcher.Capture]) {
        captures = found
        let fresh = found.filter { $0.date >= launched && !handled.contains($0.url) }
        guard fresh != pending else { return }
        let grew = fresh.count > pending.count
        pending = fresh
        guard grew, UserDefaults.standard.bool(forKey: Keys.askOnScreenshot) else { return }
        // Screenshots often come in bursts. Ask once, after the burst.
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, !self.pending.isEmpty else { return }
            if !NSApp.isActive { await self.notifyPending() }
        }
    }

    private func notifyPending() async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
        let content = UNMutableNotificationContent()
        let count = pending.count
        content.title = count == 1 ? "Mark up your screenshot?" : "Mark up \(count) screenshots?"
        content.body = "Circle what's wrong and say why."
        try? await center.add(UNNotificationRequest(identifier: "screenshots", content: content, trigger: nil))
    }

    // MARK: Navigation

    func select(_ newIndex: Int) {
        guard shots.indices.contains(newIndex), newIndex != index else { return }
        commitNote()
        index = newIndex
    }

    func step(_ delta: Int) {
        select(min(max(index + delta, 0), shots.count - 1))
    }

    func remove(_ id: Shot.ID) {
        guard let position = shots.firstIndex(where: { $0.id == id }) else { return }
        if position == index { commitNote() }
        shots.remove(at: position)
        if position < index || index >= shots.count { index = max(0, index - 1) }
    }

    func clear() {
        commitNote()
        shots = []
        index = 0
    }

    // MARK: The pen

    func penMoved(to point: CGPoint) {
        liveStroke.append(point)
    }

    /// Ends a stroke. A click opens a note there (or edits the note under it); a circle gets a
    /// note beside it; other strokes are just marks. Circles and clicks start listening.
    func penEnded(tapLength: CGFloat) {
        let stroke = liveStroke
        liveStroke = []
        guard let current = shot, let first = stroke.first else { return }

        guard let ink = Ink.recognize(stroke, tapLength: tapLength) else {
            // The first click after writing a note just puts the pen down.
            if activeNoteID != nil {
                commitNote()
                return
            }
            if let note = Markup.layout(current).note(at: first) {
                edit(note.id)
            } else {
                startNote(target: CGRect(origin: first, size: .zero))
            }
            return
        }

        commitNote()
        let mark = Mark(ink: ink)
        mutate { $0.checkpoint(); $0.marks.append(mark) }
        if ink.isLoop { startNote(target: mark.bounds) }
    }

    func cancelStroke() {
        liveStroke = []
    }

    private func startNote(target: CGRect) {
        let note = Note(target: target)
        mutate { $0.checkpoint(); $0.notes.append(note) }
        activeNoteID = note.id
        session = (true, "")
        listen()
    }

    /// Reopens a note to type into. Talking again is one shortcut away.
    func edit(_ id: Note.ID) {
        commitNote()
        guard let text = shot?.notes.first(where: { $0.id == id })?.text else { return }
        mutate { $0.checkpoint() }
        activeNoteID = id
        session = (false, text)
    }

    func listen() {
        guard let id = activeNoteID, let base = activeNote?.text else { return }
        voice.start(onText: { [weak self] spoken in
            guard let self, self.activeNoteID == id else { return }
            self.setText(base.isEmpty ? spoken : base + " " + spoken, for: id)
        }, onFinish: { [weak self] in
            guard let self, self.activeNoteID == id else { return }
            self.commitNote()
        })
    }

    func toggleListening() {
        if voice.isListening {
            voice.stop()
        } else if activeNoteID != nil {
            listen()
        }
    }

    /// Text from the note's field: typing, or Superwhisper pasting its transcript.
    func typed(_ text: String) {
        guard let id = activeNoteID, let before = activeNote?.text, text != before else { return }
        setText(text, for: id)
        guard voice.isListening else { return }
        if voice.engine == .superwhisper, text.count - before.count > 3 {
            // A transcript landed in one piece. Superwhisper is done; move on shortly unless
            // you keep typing.
            voice.superwhisperFinished()
            commitTask?.cancel()
            commitTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.6))
                guard !Task.isCancelled, let self, self.activeNoteID == id, self.activeNote?.text == text else { return }
                self.commitNote()
            }
        } else if voice.engine == .dictation {
            // You took over with the keyboard.
            voice.stop()
        }
    }

    private func setText(_ text: String, for id: Note.ID) {
        mutate { shot in
            if let i = shot.notes.firstIndex(where: { $0.id == id }) { shot.notes[i].text = text }
        }
    }

    /// Finishes the note being written. An empty note disappears; its circle stays.
    func commitNote() {
        commitTask?.cancel()
        voice.stop()
        guard let id = activeNoteID, let note = activeNote else { return }
        activeNoteID = nil
        let session = session
        self.session = nil
        mutate { shot in
            if note.isEmpty {
                shot.notes.removeAll { $0.id == id }
                // A new note that stayed empty: its circle is the last step, not the note.
                if session?.isNew == true { shot.history.removeLast() }
            } else if session?.isNew == false && session?.original == note.text {
                shot.history.removeLast()
            }
        }
    }

    func undo() {
        commitNote()
        mutate { _ = $0.undo() }
    }

    private func mutate(_ body: (inout Shot) -> Void) {
        guard shots.indices.contains(index) else { return }
        body(&shots[index])
    }

    // MARK: Export

    /// Copies the marked-up screenshot, ready to paste into a chat with a model.
    func copyCurrent() {
        commitNote()
        guard let shot, let url = write([shot], offset: index).first else { return }
        let item = NSPasteboardItem()
        if let data = try? Data(contentsOf: url) { item.setData(data, forType: .png) }
        item.setString(url.absoluteString, forType: .fileURL)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
        show("Copied. Paste it into your chat.")
    }

    func copyAll() {
        commitNote()
        let urls = write(shots, offset: 0)
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls as [NSURL])
        show(urls.count == 1 ? "Copied 1 image." : "Copied \(urls.count) images.")
    }

    func saveAll() {
        commitNote()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Save Here"
        panel.message = "Choose where to save \(shots.count == 1 ? "the image" : "\(shots.count) images")."
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let urls = write(shots, offset: 0, to: folder)
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Scratch folder for copies. One stable path, emptied on each copy.
    private static let exportFolder = FileManager.default.temporaryDirectory.appending(path: "Redpen")

    private func write(_ list: [Shot], offset: Int, to folder: URL? = nil) -> [URL] {
        let fileManager = FileManager.default
        let target = folder ?? Self.exportFolder
        if folder == nil { try? fileManager.removeItem(at: target) }
        try? fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        return list.enumerated().compactMap { position, shot in
            let url = target.appending(path: Markup.fileName(shot, index: offset + position))
            guard let data = Markup.png(shot), (try? data.write(to: url)) != nil else { return nil }
            return url
        }
    }

    func show(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
