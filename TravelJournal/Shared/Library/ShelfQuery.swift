import Foundation

enum ShelfSort: String, CaseIterable, Identifiable, Sendable {
    case newest, oldest, title

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newest: "Newest First"
        case .oldest: "Oldest First"
        case .title: "Title"
        }
    }
}

/// Search and sort for the Mac shelf. Always applied to every journey, never just the visible ones.
enum ShelfQuery {
    static func apply(_ stories: [LibraryStory], query: String, sort: ShelfSort) -> [LibraryStory] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let kept = q.isEmpty ? stories : stories.filter { matches($0, query: q) }
        return kept.sorted { areInOrder($0, $1, sort: sort) }
    }

    /// Every query word must match the title, city, country, date, a stop name or the story text
    /// (case and diacritic insensitive).
    static func matches(_ story: LibraryStory, query: String) -> Bool {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return true }
        let fields = [story.title, story.city ?? "", story.country ?? "", story.dateText, story.searchText]
        return words.allSatisfy { w in fields.contains { $0.localizedStandardContains(w) } }
    }

    private static func areInOrder(_ a: LibraryStory, _ b: LibraryStory, sort: ShelfSort) -> Bool {
        switch sort {
        case .newest: if a.date != b.date { return a.date > b.date }
        case .oldest: if a.date != b.date { return a.date < b.date }
        case .title: break
        }
        let c = a.title.localizedStandardCompare(b.title)
        if c != .orderedSame { return c == .orderedAscending }
        if sort == .title, a.date != b.date { return a.date > b.date }
        return a.id.uuidString < b.id.uuidString
    }
}
