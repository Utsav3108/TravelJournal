import XCTest
@testable import TravelJournal

/// Rows of the test table in docs/research/photo-place-pipeline.md section 3.3.
@MainActor
final class ClusteringTests: XCTestCase {
    typealias F = MumbaiFixtures
    let clusterer = PhotoClusterer()

    private func ids(_ c: PhotoCluster) -> [String] { c.photos.map(\.id) }

    // 1. happy path
    func testHappyPathFourClustersInTimeOrder() {
        let r = clusterer.cluster(F.dayTrip(withJPEG: false, includeUnplaced: false))
        XCTAssertEqual(r.clusters.count, 4)
        XCTAssertEqual(r.clusters.map { $0.photos.count }, [3, 4, 3, 2])
        XCTAssertEqual(r.clusters.map(\.arrival), [F.date(9, 0), F.date(11, 30), F.date(14, 0), F.date(17, 0)])
        XCTAssertEqual(r.clusters.map(\.timeSpentMinutes), [10, 30, 20, 5])
        XCTAssertEqual(r.clusters[0].hero?.id, "p1")
        XCTAssertTrue(r.unplaced.isEmpty)
        XCTAssertEqual(r.clusters[1].latitude!, F.Place.pavBhaji.latitude, accuracy: 1e-6)
    }

    // 2. time gap splits
    func testTimeGapSplits() {
        let r = clusterer.cluster([F.photo("a", .cst, 9, 0), F.photo("b", .cst, 9, 10), F.photo("c", .cst, 10, 0)])
        XCTAssertEqual(r.clusters.count, 2)
        XCTAssertEqual(r.clusters.map { ids($0) }, [["a", "b"], ["c"]])
    }

    // 3. distance splits
    func testDistanceSplits() {
        let r = clusterer.cluster([F.photo("a", .cst, 9, 0), F.photo("b", .cst, 9, 2, latOffsetMeters: 400)])
        XCTAssertEqual(r.clusters.count, 2)
    }

    // 4. within threshold
    func testWithinThresholdStaysOne() {
        let r = clusterer.cluster([F.photo("a", .cst, 9, 0), F.photo("b", .cst, 9, 5, latOffsetMeters: 120)])
        XCTAssertEqual(r.clusters.count, 1)
    }

    // 5. boundary: `>` splits, equal stays together
    func testBoundaryEqualStaysTogetherStrictlyOverSplits() {
        let a = F.photo("a", .cst, 9, 0)
        let b = F.photo("b", .cst, 9, 5, latOffsetMeters: 150)
        // Centroid after one photo is a itself, so distance is exactly haversine(a, b).
        let d = Geo.haversine(a.latitude!, a.longitude!, b.latitude!, b.longitude!)
        XCTAssertEqual(PhotoClusterer(config: ClusterConfig(maxDistance: d)).cluster([a, b]).clusters.count, 1)
        XCTAssertEqual(PhotoClusterer(config: ClusterConfig(maxDistance: d - 0.01)).cluster([a, b]).clusters.count, 2)
        // 30:00 exactly stays together, 30:01 splits
        let t1 = clusterer.cluster([F.photo("a", .cst, 9, 0), F.photo("b", .cst, 9, 30)])
        XCTAssertEqual(t1.clusters.count, 1)
        var late = F.photo("c", .cst, 9, 30)
        late.date = late.date!.addingTimeInterval(1)
        XCTAssertEqual(clusterer.cluster([F.photo("a", .cst, 9, 0), late]).clusters.count, 2)
    }

    // 6. no GPS, has time
    func testNoGPSWithTimeJoinsAndIsInferred() {
        let r = clusterer.cluster([F.photo("a", .cst, 9, 0), F.photo("n", nil, 9, 5), F.photo("b", .cst, 9, 10)])
        XCTAssertEqual(r.clusters.count, 1)
        XCTAssertEqual(r.clusters[0].inferredIDs, ["n"])
        XCTAssertEqual(ids(r.clusters[0]), ["a", "n", "b"])
    }

    // 7. no GPS first: joins the following cluster when the gap is fine; not otherwise
    func testNoGPSFirstJoinsFollowingClusterOnlyWithinGap() {
        let near = clusterer.cluster([F.photo("n", nil, 8, 59), F.photo("a", .cst, 9, 0)])
        XCTAssertEqual(near.clusters.count, 1)
        XCTAssertTrue(near.clusters[0].hasLocation)
        XCTAssertEqual(near.clusters[0].inferredIDs, ["n"])
        let far = clusterer.cluster([F.photo("n", nil, 7, 0), F.photo("a", .cst, 9, 0)])
        XCTAssertEqual(far.clusters.count, 2)
        XCTAssertFalse(far.clusters[0].hasLocation)
    }

