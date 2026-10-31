#if os(macOS)
import Foundation

/// The rows of the shelf window's sidebar.
nonisolated enum ShelfSidebarItem: String, CaseIterable, Identifiable, Hashable {
    case journey, map, calendar, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .journey: "Journey"
        case .map: "Map"
        case .calendar: "Calendar"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .journey: "book.closed"
        case .map: "map"
        case .calendar: "calendar"
        case .settings: "gearshape"
        }
    }

    /// Calendar and Settings are placeholders for now: shown with "Soon", not selectable.
    var isAvailable: Bool {
        switch self {
        case .journey, .map: true
        case .calendar, .settings: false
        }
    }
}
#endif
