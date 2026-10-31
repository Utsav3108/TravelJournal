import XCTest
@testable import TravelJournal

final class JourneyMapsLogicTests: XCTestCase {
    private func stop(_ n: Int, _ lat: Double?, _ lon: Double?, name: String? = nil) -> OverviewStop {
        OverviewStop(id: "stop-\(n)", number: n, name: name ?? "S\(n)", latitude: lat, longitude: lon)
    }

    private func overview(_ stops: [OverviewStop]) -> OverviewModel {
        OverviewModel(stops: stops, legs: [],
                      stats: StatsModel(stops: stops.count, km: nil, totalMinutes: 0, travelMinutes: 0,
                                        modes: [], photos: 0, moneyText: nil))
    }

    func testStopsWithoutCoordinatesAreSkippedInOrder() {
        let pins = JourneyMapsLogic.pins(from: overview([stop(1, 1, 1), stop(2, nil, nil), stop(3, 3, 3), stop(4, 4, 4)]))
        XCTAssertEqual(pins.map(\.name), ["S1", "S3", "S4"])
    }

    func testStartAndEndAreTheFirstAndLastLocatedStops() {
        let pins = JourneyMapsLogic.pins(from: overview([stop(1, nil, nil), stop(2, 2, 2), stop(3, 3, 3), stop(4, 4, 4), stop(5, nil, nil)]))
        XCTAssertEqual(pins.map(\.role), [.start, .stop, .end])
        XCTAssertEqual(pins.first?.name, "S2")
        XCTAssertEqual(pins.last?.name, "S4")
    }

    func testTwoLocatedStopsAreReady() {
        guard case .ready(let pins) = JourneyMapsLogic.readiness(for: overview([stop(1, 1, 1), stop(2, nil, nil), stop(3, 3, 3)])) else {
            return XCTFail("expected ready")
        }
        XCTAssertEqual(pins.map(\.role), [.start, .end])
    }

    func testFewerThanTwoNeedLocationsAndListTheMissingStops() {
        XCTAssertEqual(JourneyMapsLogic.readiness(for: overview([])), .needsLocations(located: 0, missing: []))
        let one = overview([stop(1, 1, 1), stop(2, nil, nil), stop(3, nil, nil)])
        XCTAssertEqual(JourneyMapsLogic.readiness(for: one),
                       .needsLocations(located: 1, missing: [stop(2, nil, nil), stop(3, nil, nil)]))
    }

    func testLatitudeWithoutLongitudeCountsAsMissing() {
        let o = overview([stop(1, 1, 1), stop(2, 2, nil)])
        XCTAssertEqual(JourneyMapsLogic.readiness(for: o), .needsLocations(located: 1, missing: [stop(2, 2, nil)]))
    }

    func testUnnamedStopFallsBackToItsNumberAndLabelsMarkStartAndEnd() {
        let pins = JourneyMapsLogic.pins(from: overview([stop(1, 1, 1, name: ""), stop(2, 2, 2)]))
        XCTAssertEqual(JourneyMapsLogic.label(for: pins[0]), "Start: Stop 1")
        XCTAssertEqual(JourneyMapsLogic.label(for: pins[1]), "End: S2")
    }
}
