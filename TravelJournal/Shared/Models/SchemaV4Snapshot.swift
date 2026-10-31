import Foundation
import SwiftData

/// Frozen copy of the V4 model set (V3 plus the export privacy columns `Journey.exportPrivacyData` /
/// `Stop.exportHidden`, before `Journey.mapStopID`). Never edit these; they exist so SwiftData can migrate V4 stores
/// to V5. Nested types shadow the live top-level models inside this enum.
enum TJSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] { [Journey.self, Stop.self, StopPhoto.self, Leg.self] }

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
        var exportPrivacyData: Data?

        @Relationship(deleteRule: .cascade, originalName: "stops", inverse: \Stop.journey)
        var stopsStorage: [Stop]?

        init(title: String, date: Date = .now, city: String? = nil, country: String? = nil) {
            self.title = title
            self.date = date
            self.city = city
            self.country = country
        }
    }

    @Model
    final class Stop {
        var id: UUID = UUID()
        var orderIndex: Int = 0
        var journey: Journey?
        var placeName: String = ""
        var story: String = ""
        var latitude: Double?
        var longitude: Double?
        var address: String?
        var cityHint: String?
        var arrivalTime: Date?
        var timeSpentMinutes: Int?
        var categoryRaw: String?
        var highlight: String?
        var ratingRaw: Int?
        var review: String?
        var costAmount: Decimal?
        var costCurrency: String?
        var exportHidden: Bool?

        @Relationship(deleteRule: .cascade, originalName: "photos", inverse: \StopPhoto.stop)
        var photosStorage: [StopPhoto]?

        @Relationship(deleteRule: .cascade, inverse: \Leg.fromStop)
        var outgoingLeg: Leg?

        @Relationship(deleteRule: .nullify, inverse: \Leg.toStop)
        var incomingLeg: Leg?

        init(placeName: String) { self.placeName = placeName }
    }

    @Model
    final class StopPhoto {
        var id: UUID = UUID()
        var stop: Stop?
        var orderIndex: Int = 0
        var isHero: Bool = false
        @Attribute(.externalStorage) var imageData: Data?
        var pixelWidth: Int = 0
        var pixelHeight: Int = 0
        var captureDate: Date?
        var latitude: Double?
        var longitude: Double?
        var caption: String?

        init() {}
    }

    @Model
    final class Leg {
        var id: UUID = UUID()
        var fromStop: Stop?
        var toStop: Stop?
        var modeRaw: String = TransportMode.walk.rawValue
        var modeWasChosen: Bool = false
        var distanceKm: Double?
        var durationMinutes: Int?
        var story: String?

        init() {}
    }
}
