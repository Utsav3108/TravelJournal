import XCTest
import SwiftData
@testable import TravelJournal

@MainActor
final class MapStopChoicesTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws { container = AppContainer.make(inMemory: true) }

    private func journey(names: [String]) -> Journey {
        let ctx = container.mainContext
        let j = Journey(title: "Trip")
        ctx.insert(j)
        for (i, n) in names.enumerated() {
            let s = Stop(placeName: n)
            s.orderIndex = i
            s.journey = j
            ctx.insert(s)
        }
        return j
    }

    func testChoicesFollowRouteOrderAndLabelUnnamedStops() {
        let j = journey(names: ["Fort", "  ", "Beach"])
        XCTAssertEqual(MapStopChoices.choices(for: j).map(\.label), ["Fort", "Stop 2", "Beach"])
        XCTAssertEqual(MapStopChoices.choices(for: j).map(\.id), j.orderedStops.map(\.id))
    }

    func testSelectedStopFollowsChoiceAndFallsBack() {
        let j = journey(names: ["A", "B"])
        XCTAssertEqual(MapStopChoices.selectedStop(for: j)?.placeName, "A")
        j.mapStopID = j.orderedStops[1].id
        XCTAssertEqual(MapStopChoices.selectedStop(for: j)?.placeName, "B")
    }

    func testNoStopsMeansNoSelection() {
        XCTAssertNil(MapStopChoices.selectedStop(for: journey(names: [])))
    }

    func testHintOnlyWhenCoordinatesAreMissing() {
        XCTAssertEqual(MapStopChoices.hint(latitude: nil, longitude: nil), "Add a location to show this story on the map")
        XCTAssertNotNil(MapStopChoices.hint(latitude: 1, longitude: nil))
        XCTAssertNil(MapStopChoices.hint(latitude: 18.9398, longitude: 72.8355))
    }

    func testJourneySnapshotRoundTripsMapStop() {
        let j = journey(names: ["A", "B"])
        j.mapStopID = j.orderedStops[1].id
        let snap = JourneyContent(j)
        j.mapStopID = nil
        snap.apply(to: j)
        XCTAssertEqual(j.mapStopID, j.orderedStops[1].id)
    }
}
