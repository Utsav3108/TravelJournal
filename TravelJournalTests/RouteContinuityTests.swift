import XCTest
import SwiftData
@testable import TravelJournal

/// The dashed route exits RIGHT of page i and must enter LEFT of page i+1 at the same absolute y.
@MainActor
final class RouteContinuityTests: XCTestCase {
    let phone = PageMetrics.phone(CGSize(width: 390, height: 844))
    let phoneSmall = PageMetrics.phone(CGSize(width: 375, height: 667))
    let a4 = PageMetrics.a4

    private func stopModels(_ pages: [StoryPage]) -> [StopPageModel] {
        pages.compactMap { if case .stop(let m) = $0 { m } else { nil } }
    }

    private func assertSeams(_ pages: [StoryPage], _ metrics: PageMetrics, _ label: String) {
        var checked = 0
        for i in 1..<pages.count {
            guard case .stop(let cur) = pages[i], case .stop(let prev) = pages[i - 1] else { continue }
            let entryY = StopLayout.entryY(at: i, in: pages, metrics: metrics)
            XCTAssertNotNil(entryY, "\(label) page \(i)")
            let a = StopLayout.make(prev, metrics: metrics, entryY: StopLayout.entryY(at: i - 1, in: pages, metrics: metrics))
            let b = StopLayout.make(cur, metrics: metrics, entryY: entryY)
            guard let exit = a.route.exitPoint, let entry = b.route.entryPoint else { XCTFail("\(label) \(i): missing points"); continue }
            XCTAssertEqual(exit.y, entry.y, accuracy: 0.001, "\(label) seam \(i - 1)->\(i)")
            XCTAssertEqual(exit.x, a.pageSize.width, accuracy: 0.001, "exit is on the right edge")
            XCTAssertEqual(entry.x, 0, accuracy: 0.001, "entry is on the left edge")
            XCTAssertEqual(a.route.exitPoly.first?.y ?? -1, b.route.entryPoly.first?.y ?? -2, accuracy: 0.001)
            XCTAssertLessThanOrEqual(entry.y, b.pageSize.height, "entry lies within its page")
            XCTAssertLessThanOrEqual(exit.y, a.pageSize.height, "exit lies within its page")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0)
    }

    func testMumbaiSeamsPhoneAndA4() throws {
        let container = AppContainer.make(inMemory: true)
        let ctx = ModelContext(container)
        let pages = StoryLayout().pages(for: SampleData.mumbai(in: ctx))
        XCTAssertGreaterThan(stopModels(pages).count, 2)
        for (m, label) in [(phone, "phone"), (phoneSmall, "phoneSmall"), (a4, "a4")] { assertSeams(pages, m, label) }
    }

    /// Every combination of 0-4 photos adjacent to every other, with long and short stories (tall phone pages included).
    func testPhotoCountPairsSeams() {
        let long = String(repeating: "The tram rattled along the waterfront and the whole city smelled of salt and chai. ", count: 6)
        for story in ["Short note.", long] {
            for a in 0...4 {
                for b in 0...4 {
                    var models = [StoryPageSamples.stop(StopTemplate(rawValue: a)!, index: 0, total: 3, story: story, seal: a == 3),
                                  StoryPageSamples.stop(StopTemplate(rawValue: b)!, index: 1, total: 3, story: story),
                                  StoryPageSamples.stop(StopTemplate(rawValue: (a + b) % 5)!, index: 2, total: 3, story: story)]
                    // distinct stop ids so wobble/anchors differ, and distinct t per leg
                    models[0].stopID = "s0-\(a)-\(b)"; models[1].stopID = "s1-\(a)-\(b)"; models[2].stopID = "s2-\(a)-\(b)"
                    models[0].exit = RoutePoint(edge: .right, t: 0.88); models[1].entry = RoutePoint(edge: .left, t: 0.88)
                    models[1].exit = RoutePoint(edge: .right, t: 0.91); models[2].entry = RoutePoint(edge: .left, t: 0.91)
                    let pages = models.map { StoryPage.stop($0) }
                    for (m, label) in [(phone, "phone"), (phoneSmall, "phoneSmall"), (a4, "a4")] {
                        assertSeams(pages, m, "\(label) \(a)->\(b) len\(story.count)")
                    }
                }
            }
        }
    }

    /// A page's own exit never depends on the incoming entry.
    func testExitIndependentOfEntry() {
        var m = StoryPageSamples.stop(.t4, index: 1, total: 3)
        m.stopID = "indep"
        let base = StopLayout.make(m, metrics: phone).route.exitPoint
        let pushed = StopLayout.make(m, metrics: phone, entryY: 1500).route.exitPoint
        XCTAssertEqual(base, pushed)
    }
}
