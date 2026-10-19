import XCTest
import SwiftUI
import UIKit
@testable import TravelJournal

@MainActor
final class StoryPagesTests: XCTestCase {
    static let renderDir = "/private/tmp/claude-501/-Users-utsav-Documents-Projects-TravelJournal/8161a91e-c450-4f0d-8adb-8fc11249eb44/scratchpad/renders"
    let a4 = PageMetrics.a4
    let phonePrint = PageMetrics(size: CGSize(width: 390, height: 844), margin: 24, mode: .print)

    // MARK: Pure geometry

    func testPagePointsOnEachEdge() {
        let size = CGSize(width: 595, height: 842)
        XCTAssertEqual(PageRouteGeometry.pagePoint(RoutePoint(edge: .left, t: 0.5), in: size), CGPoint(x: 0, y: 421))
        XCTAssertEqual(PageRouteGeometry.pagePoint(RoutePoint(edge: .right, t: 0.25), in: size), CGPoint(x: 595, y: 210.5))
        XCTAssertEqual(PageRouteGeometry.pagePoint(RoutePoint(edge: .top, t: 1), in: size), CGPoint(x: 595, y: 0))
        XCTAssertEqual(PageRouteGeometry.pagePoint(RoutePoint(edge: .bottom, t: 0), in: size), CGPoint(x: 0, y: 842))
        // out-of-range t is clamped
        XCTAssertEqual(PageRouteGeometry.pagePoint(RoutePoint(edge: .left, t: 1.7), in: size).y, 842)
        XCTAssertEqual(PageRouteGeometry.pagePoint(RoutePoint(edge: .left, t: -1), in: size).y, 0)
    }

