#if os(macOS)
import Foundation
import MapKit

/// One line of the multi-story popover.
nonisolated struct StoryPinRow: Identifiable, Equatable {
    let id: UUID
    let title: String
    let date: Date
    let city: String?

    var displayTitle: String { title.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : title }
    var subtitle: String {
        let day = date.formatted(.dateTime.day().month(.abbreviated).year())
        guard let city = city?.trimmingCharacters(in: .whitespaces), !city.isEmpty else { return day }
        return "\(day) · \(city)"
    }
}

nonisolated enum StoryMapLogic {
    /// Rows for a pin's journey ids, newest first. Ids with no matching journey are dropped.
    @MainActor
    static func rows(for ids: [UUID], in journeys: [Journey]) -> [StoryPinRow] {
        let wanted = Set(ids)
        return journeys.filter { wanted.contains($0.id) }
            .map { StoryPinRow(id: $0.id, title: $0.title, date: $0.date, city: $0.displayCity) }
            .sorted { $0.date > $1.date }
    }

    /// A region that frames every coordinate with some padding; a single point gets a city-sized span.
    static func region(fitting coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coordinates {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: min(180, max((maxLat - minLat) * 1.4, 0.2)),
                                    longitudeDelta: min(360, max((maxLon - minLon) * 1.4, 0.2)))
        return MKCoordinateRegion(center: center, span: span)
    }
}
#endif
