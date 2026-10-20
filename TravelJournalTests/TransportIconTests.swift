import XCTest
@testable import TravelJournal

final class TransportIconTests: XCTestCase {
    func testEveryModeHasIcon() {
        XCTAssertEqual(TransportMode.allCases.count, 8)
        XCTAssertEqual(Set(TransportMode.allCases.map(\.icon)).count, 8)
    }

    func testAllStoredRawsMapToExpectedIcon() {
        let expected: [(String, KraftTransport)] = [
            ("walk", .walk), ("autoRickshaw", .autoRickshaw), ("taxi", .taxi), ("bus", .bus),
            ("localTrain", .train), ("metro", .metro), ("bike", .bike), ("ferry", .ferry)
        ]
        for (raw, icon) in expected {
            let leg = StoryLeg(id: "l", modeRaw: raw, km: nil, minutes: nil, story: nil)
            XCTAssertEqual(TransportMode.icon(forRaw: leg.modeRaw), icon, raw)
        }
    }

    func testLegacyAndMissingRaws() {
        XCTAssertEqual(TransportMode.icon(forRaw: "auto-rickshaw"), .autoRickshaw)
        XCTAssertEqual(TransportMode.icon(forRaw: "train"), .train)
        XCTAssertNil(TransportMode.icon(forRaw: nil))
        XCTAssertNil(TransportMode.icon(forRaw: "hoverboard"))
    }
}
