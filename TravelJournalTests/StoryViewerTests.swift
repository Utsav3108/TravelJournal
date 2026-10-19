import XCTest
import SwiftData
@testable import TravelJournal

@MainActor
final class StoryViewerTests: XCTestCase {
    private func pages() -> [StoryPage] {
        let container = AppContainer.make(inMemory: true)
        let j = SampleData.mumbai(in: container.mainContext)
        let p = StoryLayout().pages(for: j)
        _keep = container
        return p
    }
    private var _keep: ModelContainer?

    func testIndexJump() {
        let ps = pages()
        XCTAssertEqual(StoryViewerLogic.index(of: "cover", in: ps), 0)
        XCTAssertEqual(StoryViewerLogic.index(of: "overview", in: ps), 1)
        XCTAssertEqual(StoryViewerLogic.index(of: ps[3].id, in: ps), 3)
        XCTAssertNil(StoryViewerLogic.index(of: "nope", in: ps))
        XCTAssertNil(StoryViewerLogic.index(of: nil, in: ps))
    }

    func testRebuildKeepsCurrentID() {
        let ps = pages()
        let id = ps[3].id
        // Page removed before it: id still present, so index shifts but id is stable.
        var shorter = ps; shorter.remove(at: 2)
        XCTAssertEqual(StoryViewerLogic.stableCurrentID(current: id, oldIndex: 3, in: shorter), id)
        // Current page deleted: clamp the old index.
        var without = ps; without.remove(at: 3)
        XCTAssertEqual(StoryViewerLogic.stableCurrentID(current: id, oldIndex: 3, in: without), without[3].id)
        var tiny = Array(ps.prefix(2))
        XCTAssertEqual(StoryViewerLogic.stableCurrentID(current: id, oldIndex: 9, in: tiny), tiny[1].id)
        XCTAssertEqual(StoryViewerLogic.stableCurrentID(current: nil, oldIndex: 0, in: ps), ps[0].id)
        tiny.removeAll()
        XCTAssertNil(StoryViewerLogic.stableCurrentID(current: id, oldIndex: 0, in: tiny))
    }

    func testIndicatorAndLabels() {
        let ps = pages()
        XCTAssertEqual(StoryViewerLogic.indicatorText(index: 2, total: 6), "3 / 6")
        let label = StoryViewerLogic.pageLabel(ps[2], index: 2, total: ps.count)
        XCTAssertTrue(label.hasPrefix("Page 3 of \(ps.count), Stop: "))
        XCTAssertEqual(StoryViewerLogic.pageLabel(ps[1], index: 1, total: 6), "Page 2 of 6, Route overview")
    }

    func testLegCardFull() {
        let t = StoryViewerLogic.legCardText(StoryLeg(id: "a", modeRaw: "taxi", km: 5.2, minutes: 75, story: " Rainy ride "))
        XCTAssertEqual(t.title, "Taxi")
        XCTAssertEqual(t.details, ["1 h 15 min", "5.2 km"])
        XCTAssertEqual(t.story, "Rainy ride")
        XCTAssertNil(t.emptyNote)
        XCTAssertEqual(t.accessibility, "Taxi, 1 h 15 min, 5.2 km. Rainy ride")
    }

    func testLegCardMissingFields() {
        let none = StoryViewerLogic.legCardText(StoryLeg(id: "a", modeRaw: nil, km: nil, minutes: nil, story: nil))
        XCTAssertEqual(none.title, "Travel")
        XCTAssertTrue(none.details.isEmpty)
        XCTAssertEqual(none.emptyNote, "No travel details yet.")
        let noMode = StoryViewerLogic.legCardText(StoryLeg(id: "a", modeRaw: nil, km: 3, minutes: nil, story: ""))
        XCTAssertEqual(noMode.details, ["3 km"])
        XCTAssertEqual(noMode.emptyNote, "No story for this leg yet.")
        XCTAssertEqual(StoryViewerLogic.modeName("train"), "Local train")
        XCTAssertEqual(StoryViewerLogic.modeName("localTrain"), "Local train")
        XCTAssertNil(StoryViewerLogic.modeName("rocket"))
        XCTAssertEqual(StoryViewerLogic.minutesText(45), "45 min")
        XCTAssertEqual(StoryViewerLogic.minutesText(120), "2 h")
    }
}
