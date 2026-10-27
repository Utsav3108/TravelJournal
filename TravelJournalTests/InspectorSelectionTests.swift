#if os(macOS)
import XCTest
import SwiftData
@testable import TravelJournal

@MainActor
final class InspectorSelectionTests: XCTestCase {
    private var container: ModelContainer!

    private func makeJourney() -> Journey {
        container = AppContainer.make(inMemory: true)
        let context = container.mainContext
        let journey = Journey(title: "J")
        context.insert(journey)
        let editor = JourneyEditor(context: context, photos: NoopPhotoStore())
        for n in ["A", "B", "C"] { editor.addStop(Stop(placeName: n), to: journey) }
        return journey
    }

    func testInspectorTargetFollowsSelection() {
        let model = JourneyWindowModel()
        XCTAssertEqual(model.inspectorTarget, .journey)
        model.select("stop-1", center: false)
        XCTAssertEqual(model.inspectorTarget, .stop("stop-1"))
        model.selectLeg("leg-9")
        XCTAssertEqual(model.inspectorTarget, .leg("leg-9"))
        XCTAssertNil(model.selectedStopID, "a leg and a stop are never both selected")
        model.select("stop-2", center: false)
        XCTAssertEqual(model.inspectorTarget, .stop("stop-2"))
        XCTAssertNil(model.selectedLegID)
    }

    func testShowJourneyDetailsClearsSelectionAndOpensInspector() {
        let model = JourneyWindowModel()
        model.select("stop-1", center: false)
        model.showJourneyDetails()
        XCTAssertEqual(model.inspectorTarget, .journey)
        XCTAssertTrue(model.inspectorShown)
    }

    func testSignatureChangesWithAnyEditTheStripShows() {
        let journey = makeJourney()
        let base = JourneyWindowModel.signature(of: journey)
        XCTAssertEqual(JourneyWindowModel.signature(of: journey), base)

        let stops = journey.orderedStops
        stops[1].story = "new words"
        let afterStory = JourneyWindowModel.signature(of: journey)
        XCTAssertNotEqual(afterStory, base)

        stops[0].outgoingLeg?.durationMinutes = 15
        let afterLeg = JourneyWindowModel.signature(of: journey)
        XCTAssertNotEqual(afterLeg, afterStory)

        journey.introNote = "hello"
        XCTAssertNotEqual(JourneyWindowModel.signature(of: journey), afterLeg)
    }

    func testInsertionIndexGoesAfterSelectionElseEnd() {
        let ids = ["a", "b", "c"]
        XCTAssertEqual(JourneyWindowModel.insertionIndex(selectedStopID: nil, stopIDs: ids), 3)
        XCTAssertEqual(JourneyWindowModel.insertionIndex(selectedStopID: "a", stopIDs: ids), 1)
        XCTAssertEqual(JourneyWindowModel.insertionIndex(selectedStopID: "c", stopIDs: ids), 3)
        XCTAssertEqual(JourneyWindowModel.insertionIndex(selectedStopID: "gone", stopIDs: ids), 3)
        XCTAssertEqual(JourneyWindowModel.insertionIndex(selectedStopID: nil, stopIDs: []), 0)
    }

    func testAddingAtInsertionIndexPlacesStopAfterSelection() {
        let journey = makeJourney()
        let stops = journey.orderedStops
        let index = JourneyWindowModel.insertionIndex(selectedStopID: stops[0].id.uuidString,
                                                      stopIDs: stops.map { $0.id.uuidString })
        JourneyEditor(context: container.mainContext, photos: NoopPhotoStore())
            .addStop(Stop(placeName: "New"), to: journey, at: index)
        XCTAssertEqual(journey.orderedStops.map(\.placeName), ["A", "New", "B", "C"])
    }
}
#endif
