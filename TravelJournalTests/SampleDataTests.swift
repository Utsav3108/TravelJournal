import XCTest
import SwiftData
import ImageIO
@testable import TravelJournal

/// The New York sample is the first thing a new user sees, so it has to show off the whole app: photos, locations
/// and a different way of travelling on every leg.
@MainActor
final class SampleDataTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = AppContainer.make(inMemory: true)
        context = ModelContext(container)
    }

    func testNewYorkHasEightLocatedStopsWithConsistentLegs() throws {
        let j = SampleData.newYork(in: context)
        try context.save()
        let stops = j.orderedStops
        XCTAssertEqual(stops.count, 8)
        XCTAssertTrue(LegSync.isConsistent(stops))
        XCTAssertTrue(stops.allSatisfy { $0.latitude != nil && $0.longitude != nil }, "every stop is on the map")
        XCTAssertEqual(Set(stops.map(\.placeName)).count, 8)
    }

    func testNewYorkUsesAtLeastFiveDifferentTravelModesAndFillsEveryLeg() {
        let legs = SampleData.newYork(in: context).orderedLegs
        XCTAssertEqual(legs.count, 7)
        XCTAssertGreaterThanOrEqual(Set(legs.map(\.mode)).count, 5)
        XCTAssertTrue(legs.allSatisfy { $0.modeWasChosen && $0.distanceKm != nil && $0.durationMinutes != nil })
    }

    func testNewYorkPhotosAreBundledRealImages() throws {
        let j = SampleData.newYork(in: context)
        let stops = j.orderedStops
        XCTAssertTrue(stops.allSatisfy { !$0.photos.isEmpty && $0.photos.count <= PhotoLimits.maxPerStop })
        for photo in stops.flatMap(\.photos) {
            let data = try XCTUnwrap(photo.imageData, "missing bundled photo for \(photo.caption ?? "?")")
            let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            XCTAssertNotNil(CGImageSourceCreateImageAtIndex(src, 0, nil), "undecodable photo \(photo.caption ?? "?")")
            XCTAssertGreaterThan(photo.pixelWidth, 0)
            XCTAssertLessThanOrEqual(max(photo.pixelWidth, photo.pixelHeight), PhotoLimits.displayMaxPixel)
        }
        for s in stops { XCTAssertEqual(s.photos.filter(\.isHero).count, 1) }
    }

    func testNewYorkHasACoverAndAMapStopThatResolve() throws {
        let j = SampleData.newYork(in: context)
        XCTAssertNotNil(j.coverPhoto?.imageData)
        let mapStop = try XCTUnwrap(StoryMapPins.mapStop(for: j))
        XCTAssertEqual(mapStop.id, j.mapStopID)
        XCTAssertEqual(StoryMapPins.pins(for: [j]).count, 1)
    }

    func testNewYorkTextRespectsTheEditorLimits() {
        let j = SampleData.newYork(in: context)
        for s in j.orderedStops {
            XCTAssertLessThanOrEqual(WordLimit.count(s.story), WordLimit.stopStory, s.placeName)
            XCTAssertLessThanOrEqual((s.highlight ?? "").count, EditorLogic.highlightMaxChars, s.placeName)
        }
        for l in j.orderedLegs {
            XCTAssertLessThanOrEqual(WordLimit.count(l.story ?? ""), EditorLogic.legStoryWordLimit)
        }
    }

    func testNewYorkIsReadyForMapsAndTheRouteSheet() {
        let j = SampleData.newYork(in: context)
        let stops = j.orderedStops.enumerated().map { i, s in
            OverviewStop(id: s.id.uuidString, number: i + 1, name: s.placeName, latitude: s.latitude, longitude: s.longitude)
        }
        guard case .ready(let pins) = JourneyMapsLogic.readiness(forStops: stops) else { return XCTFail("expected ready") }
        XCTAssertEqual(pins.count, 8)
    }
}
