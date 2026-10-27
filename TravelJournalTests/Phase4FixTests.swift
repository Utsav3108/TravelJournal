import Testing
import SwiftUI
@testable import TravelJournal

@MainActor
struct Phase4FixTests {
    static let out = "/private/tmp/claude-501/-Users-utsav-Documents-Projects-TravelJournal/8161a91e-c450-4f0d-8adb-8fc11249eb44/scratchpad"

    // MARK: Postmark arc text

    @Test func postmarkArcTextRenders() throws {
        KraftFonts.register()
        func render(_ top: String, _ bottom: String) throws -> CGImage {
            try #require(TestImages.render(Postmark(top: top, bottom: bottom, center: "", size: 120, seed: "x").frame(width: 140, height: 140), scale: 2))
        }
        let with = try render("STOP TWO", "MUMBAI")
        let without = try render("", "")
        #expect(TestImages.opaquePixelCount(with) > TestImages.opaquePixelCount(without) + 150)
        TestImages.writePNG(with, to: URL(fileURLWithPath: Self.out + "/postmark-arc.png"))
    }

    // MARK: Pin de-overlap

    private func anchors(_ model: OverviewModel, size: CGSize) -> [CGPoint] {
        let g = MapSnapshotService.geoPoints(of: model).points
        let region = MapProjection.fitRegion(g, aspect: size.width / size.height)!
        return g.map { p in
            let x = (p.lon - (region.centerLon - region.lonSpan / 2)) / region.lonSpan * size.width
            let y = ((region.centerLat + region.latSpan / 2) - p.lat) / region.latSpan * size.height
            return CGPoint(x: x, y: y)
        }
    }

    @Test func mumbaiBadgesDoNotOverlapAndStayInside() {
        for size in [MapSnapshotService.mapSize(for: .a4), MapSnapshotService.mapSize(for: .phone(CGSize(width: 390, height: 800)))] {
            let a = anchors(OverviewSamples.mumbai, size: size)
            let b = PinLayout.badges(anchors: a, bounds: size)
            #expect(b.count == 4)
            for i in b.indices {
                #expect(b[i].x - 13 >= 0 && b[i].x + 13 <= size.width && b[i].y - 13 >= 0 && b[i].y + 13 <= size.height)
                for j in b.indices where j > i {
                    #expect(hypot(b[i].x - b[j].x, b[i].y - b[j].y) >= PinLayout.diameter)
                }
            }
            #expect(b == PinLayout.badges(anchors: a, bounds: size))
        }
    }

    @Test func coincidentAndEdgePinsSeparate() {
        let size = CGSize(width: 300, height: 200)
        let a = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 150, y: 100), CGPoint(x: 150, y: 100)]
        let b = PinLayout.badges(anchors: a, bounds: size)
        for i in b.indices {
            #expect(b[i].x >= 13 && b[i].y >= 13)
            for j in b.indices where j > i { #expect(hypot(b[i].x - b[j].x, b[i].y - b[j].y) >= PinLayout.diameter) }
        }
        #expect(PinLayout.badges(anchors: [], bounds: size).isEmpty)
        #expect(PinLayout.badges(anchors: [CGPoint(x: 100, y: 100)], bounds: size) == [CGPoint(x: 100, y: 100)])
    }

    @Test func legsSummaryRows() {
        let rows = OverviewLegsFormat.rows(OverviewSamples.mumbai)
        #expect(rows.count == 3)
        #expect(rows[0].route == "1→2" && rows[0].detail == "walk · 9 min · 0.6 km")
    }

    @Test func seedIsUsableOffMainActor() async {
        let v = await Task.detached { Seed.rotation(id: "a") + { var s = SeededStream("a", "b"); return Double(s.int(5)) }() + Double(KraftFontName.lora.count) }.value
        #expect(v.isFinite)
    }

    @Test func renderOverviewPNG() throws {
        let img = try #require(TestImages.render(RouteOverviewPage(model: OverviewSamples.mumbai, metrics: .a4, snap: nil),
                                                 proposed: ProposedViewSize(width: 595, height: 842), scale: 2))
        TestImages.writePNG(img, to: URL(fileURLWithPath: Self.out + "/overview-fixed-fallback.png"))
    }
}
