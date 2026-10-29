#if os(macOS)
import AVFoundation
import Speech

/// Real `SpeechCapturing`: microphone → `AVAudioEngine` → `SpeechAnalyzer` + `SpeechTranscriber`, all on device.
/// One instance serves many dictations; each `start()` builds a fresh analyzer.
@MainActor
final class SpeechCapture: SpeechCapturing {
    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<String, Error>?

    /// Whether this Mac can transcribe on device at all (the voice UI is hidden otherwise).
    static var isSupported: Bool { SpeechTranscriber.isAvailable }

    func start() async throws -> AsyncStream<String> {
        cancel()
        guard await AVAudioApplication.requestRecordPermission() else { throw VoiceError.microphoneDenied }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
            throw VoiceError.speechModelUnavailable
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        guard await AssetInventory.status(forModules: [transcriber]) >= .installed else {
            // The language model isn't on the Mac yet: fetch it in the background and ask the user to retry.
            if let request = try? await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                Task { try? await request.downloadAndInstall() }
            }
            throw VoiceError.speechModelUnavailable
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw VoiceError.speechModelUnavailable
        }

        let (audio, audioIn) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let (text, textOut) = AsyncStream.makeStream(of: String.self)
        results = Task {
            var final = ""
            do {
                for try await result in transcriber.results {
                    let piece = String(result.text.characters)
                    if result.isFinal {
                        final = (final + " " + piece).trimmingCharacters(in: .whitespacesAndNewlines)
                        textOut.yield(final)
                    } else {
                        textOut.yield((final + " " + piece).trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            } catch {
                textOut.finish()
                throw error
            }
            textOut.finish()
            return final
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.start(inputSequence: audio)
        let engine = AVAudioEngine()
        try AudioFeeder.install(on: engine, targetFormat: format, into: audioIn)
        try engine.start()
        self.analyzer = analyzer
        self.engine = engine
        self.input = audioIn
        return text
    }

    func finish() async throws -> String {
        guard let analyzer, let results else { return "" }
        stopAudio()
        defer { reset() }
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await results.value
    }

    func cancel() {
        stopAudio()
        results?.cancel()
        let analyzer = analyzer
        Task { await analyzer?.cancelAndFinishNow() }
        reset()
    }

    private func stopAudio() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        input?.finish()
    }

    private func reset() {
        engine = nil
        analyzer = nil
        input = nil
        results = nil
    }
}

/// The audio tap runs on a realtime thread, so it must not inherit the module's MainActor isolation.
private nonisolated enum AudioFeeder {
    static func install(on engine: AVAudioEngine, targetFormat: AVAudioFormat,
                        into continuation: AsyncStream<AnalyzerInput>.Continuation) throws {
        let node = engine.inputNode
        let micFormat = node.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: micFormat, to: targetFormat) else {
            throw VoiceError.speechModelUnavailable
        }
        let ratio = targetFormat.sampleRate / micFormat.sampleRate
        try node.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { buffer, _ in
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
            guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            if error == nil, out.frameLength > 0 { continuation.yield(AnalyzerInput(buffer: out)) }
        }
        engine.prepare()
    }
}
#endif
