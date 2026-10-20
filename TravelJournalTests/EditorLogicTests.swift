import XCTest
import SwiftData
@testable import TravelJournal

@MainActor
final class EditorLogicTests: XCTestCase {
    func testStoryTruncatesPastLimit() {
        let text = (1...120).map { "w\($0)" }.joined(separator: " ")
        let cut = EditorLogic.limitedStory(text)
        XCTAssertEqual(WordLimit.count(cut), 100)
        XCTAssertEqual(EditorLogic.limitedStory("short story"), "short story")
    }

    func testCounter() {
        let hundred = (1...100).map { "w\($0)" }.joined(separator: " ")
        XCTAssertEqual(EditorLogic.counterText("one two"), "2 / 100")
        XCTAssertEqual(EditorLogic.counterState("one two"), .normal)
        XCTAssertEqual(EditorLogic.counterState(hundred), .atLimit)
        XCTAssertEqual(EditorLogic.counterText(hundred), "100 / 100")
    }

    func testParsing() {
        XCTAssertEqual(EditorLogic.parseMinutes(" 18 "), 18)
        XCTAssertNil(EditorLogic.parseMinutes(""))
        XCTAssertNil(EditorLogic.parseMinutes("-3"))
        XCTAssertNil(EditorLogic.parseMinutes("abc"))
        XCTAssertEqual(EditorLogic.parseKm("5.2"), 5.2)
        XCTAssertEqual(EditorLogic.parseKm("5,2"), 5.2)
        XCTAssertEqual(EditorLogic.parseKm("1,240"), 1240)
        XCTAssertEqual(EditorLogic.parseAmount("1,24,000"), Decimal(124000))
        XCTAssertEqual(EditorLogic.parseAmount("1,240.50"), Decimal(string: "1240.50"))
        XCTAssertEqual(EditorLogic.parseAmount("0,75"), Decimal(string: "0.75"))
        XCTAssertNil(EditorLogic.parseKm("-1"))
        XCTAssertNil(EditorLogic.parseKm("x"))
        XCTAssertEqual(EditorLogic.parseAmount("120.50"), Decimal(string: "120.50"))
        XCTAssertNil(EditorLogic.parseAmount(""))
    }

    func testDeleteConfirmationDecision() {
        let container = AppContainer.make(inMemory: true)
        let j = SampleData.mumbai(in: container.mainContext)
        let stops = j.orderedStops
        for s in stops {
            s.outgoingLeg?.story = nil
            s.outgoingLeg?.distanceKm = nil
            s.outgoingLeg?.durationMinutes = nil
            s.outgoingLeg?.modeWasChosen = false
        }
        XCTAssertFalse(EditorLogic.needsDeleteConfirmation(deleting: stops[1], from: stops))
        stops[1].outgoingLeg?.distanceKm = 2
        XCTAssertTrue(EditorLogic.needsDeleteConfirmation(deleting: stops[1], from: stops))   // own outgoing leg
        XCTAssertTrue(EditorLogic.needsDeleteConfirmation(deleting: stops[2], from: stops))   // incoming leg
        XCTAssertFalse(EditorLogic.needsDeleteConfirmation(deleting: stops[0], from: stops))  // empty leg only
    }

    func testLegSummary() {
        let l = Leg()
        XCTAssertNil(EditorLogic.legSummary(l))
        l.mode = .taxi; l.durationMinutes = 18; l.distanceKm = 5.2
        XCTAssertEqual(EditorLogic.legSummary(l), "taxi · 18 min · 5.2 km")
    }
}
