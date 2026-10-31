#if os(macOS)
import XCTest
import SwiftData
@testable import TravelJournal

@MainActor
private final class FakeCapture: SpeechCapturing {
    var partials: [String] = []
    var finalText = ""
    var startError: VoiceError?
    private(set) var cancelCount = 0

    func start() async throws -> AsyncStream<String> {
        if let startError { throw startError }
        let parts = partials
        return AsyncStream { c in parts.forEach { c.yield($0) }; c.finish() }
    }
    func finish() async throws -> String { finalText }
    func cancel() { cancelCount += 1 }
}

private struct FakeExtractor: DraftExtracting {
    var draft = VoiceStopDraft()
    var fails = false
    func extract(from transcript: String) async throws -> VoiceStopDraft {
        if fails { throw VoiceError.extractionFailed }
        return draft
    }
}

@MainActor
final class VoiceDictationControllerTests: XCTestCase {
    private var container: ModelContainer!
    private var journey: Journey!
    private var stop: Stop!

    override func setUp() async throws {
        container = AppContainer.make(inMemory: true)
        let context = container.mainContext
        journey = Journey(title: "J")
        context.insert(journey)
        let editor = JourneyEditor(context: context, photos: NoopPhotoStore())
        editor.addStop(Stop(placeName: "A"), to: journey)
        editor.addStop(Stop(placeName: "B"), to: journey)
        stop = journey.orderedStops[1]
    }

    private func controller(_ capture: FakeCapture, _ extractor: FakeExtractor, available: Bool = true) -> VoiceDictationController {
        VoiceDictationController(capture: capture, extractor: extractor, isAvailable: available,
                                 revealInterval: .zero, freshDuration: .zero)
    }

    /// Waits for a phase the controller reaches asynchronously.
    private func wait(for c: VoiceDictationController, until done: (VoiceDictationController.Phase) -> Bool) async {
        for _ in 0..<200 where !done(c.phase) { try? await Task.sleep(for: .milliseconds(5)) }
    }

    private func dictate(_ c: VoiceDictationController) async {
        c.begin(on: stop, journey: journey)
        c.end()
        await wait(for: c) { !$0.isActive }
    }

    func testFillsTheStopAndReportsTheFields() async {
        let capture = FakeCapture()
        capture.finalText = "four stars it was 200 rupees"
        let c = controller(capture, FakeExtractor(draft: VoiceStopDraft(rating: 4, cost: 200)))
        await dictate(c)
        XCTAssertEqual(c.phase, .filled([.rating, .cost]))
        XCTAssertEqual(stop.rating, 4)
        XCTAssertEqual(stop.costAmount, 200)
        XCTAssertEqual(c.transcript, "four stars it was 200 rupees")
    }

    func testPartialTranscriptStreamsWhileListening() async {
        let capture = FakeCapture()
        capture.partials = ["four", "four stars"]
        let c = controller(capture, FakeExtractor())
        c.begin(on: stop, journey: journey)
        await wait(for: c) { _ in c.transcript == "four stars" }
        XCTAssertEqual(c.transcript, "four stars")
        XCTAssertEqual(c.phase, .listening)
    }

    func testSecondBeginIsIgnoredWhileListening() {
        let capture = FakeCapture()
        let c = controller(capture, FakeExtractor())
        c.begin(on: stop, journey: journey)
        c.begin(on: journey.orderedStops[0], journey: journey)
        c.end()
        XCTAssertEqual(c.phase, .processing)
        c.begin(on: journey.orderedStops[0], journey: journey)
        XCTAssertEqual(c.phase, .processing, "still busy, so ignored")
    }

    func testUnavailableDeviceNeverListens() {
        let c = controller(FakeCapture(), FakeExtractor(), available: false)
        c.begin(on: stop, journey: journey)
        XCTAssertEqual(c.phase, .idle)
    }

    func testEmptyTranscriptIsNoSpeech() async {
        let capture = FakeCapture()
        capture.finalText = "   "
        let c = controller(capture, FakeExtractor())
        await dictate(c)
        XCTAssertEqual(c.phase, .failed(.noSpeech))
    }

