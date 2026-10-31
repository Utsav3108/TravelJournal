#if os(macOS)
extension VoiceDictationController {
    /// The real controller, or nil when this Mac can't run both on-device pieces (Apple Intelligence model and
    /// on-device speech): then there is no voice UI at all and the editor is typing only.
    static func makeDefault() -> VoiceDictationController? {
        guard VoiceExtractor.isSupported, SpeechCapture.isSupported else { return nil }
        return VoiceDictationController(capture: SpeechCapture(), extractor: VoiceExtractor(), isAvailable: true)
    }
}
#endif
