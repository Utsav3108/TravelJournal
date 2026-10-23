import Foundation

/// Stop category. Stored as a raw string on `Stop`; unknown raw values fall back to `.other`.
nonisolated enum StopCategory: String, CaseIterable, Codable, Sendable {
    case food, landmark, temple, stay, shopping, nature, other

    init(storedRaw: String) { self = StopCategory(rawValue: storedRaw) ?? .other }
}
typealias Category = StopCategory

/// How the traveller moved between two stops. Stored as raw string; unknown falls back to `.walk`.
nonisolated enum TransportMode: String, CaseIterable, Codable, Sendable {
    case walk, autoRickshaw, taxi, bus, localTrain, metro, bike, ferry

    init(storedRaw: String) { self = TransportMode(rawValue: storedRaw) ?? .walk }

    /// Single source of truth for the transport glyph.
    var icon: KraftTransport {
        switch self {
        case .walk: .walk
        case .autoRickshaw: .autoRickshaw
        case .taxi: .taxi
        case .bus: .bus
        case .localTrain: .train
        case .metro: .metro
        case .bike: .bike
        case .ferry: .ferry
        }
    }

    /// Icon for a stored `StoryLeg.modeRaw`; nil when no mode. Tolerates legacy KraftTransport raws.
    static func icon(forRaw raw: String?) -> KraftTransport? {
        guard let raw else { return nil }
        if let m = TransportMode(rawValue: raw) { return m.icon }
        return KraftTransport(rawValue: raw)
    }
}

/// Money amount with ISO 4217 currency code.
nonisolated struct Cost: Equatable, Hashable, Sendable {
    var amount: Decimal
    var currency: String
}
