import Foundation

struct JourneyStats: Equatable {
    var stops: Int
    var km: Double
    var hasKm: Bool
    var spentMinutes: Int
    var travelMinutes: Int
    var money: [String: Decimal]
    var photos: Int
    /// Distinct chosen modes in order of first use.
    var modes: [TransportMode]

    /// Decision 3: time at stops + travel time.
    var totalMinutes: Int { spentMinutes + travelMinutes }

    init(journey: Journey) {
        let stops = journey.orderedStops
        self.stops = stops.count
        self.photos = stops.reduce(0) { $0 + $1.photos.count }
        self.spentMinutes = stops.reduce(0) { $0 + ($1.timeSpentMinutes ?? 0) }
        var money: [String: Decimal] = [:]
        for s in stops { if let c = s.cost { money[c.currency, default: 0] += c.amount } }
        self.money = money
        let legs = stops.compactMap { $0.outgoingLeg }
        let kms = legs.compactMap { $0.distanceKm }
        self.hasKm = !kms.isEmpty
        self.km = kms.reduce(0, +)
        self.travelMinutes = legs.reduce(0) { $0 + ($1.durationMinutes ?? 0) }
        var modes: [TransportMode] = []
        for l in legs where l.modeWasChosen && !modes.contains(l.mode) { modes.append(l.mode) }
        self.modes = modes
    }
}
