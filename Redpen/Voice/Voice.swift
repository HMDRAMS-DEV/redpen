import AppKit
import AVFoundation
import Observation
import Speech

enum VoiceEngine: String, CaseIterable, Identifiable {
    /// Superwhisper records and pastes the transcript into the focused note.
    case superwhisper
    /// Apple's speech recognizer, on this Mac.
    case dictation
    /// No voice. Circling or clicking opens a note to type in.
    case typing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .superwhisper: "Superwhisper"
        case .dictation: "Mac dictation"
        case .typing: "Type only"
        }
    }
}

/// Starts and stops listening for the note being written.
///
/// With Superwhisper, Redpen only presses record and stop through Superwhisper's deep links.
/// Superwhisper pastes its transcript at the cursor, which is the focused note, so the text
/// arrives through the note's text field like typing does.
@MainActor
@Observable
final class Voice {
    static let superwhisperID = "com.superduper.superwhisper"
    static let superwhisperSite = URL(string: "https://superwhisper.com")!

    private(set) var isListening = false
    private(set) var error: String?

    var engine: VoiceEngine {
        didSet { UserDefaults.standard.set(engine.rawValue, forKey: Keys.voiceEngine) }
    }

    var superwhisperInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.superwhisperID) != nil
    }

    private let recognizer = SFSpeechRecognizer()
    private var audio: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silence: Task<Void, Never>?

    /// Pass `engine` to skip the saved setting, as tests do.
    init(engine fixed: VoiceEngine? = nil) {
        if let fixed {
            engine = fixed
            return
        }
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.superwhisperID) != nil
        let saved = UserDefaults.standard.string(forKey: Keys.voiceEngine).flatMap(VoiceEngine.init)
        engine = saved ?? (installed ? .superwhisper : .dictation)
        if engine == .superwhisper && !installed { engine = .dictation }
    }

    /// Starts listening. `onText` gets the full transcript so far (Mac dictation only), and
    /// `onFinish` runs when dictation ends on its own after a pause.
    func start(onText: @escaping (String) -> Void, onFinish: @escaping () -> Void) {
        stop()
        error = nil
        switch engine {
        case .typing:
            return
        case .superwhisper:
            guard superwhisperInstalled else {
                error = "Superwhisper isn't installed."
                return
            }
            superwhisper("record")
            isListening = true
        case .dictation:
            Task { await startDictation(onText: onText, onFinish: onFinish) }
        }
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        switch engine {
        case .superwhisper:
            superwhisper("stop")
        case .dictation, .typing:
            silence?.cancel()
            audio?.inputNode.removeTap(onBus: 0)
            audio?.stop()
            request?.endAudio()
            task?.finish()
            audio = nil
            request = nil
            task = nil
        }
    }

    /// Superwhisper pasted its transcript, so it has already stopped.
    func superwhisperFinished() {
        isListening = false
    }

    /// Opens a Superwhisper deep link without bringing Superwhisper forward, so the note keeps focus.
    private func superwhisper(_ command: String) {
        guard let url = URL(string: "superwhisper://\(command)") else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(url, configuration: configuration)
    }

    private func startDictation(onText: @escaping (String) -> Void, onFinish: @escaping () -> Void) async {
        guard await Self.authorize() else {
            error = "Allow microphone and speech recognition for Redpen in System Settings, Privacy & Security."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            error = "Speech recognition isn't available right now."
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        let audio = AVAudioEngine()
        let input = audio.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            error = "No microphone found."
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [request] buffer, _ in
            request.append(buffer)
        }
        do {
            audio.prepare()
            try audio.start()
        } catch {
            input.removeTap(onBus: 0)
            self.error = "Couldn't start the microphone."
            return
        }
        self.audio = audio
        self.request = request
        isListening = true
        armSilence(onFinish: onFinish, after: .seconds(6))

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            Task { @MainActor in
                guard let self, self.request === request else { return }
                if let text, !text.isEmpty {
                    onText(text)
                    // Stop after a pause, so you can talk and move on.
                    self.armSilence(onFinish: onFinish, after: .seconds(1.8))
                }
                if final || error != nil {
                    self.stop()
                    onFinish()
                }
            }
        }
    }

    private func armSilence(onFinish: @escaping () -> Void, after delay: Duration) {
        silence?.cancel()
        silence = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.isListening else { return }
            self.stop()
            onFinish()
        }
    }

    private static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}
