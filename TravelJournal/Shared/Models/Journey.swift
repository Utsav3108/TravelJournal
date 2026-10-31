import Foundation
import SwiftData

@Model
final class Journey {
    var id: UUID = UUID()
    var title: String = ""
    var date: Date = Date()
    var timeZoneID: String = TimeZone.current.identifier
    var city: String?
    var country: String?
    var coverPhotoID: UUID?
    var introNote: String?
    var closingNote: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var schemaTag: Int = 1
    /// JSON-encoded `ExportPrivacy` override for this journey; nil = use the global defaults (V4). Use `exportPrivacy`.
    var exportPrivacyData: Data?
    /// The `Stop.id` this story is pinned at on the bookshelf map (V5); nil or a deleted stop = the default. See `StoryMapPins`.
    var mapStopID: UUID?
    /// The `StopPhoto.id` shown as this story's pin on the Mac map (V6); nil or a deleted photo = the cover photo.
    var mapPinPhotoID: UUID?

    /// CloudKit requires to-many relationships to be optional. `originalName` keeps the V2 column ("stops") so the
    /// migration treats this as a rename, not a new relationship. Use `stops`.
    @Relationship(deleteRule: .cascade, originalName: "stops", inverse: \Stop.journey)
    var stopsStorage: [Stop]?

    var stops: [Stop] {
        get { stopsStorage ?? [] }
        set { stopsStorage = newValue }
    }

    init(title: String, date: Date = .now, city: String? = nil, country: String? = nil) {
        self.title = title
        self.date = date
        self.city = city
        self.country = country
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

    /// Stored country, trimmed; nil when empty.
    var displayCountry: String? {
        guard let c = country?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty else { return nil }
        return c
    }

    /// Cover: explicit `coverPhotoID`, else first stop's hero, else first hero of any stop.
    var coverPhoto: StopPhoto? {
        let stops = orderedStops
        if let id = coverPhotoID, let p = stops.flatMap({ $0.photos }).first(where: { $0.id == id }) { return p }
        if let h = stops.first?.hero { return h }
        return stops.lazy.compactMap { $0.hero }.first
    }

    /// Map pin photo: the chosen `mapPinPhotoID` if it still exists, else the cover photo, else nil.
    var mapPinPhoto: StopPhoto? {
        if let id = mapPinPhotoID, let p = allPhotos.first(where: { $0.id == id }) { return p }
        return coverPhoto
    }

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
