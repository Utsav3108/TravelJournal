import XCTest
import SwiftData
import CoreLocation
@testable import TravelJournal

@MainActor
final class StoryMapPinsTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = AppContainer.make(inMemory: true)
        context = ModelContext(container)
    }

    private func story(_ title: String, day: Int = 1, stops: [(String, Double?, Double?)]) -> Journey {
        let j = Journey(title: title, date: Date(timeIntervalSince1970: Double(day) * 86_400))
        context.insert(j)
        for (i, s) in stops.enumerated() {
            let stop = Stop(placeName: s.0)
            stop.orderIndex = i
            stop.latitude = s.1; stop.longitude = s.2
            stop.journey = j
            j.stops.append(stop)
        }
        return j
    }

    func testChosenStopWinsOverEarlierStopWithCoordinates() {
        let j = story("A", stops: [("one", 10, 10), ("two", 20, 20)])
        j.mapStopID = j.orderedStops[1].id
        XCTAssertEqual(StoryMapPins.mapStop(for: j)?.placeName, "two")
        XCTAssertEqual(StoryMapPins.pins(for: [j]).first?.coordinate.latitude, 20)
    }

    func testDeletedChosenStopFallsBackToDefault() {
        let j = story("A", stops: [("one", 10, 10), ("two", 20, 20)])
        j.mapStopID = UUID()
        XCTAssertEqual(StoryMapPins.mapStop(for: j)?.placeName, "one")
    }

    func testDefaultIsEarliestStopWithCoordinates() {
        let j = story("A", stops: [("none", nil, nil), ("first", 5, 6), ("second", 7, 8)])
        XCTAssertEqual(StoryMapPins.mapStop(for: j)?.placeName, "first")
        XCTAssertEqual(StoryMapPins.pins(for: [j]).count, 1)
    }

    func testNoCoordinatesAnywhereFallsToEarliestStopAndNoPin() {
        let j = story("A", stops: [("a", nil, nil), ("b", nil, nil)])
        XCTAssertEqual(StoryMapPins.mapStop(for: j)?.placeName, "a")
        XCTAssertTrue(StoryMapPins.pins(for: [j]).isEmpty)
    }

    func testNoStopsMeansNoMapStopAndNoPin() {
        let j = story("A", stops: [])
        XCTAssertNil(StoryMapPins.mapStop(for: j))
        XCTAssertTrue(StoryMapPins.pins(for: [j]).isEmpty)
    }

    func testChosenStopWithoutCoordinatesGivesNoPin() {
        let j = story("A", stops: [("one", 10, 10), ("two", nil, nil)])
        j.mapStopID = j.orderedStops[1].id
        XCTAssertTrue(StoryMapPins.pins(for: [j]).isEmpty)
    }

    func testEditingTheMapStopCoordinatesMovesThePin() {
        let j = story("A", stops: [("one", 10, 10), ("two", 20, 20)])
        j.mapStopID = j.orderedStops[1].id
        j.orderedStops[1].latitude = 30; j.orderedStops[1].longitude = 40
        let pin = StoryMapPins.pins(for: [j]).first
        XCTAssertEqual(pin?.coordinate.latitude, 30)
        XCTAssertEqual(pin?.coordinate.longitude, 40)
    }

    func testSameSpotGroupedAndDistantSeparate() {
        let a = story("A", day: 1, stops: [("x", 19.0760, 72.8777)])
        let b = story("B", day: 2, stops: [("y", 19.07602, 72.87772)])     // about 3 m away
        let c = story("C", day: 3, stops: [("z", 28.6139, 77.2090)])
        let pins = StoryMapPins.pins(for: [a, b, c])
        XCTAssertEqual(pins.count, 2)
        XCTAssertEqual(pins.first { $0.journeyIDs.count == 2 }?.journeyIDs, [b.id, a.id], "newest journey first")
        XCTAssertEqual(pins.first { $0.journeyIDs.count == 1 }?.journeyIDs, [c.id])
    }

    func testJustOutsideFiftyMetresStaysSeparate() {
        // 0.001 degrees of latitude is about 111 m.
        let a = story("A", stops: [("x", 10, 10)])
        let b = story("B", stops: [("y", 10.001, 10)])
        XCTAssertEqual(StoryMapPins.pins(for: [a, b]).count, 2)
    }

    func testOrderAndIDsAreIndependentOfInputOrder() {
        let js = [
            story("A", day: 1, stops: [("a", 10, 10)]),
            story("B", day: 1, stops: [("b", 10.00001, 10)]),
            story("C", day: 2, stops: [("c", 40, 40)]),
            story("D", day: 3, stops: [("d", 10.00002, 10)]),
        ]
        func summary(_ pins: [StoryPin]) -> [String] {
            pins.map { "\($0.id)|\($0.journeyIDs.map(\.uuidString).joined(separator: ","))|\($0.coordinate.latitude)" }
        }
        let forward = summary(StoryMapPins.pins(for: js))
        XCTAssertEqual(forward, summary(StoryMapPins.pins(for: js.reversed())))
        XCTAssertEqual(forward, summary(StoryMapPins.pins(for: [js[2], js[0], js[3], js[1]])))
        let big = StoryMapPins.pins(for: js).first { $0.journeyIDs.count == 3 }
        XCTAssertEqual(big?.journeyIDs.first, js[3].id, "date descending")
    }

    func testMapStopIDRoundTripsThroughUndoSnapshot() {
        let j = story("A", stops: [("one", 1, 1)])
        j.mapStopID = j.stops[0].id
        let before = JourneyContent(j)
        j.mapStopID = nil
        before.apply(to: j)
        XCTAssertEqual(j.mapStopID, j.stops[0].id)
    }
}
