import Foundation

/// State behind the "Find this place" sheet: searches as the query changes (after a short pause), or at once on
/// Return, and drops the answer of any search that a newer query has replaced.
@MainActor
@Observable
final class PlaceSearchModel {
    enum State: Equatable {
        case idle
        case searching
        case results
        /// Nothing came back. Lookup failures (offline) end up here too, because the lookup never throws.
        case empty
    }

    private(set) var results: [PlaceCandidate] = []
    private(set) var state: State = .idle
    var query: String

    private let lookup: any PlaceLookup
    private let latitude: Double?
    private let longitude: Double?
    private let debounce: Duration
    private var task: Task<Void, Never>?

    init(lookup: any PlaceLookup, latitude: Double?, longitude: Double?, query: String = "",
         debounce: Duration = .milliseconds(400)) {
        self.lookup = lookup
        self.latitude = latitude
        self.longitude = longitude
        self.query = query
        self.debounce = debounce
    }

    /// The text field changed: search after the user pauses typing.
    func queryChanged() { start(after: debounce) }

    /// Return, or the sheet opening with a name already filled in.
    func submit() { start(after: .zero) }

    private func start(after delay: Duration) {
        task?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            results = []
            state = .idle
            return
        }
        task = Task {
            if delay > .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            state = .searching
            let found = await lookup.search(q, nearLatitude: latitude, nearLongitude: longitude)
            guard !Task.isCancelled else { return }   // a newer query is on its way; don't show this answer
            results = found
            state = found.isEmpty ? .empty : .results
        }
    }

    var message: String? {
        switch state {
        case .idle: "Type a place name to search."
        case .searching: results.isEmpty ? "Searching..." : nil
        case .results: nil
        case .empty: "No places found. Searching needs an internet connection."
        }
    }
}
