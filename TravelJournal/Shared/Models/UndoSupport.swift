import Foundation
import SwiftData

// Explicit undo for the Mac editor. SwiftData's own `ModelContext.undoManager` is not used: attaching it and then
// deleting a stop (cascade to photos and legs) crashed inside SwiftData in the Phase 5a spike. Everything here
// registers plain closures with an `UndoManager` instead, over value snapshots of the models.

/// Every editable field of a stop except its photos and legs.
struct StopContent: Equatable {
    var placeName: String
    var story: String
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

    @MainActor
    init(_ s: Stop) {
        placeName = s.placeName; story = s.story; latitude = s.latitude; longitude = s.longitude
        address = s.address; cityHint = s.cityHint; arrivalTime = s.arrivalTime
        timeSpentMinutes = s.timeSpentMinutes; categoryRaw = s.categoryRaw; highlight = s.highlight
        ratingRaw = s.ratingRaw; review = s.review; costAmount = s.costAmount; costCurrency = s.costCurrency
    }

    @MainActor
    func apply(to s: Stop) {
        s.placeName = placeName; s.story = story; s.latitude = latitude; s.longitude = longitude
        s.address = address; s.cityHint = cityHint; s.arrivalTime = arrivalTime
        s.timeSpentMinutes = timeSpentMinutes; s.categoryRaw = categoryRaw; s.highlight = highlight
        s.ratingRaw = ratingRaw; s.review = review; s.costAmount = costAmount; s.costCurrency = costCurrency
    }
}

struct LegContent: Equatable {
    var modeRaw: String
    var modeWasChosen: Bool
    var distanceKm: Double?
    var durationMinutes: Int?
    var story: String?

    @MainActor
    init(_ l: Leg) {
        modeRaw = l.modeRaw; modeWasChosen = l.modeWasChosen
        distanceKm = l.distanceKm; durationMinutes = l.durationMinutes; story = l.story
    }

    @MainActor
    func apply(to l: Leg) {
        l.modeRaw = modeRaw; l.modeWasChosen = modeWasChosen
        l.distanceKm = distanceKm; l.durationMinutes = durationMinutes; l.story = story
    }
}

struct JourneyContent: Equatable {
    var title: String
    var date: Date
    var city: String?
    var country: String?
    var introNote: String?
    var closingNote: String?

    @MainActor
    init(_ j: Journey) {
        title = j.title; date = j.date; city = j.city; country = j.country
        introNote = j.introNote; closingNote = j.closingNote
    }

    @MainActor
    func apply(to j: Journey) {
        j.title = title; j.date = date; j.city = city; j.country = country
        j.introNote = introNote; j.closingNote = closingNote
        j.updatedAt = .now
    }
}

struct PhotoSnapshot {
    var id: UUID
    var orderIndex: Int
    var isHero: Bool
    var imageData: Data?
    var pixelWidth: Int
    var pixelHeight: Int
    var captureDate: Date?
    var latitude: Double?
    var longitude: Double?
    var caption: String?

    @MainActor
    init(_ p: StopPhoto) {
        id = p.id; orderIndex = p.orderIndex; isHero = p.isHero; imageData = p.imageData
        pixelWidth = p.pixelWidth; pixelHeight = p.pixelHeight; captureDate = p.captureDate
        latitude = p.latitude; longitude = p.longitude; caption = p.caption
    }

    @MainActor
    func makePhoto() -> StopPhoto {
        let p = StopPhoto(id: id, orderIndex: orderIndex, isHero: isHero)
        p.imageData = imageData; p.pixelWidth = pixelWidth; p.pixelHeight = pixelHeight
        p.captureDate = captureDate; p.latitude = latitude; p.longitude = longitude; p.caption = caption
        return p
    }
}

/// A deleted stop, complete enough to rebuild: its fields, photos (with bytes) and the content of both its legs.
struct StopSnapshot {
    var id: UUID
    var index: Int
    var content: StopContent
    var photos: [PhotoSnapshot]
    var incoming: LegContent?
    var outgoing: LegContent?

    @MainActor
    init(_ s: Stop, index: Int) {
        id = s.id
        self.index = index
        content = StopContent(s)
        photos = s.photos.map(PhotoSnapshot.init)
        incoming = s.incomingLeg.map(LegContent.init)
        outgoing = s.outgoingLeg.map(LegContent.init)
    }
}

/// Content of every leg that has any, keyed by the stop pair it joins (so it can be put back after a reorder).
struct LegContentMap {
    private(set) var byPair: [String: LegContent] = [:]

    @MainActor
    init(_ journey: Journey) {
        for s in journey.orderedStops {
            if let l = s.outgoingLeg, l.hasContent, let to = l.toStop { byPair[Self.key(s.id, to.id)] = LegContent(l) }
        }
    }

    static func key(_ from: UUID, _ to: UUID) -> String { "\(from)>\(to)" }

    @MainActor
    func restore(in journey: Journey) {
        for s in journey.orderedStops {
            guard let l = s.outgoingLeg, let to = l.toStop, let c = byPair[Self.key(s.id, to.id)] else { continue }
            c.apply(to: l)
        }
    }
}

/// Turns a stream of edits to one object into undo steps: compares a value snapshot of the object with the last one
/// it saw and registers "restore the old snapshot" with the manager. Typing registers one step per burst (edits
/// within `coalesceWindow` of the previous one extend it), and undo/redo applying a snapshot is not re-registered.
@MainActor
final class EditUndoTracker<S: Equatable> {
    private(set) var expected: S
    private var lastRegistered = Date.distantPast
    let coalesceWindow: TimeInterval

    init(initial: S, coalesceWindow: TimeInterval = 1.0) {
        expected = initial
        self.coalesceWindow = coalesceWindow
    }

    /// Call when the object's snapshot may have changed. `target` is the model the edit is on (the manager keeps no
    /// strong reference to it); `apply` writes a snapshot back to that model.
    func observe(_ new: S, manager: UndoManager?, target: AnyObject, now: Date = .now, apply: @escaping (S) -> Void) {
        guard new != expected else { return }
        let old = expected
        expected = new
        guard let manager, !manager.isUndoing, !manager.isRedoing else { return }
        let extendsBurst = now.timeIntervalSince(lastRegistered) <= coalesceWindow
        lastRegistered = now
        guard !extendsBurst else { return }
        register(old: old, manager: manager, target: target, apply: apply)
    }

    private func register(old: S, manager: UndoManager, target: AnyObject, apply: @escaping (S) -> Void) {
        manager.registerUndo(withTarget: target) { [self] target in
            MainActor.assumeIsolated {
                let current = expected
                expected = old
                lastRegistered = .distantPast
                apply(old)
                register(old: current, manager: manager, target: target, apply: apply)   // redo
            }
        }
    }
}
