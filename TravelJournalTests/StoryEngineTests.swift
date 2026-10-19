import XCTest
import SwiftData
@testable import TravelJournal

@MainActor
final class StoryEngineTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var editor: JourneyEditor!
    let layout = StoryLayout()

    override func setUp() async throws {
        container = AppContainer.make(inMemory: true)
        context = ModelContext(container)
        editor = JourneyEditor(context: context, photos: NoopPhotoStore())
    }

    private func stops(_ pages: [StoryPage]) -> [StopPageModel] {
        pages.compactMap { if case .stop(let m) = $0 { m } else { nil } }
    }

    func testMumbaiPageOrderAndCount() {
        let j = SampleData.mumbai(in: context)
        let pages = layout.pages(for: j)
        XCTAssertEqual(pages.count, 7)
        guard case .cover(let c) = pages[0], case .overview(let o) = pages[1], case .closing = pages[6] else {
            return XCTFail("wrong order")
        }
        XCTAssertEqual(stops(pages).map(\.name), j.orderedStops.map(\.placeName))
        XCTAssertEqual(c.title, "A Day in Mumbai")
        XCTAssertEqual(c.dateText, "19 OCT 2026")
        XCTAssertEqual(c.postmark, "ARRIVED · 19 OCT 2026 · MUMBAI")
        XCTAssertEqual(c.heroPhotos.count, 3)
        XCTAssertEqual(o.stops.count, 4)
        XCTAssertEqual(o.legs.count, 3)
        XCTAssertEqual(o.stops.map(\.number), [1, 2, 3, 4])
        XCTAssertEqual(o.stops.map(\.id), stops(pages).map(\.id))
    }

    func testTemplatesByPhotoCount() {
        let s = stops(layout.pages(for: SampleData.mumbai(in: context)))
        XCTAssertEqual(s.map(\.template), [.t4, .t3, .t1, .t0])
        XCTAssertEqual(s.map { $0.photos.count }, [4, 3, 1, 0])
        XCTAssertTrue(s[0].photos[0].isHero)
        XCTAssertEqual(StoryLayout.template(forPhotoCount: 9), .t4)
        XCTAssertEqual(StoryLayout.template(forPhotoCount: 2), .t2)
    }

    func testHeroFirstWhenHeroIsNotFirst() {
        let j = Journey(title: "H"); context.insert(j)
        let s = Stop(placeName: "A"); editor.addStop(s, to: j)
        let p1 = StopPhoto(relativePath: "sample:1", orderIndex: 0)
        let p2 = StopPhoto(relativePath: "sample:2", orderIndex: 1, isHero: true)
        s.photos.append(p1); s.photos.append(p2)
        let m = stops(layout.pages(for: j))[0]
        XCTAssertEqual(m.photos.map(\.relativePath), ["sample:2", "sample:1"])
        XCTAssertEqual(m.photos.map(\.isHero), [true, false])
        XCTAssertEqual(m.template, .t2)
    }

    func testDeterminismAndStableIDs() {
        let j = SampleData.mumbai(in: context)
        let a = layout.pages(for: j), b = layout.pages(for: j)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.map(\.id), b.map(\.id))
        let s = stops(a)
        XCTAssertEqual(s[0].id, "stop-" + j.orderedStops[0].id.uuidString)
        XCTAssertEqual(s[0].seed, Seed.fnv1a(j.orderedStops[0].id.uuidString))
        XCTAssertEqual(Set(s.map(\.seed)).count, s.count)
        // Rebuild after an unrelated edit keeps ids and seeds.
        j.orderedStops[3].story = "Changed."
        let c = stops(layout.pages(for: j))
        XCTAssertEqual(c.map(\.id), s.map(\.id))
        XCTAssertEqual(c.map(\.seed), s.map(\.seed))
        XCTAssertEqual(c.map(\.exit), s.map(\.exit))
    }

    func testRouteContinuity() {
        let s = stops(layout.pages(for: SampleData.mumbai(in: context)))
        XCTAssertNil(s.first?.entry)
        XCTAssertNil(s.last?.exit)
        for i in 0..<(s.count - 1) {
            let exit = try! XCTUnwrap(s[i].exit), entry = try! XCTUnwrap(s[i + 1].entry)
            XCTAssertEqual(exit.edge.opposite, entry.edge)
            XCTAssertEqual(exit.t, entry.t)
            XCTAssertTrue(RouteGeometry.tRange.contains(exit.t))
            XCTAssertEqual(s[i].outLeg, s[i + 1].inLeg)
        }
        XCTAssertNotNil(s[0].exit)
        XCTAssertNotNil(s[3].entry)
        // Pure function check.
        let c = RouteGeometry.crossing(forLegKey: "leg-x")
        XCTAssertEqual(c.exit.t, RouteGeometry.t(forLegKey: "leg-x"))
        XCTAssertEqual(c.exit.edge, .right); XCTAssertEqual(c.entry.edge, .left)
    }

    func testStatsTotals() {
        let pages = layout.pages(for: SampleData.mumbai(in: context))
        guard case .overview(let o) = pages[1], case .closing(let cl) = pages[6] else { return XCTFail() }
        XCTAssertEqual(o.stats, cl.stats)
        let st = o.stats
        XCTAssertEqual(st.stops, 4)
        XCTAssertEqual(st.km ?? 0, 15.2, accuracy: 0.001)
        XCTAssertEqual(st.travelMinutes, 63)
        XCTAssertEqual(st.totalMinutes, 135 + 63)   // 30 + 45 + 60 at stops
        XCTAssertEqual(st.modes, ["taxi", "autoRickshaw"])
        XCTAssertEqual(st.photos, 8)
        XCTAssertEqual(st.moneyText, "₹180")
        XCTAssertEqual(cl.closingNote, "Mumbai never sleeps, but I did.")
    }

    func testMoneyText() {
        XCTAssertEqual(StoryLayout.moneyText(["INR": 1240], order: ["INR"]), "₹1,240")
        XCTAssertEqual(StoryLayout.moneyText(["INR": 300, "USD": 5], order: ["INR", "USD"]), "₹300 + $5")
        XCTAssertEqual(StoryLayout.moneyText(["CHF": Decimal(string: "12.5")!], order: []), "CHF 12.5")
    }

    func testSealAtMostOneAndRule() {
        let s = stops(layout.pages(for: SampleData.mumbai(in: context)))
        XCTAssertEqual(s.filter(\.hasSeal).count, 1)
        XCTAssertTrue(s[1].hasSeal)   // 5-star pav bhaji beats the unrated t0 hotel
        XCTAssertEqual(StoryLayout.sealStopIndex(candidates: [(.t4, 5), (.t2, 3)]), nil)
        XCTAssertEqual(StoryLayout.sealStopIndex(candidates: [(.t0, nil), (.t0, nil)]), 0)
    }

    func testEmptyJourney() {
        let j = Journey(title: "Empty"); context.insert(j)
        let pages = layout.pages(for: j)
        XCTAssertEqual(pages.count, 3)
        guard case .overview(let o) = pages[1] else { return XCTFail() }
        XCTAssertTrue(o.stops.isEmpty); XCTAssertTrue(o.legs.isEmpty)
        XCTAssertNil(o.stats.km); XCTAssertNil(o.stats.moneyText)
        XCTAssertEqual(o.stats.totalMinutes, 0)
        guard case .cover(let c) = pages[0] else { return XCTFail() }
        XCTAssertTrue(c.heroPhotos.isEmpty)
    }

    func testSingleStopNoLegsNoCoordinates() {
        let j = Journey(title: "One"); context.insert(j)
        let s = Stop(placeName: "Only"); editor.addStop(s, to: j)
        let pages = layout.pages(for: j)
        XCTAssertEqual(pages.count, 4)
        let m = stops(pages)[0]
        XCTAssertNil(m.entry); XCTAssertNil(m.exit)
        XCTAssertNil(m.inLeg); XCTAssertNil(m.outLeg)
        XCTAssertEqual(m.template, .t0)
        XCTAssertTrue(m.hasSeal)
        XCTAssertEqual(m.categoryRaw, "other")
        guard case .overview(let o) = pages[1] else { return XCTFail() }
        XCTAssertNil(o.stops[0].latitude); XCTAssertNil(o.stops[0].longitude)
        XCTAssertTrue(o.legs.isEmpty)
    }

    func testUnplacedNoModeLegStillRenders() {
        let j = Journey(title: "L"); context.insert(j)
        let a = Stop(placeName: "A"), b = Stop(placeName: "B")
        editor.addStop(a, to: j); editor.addStop(b, to: j)
        let leg = try! XCTUnwrap(a.outgoingLeg)
        leg.distanceKm = 2.5; leg.durationMinutes = 10
        let pages = layout.pages(for: j)
        let s = stops(pages)
        XCTAssertNil(s[0].outLeg?.modeRaw)
        XCTAssertEqual(s[0].outLeg?.km, 2.5)
        XCTAssertEqual(s[1].inLeg?.minutes, 10)
        XCTAssertEqual(s[0].exit?.t, s[1].entry?.t)
        guard case .overview(let o) = pages[1] else { return XCTFail() }
        XCTAssertEqual(o.stats.modes, [])
        XCTAssertEqual(o.stats.km ?? 0, 2.5, accuracy: 0.001)
        XCTAssertEqual(o.stats.travelMinutes, 10)
    }
}
