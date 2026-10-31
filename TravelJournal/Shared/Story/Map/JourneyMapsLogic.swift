import Foundation

/// One pin to hand to the Maps app.
nonisolated struct MapsPin: Hashable, Sendable {
    enum Role: Sendable { case start, stop, end }
    var name: String
    var latitude: Double
    var longitude: Double
    var role: Role
}

/// Which of a journey's stops can be shown in Maps. Stops with no coordinates are skipped; at least two must remain.
nonisolated enum JourneyMapsLogic {
    static let minimumLocated = 2

    enum Readiness: Equatable, Sendable {
        case ready([MapsPin])
        case needsLocations(located: Int, missing: [OverviewStop])
    }

    static func pins(from overview: OverviewModel) -> [MapsPin] { pins(from: overview.stops) }

    static func pins(from stops: [OverviewStop]) -> [MapsPin] {
        let located = stops.compactMap { stop -> (OverviewStop, Double, Double)? in
            guard let lat = stop.latitude, let lon = stop.longitude else { return nil }
            return (stop, lat, lon)
        }
        return located.enumerated().map { i, item in
            let role: MapsPin.Role = i == 0 ? .start : (i == located.count - 1 ? .end : .stop)
            return MapsPin(name: item.0.name.isEmpty ? "Stop \(item.0.number)" : item.0.name,
                           latitude: item.1, longitude: item.2, role: role)
        }
    }

    static func readiness(for overview: OverviewModel) -> Readiness { readiness(forStops: overview.stops) }

    static func readiness(forStops stops: [OverviewStop]) -> Readiness {
        let pins = pins(from: stops)
        if pins.count >= minimumLocated { return .ready(pins) }
        let missing = stops.filter { $0.latitude == nil || $0.longitude == nil }
        return .needsLocations(located: pins.count, missing: missing)
    }

    /// The name Maps shows on a pin.
    static func label(for pin: MapsPin) -> String {
        switch pin.role {
        case .start: "Start: \(pin.name)"
        case .end: "End: \(pin.name)"
        case .stop: pin.name
        }
    }
}
