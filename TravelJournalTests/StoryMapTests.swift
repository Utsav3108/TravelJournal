import Testing
import XCTest
import SwiftUI
@testable import TravelJournal

@MainActor
struct StoryMapTests {
    let cst = GeoPoint(lat: 18.9398, lon: 72.8355)
    let sid = GeoPoint(lat: 19.0169, lon: 72.8300)

    @Test func regionContainsAllPointsWithPaddingAndAspect() {
        let r = MapProjection.fitRegion([cst, sid], aspect: 1.5)!
        #expect(abs(r.centerLat - (cst.lat + sid.lat) / 2) < 1e-9)
        #expect(r.latSpan >= (sid.lat - cst.lat) * 1.5 - 1e-9)
        let ground = r.lonSpan * cos(r.centerLat * .pi / 180) / r.latSpan
        #expect(abs(ground - 1.5) < 0.01)
    }

    @Test func singleStopUsesMinSpan() {
        let r = MapProjection.fitRegion([cst], aspect: 1)!
        #expect(r.latSpan >= MapProjection.minSpan)
        #expect(r.lonSpan >= MapProjection.minSpan)
        #expect(MapProjection.fitRegion([], aspect: 1) == nil)
    }

    @Test func fallbackPointsStayInsideAndKeepOrientation() {
        let size = CGSize(width: 500, height: 300)
        let pts = MapProjection.fallbackPoints([cst, sid], size: size, inset: 30)
        for p in pts { #expect(p.x >= 29.9 && p.x <= 470.1 && p.y >= 29.9 && p.y <= 270.1) }
        #expect(pts[1].y < pts[0].y)            // north is up
        let one = MapProjection.fallbackPoints([cst], size: size)
        #expect(one == [CGPoint(x: 250, y: 150)])
    }

    @Test func cacheKeyIsStableAndSensitive() {
        let s = CGSize(width: 511, height: 328)
        let a = MapProjection.cacheKey([cst, sid], size: s, scale: 2)
        #expect(a == MapProjection.cacheKey([cst, sid], size: s, scale: 2))
        #expect(a != MapProjection.cacheKey([sid, cst], size: s, scale: 2))
        #expect(a != MapProjection.cacheKey([cst, sid], size: s, scale: 3))
        #expect(a != MapProjection.cacheKey([cst, sid], size: s, scale: 2.5))
        #expect(a != MapProjection.cacheKey([cst, sid], size: CGSize(width: 300, height: 200), scale: 2))
        #expect(a == "\(a)" && !a.isEmpty)
    }

    @Test func noCoordinatesYieldsFallback() async {
        let svc = MapSnapshotService(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("maptest-\(UUID().uuidString)"))
        let size = CGSize(width: 300, height: 200)
        let snap = await svc.snapshot(for: OverviewSamples.noCoordinates, size: size)
        #expect(snap.isFallback)
        #expect(snap.pins.isEmpty)
        #expect(CGFloat(snap.image.width) / snap.scale == size.width && CGFloat(snap.image.height) / snap.scale == size.height)
    }

    @Test func partialCoordinatesKeepStopIndices() {
        let snap = MapSnapshotService.fallback(for: OverviewSamples.partial, size: CGSize(width: 300, height: 200))
        #expect(snap.stopIndices == [0, 2, 3])
        #expect(snap.pins.count == 3)
        let segs = MapProjection.segments(located: snap.stopIndices, legCount: 3)
        #expect(segs.count == 2)
        #expect(segs[0].leg == 0 && segs[1].leg == 2)
    }

    @Test func statsFormatting() {
        let s = StatsModel(stops: 4, km: 8.44, totalMinutes: 320, travelMinutes: 63, modes: ["taxi", "autoRickshaw"], photos: 0, moneyText: nil)
        #expect(OverviewStatsFormat.primaryRow(s) == ["4 stops", "8.4 km", "5½ hours"])
        #expect(OverviewStatsFormat.secondaryRow(s) == ["travel 1 hour", "taxi, auto"])
        // The strip prints in capitals (stampLabel).
        #expect(OverviewStatsFormat.secondaryRow(s).joined(separator: " · ").uppercased() == "TRAVEL 1 HOUR · TAXI, AUTO")
        #expect(OverviewStatsFormat.travelText(s) == "travel 1 hour")
        #expect(OverviewStatsFormat.kmText(8.46) == "8.5 km")
        #expect(OverviewStatsFormat.duration(45) == "45 min")
        #expect(OverviewStatsFormat.duration(120) == "2 h")
        let one = StatsModel(stops: 1, km: nil, totalMinutes: 30, travelMinutes: 0,
                             modes: ["walk", "localTrain", "bus", "ferry", "rocket"], photos: 0, moneyText: nil)
        #expect(OverviewStatsFormat.primaryRow(one) == ["1 stop", "½ hour"])
        #expect(OverviewStatsFormat.secondaryRow(one) == ["walk, local train, bus +1"])
        #expect(OverviewStatsFormat.travelText(one) == nil)
        let still = StatsModel(stops: 1, km: nil, totalMinutes: 10, travelMinutes: 0, modes: [], photos: 0, moneyText: nil)
        #expect(OverviewStatsFormat.primaryRow(still) == ["1 stop", "10 min"])
        #expect(OverviewStatsFormat.secondaryRow(still).isEmpty)
    }

    @Test func legsSummaryUsesShortModeNames() {
        let rows = OverviewLegsFormat.rows(OverviewModel(
            stops: OverviewSamples.mumbai.stops, legs: [OverviewSamples.leg(1, "autoRickshaw", 6, 20)], stats: OverviewSamples.stats))
        #expect(rows.count == 1 && rows[0].detail == "auto · 20 min · 6 km")
    }

    /// Two rows at most, whatever the content: a crowded strip is exactly as tall as a short two-row one.
    @Test func statsStripNeverWrapsPastTwoRows() throws {
        let width = PageMetrics.a4.size.width - 2 * PageMetrics.a4.margin
        func height(_ s: StatsModel, width w: CGFloat = width) throws -> Int {
            try #require(TestImages.render(OverviewStatsStrip(stats: s).frame(width: w), scale: 1)).height
        }
        let short = StatsModel(stops: 4, km: 8.4, totalMinutes: 320, travelMinutes: 63, modes: ["taxi"], photos: 0, moneyText: nil)
        let crowded = StatsModel(stops: 12, km: 1234.5, totalMinutes: 14 * 60 + 30, travelMinutes: 9 * 60 + 15,
                                 modes: ["localTrain", "autoRickshaw", "ferry", "metro", "walk"], photos: 0, moneyText: nil)
        let h = try height(short)
        #expect(abs(try height(crowded) - h) <= 1)
        // Even squeezed to a width where the rows would have to wrap, the strip keeps its two-row height.
        #expect(abs(try height(crowded, width: 220) - h) <= 1)
    }

    @Test func zoomedOutWidensRegionAndHasItsOwnCacheKey() {
        let size = CGSize(width: 511, height: 400)
        let tight = MapSnapshotService.region(for: [cst, sid], size: size, zoomedOut: false)!
        let wide = MapSnapshotService.region(for: [cst, sid], size: size, zoomedOut: true)!
        #expect(wide.centerLat == tight.centerLat && wide.centerLon == tight.centerLon)
        #expect(abs(wide.latSpan / tight.latSpan - MapProjection.zoomOutFactor) < 1e-9)
        #expect(abs(wide.lonSpan / tight.lonSpan - MapProjection.zoomOutFactor) < 1e-9)
        #expect(MapSnapshotService.isZoomedOut(.zoomedOut) && MapSnapshotService.isZoomedOut(.hidden))
        #expect(!MapSnapshotService.isZoomedOut(.show))
        let normal = MapProjection.cacheKey([cst, sid], size: size, scale: 2)
        #expect(normal == MapProjection.cacheKey([cst, sid], size: size, scale: 2, zoomedOut: false))
        #expect(normal != MapProjection.cacheKey([cst, sid], size: size, scale: 2, zoomedOut: true))
    }

    @Test func zoomedOutFallbackGathersPinsTowardCentre() {
        let size = CGSize(width: 300, height: 200)
        let normal = MapSnapshotService.fallback(for: OverviewSamples.mumbai, size: size)
        let wide = MapSnapshotService.fallback(for: OverviewSamples.mumbai, size: size, mapMode: .zoomedOut)
        let c = CGPoint(x: 150, y: 100)
        for (a, b) in zip(normal.pins, wide.pins) {
            #expect(abs(hypot(b.x - c.x, b.y - c.y) * MapProjection.zoomOutFactor - hypot(a.x - c.x, a.y - c.y)) < 0.01)
        }
    }

    @Test func hitPathContainsSegmentNotFarAway() {
        let a = CGPoint(x: 20, y: 20), b = CGPoint(x: 220, y: 120)
        let path = MapProjection.hitPath(from: a, to: b)
        #expect(path.contains(CGPoint(x: 120, y: 70)))
        #expect(path.contains(CGPoint(x: 120, y: 70 + 12)))      // within 14pt of the line
        #expect(!path.contains(CGPoint(x: 120, y: 70 + 40)))
        #expect(!path.contains(CGPoint(x: 400, y: 300)))
    }

    @Test func rendersOverviewWithFallbackToNonEmptyImage() throws {
        let img = try render(OverviewSamples.mumbai, snap: nil)
        #expect(img.width / 2 > 500 && img.height / 2 > 800)   // rendered at 2x
        #expect(ImageDrawing.pngData(img)!.count > 20_000)
        try write(img, "overview-fallback")
        try write(try render(OverviewSamples.partial, snap: nil), "overview-partial")
        try write(try render(OverviewSamples.noCoordinates, snap: nil), "overview-nocoords")
        try write(try render(OverviewSamples.oneStop, snap: nil), "overview-onestop")
    }

    @Test func realSnapshotRendersWhenNetworkAvailable() async throws {
        let svc = MapSnapshotService(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("maptest-\(UUID().uuidString)"))
        svc.timeout = .seconds(15)
        let size = MapSnapshotService.mapSize(for: .a4)
        let snap = await svc.snapshot(for: OverviewSamples.mumbai, size: size, scale: 2)
        #expect(snap.pins.count == 4)
        try write(try render(OverviewSamples.mumbai, snap: snap), snap.isFallback ? "overview-realsnap-FELLBACK" : "overview-realsnap")
        if !snap.isFallback {
            // Second call must come from cache (same object content).
            let again = await svc.snapshot(for: OverviewSamples.mumbai, size: size, scale: 2)
            #expect(again.pins == snap.pins)
        }
    }

    // MARK: helpers

    private func render(_ model: OverviewModel, snap: MapSnap?) throws -> CGImage {
        try #require(TestImages.render(RouteOverviewPage(model: model, metrics: .a4, snap: snap),
                                       proposed: ProposedViewSize(width: 595, height: 842), scale: 2))
    }

    private func write(_ img: CGImage, _ name: String) throws {
        // Set TEST_RUNNER_MAP_OUT=<dir> on xcodebuild to keep these PNGs for a look by eye.
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["MAP_OUT"] ?? env["SIMCTL_CHILD_MAP_OUT"] else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        TestImages.writePNG(img, to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}

/// Reference images for the overview page (illustrated fallback, so no network and deterministic).
@MainActor
final class RouteOverviewSnapshotTests: XCTestCase {
    private func overview(_ fixture: JourneyFixtures.Fixture) throws -> OverviewModel {
        for page in StoryLayout().pages(for: fixture.journey) { if case .overview(let m) = page { return m } }
        throw XCTSkip("no overview page")
    }

    private func render(_ model: OverviewModel, mapMode: ExportPrivacy.MapMode = .show, snap: MapSnap? = nil) throws -> CGImage {
        try XCTUnwrap(TestImages.render(RouteOverviewPage(model: model, metrics: .a4, snap: snap, mapMode: mapMode),
                                        proposed: ProposedViewSize(width: 595, height: 842), scale: 2))
    }

    func testFourStopsA4() throws {
        let f = JourneyFixtures.fourStops()
        let model = try overview(f)
        let shots = [("overview-fourStops-a4", try render(model)),
                     ("overview-fourStops-a4-zoomedOut", try render(model, mapMode: .zoomedOut))]
        #if os(macOS)
        // The sandboxed macOS test host cannot write into the source tree, so it cannot record references
        // (same as VerticalComposerTests). Keep copies in the host's temporary directory to record from by hand.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("overview-snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, img) in shots { TestImages.writePNG(img, to: dir.appendingPathComponent("\(name)-macos.png")) }
        if shots.contains(where: { !FileManager.default.fileExists(atPath: Snapshots.referenceURL(named: $0.0).path) }) {
            throw XCTSkip("No macOS references yet for the overview page; copy them from the test host's tmp/overview-snapshots.")
        }
        #endif
        for (name, img) in shots { assertSnapshot(img, named: name) }
    }

    /// Not asserted (network-dependent): with TEST_RUNNER_MAP_OUT=<dir>, writes the live MapKit page so the
    /// halos can be checked by eye over real map labels.
    func testFourStopsLiveMapForEyeCheck() async throws {
        guard let dir = ProcessInfo.processInfo.environment["MAP_OUT"] else { throw XCTSkip("set TEST_RUNNER_MAP_OUT") }
        let f = JourneyFixtures.fourStops()
        let model = try overview(f)
        let svc = MapSnapshotService(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("maptest-\(UUID().uuidString)"))
        svc.timeout = .seconds(15)
        for mode in [ExportPrivacy.MapMode.show, .zoomedOut] {
            let snap = await svc.snapshot(for: model, size: MapSnapshotService.mapSize(for: .a4), scale: 2, mapMode: mode)
            let name = "overview-fourStops-live-\(mode.rawValue)\(snap.isFallback ? "-FELLBACK" : "")"
            TestImages.writePNG(try render(model, mapMode: mode, snap: snap),
                                to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
