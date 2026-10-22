import Foundation
import CoreLocation
import SwiftData

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
    /// Locality from reverse geocoding; used as the journey city default.
    var cityHint: String?
    var arrivalTime: Date?
    var timeSpentMinutes: Int?
    var categoryRaw: String?
    var highlight: String?
    var ratingRaw: Int?
    var review: String?
    var costAmount: Decimal?
    var costCurrency: String?

    /// CloudKit requires to-many relationships to be optional. `originalName` keeps the V2 column ("photos") so the
    /// migration treats this as a rename, not a new relationship. Use `photos`.
    @Relationship(deleteRule: .cascade, originalName: "photos", inverse: \StopPhoto.stop)
    var photosStorage: [StopPhoto]?

    var photos: [StopPhoto] {
        get { photosStorage ?? [] }
        set { photosStorage = newValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \Leg.fromStop)
    var outgoingLeg: Leg?

    @Relationship(deleteRule: .nullify, inverse: \Leg.toStop)
    var incomingLeg: Leg?

    init(placeName: String, story: String = "", category: StopCategory? = nil) {
        self.placeName = placeName
        self.story = story
        self.categoryRaw = category?.rawValue
    }

    var category: StopCategory? {
        get { categoryRaw.map { StopCategory(storedRaw: $0) } }
        set { categoryRaw = newValue?.rawValue }
    }

    /// 1...5, clamped on set.
    var rating: Int? {
        get { ratingRaw }
        set { ratingRaw = newValue.map { min(5, max(1, $0)) } }
    }

    var cost: Cost? {
        get {
            guard let a = costAmount, let c = costCurrency, !c.isEmpty else { return nil }
            return Cost(amount: a, currency: c)
        }
        set { costAmount = newValue?.amount; costCurrency = newValue?.currency }
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var orderedPhotos: [StopPhoto] { photos.sorted { $0.orderIndex < $1.orderIndex } }
    var hero: StopPhoto? { photos.first(where: \.isHero) ?? orderedPhotos.first }

    /// Make `photo` the hero, clearing all others.
    func setHero(_ photo: StopPhoto) {
        for p in photos { p.isHero = (p === photo) }
    }
}
