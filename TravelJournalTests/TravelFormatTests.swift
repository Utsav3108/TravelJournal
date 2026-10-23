import XCTest
@testable import TravelJournal

final class TravelFormatTests: XCTestCase {
    func testHours() {
        XCTAssertEqual(TravelFormat.hours(minutes: 0), "0 hours")
        XCTAssertEqual(TravelFormat.hours(minutes: 10), "10 min")
        XCTAssertEqual(TravelFormat.hours(minutes: 14), "14 min")
        XCTAssertEqual(TravelFormat.hours(minutes: 15), "½ hour")
        XCTAssertEqual(TravelFormat.hours(minutes: 30), "½ hour")
        XCTAssertEqual(TravelFormat.hours(minutes: 63), "1 hour")
        XCTAssertEqual(TravelFormat.hours(minutes: 75), "1½ hours")   // tie rounds up
        XCTAssertEqual(TravelFormat.hours(minutes: 90), "1½ hours")
        XCTAssertEqual(TravelFormat.hours(minutes: 320), "5½ hours")
        XCTAssertEqual(TravelFormat.hours(minutes: -3), "0 hours")
    }

    func testLegDuration() {
        XCTAssertEqual(TravelFormat.legDuration(minutes: 20), "20 min")
        XCTAssertEqual(TravelFormat.legDuration(minutes: 60), "1 h")
        XCTAssertEqual(TravelFormat.legDuration(minutes: 65), "1 h 5 min")
        XCTAssertEqual(TravelFormat.legDuration(minutes: -1), "0 min")
    }

    func testModeNames() {
        let expected: [TransportMode: String] = [.walk: "Walk", .autoRickshaw: "Auto", .taxi: "Taxi", .bus: "Bus",
                                                 .localTrain: "Local train", .metro: "Metro", .bike: "Bike", .ferry: "Ferry"]
        for m in TransportMode.allCases { XCTAssertEqual(TravelFormat.modeName(m), expected[m]) }
        XCTAssertEqual(TravelFormat.modeName(raw: "autoRickshaw"), "Auto")
        XCTAssertEqual(TravelFormat.modeName(raw: "auto-rickshaw"), "Auto")    // legacy KraftTransport raw
        XCTAssertEqual(TravelFormat.modeName(raw: "train"), "Local train")
        XCTAssertNil(TravelFormat.modeName(raw: "rocket"))
        XCTAssertNil(TravelFormat.modeName(raw: nil))
        XCTAssertEqual(TravelFormat.modeList(raws: ["taxi", "autoRickshaw"]), "Taxi, Auto")
        XCTAssertEqual(TravelFormat.modeList(raws: ["walk", "taxi", "bus", "ferry", "rocket"]), "Walk, Taxi, Bus +1")
        XCTAssertNil(TravelFormat.modeList(raws: ["rocket"]))
    }

    func testKm() {
        XCTAssertEqual(TravelFormat.km(6), "6 km")
        XCTAssertEqual(TravelFormat.km(5.96), "6 km")
        XCTAssertEqual(TravelFormat.km(8.46), "8.5 km")
        XCTAssertEqual(TravelFormat.km(0.6), "0.6 km")
        XCTAssertEqual(TravelFormat.km(0.02), "0.1 km")
        XCTAssertEqual(TravelFormat.km(0), "0 km")
    }

    @MainActor
    func testKraftLegLabel() {
        XCTAssertEqual(KraftFormat.legLabel(mode: .autoRickshaw, minutes: 20, km: 6).uppercased(), "AUTO · 20 MIN · 6 KM")
        XCTAssertEqual(KraftFormat.legLabel(mode: .train, minutes: 65, km: 5.24), "local train · 1 h 5 min · 5.2 km")
        XCTAssertEqual(KraftFormat.legLabel(mode: nil, minutes: nil, km: 1.5), "1.5 km")
        XCTAssertEqual(KraftFormat.duration(minutes: 320), "5 h 20 min")
        XCTAssertEqual(KraftFormat.statsLine(stops: 4, km: 8.4, minutes: 320, modes: [.taxi, .autoRickshaw]),
                       ["4 stops", "8.4 km", "5½ hours", "taxi, auto"])
    }

    func testViewerLogicUsesTravelFormat() {
        XCTAssertEqual(StoryViewerLogic.modeName("autoRickshaw"), "Auto")
        XCTAssertEqual(StoryViewerLogic.minutesText(65), "1 h 5 min")
        XCTAssertEqual(StoryViewerLogic.kmText(6.0), "6 km")
    }
}