    func testDashTrimmingEndsOnWholeDash() {
        let firstEnd = PageRouteGeometry.dash - PageRouteGeometry.phase
        for len in stride(from: CGFloat(5), through: 500, by: 7.3) {
            let t = PageRouteGeometry.trimmedLength(len)
            XCTAssertLessThanOrEqual(t, len)
            XCTAssertGreaterThan(len - t, -0.001)
            XCTAssertLessThan(len - t, PageRouteGeometry.period + 0.001, "never trims more than one period")
            let k = (t - firstEnd) / PageRouteGeometry.period
            XCTAssertEqual(k, k.rounded(), accuracy: 0.0001, "length \(len) -> \(t) must end on a dash")
        }
        XCTAssertEqual(PageRouteGeometry.trimmedLength(3), 3)
        XCTAssertEqual(PageRouteGeometry.trimmedLength(100), 4.5 + 5 * 16, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(PageRouteGeometry.trimFraction(length: 100), 1)
        XCTAssertEqual(PageRouteGeometry.trimFraction(length: 0), 1)
    }

    func testPolylineSampling() {
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)]
        XCTAssertEqual(PageRouteGeometry.polylineLength(pts), 20, accuracy: 0.001)
        let s = PageRouteGeometry.sample(pts, atDistance: 14)!
        XCTAssertEqual(s.point.x, 10, accuracy: 0.001)
        XCTAssertEqual(s.point.y, 4, accuracy: 0.001)
        XCTAssertEqual(s.dir.dy, 1, accuracy: 0.001)
    }

    func testRoutesMeetAtSharedEdge() {
        let size = a4.size
        let t = 0.9
        let pageA = RoutePlan.make(stopID: "A", size: size, anchor: CGPoint(x: 49, y: 47), entry: nil,
                                   exit: RoutePoint(edge: .right, t: t), slotSize: CGSize(width: 280, height: 100))
        let pageB = RoutePlan.make(stopID: "B", size: size, anchor: CGPoint(x: 49, y: 47), entry: RoutePoint(edge: .left, t: t),
                                   exit: nil, slotSize: .zero)
        let exitEdge = pageA.exitPoly.first!
        let entryEdge = pageB.entryPoly.first!
        XCTAssertEqual(exitEdge.x, size.width, accuracy: 0.001)
        XCTAssertEqual(entryEdge.x, 0, accuracy: 0.001)
        XCTAssertEqual(exitEdge.y, entryEdge.y, accuracy: 0.001, "route crosses the gutter at the same height")
        XCTAssertEqual(pageA.exitPoly.last!.x, 49, accuracy: 0.001)
        XCTAssertEqual(pageA.exitPoly.last!.y, 47, accuracy: 0.001)
        XCTAssertEqual(pageB.entryPoly.last!.y, 47, accuracy: 0.001)
        XCTAssertNotNil(pageA.badgeCenter)
        XCTAssertNotNil(pageA.arrowTip)
        XCTAssertLessThan(abs(pageA.arrowTip!.x - size.width), 15, "arrow sits 14pt before the edge")
        XCTAssertEqual(pageA.slot?.maxX ?? 0, size.width, accuracy: 0.001)
        XCTAssertEqual(pageA.slot?.height ?? 0, 100)
    }

    func testPageSeedMatchesDesignSystemSeed() {
        for id in ["a", "stop-1/hero", "00000000-0000-0000-0000-000000000001/ticket"] {
            XCTAssertEqual(PageSeed.rotation(id: id), Seed.rotation(id: id), accuracy: 1e-12)
            XCTAssertEqual(PageSeed.rotation(id: id, limit: 3), Seed.rotation(id: id, limit: 3), accuracy: 1e-12)
        }
        var a = PageSeed.Stream("x", "wobble"), b = SeededStream("x", "wobble")
        XCTAssertEqual(a.unit(), b.unit())
    }

    func testFontNamesMatchTokens() {
        XCTAssertEqual(PageFont.lora, KraftFontName.lora)
        XCTAssertEqual(PageFont.caveat, KraftFontName.caveat)
        XCTAssertEqual(PageFont.elite, KraftFontName.elite)
    }

    func testPostmarkParts() {
        let p = PageFormat.postmarkParts("ARRIVED · 19 OCT 2026 · MUMBAI")
        XCTAssertEqual(p.center, "ARRIVED"); XCTAssertEqual(p.top, "19 OCT 2026"); XCTAssertEqual(p.bottom, "MUMBAI")
        XCTAssertEqual(PageFormat.postmarkParts("ARRIVED").top, "")
    }

    func testClosingTiles() {
        let t = ClosingTile.tiles(for: StoryPageSamples.stats)
        XCTAssertEqual(t.map(\.label), ["STOPS", "KM", "MINUTES", "SPENT", "PHOTOS"])
        XCTAssertEqual(t[1].numeral, "8.4")
        var s = StoryPageSamples.stats; s.km = nil; s.moneyText = nil
        XCTAssertEqual(ClosingTile.tiles(for: s)[1].numeral, "–")
        XCTAssertEqual(ClosingTile.tiles(for: s)[3].numeral, "–")
    }

    // MARK: Layout

    func testA4LayoutBudgetsFitForEveryTemplate() {
        for t in [StopTemplate.t0, .t1, .t2, .t3, .t4] {
            for story in [StoryPageSamples.story100, StoryPageSamples.worstCase100] {
                let m = StoryPageSamples.stop(t, index: 1, total: 4, story: story, seal: true)
                let L = StopLayout.make(m, metrics: a4)
                let limit = a4.size.height - a4.margin - L.slotSize.height
                let page = CGRect(origin: .zero, size: a4.size)
                let all = [L.hero, L.cost, L.highlight, L.rating, L.postmark, L.seal].compactMap { $0 } + L.taped + [L.ticket, L.card]
                for r in all { XCTAssertTrue(page.insetBy(dx: -1, dy: -1).contains(r), "T\(t.rawValue): \(r) outside page") }
                XCTAssertLessThanOrEqual(L.card.maxY, limit + 0.5, "T\(t.rawValue) card must clear the connector slot")
                if story == StoryPageSamples.story100 {
                    XCTAssertFalse(L.cardClipped, "T\(t.rawValue): 100-word story must fit without shrinking")
                }
                print("LAYOUT T\(t.rawValue) \(story == StoryPageSamples.story100 ? "100w" : "worst") card.h=\(Int(L.card.height)) card.maxY=\(Int(L.card.maxY)) limit=\(Int(limit)) bandScale=\(L.bandScale) clipped=\(L.cardClipped)")
            }
        }
    }

    func testNoOverlapBetweenMainElementsA4() {
        for t in [StopTemplate.t1, .t2, .t3, .t4] {
            let L = StopLayout.make(StoryPageSamples.stop(t, story: StoryPageSamples.story100), metrics: a4)
            XCTAssertFalse(L.ticket.intersects(L.card), "T\(t.rawValue) ticket/card")
            if let h = L.highlight { XCTAssertFalse(h.intersects(L.card), "T\(t.rawValue) highlight/card") }
            if let r = L.rating { XCTAssertFalse(r.intersects(L.card), "T\(t.rawValue) rating/card") }
            for p in L.taped { XCTAssertFalse(p.intersects(L.card), "T\(t.rawValue) taped/card") }
            if let r = L.rating, let h = L.highlight { XCTAssertFalse(r.intersects(h), "T\(t.rawValue) rating/highlight") }
            if let r = L.rating { XCTAssertFalse(r.intersects(L.ticket), "T\(t.rawValue) rating/ticket") }
        }
    }

    func testPhoneLayoutGrowsInsteadOfOverflowing() {
        for t in [StopTemplate.t0, .t1, .t2, .t3, .t4] {
            let m = StoryPageSamples.stop(t, story: StoryPageSamples.story100)
            let L = StopLayout.make(m, metrics: .phone(CGSize(width: 390, height: 844)))
            XCTAssertGreaterThanOrEqual(L.pageSize.height, 844)
            XCTAssertLessThanOrEqual(L.card.maxY + L.slotSize.height, L.pageSize.height)
            XCTAssertEqual(L.card.width, 342)
            XCTAssertEqual(L.pageSize.width, 390)
            XCTAssertNotNil(L.route.exitPoint)
            XCTAssertEqual(L.route.exitPoint!.x, 390, accuracy: 0.001)
        }
    }

    func testHeroRotationIsSeededAndBounded() {
        for id in ["a", "b", "c", "d"] { XCTAssertLessThanOrEqual(abs(PageSeed.rotation(id: "\(id)/hero")), 4) }
        XCTAssertEqual(PageSeed.rotation(id: "x/hero"), PageSeed.rotation(id: "x/hero"))
    }

    // MARK: Image provider

    private func tempStore() throws -> (FilePhotoStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("story-pages-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Photos/thumbs"), withIntermediateDirectories: true)
        return (FilePhotoStore(baseURL: dir), dir)
    }

    private func writeJPEG(_ url: URL, side: CGFloat) throws {
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            UIColor.orange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
        try img.jpegData(compressionQuality: 0.8)!.write(to: url)
    }

    func testImageProviderFallbacksAndCache() throws {
        let (store, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeJPEG(dir.appendingPathComponent("Photos/full.jpg"), side: 400)
        try writeJPEG(dir.appendingPathComponent("Photos/thumbs/thumb.jpg"), side: 100)
        let provider = FileStoryImageProvider(store: store)

        let both = StoryPhoto(id: "1", relativePath: "Photos/full.jpg", thumbPath: "Photos/thumbs/thumb.jpg", isHero: true)
        let thumbPx = CGFloat(provider.image(for: both, preferThumbnail: true)!.cgImage!.width)
        let fullPx = CGFloat(provider.image(for: both, preferThumbnail: false)!.cgImage!.width)
        XCTAssertEqual(thumbPx, 300, accuracy: 1, "interactive mode prefers the thumbnail")
        XCTAssertEqual(fullPx, 1200, accuracy: 1, "print mode uses the display file")

        // cache: repeated loads do not decode again
        let before = provider.loadCount
        _ = provider.image(for: both, preferThumbnail: true)
        _ = provider.image(for: both, preferThumbnail: false)
        XCTAssertEqual(provider.loadCount, before)

        // thumb missing -> falls back to full; full missing -> falls back to thumb
        let noThumb = StoryPhoto(id: "2", relativePath: "Photos/full.jpg", thumbPath: "Photos/thumbs/missing.jpg", isHero: false)
        XCTAssertNotNil(provider.image(for: noThumb, preferThumbnail: true))
        let noFull = StoryPhoto(id: "3", relativePath: "Photos/missing.jpg", thumbPath: "Photos/thumbs/thumb.jpg", isHero: false)
        XCTAssertNotNil(provider.image(for: noFull, preferThumbnail: false))

        // sample: and missing files -> nil (placeholder)
        XCTAssertNil(provider.image(for: StoryPhoto(id: "4", relativePath: "sample:x-1", thumbPath: "sample:x-1", isHero: true), preferThumbnail: true))
        XCTAssertNil(provider.image(for: StoryPhoto(id: "5", relativePath: "Photos/nope.jpg", thumbPath: nil, isHero: true), preferThumbnail: false))
        XCTAssertNil(provider.image(for: StoryPhoto(id: "6", relativePath: "", thumbPath: nil, isHero: true), preferThumbnail: false))

        // a corrupt file is also a placeholder, not a crash
        try Data("not a jpeg".utf8).write(to: dir.appendingPathComponent("Photos/bad.jpg"))
        XCTAssertNil(provider.image(for: StoryPhoto(id: "7", relativePath: "Photos/bad.jpg", thumbPath: nil, isHero: true), preferThumbnail: false))
        XCTAssertTrue(FileStoryImageProvider.isLoadable("Photos/a.jpg"))
        XCTAssertFalse(FileStoryImageProvider.isLoadable("sample:a"))
    }

    // MARK: Rendering

    private func render(_ page: StoryPage, metrics: PageMetrics, provider: StoryImageProvider = PlaceholderImageProvider()) -> UIImage? {
        let view = StoryPageView(page: page, metrics: metrics).environment(\.storyImageProvider, provider)
        let r = ImageRenderer(content: view)
        r.scale = 1
        return r.uiImage
    }

    private func save(_ img: UIImage?, _ name: String) {
        guard FileManager.default.fileExists(atPath: Self.renderDir), let data = img?.pngData() else { return }
        try? data.write(to: URL(fileURLWithPath: Self.renderDir).appendingPathComponent(name + ".png"))
    }

    func testEveryPageTypeRendersAtA4() {
        for (label, page) in StoryPageSamples.all {
            let img = render(page, metrics: a4)
            XCTAssertNotNil(img, label)
            XCTAssertEqual(img?.size.width ?? 0, 595, accuracy: 0.5, label)
            XCTAssertEqual(img?.size.height ?? 0, 842, accuracy: 0.5, label)
            XCTAssertGreaterThan(img?.pngData()?.count ?? 0, 5_000, "\(label) rendered blank")
            save(img, "a4-" + label.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: ""))
        }
    }

    func testEveryTemplateRendersAtPhoneSize() {
        for t in [StopTemplate.t0, .t1, .t2, .t3, .t4] {
            let page = StoryPage.stop(StoryPageSamples.stop(t, story: StoryPageSamples.story100, seal: t == .t2))
            let img = render(page, metrics: phonePrint)
            XCTAssertGreaterThanOrEqual(img?.size.height ?? 0, 844, "T\(t.rawValue)")
            XCTAssertEqual(img?.size.width ?? 0, 390, accuracy: 0.5)
            save(img, "phone-stop-t\(t.rawValue)")
        }
        save(render(.cover(StoryPageSamples.cover), metrics: phonePrint), "phone-cover")
        save(render(.closing(StoryPageSamples.closing), metrics: phonePrint), "phone-closing")
    }

    func testStopWithRealPhotosRenders() throws {
        let (store, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeJPEG(dir.appendingPathComponent("Photos/a.jpg"), side: 600)
        let provider = FileStoryImageProvider(store: store)
        var m = StoryPageSamples.stop(.t3, story: StoryPageSamples.story100)
        m.photos = (0..<3).map { StoryPhoto(id: "r\($0)", relativePath: "Photos/a.jpg", thumbPath: nil, isHero: $0 == 0) }
        let img = render(.stop(m), metrics: a4, provider: provider)
        XCTAssertNotNil(img)
        save(img, "a4-real-photos-t3")
    }

    func testMinimalModelsDoNotCrash() {
        var m = StoryPageSamples.stop(.t0, story: "", withLegs: false, rating: nil, highlight: nil)
        m.costText = nil; m.arrival = nil; m.spentMinutes = nil; m.review = nil
        XCTAssertNotNil(render(.stop(m), metrics: a4))
        var leg = StoryPageSamples.leg; leg.modeRaw = nil; leg.km = nil; leg.minutes = nil; leg.story = nil
        var n = StoryPageSamples.stop(.t2); n.outLeg = leg
        XCTAssertNotNil(render(.stop(n), metrics: a4))
        let c = CoverModel(title: "Untitled", dateText: "", city: nil, postmark: "", heroPhotos: [], intro: nil, seed: 1)
        XCTAssertNotNil(render(.cover(c), metrics: a4))
        let cl = ClosingModel(stats: StatsModel(stops: 0, km: nil, totalMinutes: 0, travelMinutes: 0, modes: [], photos: 0, moneyText: nil), closingNote: nil, seed: 1)
        XCTAssertNotNil(render(.closing(cl), metrics: a4))
    }
}
