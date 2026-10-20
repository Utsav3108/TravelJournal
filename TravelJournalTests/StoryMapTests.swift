import Testing
import SwiftUI
import UIKit
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
        #expect(a != MapProjection.cacheKey([cst, sid], size: CGSize(width: 300, height: 200), scale: 2))
        #expect(a == "\(a)" && !a.isEmpty)
    }

    @Test func noCoordinatesYieldsFallback() async {
        let svc = MapSnapshotService(cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("maptest-\(UUID().uuidString)"))
        let size = CGSize(width: 300, height: 200)
        let snap = await svc.snapshot(for: OverviewSamples.noCoordinates, size: size)
        #expect(snap.isFallback)
        #expect(snap.pins.isEmpty)
        #expect(snap.image.size == size)
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
        let s = StatsModel(stops: 4, km: 8.44, totalMinutes: 320, travelMinutes: 65, modes: ["walk", "taxi"], photos: 0, moneyText: nil)
        #expect(OverviewStatsFormat.items(s) == ["4 stops", "8.4 km", "5½ HOURS", "walk, taxi"])
        #expect(OverviewStatsFormat.travelText(s) == "travel 1 h 5 min")
        #expect(OverviewStatsFormat.kmText(8.46) == "8.5 km")
        #expect(OverviewStatsFormat.duration(45) == "45 min")
        #expect(OverviewStatsFormat.duration(120) == "2 h")
        let one = StatsModel(stops: 1, km: nil, totalMinutes: 30, travelMinutes: 0, modes: ["a", "b", "c", "d"], photos: 0, moneyText: nil)
        #expect(OverviewStatsFormat.items(one) == ["1 stop", "½ HOUR", "a, b, c +1"])
        #expect(OverviewStatsFormat.travelText(one) == nil)
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
        #expect(img.size.width > 500 && img.size.height > 800)
        #expect(img.pngData()!.count > 20_000)
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

    private func render(_ model: OverviewModel, snap: MapSnap?) throws -> UIImage {
        let r = ImageRenderer(content: RouteOverviewPage(model: model, metrics: .a4, snap: snap))
        r.proposedSize = ProposedViewSize(width: 595, height: 842)
        r.scale = 2
        return try #require(r.uiImage)
    }

    private func write(_ img: UIImage, _ name: String) throws {
        guard let dir = ProcessInfo.processInfo.environment["SIMCTL_CHILD_MAP_OUT"] ?? Optional("/private/tmp/claude-501/-Users-utsav-Documents-Projects-TravelJournal/8161a91e-c450-4f0d-8adb-8fc11249eb44/scratchpad") else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? img.pngData()?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
