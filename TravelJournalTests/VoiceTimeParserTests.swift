#if os(macOS)
import XCTest
@testable import TravelJournal

final class VoiceTimeParserTests: XCTestCase {
    private func arrival(_ s: String) -> String? { VoiceTimeParser.arrival(in: s) }
    private func minutes(_ s: String) -> Int? { VoiceTimeParser.minutes(in: s) }

    // MARK: Arrival

    func testArrivalWithMeridiem() {
        XCTAssertEqual(arrival("i arrived at 2 pm"), "14:00")
        XCTAssertEqual(arrival("we got there at 9 am"), "09:00")
        XCTAssertEqual(arrival("reached around 11 15 am"), nil, "'11 15' without a colon is left to the model")
        XCTAssertEqual(arrival("reached at 12 pm"), "12:00")
        XCTAssertEqual(arrival("got in at 12 am"), "00:00")
    }

    func testArrivalSpellings() {
        XCTAssertEqual(arrival("I arrived at 2 PM"), "14:00")
        XCTAssertEqual(arrival("arrived at 2 p.m."), "14:00")
        XCTAssertEqual(arrival("arrived at 2:30 p.m. and it was crowded"), "14:30")
        XCTAssertEqual(arrival("we arrived at two pm"), "14:00")
        XCTAssertEqual(arrival("we reached at ten thirty am"), nil, "spoken minutes without a colon are left to the model")
    }

    func testArrivalTwentyFourHourAndWords() {
        XCTAssertEqual(arrival("we reached at 14:30"), "14:30")
        XCTAssertEqual(arrival("we got there at noon"), "12:00")
        XCTAssertEqual(arrival("showed up around midnight"), "00:00")
        XCTAssertEqual(arrival("we arrived at 9 in the morning"), "09:00")
        XCTAssertEqual(arrival("got there at 7 in the evening"), "19:00")
    }

    func testArrivalIgnoresLeavingTimesAndOtherNumbers() {
        XCTAssertEqual(arrival("arrived at 2 pm and left at 4 pm"), "14:00")
        XCTAssertNil(arrival("we left at 5 pm"))
        XCTAssertNil(arrival("open until 6 pm"))
        XCTAssertNil(arrival("room 204 was nice"))
        XCTAssertNil(arrival("we spent 2 hours there"))
        XCTAssertNil(arrival("it was a 5 star experience"))
        XCTAssertNil(arrival("the ticket was 150 rupees"))
        XCTAssertNil(arrival("2:30 hours of queueing"), "a duration is not a clock time")
    }

    // MARK: Time spent

    func testMinutesAndHours() {
        XCTAssertEqual(minutes("we spent 45 minutes there"), 45)
        XCTAssertEqual(minutes("about 30 mins"), 30)
        XCTAssertEqual(minutes("spent 2 hours"), 120)
        XCTAssertEqual(minutes("spent two hours there"), 120)
        XCTAssertEqual(minutes("spent 1.5 hours"), 90)
        XCTAssertEqual(minutes("stayed 2 hours 15 minutes"), 135)
        XCTAssertEqual(minutes("spent forty five minutes"), 45)
        XCTAssertEqual(minutes("spent twenty-five minutes"), 25)
    }

    func testSpokenFractionsOfAnHour() {
        XCTAssertEqual(minutes("spent about an hour"), 60)
        XCTAssertEqual(minutes("spent half an hour"), 30)
        XCTAssertEqual(minutes("half an hour was enough"), 30)
        XCTAssertEqual(minutes("we spent an hour and a half there"), 90)
        XCTAssertEqual(minutes("we spent two hours and a half there"), 150)
        XCTAssertEqual(minutes("spent a quarter of an hour"), 15)
        XCTAssertEqual(minutes("spent three quarters of an hour"), 45)
        XCTAssertEqual(minutes("spent a couple of hours"), 120)
    }

    func testTravelDurationsAreNotTimeSpent() {
        XCTAssertEqual(VoiceTimeParser.duration(in: "walked 20 minutes to get there"), .travelOnly)
        XCTAssertEqual(VoiceTimeParser.duration(in: "it took an hour to reach"), .travelOnly)
        XCTAssertEqual(VoiceTimeParser.duration(in: "the auto ride took 20 minutes"), .travelOnly)
        XCTAssertNil(minutes("walked 20 minutes to get there"))
    }

    func testStayCueBeatsATravelWordNearby() {
        XCTAssertEqual(minutes("we spent an hour there and the auto ride took 20 minutes"), 60)
        XCTAssertEqual(minutes("the auto ride took 20 minutes and we spent an hour"), 60)
    }

    func testNoDuration() {
        XCTAssertEqual(VoiceTimeParser.duration(in: "the food was great"), .none)
        XCTAssertEqual(VoiceTimeParser.duration(in: "it was a 5 star experience"), .none)
        XCTAssertEqual(VoiceTimeParser.duration(in: "room 204"), .none)
    }
}
#endif
