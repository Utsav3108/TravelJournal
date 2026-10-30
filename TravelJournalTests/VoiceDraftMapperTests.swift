#if os(macOS)
import XCTest
@testable import TravelJournal

final class VoiceDraftMapperTests: XCTestCase {
    private func output(hasPlace: Bool = false, place: String = "", hasCost: Bool = false, cost: Double = 0,
                        hasRating: Bool = false, rating: Int = 1, hasStory: Bool = false, story: String = "",
                        highlight: String = "", hasMode: Bool = false, mode: VoiceStopDraft.TravelMode = .walk,
                        hasMinutes: Bool = false, minutes: Int = 0, hasCategory: Bool = false,
                        category: VoiceStopDraft.Category = .other) -> VoiceModelOutput {
        VoiceModelOutput(hasPlace: hasPlace, placeName: place, hasCategory: hasCategory, category: category,
                         hasArrival: false, arrival: "", hasStory: hasStory, story: story, highlight: highlight,
                         hasRating: hasRating, rating: rating, hasCost: hasCost, cost: cost, hasMinutes: hasMinutes,
                         minutesSpent: minutes, hasTravelMode: hasMode, travelMode: mode)
    }

    func testFalseFlagsGiveNilNotDefaults() {
        let d = VoiceDraftMapper.draft(from: output(), transcript: "hello testing")
        XCTAssertEqual(d, VoiceStopDraft())
    }

    func testFlaggedValuesArePassedThrough() {
        let out = output(hasPlace: true, place: "Juhu Beach", hasCost: true, cost: 90, hasRating: true, rating: 4,
                         hasMode: true, mode: .taxi, hasMinutes: true, minutes: 120)
        let d = VoiceDraftMapper.draft(from: out, transcript: "juhu beach took a cab 90 rupees 2 hours four stars")
        XCTAssertEqual(d.placeName, "Juhu Beach")
        XCTAssertEqual(d.cost, 90)
        XCTAssertEqual(d.rating, 4)
        XCTAssertEqual(d.travelMode, .taxi)
        XCTAssertEqual(d.minutesSpent, 120)
    }

    func testFreeIsKeptAsZero() {
        let d = VoiceDraftMapper.draft(from: output(hasCost: true, cost: 0), transcript: "the museum ticket was free")
        XCTAssertEqual(d.cost, 0)
    }

    func testKeywordGateDropsCostOnAStarExperience() {
        let d = VoiceDraftMapper.draft(from: output(hasCost: true, cost: 5), transcript: "a 5 star experience")
        XCTAssertNil(d.cost)
    }

    func testKeywordGateDropsTravelModeThatWasNeverMentioned() {
        let d = VoiceDraftMapper.draft(from: output(hasMode: true, mode: .walk), transcript: "loved the sunset")
        XCTAssertNil(d.travelMode)
    }

    func testNullAndBlankStringsAreCleaned() {
        XCTAssertNil(VoiceDraftMapper.clean("null"))
        XCTAssertNil(VoiceDraftMapper.clean("  NULL "))
        XCTAssertNil(VoiceDraftMapper.clean(""))
        XCTAssertEqual(VoiceDraftMapper.clean(" Chai "), "Chai")
    }

    func testStoryAndHighlightNeedTheStoryFlag() {
        let d = VoiceDraftMapper.draft(from: output(story: "Nice.", highlight: "Nice"), transcript: "nice")
        XCTAssertNil(d.story)
        XCTAssertNil(d.highlight)
        let on = VoiceDraftMapper.draft(from: output(hasStory: true, story: "Nice.", highlight: "null"), transcript: "nice")
        XCTAssertEqual(on.story, "Nice.")
        XCTAssertNil(on.highlight)
    }

    func testRulesFillArrivalAndMinutesTheModelMissed() {
        let d = VoiceDraftMapper.draft(from: output(), transcript: "i arrived at 2 pm and spent about half an hour")
        XCTAssertEqual(d.arrival, "14:00")
        XCTAssertEqual(d.minutesSpent, 30)
    }

    func testRulesOverrideAWrongModelDuration() {
        let out = output(hasMinutes: true, minutes: 60)
        let d = VoiceDraftMapper.draft(from: out, transcript: "we spent an hour and a half there")
        XCTAssertEqual(d.minutesSpent, 90)
    }

    func testTravelOnlyDurationDropsTheModelsMinutes() {
        let out = output(hasMinutes: true, minutes: 20)
        let d = VoiceDraftMapper.draft(from: out, transcript: "walked 20 minutes to get there")
        XCTAssertNil(d.minutesSpent)
    }

    func testModelResultStandsWhenRulesFindNothing() {
        let out = output(hasMinutes: true, minutes: 40)
        let d = VoiceDraftMapper.draft(from: out, transcript: "we hung around for 40 mins")
        XCTAssertEqual(d.minutesSpent, 40)
    }

    func testGenericOrNumericPlaceNamesAreRejected() {
        for bad in ["place", "The Temple", "6pm", "rs", "room", "  "] {
            XCTAssertFalse(VoiceDraftMapper.isPlausiblePlace(bad), bad)
        }
        XCTAssertTrue(VoiceDraftMapper.isPlausiblePlace("Hawa Mahal"))
    }
}
#endif
