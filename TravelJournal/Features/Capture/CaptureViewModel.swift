import Foundation
import Observation
import SwiftData
import UIKit
import ImageIO

/// One editable suggested stop in the review step.
struct StopCard: Identifiable, Equatable {
    enum Lookup: Equatable { case idle, loading, found, notFound }

    var cluster: PhotoCluster
    var name = ""
    /// True once the user typed or picked a name; lookups never overwrite it.
    var nameEdited = false
    /// Place applied from lookup or search; its coordinate/address win over the photo centroid.
    var place: PlaceCandidate?
    var lookup: Lookup = .idle

    var id: UUID { cluster.id }
    var photos: [PhotoMeta] { cluster.photos }
    var hasLocation: Bool { cluster.hasLocation }
    var needsPlace: Bool { name.trimmingCharacters(in: .whitespaces).isEmpty && lookup != .loading }
}

struct CommitSummary: Equatable {
    var stopsCreated = 0
    var photosSaved = 0
    /// Photos not saved: over the per-stop cap, or the store failed.
    var skipped: [PhotoMeta] = []
}

/// State machine behind AddPhotosFlowView. No SwiftUI, so it is unit-testable.
@MainActor @Observable
final class CaptureViewModel {
    enum Step: Equatable { case chooseSource, importing, review, done(CommitSummary) }

    private(set) var step: Step = .chooseSource
    private(set) var statusText = ""
    private(set) var cards: [StopCard] = []
    private(set) var unplaced: [PhotoMeta] = []
    var notice: String?

    /// Max PlaceLookup.place calls per session (cache hits are free).
    var maxLookups = 10

    @ObservationIgnored private let importer: PhotoImporting
    @ObservationIgnored private let lookup: PlaceLookup
    @ObservationIgnored private let clusterer: PhotoClusterer
    @ObservationIgnored private var lookupTask: Task<Void, Never>?
    @ObservationIgnored private var lookupCalls = 0
    @ObservationIgnored private var cache: [String: PlaceCandidate?] = [:]
    @ObservationIgnored private var thumbs: [String: UIImage] = [:]

    init(importer: PhotoImporting, lookup: PlaceLookup, config: ClusterConfig = ClusterConfig()) {
        self.importer = importer
        self.lookup = lookup
        self.clusterer = PhotoClusterer(config: config)
    }

    // MARK: Import + cluster

    func process(items: [AnyHashable]) async {
        step = .importing
        statusText = "Reading your photos"
        let metas = await importer.importItems(items)
        ingest(metas)
    }

    /// Cluster already-imported photos (also used for camera shots).
    func ingest(_ metas: [PhotoMeta]) {
        guard !metas.isEmpty else {
            notice = "No photos could be read. Try choosing them again."
            step = .chooseSource
            return
        }
        statusText = "Grouping into stops"
        let result = clusterer.cluster(metas)
        cards = result.clusters.map { StopCard(cluster: $0) }
        unplaced = result.unplaced
        notice = nil
        step = .review
        startLookups()
    }

    func reset() {
        lookupTask?.cancel()
        lookupTask = nil
        cards = []; unplaced = []; notice = nil
        step = .chooseSource
    }

    // MARK: Place lookups (serial)

    func startLookups() {
        guard lookupTask == nil else { return }
        lookupGeneration += 1
        let generation = lookupGeneration
        lookupTask = Task { [weak self] in
            await self?.runLookups()
            // A cancelled loop must not clear a newer loop's task handle.
            if self?.lookupGeneration == generation { self?.lookupTask = nil }
        }
    }

    /// Test hook: wait for the serial lookup loop to drain.
    func waitForLookups() async { await lookupTask?.value }

    private var lookupGeneration = 0

    func cancelLookups() {
        lookupTask?.cancel(); lookupTask = nil
        lookupGeneration += 1
        // Anything mid-lookup goes back to the queue so a later run (or the user) can resolve it.
        for j in cards.indices where cards[j].lookup == .loading { cards[j].lookup = .idle }
    }

    private func runLookups() async {
        while !Task.isCancelled,
              let i = cards.firstIndex(where: { $0.lookup == .idle && $0.hasLocation && !$0.nameEdited }) {
            let id = cards[i].id
            let lat = cards[i].cluster.latitude!, lon = cards[i].cluster.longitude!
            let key = String(format: "%.3f,%.3f", lat, lon)
            if let hit = cache[key] {
                apply(hit, toCardID: id)
                continue
            }
            guard lookupCalls < maxLookups else {
                // Over the cap: leave the rest for the user ("Find this place").
                for j in cards.indices where cards[j].lookup == .idle { cards[j].lookup = .notFound }
                return
            }
            cards[i].lookup = .loading
            lookupCalls += 1
            let found = await lookup.place(near: lat, longitude: lon)
            if Task.isCancelled {
                if let j = cards.firstIndex(where: { $0.id == id }), cards[j].lookup == .loading { cards[j].lookup = .idle }
                return
            }
            cache[key] = .some(found)
            apply(found, toCardID: id)
        }
    }

    private func apply(_ found: PlaceCandidate?, toCardID id: UUID) {
        guard let i = cards.firstIndex(where: { $0.id == id }) else { return }
        guard let found else { cards[i].lookup = .notFound; return }
        cards[i].lookup = .found
        if !cards[i].nameEdited {
            cards[i].name = found.name
            cards[i].place = found
        }
    }

    // MARK: Edits

    func rename(_ id: UUID, to name: String) {
        guard let i = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[i].name = name
        cards[i].nameEdited = true
    }

