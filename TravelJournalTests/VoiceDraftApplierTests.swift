#if os(macOS)
import XCTest
import SwiftData
@testable import TravelJournal

@MainActor
final class VoiceDraftApplierTests: XCTestCase {
    private let zone = TimeZone(identifier: "Asia/Kolkata")!
    private let base = Date(timeIntervalSince1970: 1_760_000_000)

    private func changes(_ draft: VoiceStopDraft, stop: Stop, leg: Leg? = nil) -> [VoiceChange] {
        VoiceDraftApplier.changes(for: draft, current: StopContent(stop), incomingLeg: leg.map(LegContent.init),
                                  arrivalBase: base, timeZone: zone)
    }

    private func filledStop() -> Stop {
        let s = Stop(placeName: "Hawa Mahal", story: "Pink sandstone.")
        return s
    }

    func testEmptyDraftChangesNothing() {
        XCTAssertTrue(changes(VoiceStopDraft(), stop: Stop(placeName: "")).isEmpty)
    }

    func testNewStopFillsPlaceCategoryAndArrival() {
        let draft = VoiceStopDraft(placeName: " Marine Drive ", category: .nature, arrival: "18:05")
        let c = changes(draft, stop: Stop(placeName: ""))
        XCTAssertEqual(c.map(\.field), [.place, .category, .arrived])
        XCTAssertEqual(c.first, .place("Marine Drive"))
    }

    func testExistingStopKeepsItsPlaceButTakesArrivalAndMissingCategory() {
        let draft = VoiceStopDraft(placeName: "Elsewhere", category: .food, arrival: "09:00", rating: 4)
        XCTAssertEqual(changes(draft, stop: filledStop()).map(\.field), [.category, .arrived, .rating])
    }

    func testExistingCategoryIsNotOverwritten() {
        let stop = filledStop()
        stop.category = .temple
        XCTAssertTrue(changes(VoiceStopDraft(category: .food), stop: stop).isEmpty)
    }

    func testArrivalCorrectsAnExistingArrivalOnItsOwnDay() throws {
        let stop = filledStop()
        stop.arrivalTime = try XCTUnwrap(VoiceDraftApplier.arrival("08:30", on: base, in: zone))
        let c = changes(VoiceStopDraft(arrival: "14:00"), stop: stop)
        XCTAssertEqual(c, [.arrived(try XCTUnwrap(VoiceDraftApplier.arrival("14:00", on: base, in: zone)))])
    }

    func testArrivalAcceptsTwelveHourAnswersFromTheModel() throws {
        let want = try XCTUnwrap(VoiceDraftApplier.arrival("14:00", on: base, in: zone))
        for said in ["2 pm", "2:00 PM", "2 p.m.", "14:00"] {
            XCTAssertEqual(VoiceDraftApplier.arrival(said, on: base, in: zone), want, said)
        }
    }

    func testArrivalIsAppliedInJourneyTimeZone() throws {
        let d = try XCTUnwrap(VoiceDraftApplier.arrival("14:30", on: base, in: zone))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        XCTAssertEqual(cal.component(.hour, from: d), 14)
        XCTAssertEqual(cal.component(.minute, from: d), 30)
    }

    func testInvalidArrivalIsIgnored() {
        for bad in ["25:00", "9", "12:75", "noon", ""] {
            XCTAssertNil(VoiceDraftApplier.arrival(bad, on: base, in: zone), bad)
        }
    }

    func testRatingAndMinutesAreClamped() {
        let c = changes(VoiceStopDraft(rating: 9, minutesSpent: 5000), stop: filledStop())
        XCTAssertEqual(c, [.timeSpent(1440), .rating(5)])
    }

    func testUnchangedValuesProduceNoChange() {
        let s = filledStop()
        s.rating = 4
        s.timeSpentMinutes = 30
        XCTAssertTrue(changes(VoiceStopDraft(rating: 4, minutesSpent: 30), stop: s).isEmpty)
    }

    func testStoryIsAppendedToExistingStory() {
        let c = changes(VoiceStopDraft(story: "Crowded at noon."), stop: filledStop())
        XCTAssertEqual(c, [.story("Pink sandstone. Crowded at noon.")])
    }

