import AppKit
import AVFoundation
import Observation
import Speech

enum VoiceEngine: String, CaseIterable, Identifiable {
    /// A Parakeet model, on this Mac. The note is written when you pause.
    case parakeet
    /// Apple's speech recognizer, on this Mac.
    case dictation
    /// No voice. Circling or clicking opens a note to type in.
    case typing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .parakeet: "Parakeet"
        case .dictation: "Mac dictation"
        case .typing: "Type only"
        }
    }
}

/// Starts and stops listening for the note being written.
///
/// Mac dictation writes as you talk. Parakeet records until you pause, then writes the whole
/// note at once.
@MainActor
@Observable
final class Voice {
    private(set) var isListening = false
    /// Parakeet heard you stop and is writing the note down, or loading its model first.
    private(set) var isTranscribing = false
    private(set) var error: String?

    var engine: VoiceEngine {
        didSet { UserDefaults.standard.set(engine.rawValue, forKey: Keys.voiceEngine) }
    }

    var model: ParakeetModel {
        didSet {
            UserDefaults.standard.set(model.rawValue, forKey: Keys.parakeetModel)
            if parakeet?.model != model { parakeet = nil }
        }
    }

    private let recognizer = SFSpeechRecognizer()
    private var audio: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silence: Task<Void, Never>?

    /// Loaded on first use and kept, so later notes don't wait for the model.
    private var parakeet: ParakeetEngine?
    private var recording: SpeechRecording?
    private var writing: Task<Void, Never>?
    private var onText: ((String) -> Void)?
    private var onFinish: (() -> Void)?

    /// Pass `engine` to skip the saved setting, as tests do.
    init(engine fixed: VoiceEngine? = nil) {
        model = UserDefaults.standard.string(forKey: Keys.parakeetModel).flatMap(ParakeetModel.init) ?? .default
        if let fixed {
            engine = fixed
            return
        }
        // An engine saved by an older version that no longer exists becomes Parakeet.
        engine = UserDefaults.standard.string(forKey: Keys.voiceEngine).flatMap(VoiceEngine.init) ?? .parakeet
    }

    /// Starts listening. `onText` gets the full transcript so far, and `onFinish` runs when
    /// dictation ends on its own after a pause, or after Parakeet writes the note.
    func start(onText: @escaping (String) -> Void, onFinish: @escaping () -> Void) {
        cancel()
        error = nil
        switch engine {
        case .typing:
            return
        case .parakeet:
            Task { await startParakeet(onText: onText, onFinish: onFinish) }
        case .dictation:
            Task { await startDictation(onText: onText, onFinish: onFinish) }
        }
    }

    /// Stops listening. Parakeet then writes down what it heard and finishes the note.
    func stop() {
        guard isListening else { return }
        if engine == .parakeet {
            transcribe()
        } else {
            cancel()
        }
    }

    /// Stops listening and drops anything not yet written down.
    func cancel() {
        isListening = false
        isTranscribing = false
        writing?.cancel()
        writing = nil
        _ = recording?.stop()
        recording = nil
        onText = nil
        onFinish = nil
        silence?.cancel()
        audio?.inputNode.removeTap(onBus: 0)
        audio?.stop()
        request?.endAudio()
        task?.finish()
        audio = nil
        request = nil
        task = nil
    }

    /// Loads Parakeet in the background, downloading it the first time, so the first note
    /// doesn't wait on it.
    func preload() {
        guard engine == .parakeet else { return }
        let engine = parakeet ?? ParakeetEngine(model: model)
        parakeet = engine
        Task { try? await engine.prepare() }
    }

    /// Asks for the microphone, and for speech recognition when Mac dictation needs it.
    func requestAccess() async -> Bool {
        engine == .dictation ? await Self.authorize() : await AVCaptureDevice.requestAccess(for: .audio)
    }

    private func startParakeet(onText: @escaping (String) -> Void, onFinish: @escaping () -> Void) async {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            error = "Allow microphone access for Redpen in System Settings, Privacy & Security."
            return
        }
        // Load while you talk. The first time, this downloads the model.
        preload()

        let recording = SpeechRecording()
        do {
            try recording.start(onEnd: { [weak self, weak recording] end in
                guard let self, self.recording === recording else { return }
                switch end {
                case .paused: self.transcribe()
                case .silent:
                    self.cancel()
                    onFinish()
                }
            }, onFailure: { [weak self, weak recording] message in
                guard let self, self.recording === recording else { return }
                self.cancel()
                self.error = message
            })
        } catch {
            self.error = error.localizedDescription
            return
        }
        self.recording = recording
        self.onText = onText
        self.onFinish = onFinish
        isListening = true
    }

    private func transcribe() {
        guard let recording, let parakeet, let onText, let onFinish else { return }
        let samples = recording.stop()
        self.recording = nil
        isListening = false
        isTranscribing = true
        let model = parakeet.model
        writing = Task { [weak self] in
            do {
                let text = try await parakeet.transcribe(samples).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !Task.isCancelled, let self else { return }
                self.isTranscribing = false
                self.writing = nil
                if !text.isEmpty { onText(text) }
                onFinish()
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.isTranscribing = false
                self.writing = nil
                self.error = "\(model.name) couldn't write this down: \(error.localizedDescription)"
            }
        }
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
        Self.feed(input, format: format, to: request)
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
                    self.cancel()
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
            self.cancel()
            onFinish()
        }
    }

    /// Nonisolated, so the tap closure doesn't inherit the main actor and trap when Core Audio
    /// calls it on the audio thread.
    private nonisolated static func feed(_ input: AVAudioInputNode, format: AVAudioFormat, to request: SFSpeechAudioBufferRecognitionRequest) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    /// Nonisolated for the same reason: TCC answers on a background queue.
    private nonisolated static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}
