import AVFoundation
import FluidAudio
import Foundation
import Synchronization

/// NVIDIA Parakeet and its derivatives, run on the Neural Engine through FluidAudio. Each model
/// downloads once to ~/Library/Application Support/FluidAudio/Models, the first time you use it.
enum ParakeetModel: String, CaseIterable, Identifiable, Sendable {
    // Newest first.
    case ultra
    case phonon2
    case redux
    case v3
    case v2

    static let `default`: ParakeetModel = .ultra

    var id: String { rawValue }

    var name: String {
        switch self {
        case .ultra: "Parakeet Ultra"
        case .phonon2: "Phonon-2"
        case .redux: "Parakeet Redux"
        case .v3: "Parakeet v3"
        case .v2: "Parakeet v2"
        }
    }

    var detail: String {
        switch self {
        case .ultra: "Most accurate. 25 languages."
        case .phonon2: "English. First load takes about a minute."
        case .redux: "Smallest, 178 MB. 25 languages."
        case .v3: "25 European languages, detects which one you speak."
        case .v2: "English only."
        }
    }

    var version: AsrModelVersion {
        switch self {
        case .ultra: .ultra
        case .phonon2: .phonon2
        case .redux: .redux
        case .v3: .v3
        case .v2: .v2
        }
    }

    var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: AsrModels.defaultCacheDirectory(for: version).path)
    }
}

actor ParakeetEngine {
    let model: ParakeetModel
    private var manager: AsrManager?
    /// The load in progress, shared so a preload and the first note don't download twice.
    private var loading: Task<AsrManager, Error>?

    init(model: ParakeetModel) {
        self.model = model
    }

    func prepare() async throws {
        guard manager == nil else { return }
        let version = model.version
        let loading = loading ?? Task {
            let models = try await AsrModels.downloadAndLoad(version: version)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            return manager
        }
        self.loading = loading
        do {
            manager = try await loading.value
        } catch {
            self.loading = nil
            throw error
        }
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await prepare()
        guard let manager else { return "" }
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        return try await manager.transcribe(samples, decoderState: &state).text
    }
}

/// Records the microphone and watches for the end of speech with a small voice detector
/// (Silero, about 2 MB). Nothing is transcribed until you stop talking.
@MainActor
final class SpeechRecording {
    enum End: Sendable {
        /// You paused after talking.
        case paused
        /// Nothing was said before the wait ran out.
        case silent
    }

    /// How long a pause ends the note.
    static let pause: TimeInterval = 1.5
    /// How long to wait for the first word.
    static let wait: TimeInterval = 6
    /// Longer than this, the note ends anyway.
    static let longest: TimeInterval = 120

    private var session: MicSession?
    private var loop: Task<Void, Never>?
    private let samples = Samples()

    /// Starts recording. `onEnd` runs once, on the main actor, when the detector hears you stop.
    func start(onEnd: @escaping @MainActor (End) -> Void, onFailure: @escaping @MainActor (String) -> Void) throws {
        let (stream, continuation) = AsyncStream.makeStream(of: [Float].self, bufferingPolicy: .bufferingNewest(400))
        let collected = samples
        session = try MicSession { chunk in
            collected.append(chunk)
            continuation.yield(chunk)
        }
        loop = Task {
            do {
                let end = try await Self.watch(stream)
                onEnd(end)
            } catch is CancellationError {
            } catch {
                onFailure(error.localizedDescription)
            }
        }
    }

    /// Stops recording and returns everything heard since `start`.
    func stop() -> [Float] {
        loop?.cancel()
        loop = nil
        session?.stop()
        session = nil
        return samples.reset()
    }

    private static func watch(_ stream: AsyncStream<[Float]>) async throws -> End {
        let vad = try await VadManager()
        let rate = VadManager.sampleRate
        let config = VadSegmentationConfig(minSpeechDuration: 0.25, minSilenceDuration: pause, speechPadding: 0.2)
        var state = await vad.makeStreamState()
        var pending: [Float] = []
        var heardSpeech = false

        for await chunk in stream {
            try Task.checkCancellation()
            pending.append(contentsOf: chunk)
            while pending.count >= VadManager.chunkSize {
                let frame = Array(pending.prefix(VadManager.chunkSize))
                pending.removeFirst(VadManager.chunkSize)
                let result = try await vad.processStreamingChunk(frame, state: state, config: config)
                state = result.state
                if let event = result.event {
                    if event.isStart { heardSpeech = true } else if heardSpeech { return .paused }
                }
                if !heardSpeech, state.processedSamples > Int(wait) * rate { return .silent }
                if state.processedSamples > Int(longest) * rate { return .paused }
            }
        }
        throw CancellationError()
    }

    private final class Samples: Sendable {
        private let buffer = Mutex<[Float]>([])

        func append(_ chunk: [Float]) {
            buffer.withLock { $0.append(contentsOf: chunk) }
        }

        @discardableResult func reset() -> [Float] {
            buffer.withLock { taken in
                defer { taken = [] }
                return taken
            }
        }
    }
}

/// An audio engine on the default microphone, handing 16 kHz mono chunks to `deliver` on the
/// audio thread.
@MainActor
final class MicSession {
    nonisolated static let sampleRate: Double = 16_000

    private let engine = AVAudioEngine()

    init(deliver: @escaping @Sendable ([Float]) -> Void) throws {
        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        let sink = try Converter(from: format, deliver: deliver)
        sink.install(on: node, format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            node.removeTap(onBus: 0)
            throw error
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}

/// Turns any audio into 16 kHz mono and hands it on. Lives on the audio thread. It is a plain
/// class, not main-actor isolated, so the tap closure it installs doesn't inherit the main actor
/// and trap when Core Audio calls it.
final class Converter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let output: AVAudioFormat
    private let deliver: @Sendable ([Float]) -> Void

    init(from input: AVAudioFormat, deliver: @escaping @Sendable ([Float]) -> Void) throws {
        guard input.sampleRate > 0,
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: MicSession.sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: input, to: output)
        else { throw MicError.noMicrophone }
        self.output = output
        self.converter = converter
        self.deliver = deliver
    }

    func install(on node: AVAudioInputNode, format: AVAudioFormat) {
        node.installTap(onBus: 0, bufferSize: 4096, format: format) { [self] buffer, _ in
            convert(buffer)
        }
    }

    func convert(_ buffer: AVAudioPCMBuffer) {
        let ratio = output.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = converted.floatChannelData?[0] else { return }
        deliver(Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength))))
    }
}

enum MicError: LocalizedError {
    case noMicrophone

    var errorDescription: String? { "No microphone found." }
}
