import Foundation
import CoreLocation

/// One pin on the bookshelf map: the stories whose map stops lie within `StoryMapPins.groupRadius` of each other.
nonisolated struct StoryPin: Identifiable {
    /// Stable across runs: the smallest journey id in the group.
    let id: String
    let coordinate: CLLocationCoordinate2D
    /// `Journey.id` values, newest journey date first, ties by id.
    let journeyIDs: [UUID]
}

/// Which stop pins a story on the map, and how nearby pins merge. Pure; the views only draw the result.
nonisolated enum StoryMapPins {
    /// Pins closer than this (metres) share one `StoryPin`.
    static let groupRadius: CLLocationDistance = 50

    /// The chosen stop if it still exists, else the earliest stop with coordinates, else the earliest stop.
    @MainActor
    static func mapStop(for journey: Journey) -> Stop? {
        let stops = journey.orderedStops
        if let id = journey.mapStopID, let chosen = stops.first(where: { $0.id == id }) { return chosen }
        return stops.first(where: { $0.coordinate != nil }) ?? stops.first
    }

    @MainActor
    static func pins(for journeys: [Journey]) -> [StoryPin] {
        let items: [Item] = journeys.compactMap { journey in
            guard let c = mapStop(for: journey)?.coordinate else { return nil }
            return Item(id: journey.id, date: journey.date, coordinate: c)
        }
        return group(items)
    }

    struct Item {
        var id: UUID
        var date: Date
        var coordinate: CLLocationCoordinate2D
    }

    /// Single-link clustering (connected components under `groupRadius`), so the result does not depend on input order.
    static func group(_ items: [Item]) -> [StoryPin] {
        var parent = Array(items.indices)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        for i in items.indices {
            for j in items.indices where j > i && distance(items[i].coordinate, items[j].coordinate) <= groupRadius {
                parent[find(i)] = find(j)
            }
        }
        let clusters = Dictionary(grouping: items.indices, by: find).values.map { $0.map { items[$0] } }
        let pins = clusters.map { cluster -> StoryPin in
            let ordered = cluster.sorted { $0.date != $1.date ? $0.date > $1.date : $0.id.uuidString < $1.id.uuidString }
            // Centre = mean of the members, summed in id order so float rounding is order independent.
            let byID = cluster.sorted { $0.id.uuidString < $1.id.uuidString }
            let lat = byID.map(\.coordinate.latitude).reduce(0, +) / Double(byID.count)
            let lon = byID.map(\.coordinate.longitude).reduce(0, +) / Double(byID.count)
            return StoryPin(id: byID[0].id.uuidString,
                            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                            journeyIDs: ordered.map(\.id))
        }
        return pins.sorted { $0.id < $1.id }
    }

    private static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
