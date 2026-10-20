import Foundation

/// Pure grouping, slot and search logic for the library. CONTRACT STUB: Agent B replaces the bodies.
/// Signatures are frozen; other agents code against them.
enum LibraryIndex {
    static let maxSlotsPerShelf = 10
    static let minStoriesForGrouping = 7
    static let paletteSize = 8

    /// Shelves for the bookcase. Grouping is decided on the FULL library; `query` then filters each shelf's
    /// stories (same slot rule applies) and hides empty shelves.
    ///  - < minStoriesForGrouping stories: one "All Stories" shelf.
    ///  - else: "Recent" (only if total > maxSlotsPerShelf) then one shelf per country; one country only -> per city.
    ///  - Order: Recent, then categories by newest story date (ties by name), "Other" (no country) last.
    ///  - Slots: <= 10 stories -> all spines; > 10 -> 9 spines + .more(count: n - 9, firstHiddenIndex: 9).
    static func shelves(from stories: [LibraryStory], query: String = "") -> [LibraryShelf] { [] }

    /// Stories a Cover Rack shows for `scope` (newest first), with `scope.query` applied.
    static func stories(in scope: StoryScope, from all: [LibraryStory]) -> [LibraryStory] { [] }

    /// Every query word must match title, city, country or dateText (case/diacritic-insensitive).
    static func matches(_ story: LibraryStory, query: String) -> Bool { false }

    /// Cities (with counts) among `stories`, for the Cover Rack chips.
    static func cities(in stories: [LibraryStory]) -> [LibraryCity] { [] }

    /// Countries with their cities, for the Places browser. Stories without a country are excluded.
    static func countries(from stories: [LibraryStory]) -> [LibraryCountry] { [] }

    /// Stable palette index for a category name (FNV-1a, never `hashValue`).
    static func colorIndex(forCategory name: String) -> Int { 0 }
}