    func applyPlace(_ candidate: PlaceCandidate, to id: UUID) {
        guard let i = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[i].name = candidate.name
        cards[i].place = candidate
        cards[i].nameEdited = true
        cards[i].lookup = .found
    }

    func search(_ query: String, near id: UUID) async -> [PlaceCandidate] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let card = cards.first { $0.id == id }
        var lat = card?.place?.latitude ?? card?.cluster.latitude
        var lon = card?.place?.longitude ?? card?.cluster.longitude
        if lat == nil, let anchor = cards.first(where: { $0.hasLocation }) {
            lat = anchor.cluster.latitude; lon = anchor.cluster.longitude
        }
        return await lookup.search(q, nearLatitude: lat, nearLongitude: lon)
    }

    /// Merge card at `id` into the one before it. No-op for the first card.
    func mergeWithPrevious(_ id: UUID) {
        guard let i = cards.firstIndex(where: { $0.id == id }), i > 0 else { return }
        let prev = cards[i - 1], cur = cards[i]
        var merged = prev
        merged.cluster = PhotoCluster(id: prev.cluster.id, photos: prev.photos + cur.photos,
                                      inferredIDs: prev.cluster.inferredIDs.union(cur.cluster.inferredIDs))
        let prevNamed = !prev.name.trimmingCharacters(in: .whitespaces).isEmpty
        if !prevNamed { merged.name = cur.name; merged.place = cur.place; merged.nameEdited = cur.nameEdited
            // An in-flight lookup is keyed to the removed card's id, so its result would be dropped: requeue instead.
            merged.lookup = cur.lookup == .loading ? .idle : cur.lookup }
        cards[i - 1] = merged
        cards.remove(at: i)
        startLookups()
    }

    /// Move one photo out of its card into a new card right after it. Needs at least two photos.
    func split(photoID: String, from id: UUID) {
        guard let i = cards.firstIndex(where: { $0.id == id }), cards[i].photos.count > 1,
              let photo = cards[i].photos.first(where: { $0.id == photoID }) else { return }
        let rest = cards[i].photos.filter { $0.id != photoID }
        cards[i].cluster = PhotoCluster(id: id, photos: rest, inferredIDs: cards[i].cluster.inferredIDs.subtracting([photoID]))
        cards.insert(StopCard(cluster: PhotoCluster(photos: [photo])), at: i + 1)
        startLookups()
    }

    func drop(_ id: UUID) { cards.removeAll { $0.id == id } }

    func assign(photoID: String, toCard id: UUID) {
        guard let u = unplaced.firstIndex(where: { $0.id == photoID }),
              let i = cards.firstIndex(where: { $0.id == id }) else { return }
        let p = unplaced.remove(at: u)
        var inferred = cards[i].cluster.inferredIDs
        if !p.hasLocation { inferred.insert(p.id) }
        cards[i].cluster = PhotoCluster(id: id, photos: cards[i].photos + [p], inferredIDs: inferred)
    }

    func newStop(fromUnplaced photoID: String) {
        guard let u = unplaced.firstIndex(where: { $0.id == photoID }) else { return }
        let p = unplaced.remove(at: u)
        cards.append(StopCard(cluster: PhotoCluster(photos: [p])))
        startLookups()
    }

    func discardUnplaced(_ photoID: String) { unplaced.removeAll { $0.id == photoID } }

    var canCommit: Bool { !cards.isEmpty }

    // MARK: Commit

    /// Create stops (in card order), save up to 4 photos each, fill journey date/city when empty.
    @discardableResult
    func commit(to journey: Journey, editor: JourneyEditor) -> CommitSummary {
        cancelLookups()
        var summary = CommitSummary()
        let wasEmpty = journey.stops.isEmpty

        for card in cards {
            let name = card.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let stop = Stop(placeName: name.isEmpty ? "Stop \(journey.stops.count + 1)" : name)
            stop.latitude = card.place?.latitude ?? card.cluster.latitude
            stop.longitude = card.place?.longitude ?? card.cluster.longitude
            stop.address = card.place?.address
            stop.cityHint = card.place?.city
            stop.arrivalTime = card.cluster.arrival
            stop.timeSpentMinutes = card.cluster.timeSpentMinutes
            editor.addStop(stop, to: journey)

            for photo in card.photos {
                guard stop.photos.count < PhotoLimits.maxPerStop else { summary.skipped.append(photo); continue }
                do {
                    let saved = try editor.photos.importPhoto(data: photo.jpegData, into: stop, journeyID: journey.id)
                    if saved.captureDate == nil { saved.captureDate = photo.date }
                    if saved.latitude == nil { saved.latitude = photo.latitude; saved.longitude = photo.longitude }
                    summary.photosSaved += 1
                } catch {
                    summary.skipped.append(photo)
                }
            }
            summary.stopsCreated += 1
        }

        if wasEmpty {
            let dates = cards.flatMap { $0.photos.compactMap(\.date) }
            if !dates.isEmpty { journey.date = Journey.defaultDate(photoDates: dates, fallback: journey.date) }
        }
        let cityEmpty = (journey.city ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        if cityEmpty, let c = journey.orderedStops.first?.cityHint, !c.isEmpty { journey.city = c }
        journey.updatedAt = .now
        try? editor.context.save()

        step = .done(summary)
        return summary
    }

    // MARK: Thumbnails

    func thumbnail(for photo: PhotoMeta) -> UIImage? {
        if let t = thumbs[photo.id] { return t }
        guard let src = CGImageSourceCreateWithData(photo.jpegData as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 240,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let img = UIImage(cgImage: cg)
        thumbs[photo.id] = img
        return img
    }
}
