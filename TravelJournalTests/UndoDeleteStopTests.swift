import XCTest
import SwiftData
@testable import TravelJournal

/// Spec checklist: "Undo restores a deleted stop with its photos and legs."
///
/// Phase 5a spike result: attaching `ModelContext.undoManager` and deleting a stop (cascade to photos and legs)
/// crashed inside SwiftData (assertion at save, dynamic-cast abort), so undo is explicit, via `JourneyEditor`.
@MainActor
final class UndoDeleteStopTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var undo: UndoManager!
    private var editor: JourneyEditor!
    private var journey: Journey!
    private var stops: [Stop] = []

    override func setUp() async throws {
        container = AppContainer.make(inMemory: true)
        context = container.mainContext
        undo = UndoManager()
        undo.groupsByEvent = false
        editor = JourneyEditor(context: context, photos: NoopPhotoStore(), undoManager: nil)
        journey = Journey(title: "T")
        context.insert(journey)
        stops = ["A", "B", "C"].map { Stop(placeName: $0) }
        for s in stops { editor.addStop(s, to: journey) }
        // Content on both legs of B, and two photos with bytes.
        stops[0].outgoingLeg?.story = "A to B"
        stops[0].outgoingLeg?.distanceKm = 4.5
        stops[1].outgoingLeg?.mode = .taxi
        stops[1].outgoingLeg?.durationMinutes = 20
        stops[1].story = "Middle story"
        for i in 0..<2 {
            let p = StopPhoto(orderIndex: i, isHero: i == 0)
            p.imageData = Data(repeating: UInt8(i + 1), count: 2048)
            context.insert(p)
            p.stop = stops[1]
        }
        try context.save()
        editor = JourneyEditor(context: context, photos: NoopPhotoStore(), undoManager: undo)
    }

    /// One undoable user action: group, run, close.
    private func act(_ body: () -> Void) {
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
    }

    private func assertRestored(file: StaticString = #filePath, line: UInt = #line) throws {
        let restored = journey.orderedStops
        XCTAssertEqual(restored.map(\.placeName), ["A", "B", "C"], file: file, line: line)
        let b = restored[1]
        XCTAssertEqual(b.story, "Middle story", file: file, line: line)
        XCTAssertEqual(b.orderedPhotos.map(\.imageData), [Data(repeating: 1, count: 2048), Data(repeating: 2, count: 2048)],
                       file: file, line: line)
        XCTAssertTrue(b.orderedPhotos[0].isHero, file: file, line: line)
        XCTAssertTrue(LegSync.isConsistent(restored), file: file, line: line)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Leg>()), 2, file: file, line: line)
        XCTAssertEqual(restored[0].outgoingLeg?.story, "A to B", file: file, line: line)
        XCTAssertEqual(restored[0].outgoingLeg?.distanceKm, 4.5, file: file, line: line)
        XCTAssertEqual(restored[1].outgoingLeg?.mode, .taxi, file: file, line: line)
        XCTAssertEqual(restored[1].outgoingLeg?.durationMinutes, 20, file: file, line: line)
    }

    func testUndoRestoresDeletedStopWithPhotosAndLegs() throws {
        act { editor.deleteStop(stops[1], in: journey) }
        try context.save()
        XCTAssertEqual(journey.orderedStops.map(\.placeName), ["A", "C"])
        XCTAssertTrue(undo.canUndo)

        undo.undo()
        try context.save()
        try assertRestored()
    }

    func testRedoDeletesAgainAndUndoRestoresAgain() throws {
        act { editor.deleteStop(stops[1], in: journey) }
        undo.undo()
        XCTAssertTrue(undo.canRedo)
        undo.redo()
        try context.save()
        XCTAssertEqual(journey.orderedStops.map(\.placeName), ["A", "C"])
        XCTAssertTrue(LegSync.isConsistent(journey.orderedStops))

        undo.undo()
        try context.save()
        try assertRestored()
    }

    func testUndoAddStopRemovesItAndRedoPutsItBack() throws {
        act { editor.addStop(Stop(placeName: "New"), to: journey, at: 1) }
        XCTAssertEqual(journey.orderedStops.map(\.placeName), ["A", "New", "B", "C"])
        undo.undo()
        XCTAssertEqual(journey.orderedStops.map(\.placeName), ["A", "B", "C"])
        XCTAssertTrue(LegSync.isConsistent(journey.orderedStops))
        undo.redo()
        XCTAssertEqual(journey.orderedStops.map(\.placeName), ["A", "New", "B", "C"])
        XCTAssertTrue(LegSync.isConsistent(journey.orderedStops))
    }

    func testUndoMoveRestoresOrderAndLegContent() throws {
        // Moving C first drops A>B and B>C, which both carry content.
        act { editor.moveStops(in: journey, from: IndexSet(integer: 2), to: 0) }
        XCTAssertEqual(journey.orderedStops.map(\.placeName), ["C", "A", "B"])
        undo.undo()
        try assertRestored()
        undo.redo()
        XCTAssertEqual(journey.orderedStops.map(\.placeName), ["C", "A", "B"])
        XCTAssertTrue(LegSync.isConsistent(journey.orderedStops))
    }
}

