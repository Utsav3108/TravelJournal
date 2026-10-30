#if os(macOS)
import Foundation
import FoundationModels

/// The shape the on-device model fills. The small model almost never returns nil for an optional enum or number
/// (it writes 1, 0, walk or other instead), so each value sits behind a `has…` flag it must set first; a false flag
/// becomes nil in `VoiceStopDraft`. Measured with the prompt-tuning harness: ~2% invented fields with flags vs ~60%
/// with optionals.
@Generable
struct VoiceModelOutput {
    @Guide(description: "true only if a specific place name was spoken") var hasPlace: Bool
    @Guide(description: VoiceExtractionPrompts.placeName) var placeName: String
    @Guide(description: "true only if the kind of place is clearly stated or obvious from its name") var hasCategory: Bool
    @Guide(description: VoiceExtractionPrompts.category) var category: VoiceStopDraft.Category
    @Guide(description: "true only if an arrival clock time was spoken") var hasArrival: Bool
    @Guide(description: VoiceExtractionPrompts.arrival) var arrival: String
    @Guide(description: "true only if the traveller described the visit or experience in words") var hasStory: Bool
    @Guide(description: VoiceExtractionPrompts.story) var story: String
    @Guide(description: VoiceExtractionPrompts.highlight) var highlight: String
    @Guide(description: "true only if a star rating or score out of 5 was spoken") var hasRating: Bool
    @Guide(description: VoiceExtractionPrompts.rating, .range(1...5)) var rating: Int
    @Guide(description: "true only if an amount of money or free was spoken") var hasCost: Bool
    @Guide(description: VoiceExtractionPrompts.cost, .range(0...10_000_000)) var cost: Double
    @Guide(description: "true only if a duration spent at the place was spoken") var hasMinutes: Bool
    @Guide(description: VoiceExtractionPrompts.minutes, .range(0...1440)) var minutesSpent: Int
    @Guide(description: "true only if a vehicle or walking was explicitly spoken") var hasTravelMode: Bool
    @Guide(description: VoiceExtractionPrompts.travelMode) var travelMode: VoiceStopDraft.TravelMode
}

/// Pure post-processing of the model output: presence flags to nil, junk strings cleaned, and a keyword gate that drops
/// a value whose topic never came up in the transcript (the model sometimes sets `hasCost` on "5 star experience").
enum VoiceDraftMapper {
    static func draft(from out: VoiceModelOutput, transcript: String) -> VoiceStopDraft {
        let text = transcript.lowercased()
        func allowed(_ topic: Topic) -> Bool { text.range(of: topic.pattern, options: .regularExpression) != nil }

        var d = VoiceStopDraft()
        if out.hasPlace, let name = clean(out.placeName), isPlausiblePlace(name) { d.placeName = name }
        if out.hasCategory, allowed(.category) { d.category = out.category }
        if out.hasArrival, allowed(.arrival) { d.arrival = clean(out.arrival) }
        if out.hasStory { d.story = clean(out.story); d.highlight = clean(out.highlight) }
        if out.hasRating, allowed(.rating) { d.rating = out.rating }
        if out.hasCost, allowed(.cost) { d.cost = out.cost }
        if out.hasMinutes, allowed(.minutes) { d.minutesSpent = out.minutesSpent }
        if out.hasTravelMode, allowed(.travelMode) { d.travelMode = out.travelMode }

        // Clock times and durations are regular, and the model is unreliable on them: a rule result wins.
        if let hhmm = VoiceTimeParser.arrival(in: transcript) { d.arrival = hhmm }
        switch VoiceTimeParser.duration(in: transcript) {
        case .minutes(let m): d.minutesSpent = m
        case .travelOnly: d.minutesSpent = nil   // "walked 20 minutes" is travel, not time spent
        case .none: break
        }
        return d
    }

    /// nil for blank text and for the literal "null" the model sometimes writes.
    static func clean(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t.lowercased() == "null" ? nil : t
    }

    private static let genericPlaces: Set<String> = ["place", "the place", "temple", "the temple", "market", "station",
                                                      "tickets", "room", "rs"]

    static func isPlausiblePlace(_ name: String) -> Bool {
        let n = name.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }.trimmingCharacters(in: .whitespaces)
        if n.isEmpty || genericPlaces.contains(n) { return false }
        return n.range(of: #"^[\d ]*(am|pm|rs)?[\d ]*$"#, options: .regularExpression) == nil
    }

    enum Topic {
        case rating, cost, minutes, travelMode, arrival, category

        var pattern: String {
            switch self {
            case .rating: #"star|out of (5|five)|/ ?5|\brat(e|ed|ing)\b|gave it (a |an )?(\d|one|two|three|four|five)|\b(one|two|three|four|five) stars?\b"#
            case .cost: #"rupee|\brs\b|₹|\bfree\b|nothing|paid|cost|spent|price|fee\b|ticket|\bbill\b|\d{2,}"#
            case .minutes: #"hour|minute|\bmins?\b|\bhrs?\b"#
            case .travelMode: #"\bauto\b|rickshaw|\bcab\b|taxi|\bola\b|uber|\bbus\b|train|local|metro|\bwalk|\bbik(e|ed|ing)\b|rode|\bferry|boat"#
            case .arrival: #"\b(a\.?m|p\.?m)\b|\bat \d|\bat (noon|midnight)|reached|arrived|got (there|in)|quarter|noon|showed up|around \d"#
            case .category: #"temple|mandir|food|ate|eat|lunch|dinner|breakfast|cafe|restaurant|thali|stay|hotel|room|hostel|zostel|shop|market|bought|souvenir|fort|palace|gate|mahal|minar|park|lake|beach|ghat|garden|caves|station|drive|chowk|haat|museum"#
            }
        }
    }
}

/// Real extractor: one fresh `LanguageModelSession` per dictation.
struct VoiceExtractor: DraftExtracting {
    static var isSupported: Bool { SystemLanguageModel.default.availability == .available }

    func extract(from transcript: String) async throws -> VoiceStopDraft {
        let session = LanguageModelSession(instructions: VoiceExtractionPrompts.instructions)
        let out = try await session.respond(to: transcript, generating: VoiceModelOutput.self).content
        return VoiceDraftMapper.draft(from: out, transcript: transcript)
    }
}
#endif
