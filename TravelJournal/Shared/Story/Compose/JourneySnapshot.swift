import Foundation
import CoreGraphics

/// Plain value copy of a `Journey` for export: stops, legs, photo references (no image bytes) and totals.
/// Built once on the main actor; `PrivacyFilter` and the composers read only this, never SwiftData models.
///
/// Invariant: `legs.count == max(stops.count - 1, 0)` and `legs[i]` joins `stops[i]` -> `stops[i + 1]`.
nonisolated struct JourneySnapshot: Hashable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var date: Date
    var timeZoneID: String
    var city: String?                 // `Journey.displayCity`
    var country: String?              // `Journey.displayCountry`
    var postmark: String              // "ARRIVED · 19 OCT 2026 · MUMBAI"
    var coverPhotoID: UUID?           // resolved `Journey.coverPhoto`
    var introNote: String?            // nil when empty
    var closingNote: String?          // nil when empty
    var stops: [StopSnapshot]         // route order
    var legs: [LegSnapshot]
    var totals: Totals
    /// How the route map is drawn. `.show` until `PrivacyFilter` applies the export settings.
    var mapMode: ExportPrivacy.MapMode = .show

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    // MARK: Nested values

    /// Arrival time as shown in an export: the exact time, or a coarse bucket when exact times are hidden.
    nonisolated enum TimeOfDay: Hashable, Sendable {
        case exact(Date)
        case bucket(DayPart)
    }

    nonisolated enum DayPart: String, Hashable, Sendable, CaseIterable {
        case morning, afternoon, evening
    }

    nonisolated struct PhotoRef: Hashable, Sendable, Identifiable {
        var id: UUID                  // `StopPhoto.id`; the image provider fetches bytes by `id.uuidString`
        var pixelSize: CGSize         // stored pixel size; .zero if unknown
        var isHero: Bool
        var caption: String?
        var hasImageData: Bool        // false = draws a placeholder (sample data)
    }

    nonisolated struct StopSnapshot: Hashable, Sendable, Identifiable {
        var id: UUID                  // `Stop.id`
        var placeName: String
        var story: String
        var highlight: String?        // nil when empty
        var rating: Int?              // 1...5
        var review: String?           // nil when empty
        var category: StopCategory?
        var latitude: Double?
        var longitude: Double?        // both nil = stop left off the map
        var cityHint: String?
        /// Raw arrival time. `PrivacyFilter` clears it when exact times are hidden; draw `timeOfDay` instead.
        var arrivalTime: Date?
        /// What renderers show for the arrival: `.exact(arrivalTime)` from the builder, a bucket after `PrivacyFilter`.
        var timeOfDay: TimeOfDay?
        var timeSpentMinutes: Int?
        var cost: Cost?               // nil when none, or when costs are hidden
        var exportHidden: Bool?       // per-stop override; see `ExportPrivacy.isHidden`
        var photos: [PhotoRef]        // all photos, hero first, then the rest in order (`StoryLayout.storyPhotos` order, uncapped)

        var hasLocation: Bool { latitude != nil && longitude != nil }
        var hero: PhotoRef? { photos.first(where: \.isHero) ?? photos.first }
    }

    nonisolated struct LegSnapshot: Hashable, Sendable, Identifiable {
        /// `Leg.id`, or the from-stop id when the leg row is missing (same fallback as `StoryLayout`).
        var id: UUID
        var fromStopID: UUID
        var toStopID: UUID
        var mode: TransportMode?      // nil = no mode chosen (still shows km/minutes)
        var km: Double?
        var minutes: Int?
        var story: String?            // nil when empty
    }

    /// Same rules as `JourneyStats`, computed from snapshot values so the privacy filter can recompute them.
    nonisolated struct Totals: Hashable, Sendable {
        var stops: Int
        var km: Double?               // nil when no leg has km
        var stopMinutes: Int          // time spent at stops
        var travelMinutes: Int
        var photos: Int
        var spent: [Cost]             // one per currency, summed, in first-use order; empty when none (or hidden)
        var modes: [TransportMode]    // distinct chosen modes, first-use order

        /// Time at stops + travel (decision 3).
        var totalMinutes: Int { stopMinutes + travelMinutes }

        init(stops: Int, km: Double?, stopMinutes: Int, travelMinutes: Int, photos: Int, spent: [Cost],
             modes: [TransportMode]) {
            self.stops = stops; self.km = km; self.stopMinutes = stopMinutes; self.travelMinutes = travelMinutes
            self.photos = photos; self.spent = spent; self.modes = modes
        }

        /// Totals over the given stops and legs. Photo count is every stop's `photos.count`.
        init(stops: [StopSnapshot], legs: [LegSnapshot]) {
            self.stops = stops.count
            photos = stops.reduce(0) { $0 + $1.photos.count }
            stopMinutes = stops.reduce(0) { $0 + ($1.timeSpentMinutes ?? 0) }
            var spent: [Cost] = []
            for c in stops.compactMap(\.cost) {
                if let i = spent.firstIndex(where: { $0.currency == c.currency }) { spent[i].amount += c.amount }
                else { spent.append(c) }
            }
            self.spent = spent
            let kms = legs.compactMap(\.km)
            km = kms.isEmpty ? nil : kms.reduce(0, +)
            travelMinutes = legs.reduce(0) { $0 + ($1.minutes ?? 0) }
            var modes: [TransportMode] = []
            for m in legs.compactMap(\.mode) where !modes.contains(m) { modes.append(m) }
            self.modes = modes
        }
    }
}

