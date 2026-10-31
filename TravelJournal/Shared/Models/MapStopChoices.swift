import Foundation

/// Picker choices and hint logic for the cover editor's "Map location" section.
nonisolated enum MapStopChoices {
    static let missingLocationHint = "Add a location to show this story on the map"

    struct Choice: Equatable, Identifiable {
        let id: UUID
        let label: String
    }

    /// One choice per stop, in route order. Unnamed stops are labelled by position.
    @MainActor
    static func choices(for journey: Journey) -> [Choice] {
        journey.orderedStops.enumerated().map { i, s in
            let name = s.placeName.trimmingCharacters(in: .whitespacesAndNewlines)
            return Choice(id: s.id, label: name.isEmpty ? "Stop \(i + 1)" : name)
        }
    }

    /// The stop the map pins: the chosen one, else the default from `StoryMapPins`.
    @MainActor
    static func selectedStop(for journey: Journey) -> Stop? { StoryMapPins.mapStop(for: journey) }

    /// The hint to show under the Location block, or nil when the stop has coordinates.
    static func hint(latitude: Double?, longitude: Double?) -> String? {
        latitude != nil && longitude != nil ? nil : missingLocationHint
    }
}
