import Foundation

/// DesignSystem-local mirrors of the spec lists (raw values match the spec).
enum KraftCategory: String, CaseIterable, Identifiable {
    case food, landmark, temple, stay, shopping, nature, other
    var id: String { rawValue }
}

enum KraftTransport: String, CaseIterable, Identifiable {
    case walk, autoRickshaw = "auto-rickshaw", taxi, bus, train, metro, bike, ferry
    var id: String { rawValue }
}