    // 8. all no GPS
    func testAllNoGPSClusteredByTimeOnly() {
        let r = clusterer.cluster([F.photo("a", nil, 9, 0), F.photo("b", nil, 9, 10), F.photo("c", nil, 9, 20),
                                   F.photo("d", nil, 11, 0), F.photo("e", nil, 11, 5)])
        XCTAssertEqual(r.clusters.count, 2)
        XCTAssertTrue(r.clusters.allSatisfy { $0.latitude == nil })
        XCTAssertTrue(r.unplaced.isEmpty)
    }

    // 9. GPS, no time
    func testGPSNoTimeAttachesToNearestCluster() {
        let r = clusterer.cluster([F.photo("a", .pavBhaji, 11, 30), F.photo("b", .cst, 9, 0),
                                   F.photo("g", .pavBhaji, nil, latOffsetMeters: 20)])
        XCTAssertEqual(r.clusters.count, 2)
        XCTAssertTrue(ids(r.clusters[1]).contains("g"))
        XCTAssertFalse(ids(r.clusters[0]).contains("g"))
        // Nowhere near any cluster: own trailing cluster with no arrival.
        let r2 = clusterer.cluster([F.photo("b", .cst, 9, 0), F.photo("h", .hotel, nil)])
        XCTAssertEqual(r2.clusters.count, 2)
        XCTAssertNil(r2.clusters[1].arrival)
    }

    // 10. neither
    func testNeitherGoesToUnplaced() {
        let r = clusterer.cluster([F.photo("x", nil, nil), F.photo("y", nil, nil)])
        XCTAssertTrue(r.clusters.isEmpty)
        XCTAssertEqual(r.unplaced.map(\.id), ["x", "y"])
    }

    // 11. unsorted input
    func testUnsortedInputSameAsSorted() {
        let sorted = F.dayTrip(withJPEG: false)
        let a = clusterer.cluster(sorted)
        let b = clusterer.cluster(sorted.reversed())
        XCTAssertEqual(a.clusters.map(ids), b.clusters.map(ids))
        XCTAssertEqual(a.unplaced.map(\.id), b.unplaced.map(\.id))
        XCTAssertEqual(a.clusters.map(\.arrival), b.clusters.map(\.arrival))
    }

    // 12. revisit is not merged
    func testRevisitStaysThreeClusters() {
        let r = clusterer.cluster([F.photo("a", .hotel, 9, 0), F.photo("b", .cst, 10, 0), F.photo("c", .hotel, 18, 0)])
        XCTAssertEqual(r.clusters.count, 3)
    }

    // 13. max span
    func testMaxSpanSplits() {
        var photos: [PhotoMeta] = []
        for i in 0...12 { photos.append(F.photo("p\(i)", .cst, 9 + (i * 20) / 60, (i * 20) % 60)) } // 09:00...13:00
        let r = clusterer.cluster(photos)
        XCTAssertEqual(r.clusters.count, 2)
        XCTAssertEqual(r.clusters[0].photos.count, 10) // 09:00 ... 12:00 inclusive (span exactly 3 h)
    }

    // 14. config
    func testConfigMaxDistance500MergesFourHundredMeterCase() {
        let photos = [F.photo("a", .cst, 9, 0), F.photo("b", .cst, 9, 2, latOffsetMeters: 400)]
        XCTAssertEqual(PhotoClusterer(config: ClusterConfig(maxDistance: 500)).cluster(photos).clusters.count, 1)
    }

    // 15. time zone: ordering is by absolute instant, not wall clock
    func testTimeZoneMonotonic() {
        // 10:00 in New York is later than 09:00 IST the same day; instants differ by more than the gap.
        var ny = F.photo("ny", .cst, 0)
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!
        ny.date = c.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 10))
        let ist = F.photo("ist", .cst, 9, 0)
        let r = clusterer.cluster([ny, ist])
        XCTAssertEqual(r.clusters.count, 2)
        XCTAssertEqual(ids(r.clusters[0]), ["ist"]) // 03:30 UTC before 14:00 UTC
        // Same instant expressed in different zones clusters together.
        var c2 = Calendar(identifier: .gregorian); c2.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var tokyo = F.photo("tk", .cst, 9, 5)
        tokyo.date = c2.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12, minute: 35)) // = 09:05 IST
        XCTAssertEqual(clusterer.cluster([ist, tokyo]).clusters.count, 1)
    }

    // 16. perf
    func testPerformance500Photos() {
        var photos: [PhotoMeta] = []
        for i in 0..<500 {
            photos.append(PhotoMeta(id: "s\(i)", date: F.date(8, 0).addingTimeInterval(Double(i) * 240),
                                    latitude: 18.9 + Double(i / 5) * 0.002, longitude: 72.8, jpegData: Data()))
        }
        let t0 = Date()
        let r = clusterer.cluster(photos)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 0.05)
        XCTAssertEqual(r.clusters.reduce(0) { $0 + $1.photos.count }, 500)
    }

    // Defaults
    func testSinglePhotoHasNoTimeSpent() {
        let r = clusterer.cluster([F.photo("a", .cst, 9, 0)])
        XCTAssertNil(r.clusters[0].timeSpentMinutes)
        XCTAssertEqual(r.clusters[0].arrival, F.date(9, 0))
    }
}
