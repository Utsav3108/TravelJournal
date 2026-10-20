import XCTest
@testable import TravelJournal

final class StatsFormatTests: XCTestCase {
    func testHours() {
        let cases: [(Int, String, String)] = [
            (0, "0", "HOURS"), (14, "½", "HOUR"), (15, "½", "HOUR"), (29, "½", "HOUR"), (30, "½", "HOUR"),
            (44, "½", "HOUR"), (45, "1", "HOUR"), (60, "1", "HOUR"), (90, "1½", "HOURS"),
            (156, "2½", "HOURS"), (291, "5", "HOURS")]
        for (m, n, u) in cases {
            let h = StatsFormat.hours(minutes: m)
            XCTAssertEqual(h.numeral, n, "\(m)"); XCTAssertEqual(h.unit, u, "\(m)")
            XCTAssertEqual(StatsFormat.hoursText(minutes: m), "\(n) \(u)")
        }
        XCTAssertEqual(StatsFormat.hours(minutes: -5).joined, "0 HOURS")
        XCTAssertEqual(StatsFormat.hoursText(minutes: 75), "1½ HOURS")   // tie rounds up
    }
}
