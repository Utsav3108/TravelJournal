import Foundation

/// Pure helpers for the story viewer (unit tested).
nonisolated enum StoryViewerLogic {
    /// Index of the page with `id`, or nil.
    static func index(of id: String?, in pages: [StoryPage]) -> Int? {
        guard let id else { return nil }
        return pages.firstIndex { $0.id == id }
    }

    /// Page id to show after the page list was rebuilt: keep `current` if it still exists,
    /// otherwise clamp the old index into the new list, otherwise nil when empty.
    static func stableCurrentID(current: String?, oldIndex: Int, in pages: [StoryPage]) -> String? {
        guard !pages.isEmpty else { return nil }
        if let current, pages.contains(where: { $0.id == current }) { return current }
        return pages[min(max(oldIndex, 0), pages.count - 1)].id
    }

    /// How long a tap-revealed bar stays on pages 2+.
    static let barRevealSeconds: Double = 3

    /// Navigation bar shows on the cover, or temporarily after a tap on later pages.
    static func barVisible(pageIndex: Int, tempReveal: Bool) -> Bool { pageIndex <= 0 || tempReveal }

    /// A temporary reveal only survives while staying on the same page; any page change clears it.
    static func revealAfterPageChange(from old: Int, to new: Int, tempReveal: Bool) -> Bool {
        old == new ? tempReveal : false
    }

    /// "3 / 6"
    static func indicatorText(index: Int, total: Int) -> String { "\(index + 1) / \(total)" }

    static func pageLabel(_ page: StoryPage, index: Int, total: Int) -> String {
        let head = "Page \(index + 1) of \(total), "
        switch page {
        case .cover(let m): return head + "Cover: \(m.title)"
        case .overview: return head + "Route overview"
        case .stop(let m): return head + "Stop: \(m.name)"
        case .closing: return head + "The end"
        }
    }

    // MARK: Leg card

    /// "Auto", "Local train", ... (accepts TransportMode and legacy KraftTransport raws).
    static func modeName(_ raw: String?) -> String? { TravelFormat.modeName(raw: raw) }

    static func kmText(_ km: Double?) -> String? { km.map(TravelFormat.km) }

    static func minutesText(_ m: Int?) -> String? { m.map { TravelFormat.legDuration(minutes: $0) } }

    struct LegCardText: Equatable {
        var title: String
        var details: [String]
        var story: String?
        var emptyNote: String?
        var accessibility: String
    }

    static func legCardText(_ leg: StoryLeg) -> LegCardText {
        let mode = modeName(leg.modeRaw)
        let title = mode ?? "Travel"
        let details = [minutesText(leg.minutes), kmText(leg.km)].compactMap { $0 }
        let trimmed = leg.story?.trimmingCharacters(in: .whitespacesAndNewlines)
        let story = (trimmed?.isEmpty == false) ? trimmed : nil
        let empty: String? = story == nil ? (details.isEmpty && mode == nil ? "No travel details yet." : "No story for this leg yet.") : nil
        var acc = ([title] + details).joined(separator: ", ")
        if let story { acc += ". " + story } else if let empty { acc += ". " + empty }
        return LegCardText(title: title, details: details, story: story, emptyNote: empty, accessibility: acc)
    }
}