// MARK: Builder

nonisolated extension JourneySnapshot {
    init(id: UUID, title: String, date: Date, timeZoneID: String, city: String?, country: String?, postmark: String,
         coverPhotoID: UUID?, introNote: String?, closingNote: String?, stops: [StopSnapshot], legs: [LegSnapshot],
         mapMode: ExportPrivacy.MapMode = .show) {
        self.id = id; self.title = title; self.date = date; self.timeZoneID = timeZoneID
        self.city = city; self.country = country; self.postmark = postmark; self.coverPhotoID = coverPhotoID
        self.introNote = introNote; self.closingNote = closingNote
        self.stops = stops; self.legs = legs; self.totals = Totals(stops: stops, legs: legs); self.mapMode = mapMode
    }

    /// Copies everything an export needs out of `journey`. No privacy rules are applied here.
    @MainActor
    init(journey: Journey) {
        let stops = journey.orderedStops
        let legs: [LegSnapshot] = stops.indices.dropLast().map { i in
            let from = stops[i], to = stops[i + 1]
            guard let leg = from.outgoingLeg else {
                return LegSnapshot(id: from.id, fromStopID: from.id, toStopID: to.id,
                                   mode: nil, km: nil, minutes: nil, story: nil)
            }
            return LegSnapshot(id: leg.id, fromStopID: from.id, toStopID: to.id,
                               mode: leg.modeWasChosen ? leg.mode : nil, km: leg.distanceKm,
                               minutes: leg.durationMinutes, story: StoryLayout.nonEmpty(leg.story))
        }
        self.init(id: journey.id, title: journey.title, date: journey.date, timeZoneID: journey.timeZoneID,
                  city: journey.displayCity, country: journey.displayCountry, postmark: journey.postmarkText,
                  coverPhotoID: journey.coverPhoto?.id, introNote: StoryLayout.nonEmpty(journey.introNote),
                  closingNote: StoryLayout.nonEmpty(journey.closingNote),
                  stops: stops.map(StopSnapshot.init(stop:)), legs: legs)
    }
}

extension JourneySnapshot.StopSnapshot {
    @MainActor
    init(stop s: Stop) {
        let ordered = s.orderedPhotos
        let hero = s.hero
        let photos = (hero.map { [$0] } ?? []) + ordered.filter { $0 !== hero }
        self.init(id: s.id, placeName: s.placeName, story: s.story, highlight: StoryLayout.nonEmpty(s.highlight),
                  rating: s.rating, review: StoryLayout.nonEmpty(s.review), category: s.category,
                  latitude: s.latitude, longitude: s.longitude, cityHint: s.cityHint, arrivalTime: s.arrivalTime,
                  timeOfDay: s.arrivalTime.map { .exact($0) }, timeSpentMinutes: s.timeSpentMinutes, cost: s.cost,
                  exportHidden: s.exportHidden,
                  photos: photos.map { p in
                      JourneySnapshot.PhotoRef(id: p.id, pixelSize: CGSize(width: p.pixelWidth, height: p.pixelHeight),
                                               isHero: p === hero, caption: StoryLayout.nonEmpty(p.caption),
                                               hasImageData: p.imageData != nil)
                  })
    }
}