    func testStoryIsCappedAtTheWordLimit() throws {
        let long = Array(repeating: "word", count: 150).joined(separator: " ")
        let c = changes(VoiceStopDraft(story: long), stop: Stop(placeName: "X"))
        guard case .story(let text)? = c.first else { return XCTFail("expected a story change") }
        XCTAssertEqual(WordLimit.count(text), WordLimit.stopStory)
    }

    func testFullStoryAcceptsNoMoreText() {
        let full = Array(repeating: "word", count: WordLimit.stopStory).joined(separator: " ")
        let s = Stop(placeName: "X", story: full)
        XCTAssertTrue(changes(VoiceStopDraft(story: "even more"), stop: s).isEmpty)
    }

    func testHighlightIsCut() {
        let c = changes(VoiceStopDraft(highlight: String(repeating: "a", count: 90)), stop: filledStop())
        XCTAssertEqual(c, [.highlight(String(repeating: "a", count: EditorLogic.highlightMaxChars))])
    }

    func testBlankStringsAreIgnored() {
        XCTAssertTrue(changes(VoiceStopDraft(placeName: "  ", story: " ", highlight: ""), stop: Stop(placeName: "")).isEmpty)
    }

    func testFreeCostIsZeroNotMissing() {
        XCTAssertEqual(changes(VoiceStopDraft(cost: 0), stop: filledStop()), [.cost(0)])
    }

    func testNegativeCostIsIgnored() {
        XCTAssertTrue(changes(VoiceStopDraft(cost: -5), stop: filledStop()).isEmpty)
    }

    func testTravelModeNeedsAnIncomingLeg() {
        let draft = VoiceStopDraft(travelMode: .autoRickshaw)
        XCTAssertTrue(changes(draft, stop: filledStop(), leg: nil).isEmpty, "first stop has no 'got here by'")
        XCTAssertEqual(changes(draft, stop: filledStop(), leg: Leg()), [.travelMode(.autoRickshaw)])
    }

    func testTravelModeAlreadyChosenIsNotRepeated() {
        let leg = Leg()
        leg.mode = .metro
        XCTAssertTrue(changes(VoiceStopDraft(travelMode: .metro), stop: filledStop(), leg: leg).isEmpty)
        XCTAssertEqual(changes(VoiceStopDraft(travelMode: .bus), stop: filledStop(), leg: leg), [.travelMode(.bus)])
    }

    func testChangesComeInChipOrder() {
        let draft = VoiceStopDraft(placeName: "Cafe", category: .food, arrival: "10:00", story: "Great chai.",
                                   highlight: "Chai", rating: 5, cost: 120, minutesSpent: 45, travelMode: .walk)
        let c = changes(draft, stop: Stop(placeName: ""), leg: Leg())
        XCTAssertEqual(c.map(\.field), VoiceField.allCases)
    }

    func testApplyWritesTheStopAndLeg() {
        let stop = Stop(placeName: "")
        let leg = Leg()
        stop.incomingLeg = leg
        let draft = VoiceStopDraft(placeName: "Cafe", category: .food, story: "Great chai.", highlight: "Chai",
                                   rating: 5, cost: 120.5, minutesSpent: 45, travelMode: .taxi)
        for change in changes(draft, stop: stop, leg: leg) { VoiceDraftApplier.apply(change, to: stop) }
        XCTAssertEqual(stop.placeName, "Cafe")
        XCTAssertEqual(stop.category, .food)
        XCTAssertEqual(stop.story, "Great chai.")
        XCTAssertEqual(stop.highlight, "Chai")
        XCTAssertEqual(stop.rating, 5)
        XCTAssertEqual(stop.timeSpentMinutes, 45)
        XCTAssertEqual(stop.cost, Cost(amount: Decimal(string: "120.5")!, currency: EditorLogic.defaultCurrency))
        XCTAssertEqual(leg.mode, .taxi)
        XCTAssertTrue(leg.modeWasChosen)
    }

    func testApplyKeepsAnExistingCurrency() {
        let stop = filledStop()
        stop.costCurrency = "USD"
        VoiceDraftApplier.apply(.cost(10), to: stop)
        XCTAssertEqual(stop.costCurrency, "USD")
    }
}
#endif
