import Foundation

/// Stop category. Stored as a raw string on `Stop`; unknown raw values fall back to `.other`.
enum StopCategory: String, CaseIterable, Codable {
    case food, landmark, temple, stay, shopping, nature, other

    init(storedRaw: String) { self = StopCategory(rawValue: storedRaw) ?? .other }
}
typealias Category = StopCategory

/// How the traveller moved between two stops. Stored as raw string; unknown falls back to `.walk`.
enum TransportMode: String, CaseIterable, Codable {
    case walk, autoRickshaw, taxi, bus, localTrain, metro, bike, ferry

    init(storedRaw: String) { self = TransportMode(rawValue: storedRaw) ?? .walk }
}

/// Money amount with ISO 4217 currency code.
struct Cost: Equatable, Hashable {
    var amount: Decimal
    var currency: String
}