@MainActor
final class EditUndoTrackerTests: XCTestCase {
    private var container: ModelContainer!   // must outlive the models

    private func makeStop() -> (Stop, ModelContext) {
        container = AppContainer.make(inMemory: true)
        let context = container.mainContext
        let stop = Stop(placeName: "Start")
        context.insert(stop)
        return (stop, context)
    }

    func testEditsWithinABurstAreOneUndoStepAndRedoWorks() {
        let (stop, _) = makeStop()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let tracker = EditUndoTracker(initial: StopContent(stop))
        let t0 = Date()

        // `newStep` edits run in their own undo group; burst edits register nothing, so (as with one group per run
        // loop event in the app) they must not leave an empty group behind.
        func edit(_ name: String, at offset: TimeInterval, newStep: Bool) {
            if newStep { undo.beginUndoGrouping() }
            stop.placeName = name
            tracker.observe(StopContent(stop), manager: undo, target: stop, now: t0.addingTimeInterval(offset)) {
                $0.apply(to: stop)
            }
            if newStep { undo.endUndoGrouping() }
        }
        edit("S", at: 0, newStep: true); edit("St", at: 0.2, newStep: false); edit("Sta", at: 0.4, newStep: false)
        edit("Station", at: 3, newStep: true)        // a pause starts a new step

        undo.undo()
        XCTAssertEqual(stop.placeName, "Sta")
        undo.undo()
        XCTAssertEqual(stop.placeName, "Start")
        XCTAssertFalse(undo.canUndo)
        undo.redo()
        XCTAssertEqual(stop.placeName, "Sta")
        undo.redo()
        XCTAssertEqual(stop.placeName, "Station")
    }

    func testApplyingASnapshotIsNotRegisteredAgain() {
        let (stop, _) = makeStop()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let tracker = EditUndoTracker(initial: StopContent(stop))
        undo.beginUndoGrouping()
        stop.story = "one"
        tracker.observe(StopContent(stop), manager: undo, target: stop) { $0.apply(to: stop) }
        undo.endUndoGrouping()
        undo.undo()
        // The view's onChange fires after the undo applied the old snapshot: nothing new may be registered.
        tracker.observe(StopContent(stop), manager: undo, target: stop) { $0.apply(to: stop) }
        XCTAssertFalse(undo.canUndo)
        XCTAssertTrue(undo.canRedo)
    }

    func testContentSnapshotsRoundTrip() {
        let (stop, context) = makeStop()
        let leg = Leg()
        context.insert(leg)
        leg.mode = .localTrain
        leg.distanceKm = 3
        stop.story = "s"; stop.ratingRaw = 4; stop.costAmount = 12; stop.costCurrency = "INR"
        let sc = StopContent(stop), lc = LegContent(leg)
        stop.story = ""; stop.ratingRaw = nil; stop.costAmount = nil
        leg.mode = .walk; leg.distanceKm = nil
        sc.apply(to: stop); lc.apply(to: leg)
        XCTAssertEqual(StopContent(stop), sc)
        XCTAssertEqual(LegContent(leg), lc)
        XCTAssertEqual(leg.mode, .localTrain)
    }
}
