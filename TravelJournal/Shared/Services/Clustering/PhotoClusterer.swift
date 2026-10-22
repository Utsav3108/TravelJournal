import Foundation

/// All clustering thresholds in one place. Boundary rule: distance/time `>` the limit splits; equal stays together.
struct ClusterConfig: Equatable, Sendable {
    /// Metres from a photo to the running centroid of the current cluster.
    var maxDistance: Double = 150
    /// Seconds between consecutive photos.
    var maxGap: TimeInterval = 30 * 60
    /// Safety cap on one cluster's first-to-last span.
    var maxSpan: TimeInterval = 3 * 3600
    /// Distance-split neighbours whose centroids are this close are merged back (wandering inside a market).
    var mergeDistance: Double = 100
    /// Radius for attaching GPS-but-no-time photos to an existing cluster.
    var noTimeAttachRadius: Double = 150
}

/// A suggested stop: photos taken at one place in one stretch of time.
struct PhotoCluster: Identifiable, Equatable, Sendable {
    var id = UUID()
    /// Time-sorted (untimed photos last).
    var photos: [PhotoMeta]
    /// Photo ids whose place was inferred from time alone (no GPS of their own).
    var inferredIDs: Set<String> = []

    init(id: UUID = UUID(), photos: [PhotoMeta], inferredIDs: Set<String> = []) {
        self.id = id
        self.photos = PhotoCluster.sorted(photos)
        self.inferredIDs = inferredIDs
    }

    static func sorted(_ p: [PhotoMeta]) -> [PhotoMeta] {
        p.enumerated().sorted { a, b in
            switch (a.element.date, b.element.date) {
            case let (x?, y?): return x != y ? x < y : a.element.id < b.element.id
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.offset < b.offset
            }
        }.map(\.element)
    }

    private var gps: [PhotoMeta] { photos.filter(\.hasLocation) }
    /// Mean of GPS members (fine at city scale), nil when no member has GPS.
    var latitude: Double? { let g = gps; return g.isEmpty ? nil : g.reduce(0) { $0 + $1.latitude! } / Double(g.count) }
    var longitude: Double? { let g = gps; return g.isEmpty ? nil : g.reduce(0) { $0 + $1.longitude! } / Double(g.count) }
    var hasLocation: Bool { latitude != nil }
    var firstDate: Date? { photos.compactMap(\.date).min() }
    var lastDate: Date? { photos.compactMap(\.date).max() }
    /// Default arrival: earliest photo date.
    var arrival: Date? { firstDate }
    /// Default time spent: photo span in minutes (min 1), only with two or more timed photos.
    var timeSpentMinutes: Int? {
        let d = photos.compactMap(\.date)
        guard d.count > 1, let f = d.min(), let l = d.max() else { return nil }
        return max(1, Int((l.timeIntervalSince(f) / 60).rounded(.up)))
    }
    /// Default hero: first photo.
    var hero: PhotoMeta? { photos.first }
}

struct ClusterResult: Equatable, Sendable {
    var clusters: [PhotoCluster]
    /// Photos with neither GPS nor time; never dropped.
    var unplaced: [PhotoMeta]
}

nonisolated enum Geo {
    /// Great-circle distance in metres.
    static func haversine(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6_371_000.0
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = (lat2 - lat1) * .pi / 180, dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * asin(min(1, sqrt(a)))
    }
}

struct PhotoClusterer: Sendable {
    var config = ClusterConfig()
    init(config: ClusterConfig = ClusterConfig()) { self.config = config }

    func cluster(_ photos: [PhotoMeta]) -> ClusterResult {
        let timed = photos.filter { $0.date != nil }
            .sorted { ($0.date!, $0.id) < ($1.date!, $1.id) }
        let untimed = photos.filter { $0.date == nil }

        // Working accumulator keeps running centroid sums.
        struct Acc {
            var photos: [PhotoMeta] = []
            var inferred: Set<String> = []
            var sumLat = 0.0, sumLon = 0.0, n = 0
            var first: Date, last: Date
            /// True when this accumulator was started only because of the distance test.
            var startedByDistance = false
            var centroid: (Double, Double)? { n == 0 ? nil : (sumLat / Double(n), sumLon / Double(n)) }
            mutating func add(_ p: PhotoMeta) {
                photos.append(p)
                if let la = p.latitude, let lo = p.longitude { sumLat += la; sumLon += lo; n += 1 }
                if let d = p.date { last = max(last, d); first = min(first, d) }
            }
        }

        var accs: [Acc] = []
        for p in timed {
            let d = p.date!
            if let cur = accs.last {
                let gap = d.timeIntervalSince(cur.last)
                let span = d.timeIntervalSince(cur.first)
                var distanceSplit = false
                if let la = p.latitude, let lo = p.longitude, let c = cur.centroid {
                    distanceSplit = Geo.haversine(la, lo, c.0, c.1) > config.maxDistance
                }
                if gap > config.maxGap || span > config.maxSpan || distanceSplit {
                    let onlyDistance = distanceSplit && gap <= config.maxGap && span <= config.maxSpan
                    var a = Acc(first: d, last: d, startedByDistance: onlyDistance)
                    a.add(p)
                    accs.append(a)
                } else {
                    if !p.hasLocation { accs[accs.count - 1].inferred.insert(p.id) }
                    accs[accs.count - 1].add(p)
                }
            } else {
                var a = Acc(first: d, last: d)
                a.add(p)
                accs.append(a)
            }
        }

        // Post-pass: undo distance splits where the centroids ended up close together.
        var merged: [Acc] = []
        for a in accs {
            if var prev = merged.last, a.startedByDistance,
               let c1 = prev.centroid, let c2 = a.centroid,
               Geo.haversine(c1.0, c1.1, c2.0, c2.1) <= config.mergeDistance,
               a.last.timeIntervalSince(prev.first) <= config.maxSpan {
                prev.photos += a.photos
                prev.inferred.formUnion(a.inferred)
                prev.sumLat += a.sumLat; prev.sumLon += a.sumLon; prev.n += a.n
                prev.last = max(prev.last, a.last)
                merged[merged.count - 1] = prev
            } else {
                merged.append(a)
            }
        }

        var clusters = merged.map { a -> PhotoCluster in
            // No-GPS photos inherit the place of a cluster that has GPS: flag them as inferred.
            let inferred: Set<String> = a.n > 0 ? Set(a.photos.filter { !$0.hasLocation }.map(\.id)) : []
            return PhotoCluster(photos: a.photos, inferredIDs: inferred)
        }

        // GPS but no time: nearest cluster within radius, else grouped into their own trailing clusters.
        var unplaced: [PhotoMeta] = []
        var orphans: [PhotoCluster] = []
        for p in untimed {
            guard let la = p.latitude, let lo = p.longitude else { unplaced.append(p); continue }
            var best: (Int, Double)?
            for (i, c) in clusters.enumerated() {
                guard let cl = c.latitude, let cn = c.longitude else { continue }
                let d = Geo.haversine(la, lo, cl, cn)
                if d <= config.noTimeAttachRadius, best == nil || d < best!.1 { best = (i, d) }
            }
            if let (i, _) = best {
                clusters[i].photos.append(p)
            } else if let j = orphans.firstIndex(where: {
                Geo.haversine(la, lo, $0.latitude!, $0.longitude!) <= config.maxDistance }) {
                orphans[j].photos.append(p)
            } else {
                orphans.append(PhotoCluster(photos: [p]))
            }
        }
        clusters += orphans
        return ClusterResult(clusters: clusters, unplaced: unplaced)
    }
}
