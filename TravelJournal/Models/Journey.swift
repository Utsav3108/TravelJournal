import Foundation
import SwiftData

@Model
final class Journey {
    var id: UUID = UUID()
    var title: String = ""
    var date: Date = Date()
    var timeZoneID: String = TimeZone.current.identifier
    var city: String?
    var coverPhotoID: UUID?
    var introNote: String?
    var closingNote: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var schemaTag: Int = 1

    @Relationship(deleteRule: .cascade, inverse: \Stop.journey)
    var stops: [Stop] = []

    init(title: String, date: Date = .now, city: String? = nil) {
        self.title = title
        self.date = date
        self.city = city
    }

    var orderedStops: [Stop] { stops.sorted { $0.orderIndex < $1.orderIndex } }

    var allPhotos: [StopPhoto] { orderedStops.flatMap { $0.orderedPhotos } }

    /// Legs in route order (leg i joins stop i and i+1).
    var orderedLegs: [Leg] { orderedStops.compactMap { $0.outgoingLeg } }

    // MARK: Derived defaults

    /// Journey date default: earliest photo capture date (start of day), else `fallback`.
    static func defaultDate(photoDates: [Date], fallback: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: photoDates.min() ?? fallback)
    }

    /// Stored city if non-empty, else the first stop's `cityHint` (if any).
    var displayCity: String? {
        if let c = city?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty { return c }
        return orderedStops.first?.cityHint
    }

    /// Cover: explicit `coverPhotoID`, else first stop's hero, else first hero of any stop.
    var coverPhoto: StopPhoto? {
        let stops = orderedStops
        if let id = coverPhotoID, let p = stops.flatMap({ $0.photos }).first(where: { $0.id == id }) { return p }
        if let h = stops.first?.hero { return h }
        return stops.lazy.compactMap { $0.hero }.first
    }

    /// Relative path (resolve through `PhotoStoring.url(for:)`) of the cover photo's display image.
    var coverPhotoPath: String? { coverPhoto?.relativePath }
    var coverThumbPath: String? { coverPhoto?.thumbRelativePath }

    /// "ARRIVED · 19 OCT 2026 · MUMBAI"
    var postmarkText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM yyyy"
        f.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        var s = "ARRIVED · \(f.string(from: date).uppercased())"
        if let c = displayCity { s += " · \(c.uppercased())" }
        return s
    }
}
