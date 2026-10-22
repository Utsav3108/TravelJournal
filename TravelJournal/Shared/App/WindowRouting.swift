import SwiftUI
import SwiftData

/// How a platform opens a journey from the shelf. `nil` (iPhone) means "push it onto the shelf's navigation stack";
/// the Mac app injects a closure that opens the journey's own window.
private struct OpenJourneyKey: EnvironmentKey {
    static let defaultValue: ((Journey) -> Void)? = nil
}

/// A request for the shelf to present its create-story sheet. The Mac menu bar sets `pending` (and opens the shelf
/// window if it is closed); the shelf consumes it.
@MainActor
@Observable
final class NewJourneyRequests {
    var pending = false
}

private struct NewJourneyRequestsKey: EnvironmentKey {
    static let defaultValue: NewJourneyRequests? = nil
}

/// What the editor's "Read story" button does. `nil` (iPhone) pushes the swipe viewer; the Mac journey window
/// injects a closure that returns to its story strip, so Mac never shows the swipe viewer.
private struct ReadStoryKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var readStory: (() -> Void)? {
        get { self[ReadStoryKey.self] }
        set { self[ReadStoryKey.self] = newValue }
    }

    var openJourney: ((Journey) -> Void)? {
        get { self[OpenJourneyKey.self] }
        set { self[OpenJourneyKey.self] = newValue }
    }

    var newJourneyRequests: NewJourneyRequests? {
        get { self[NewJourneyRequestsKey.self] }
        set { self[NewJourneyRequestsKey.self] = newValue }
    }
}

extension Journey {
    /// Matches the one journey with this id (the value a Mac journey window is keyed by).
    static func matching(id: UUID) -> Predicate<Journey> {
        #Predicate<Journey> { $0.id == id }
    }
}
