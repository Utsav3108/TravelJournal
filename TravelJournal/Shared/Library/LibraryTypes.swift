import Foundation

/// Value snapshot of a story for the library screens. Pure data (no SwiftData), so grouping is unit-testable.
struct LibraryStory: Identifiable, Hashable, Sendable {
    let id: UUID                // Journey.id
    var title: String
    var date: Date
    var dateText: String        // "19 Oct 2026", shown on the cover and matched by search
    var city: String?
    var country: String?
    var weight: Int             // stops count; drives spine thickness
    var coverPhotoID: UUID?     // Journey.coverPhoto?.id; nil if none (or a sample photo with no image)
}

/// Which stories a Cover Rack shows. `query` (non-empty) narrows the scope to search matches.
struct StoryScope: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case all                    // the "All Stories" shelf
        case recent                 // the "Recent" shelf: newest `LibraryIndex.maxSlotsPerShelf` stories
        case country(String)
        case city(String)           // city shelf (used when the library has a single country) or a city chip
        case other                  // stories without a country
    }
    var kind: Kind
    var title: String               // navigation title, e.g. "India"
    var query: String = ""
}

enum LibraryShelfSlot: Hashable, Sendable {
    case spine(LibraryStory)
    /// `count` = hidden stories (the "+N more" number); `firstHiddenIndex` indexes `LibraryShelf.stories`.
    case more(count: Int, firstHiddenIndex: Int)
}

struct LibraryShelf: Identifiable, Hashable, Sendable {
    var id: String                  // stable per category, e.g. "country:India", "recent", "all", "other"
    var title: String               // label plate text
    var scope: StoryScope
    var stories: [LibraryStory]     // every story on this shelf (after any search filter), newest first
    var slots: [LibraryShelfSlot]   // at most `LibraryIndex.maxSlotsPerShelf`
    var colorIndex: Int             // 0..<LibraryIndex.paletteSize, stable per category
}

struct LibraryCity: Identifiable, Hashable, Sendable {
    var name: String
    var count: Int
    var id: String { name }
}

struct LibraryCountry: Identifiable, Hashable, Sendable {
    var name: String                // "Other" is never listed here
    var count: Int
    var cities: [LibraryCity]       // newest-first by latest story, then name
    var id: String { name }
}

/// Everything the Bookcase needs from its host.
struct LibraryActions {
    var openStory: (LibraryStory) -> Void
    var openRack: (StoryScope, UUID) -> Void    // scope + the story to start on
    var openPlaces: () -> Void
    var requestDelete: (LibraryStory) -> Void
}
