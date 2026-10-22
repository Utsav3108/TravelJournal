import Foundation

/// Pure grouping, slot and search logic for the library.
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
    static func shelves(from stories: [LibraryStory], query: String = "") -> [LibraryShelf] {
        let sorted = sortNewestFirst(stories)
        var groups: [(id: String, title: String, kind: StoryScope.Kind, items: [LibraryStory])] = []

        if sorted.count < minStoriesForGrouping {
            groups.append(("all", "All Stories", .all, sorted))
        } else {
            let distinct = Set(sorted.compactMap { clean($0.country) })
            var categories: [(name: String, kind: StoryScope.Kind, id: String, items: [LibraryStory])] = []
            var other: [LibraryStory] = []
            if distinct.count == 1 {
                var byCity: [String: [LibraryStory]] = [:]
                for st in sorted {
                    if let c = clean(st.city) { byCity[c, default: []].append(st) } else { other.append(st) }
                }
                categories = byCity.map { ($0.key, StoryScope.Kind.city($0.key), "city:\($0.key)", $0.value) }
            } else {
                var byCountry: [String: [LibraryStory]] = [:]
                for st in sorted {
                    if let c = clean(st.country) { byCountry[c, default: []].append(st) } else { other.append(st) }
                }
                categories = byCountry.map { ($0.key, StoryScope.Kind.country($0.key), "country:\($0.key)", $0.value) }
            }
            categories.sort { a, b in
                let da = a.items[0].date, db = b.items[0].date   // newest first, never empty
                if da != db { return da > db }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            if sorted.count > maxSlotsPerShelf {
                groups.append(("recent", "Recent", .recent, Array(sorted.prefix(maxSlotsPerShelf))))
            }
            for c in categories { groups.append((c.id, c.name, c.kind, c.items)) }
            if !other.isEmpty { groups.append(("other", "Other", .other, other)) }
        }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return groups.compactMap { g in
            let items = q.isEmpty ? g.items : g.items.filter { matches($0, query: q) }
            guard !items.isEmpty else { return nil }
            return LibraryShelf(
                id: g.id, title: g.title,
                scope: StoryScope(kind: g.kind, title: g.title, query: q),
                stories: items, slots: slots(for: items),
                colorIndex: colorIndex(forCategory: g.title))
        }
    }

    /// Stories a Cover Rack shows for `scope` (newest first), with `scope.query` applied.
    /// `.other` rule: stories without a country; EXCEPT when the library has exactly one distinct country
    /// (city-grouped shelves), where "Other" holds the stories without a city (matching the shelf).
    static func stories(in scope: StoryScope, from all: [LibraryStory]) -> [LibraryStory] {
        let sorted = sortNewestFirst(all)
        let base: [LibraryStory]
        switch scope.kind {
        case .all: base = sorted
        case .recent: base = Array(sorted.prefix(maxSlotsPerShelf))
        case .country(let c): base = sorted.filter { clean($0.country) == c }
        case .city(let c): base = sorted.filter { clean($0.city) == c }
        case .other:
            let distinct = Set(sorted.compactMap { clean($0.country) })
            if distinct.count == 1 {
                base = sorted.filter { clean($0.city) == nil }
            } else {
                base = sorted.filter { clean($0.country) == nil }
            }
        }
        let q = scope.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? base : base.filter { matches($0, query: q) }
    }

    /// Every query word must match title, city, country or dateText (case/diacritic-insensitive).
    static func matches(_ story: LibraryStory, query: String) -> Bool {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return true }
        let fields = [story.title, story.city ?? "", story.country ?? "", story.dateText]
        return words.allSatisfy { w in fields.contains { $0.localizedStandardContains(w) } }
    }

    /// Cities (with counts) among `stories`, for the Cover Rack chips.
    static func cities(in stories: [LibraryStory]) -> [LibraryCity] {
        var counts: [String: Int] = [:]
        for st in stories { if let c = clean(st.city) { counts[c, default: 0] += 1 } }
        return counts.map { LibraryCity(name: $0.key, count: $0.value) }.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Countries with their cities, for the Places browser. Stories without a country are excluded.
    static func countries(from stories: [LibraryStory]) -> [LibraryCountry] {
        var by: [String: [LibraryStory]] = [:]
        for st in stories { if let c = clean(st.country) { by[c, default: []].append(st) } }
        func newest(_ xs: [LibraryStory]) -> Date { xs.map(\.date).max() ?? .distantPast }
        let result = by.map { (name, items) -> (LibraryCountry, Date) in
            var cityItems: [String: [LibraryStory]] = [:]
            for st in items { if let c = clean(st.city) { cityItems[c, default: []].append(st) } }
            let cities = cityItems.sorted { a, b in
                let da = newest(a.value), db = newest(b.value)
                if da != db { return da > db }
                return a.key.localizedStandardCompare(b.key) == .orderedAscending
            }.map { LibraryCity(name: $0.key, count: $0.value.count) }
            return (LibraryCountry(name: name, count: items.count, cities: cities), newest(items))
        }
        return result.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            return a.0.name.localizedStandardCompare(b.0.name) == .orderedAscending
        }.map(\.0)
    }

    /// Stable palette index for a category name (FNV-1a, never `hashValue`).
    static func colorIndex(forCategory name: String) -> Int {
        var h: UInt32 = 2166136261
        for b in name.utf8 { h ^= UInt32(b); h = h &* 16777619 }
        return Int(h % UInt32(paletteSize))
    }

    // MARK: - Helpers

    private static func clean(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    private static func sortNewestFirst(_ xs: [LibraryStory]) -> [LibraryStory] {
        xs.sorted { a, b in
            if a.date != b.date { return a.date > b.date }
            let c = a.title.localizedStandardCompare(b.title)
            if c != .orderedSame { return c == .orderedAscending }
            return a.id.uuidString < b.id.uuidString
        }
    }

    private static func slots(for items: [LibraryStory]) -> [LibraryShelfSlot] {
        if items.count <= maxSlotsPerShelf { return items.map { .spine($0) } }
        let shown = maxSlotsPerShelf - 1
        return items.prefix(shown).map { .spine($0) }
            + [.more(count: items.count - shown, firstHiddenIndex: shown)]
    }
}
