import Foundation
import SwiftData

/// Frozen copy of the V1 model set (before `Journey.country`). Never edit these; they exist so SwiftData can
/// migrate V1 stores to V2. Nested types shadow the live top-level models inside this enum.
enum TJSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Journey.self, Stop.self, StopPhoto.self, Leg.self] }

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

        @Relationship(deleteRule: .cascade, inverse: \StopPhoto.stop)
        var photos: [StopPhoto] = []

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
        var relativePath: String = ""
        var thumbRelativePath: String = ""
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
