import Foundation

/// A latitude/longitude pair that is cheap to hash and send across actors.
nonisolated struct Coordinate: Hashable, Sendable {
    var latitude: Double
    var longitude: Double
}

/// How Maps should travel between two points.
nonisolated enum MapsTransport: Hashable, Sendable { case driving, walking, transit, cycling }

/// How a leg is turned into a line on the map.
nonisolated enum RouteStrategy: Equatable, Sendable {
    case directions(MapsTransport)
    case straightLine
}

/// Look of a leg's line. `colorToken` names a static `KraftColor` property.
nonisolated struct LegLineStyle: Hashable, Sendable {
    var colorToken: String
    var dash: [CGFloat]          // empty = solid
    var width: CGFloat
}

/// One drawable hop between two located stops.
nonisolated struct LegSegment: Hashable, Identifiable, Sendable {
    var id: String
    var fromStopID: String
    var toStopID: String
    var from: Coordinate
    var to: Coordinate
    var mode: TransportMode
}

nonisolated enum LegRouting {
    static func strategy(for mode: TransportMode) -> RouteStrategy {
        switch mode {
        case .walk: .directions(.walking)
        case .taxi, .autoRickshaw: .directions(.driving)
        case .bike: .directions(.cycling)
        case .bus, .localTrain, .metro: .directions(.transit)
        case .ferry: .straightLine
        }
    }

    static func style(for mode: TransportMode) -> LegLineStyle {
        switch mode {
        case .taxi, .autoRickshaw, .bike: LegLineStyle(colorToken: "route", dash: [], width: 3)
        case .bus: LegLineStyle(colorToken: "route", dash: [10, 4], width: 3)
        case .localTrain, .metro: LegLineStyle(colorToken: "stampTeal", dash: [12, 3, 2, 3], width: 3.5)
        case .walk: LegLineStyle(colorToken: "kraftDark", dash: [1, 5], width: 2.5)
        case .ferry: LegLineStyle(colorToken: "stampTeal", dash: [8, 6], width: 2.5)
        }
    }

    /// Segments between consecutive located stops. Unlocated stops are skipped; a segment uses
    /// the mode of the leg leaving the previous located stop.
    static func segments(for model: OverviewModel) -> [LegSegment] {
        var result: [LegSegment] = []
        var previous: (index: Int, stop: OverviewStop, coord: Coordinate)?
        for (i, stop) in model.stops.enumerated() {
            guard let lat = stop.latitude, let lon = stop.longitude else { continue }
            let coord = Coordinate(latitude: lat, longitude: lon)
            if let p = previous {
                let raw = p.index < model.legs.count ? model.legs[p.index].modeRaw : nil
                let mode = raw.map(TransportMode.init(storedRaw:)) ?? .walk
                result.append(LegSegment(id: "\(p.stop.id)->\(stop.id)", fromStopID: p.stop.id, toStopID: stop.id,
                                         from: p.coord, to: coord, mode: mode))
            }
            previous = (i, stop, coord)
        }
        return result
    }
}
