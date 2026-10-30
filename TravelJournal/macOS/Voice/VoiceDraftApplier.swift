#if os(macOS)
import Foundation

/// A stop field dictation can fill, in the order the "Filled in" chips list them.
enum VoiceField: String, CaseIterable {
    case place, category, arrived, timeSpent, story, highlight, rating, cost, travelMode

    var label: String {
        switch self {
        case .place: "Place"
        case .category: "Category"
        case .arrived: "Arrived"
        case .timeSpent: "Time spent"
        case .story: "Story"
        case .highlight: "Highlight"
        case .rating: "Rating"
        case .cost: "Cost"
        case .travelMode: "Got here by"
        }
    }
}

/// One field write produced from a draft, applied one at a time so the inspector can flash each row.
enum VoiceChange: Equatable {
    case place(String)
    case category(StopCategory)
    case arrived(Date)
    case timeSpent(Int)
    case story(String)
    case highlight(String)
    case rating(Int)
    case cost(Decimal)
    case travelMode(TransportMode)

    var field: VoiceField {
        switch self {
        case .place: .place
        case .category: .category
        case .arrived: .arrived
        case .timeSpent: .timeSpent
        case .story: .story
        case .highlight: .highlight
        case .rating: .rating
        case .cost: .cost
        case .travelMode: .travelMode
        }
    }
}

/// Turns a `VoiceStopDraft` into field writes. Pure value logic; the only model touch is `apply`.
enum VoiceDraftApplier {
    /// A stop nobody has filled in yet: dictation may also set its place, category and arrival time.
    static func isNewStop(placeName: String, story: String) -> Bool {
        placeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && story.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The writes for `draft`, in chip order. Only fields the draft carries, and only ones that would change something.
    /// - Parameters:
    ///   - incomingLeg: nil for the first stop (no "Got here by").
    ///   - arrivalBase: the journey date; the spoken HH:mm is applied to its day in `timeZone`.
    static func changes(for draft: VoiceStopDraft, current: StopContent, incomingLeg: LegContent?,
                        arrivalBase: Date, timeZone: TimeZone) -> [VoiceChange] {
        let isNew = isNewStop(placeName: current.placeName, story: current.story)
        var out: [VoiceChange] = []

        if isNew, let name = draft.placeName?.trimmed, !name.isEmpty { out.append(.place(name)) }
        // A category is only filled where there is none yet (or on a new stop); it is a guess, not a statement.
        if let c = draft.category?.stopCategory, isNew || current.categoryRaw == nil, c.rawValue != current.categoryRaw {
            out.append(.category(c))
        }
        // An arrival time is something the traveller states outright, so it also corrects an existing stop.
        if let hhmm = draft.arrival, let d = arrival(hhmm, on: arrivalBase, in: timeZone), d != current.arrivalTime {
            out.append(.arrived(d))
        }
        if let m = draft.minutesSpent {
            let v = min(max(m, 0), 24 * 60)
            if v != current.timeSpentMinutes { out.append(.timeSpent(v)) }
        }
        if let said = draft.story?.trimmed, !said.isEmpty {
            let existing = current.story.trimmed
            let joined = existing.isEmpty ? said : existing + " " + said
            let limited = EditorLogic.limitedStory(joined)
            if limited != current.story { out.append(.story(limited)) }
        }
        if let h = draft.highlight?.trimmed, !h.isEmpty {
            let v = EditorLogic.limitedChars(h, max: EditorLogic.highlightMaxChars)
            if v != current.highlight { out.append(.highlight(v)) }
        }
        if let r = draft.rating {
            let v = min(max(r, 1), 5)
            if v != current.ratingRaw { out.append(.rating(v)) }
        }
        if let c = draft.cost, c.isFinite, c >= 0 {
            let v = Decimal((c * 100).rounded()) / 100
            if v != current.costAmount { out.append(.cost(v)) }
        }
        if let mode = draft.travelMode?.transportMode, let leg = incomingLeg,
           !(leg.modeWasChosen && leg.modeRaw == mode.rawValue) {
            out.append(.travelMode(mode))
        }
        return out
    }

    /// The time of day `hhmm` on the day of `base` in `zone`. Accepts "14:30" and, as a model might answer, "2:30 PM"
    /// or "2 pm"; nil when it isn't a valid time.
    static func arrival(_ hhmm: String, on base: Date, in zone: TimeZone) -> Date? {
        let parts = hhmm.trimmed.split(separator: ":")
        var time: (Int, Int)?
        if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0..<24).contains(h), (0..<60).contains(m) {
            time = (h, m)
        } else if let normalized = VoiceTimeParser.arrival(in: hhmm) {
            let hm = normalized.split(separator: ":").compactMap { Int($0) }
            if hm.count == 2 { time = (hm[0], hm[1]) }
        }
        guard let (h, m) = time else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.date(bySettingHour: h, minute: m, second: 0, of: base)
    }

    @MainActor
    static func apply(_ change: VoiceChange, to stop: Stop) {
        switch change {
        case .place(let v): stop.placeName = v
        case .category(let v): stop.category = v
        case .arrived(let v): stop.arrivalTime = v
        case .timeSpent(let v): stop.timeSpentMinutes = v
        case .story(let v): stop.story = v
        case .highlight(let v): stop.highlight = v
        case .rating(let v): stop.rating = v
        case .cost(let v):
            stop.costAmount = v
            if stop.costCurrency?.isEmpty != false { stop.costCurrency = EditorLogic.defaultCurrency }
        case .travelMode(let v): stop.incomingLeg?.mode = v
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
#endif
