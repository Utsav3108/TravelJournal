#if os(macOS)
import Foundation
import FoundationModels

/// What dictation pulled out of a spoken note. Every field is optional: anything the traveller didn't say stays nil so
/// dictation never overwrites a field with an invented value. The model fills `VoiceModelOutput`; `VoiceExtractor`
/// maps that into this.
struct VoiceStopDraft: Equatable {
    var placeName: String?
    var category: Category?
    var arrival: String?
    var story: String?
    var highlight: String?
    var rating: Int?
    var cost: Double?
    var minutesSpent: Int?
    var travelMode: TravelMode?

    /// Mirrors `StopCategory`; kept separate so the model sees plain case names.
    @Generable
    enum Category: String, CaseIterable {
        case food, landmark, temple, stay, shopping, nature, other

        var stopCategory: StopCategory { StopCategory(storedRaw: rawValue) }
    }

    /// Mirrors `TransportMode`.
    @Generable
    enum TravelMode: String, CaseIterable {
        case walk, autoRickshaw, taxi, bus, localTrain, metro, bike, ferry

        var transportMode: TransportMode { TransportMode(storedRaw: rawValue) }
    }
}

/// Speech capture seam. The real implementation wraps `SpeechAnalyzer`; tests inject a fake.
@MainActor
protocol SpeechCapturing: AnyObject {
    /// Starts listening and streams the transcript so far (volatile text included). Throws `VoiceError`.
    func start() async throws -> AsyncStream<String>
    /// Stops listening and returns the final transcript.
    func finish() async throws -> String
    /// Abandons the session without a result.
    func cancel()
}

/// Extraction seam. The real implementation wraps `LanguageModelSession`; tests inject a fake.
protocol DraftExtracting: Sendable {
    func extract(from transcript: String) async throws -> VoiceStopDraft
}

/// Everything that can stop dictation, with the copy shown inline in the voice card.
enum VoiceError: Error, Equatable {
    case microphoneDenied
    case speechDenied
    case speechModelUnavailable
    case noSpeech
    case extractionFailed
    case nothingToFill

    var message: String {
        switch self {
        case .nothingToFill: "Heard you, but found nothing to fill in. Try the place, cost, time or stars."
        case .microphoneDenied: "Microphone access is off."
        case .speechDenied: "Speech recognition is off."
        case .speechModelUnavailable: "The on-device speech model isn't ready yet."
        case .noSpeech: "Didn't catch anything. Hold the button and try again."
        case .extractionFailed: "Couldn't turn that into stop details. Try again."
        }
    }

    /// Whether the card offers an "Open Settings" button.
    var offersSettings: Bool { self == .microphoneDenied || self == .speechDenied }
}
#endif