    func testNothingExtractedIsReported() async {
        let capture = FakeCapture()
        capture.finalText = "hello testing"
        let c = controller(capture, FakeExtractor())
        await dictate(c)
        XCTAssertEqual(c.phase, .failed(.nothingToFill))
        XCTAssertNil(stop.rating)
    }

    func testExtractorFailureIsReported() async {
        let capture = FakeCapture()
        capture.finalText = "something"
        let c = controller(capture, FakeExtractor(fails: true))
        await dictate(c)
        XCTAssertEqual(c.phase, .failed(.extractionFailed))
    }

    func testDeniedMicrophoneFailsImmediatelyAndCancelsCapture() async {
        let capture = FakeCapture()
        capture.startError = .microphoneDenied
        let c = controller(capture, FakeExtractor())
        c.begin(on: stop, journey: journey)
        await wait(for: c) { !$0.isActive }
        XCTAssertEqual(c.phase, .failed(.microphoneDenied))
        XCTAssertEqual(capture.cancelCount, 1)
        c.end()   // releasing the button afterwards changes nothing
        XCTAssertEqual(c.phase, .failed(.microphoneDenied))
    }

    func testUndoRestoresStopAndIncomingLeg() async {
        stop.rating = 2
        let leg = stop.incomingLeg!
        let before = LegContent(leg)
        let capture = FakeCapture()
        capture.finalText = "took a taxi, five stars"
        let c = controller(capture, FakeExtractor(draft: VoiceStopDraft(rating: 5, travelMode: .taxi)))
        await dictate(c)
        XCTAssertEqual(stop.rating, 5)
        XCTAssertEqual(leg.mode, .taxi)

        c.undo()
        XCTAssertEqual(c.phase, .idle)
        XCTAssertEqual(stop.rating, 2)
        XCTAssertEqual(LegContent(leg), before)
    }

    func testDismissClearsTheSummaryButKeepsTheValues() async {
        let capture = FakeCapture()
        capture.finalText = "five stars"
        let c = controller(capture, FakeExtractor(draft: VoiceStopDraft(rating: 5)))
        await dictate(c)
        c.dismiss()
        XCTAssertEqual(c.phase, .idle)
        XCTAssertEqual(stop.rating, 5)
    }

    func testHighlightsRevealThenClear() async {
        let capture = FakeCapture()
        capture.finalText = "five stars 100 rupees"
        let c = controller(capture, FakeExtractor(draft: VoiceStopDraft(rating: 5, cost: 100)))
        await dictate(c)
        await wait(for: c) { _ in c.freshFields.isEmpty }
        XCTAssertTrue(c.freshFields.isEmpty)
    }

    func testSelectionIsLockedWhileListeningAndProcessing() {
        let model = JourneyWindowModel()
        model.rebuild(from: journey)
        let ids = journey.orderedStops.map { $0.id.uuidString }
        model.select(ids[0], center: false)
        let c = controller(FakeCapture(), FakeExtractor())
        model.voice = c

        c.begin(on: journey.orderedStops[0], journey: journey)
        model.select(ids[1], center: false)
        XCTAssertEqual(model.selectedStopID, ids[0], "locked while listening")
        model.selectLeg("leg-x")
        XCTAssertNil(model.selectedLegID)
        model.showJourneyDetails()
        XCTAssertEqual(model.selectedStopID, ids[0])

        c.end()
        model.select(ids[1], center: false)
        XCTAssertEqual(model.selectedStopID, ids[0], "locked while processing")
    }

    func testSelectingAnotherStopClearsTheFilledSummary() async {
        let model = JourneyWindowModel()
        model.rebuild(from: journey)
        let ids = journey.orderedStops.map { $0.id.uuidString }
        let capture = FakeCapture()
        capture.finalText = "five stars"
        let c = controller(capture, FakeExtractor(draft: VoiceStopDraft(rating: 5)))
        model.voice = c
        model.select(ids[1], center: false)
        await dictate(c)
        XCTAssertEqual(c.phase, .filled([.rating]))

        model.select(ids[0], center: false)
        XCTAssertEqual(c.phase, .idle)
        XCTAssertEqual(model.selectedStopID, ids[0])
    }
}

private extension VoiceDictationController.Phase {
    var isActive: Bool { self == .listening || self == .processing }
}
#endif
