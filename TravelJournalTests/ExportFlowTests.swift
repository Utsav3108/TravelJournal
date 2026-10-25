import XCTest
import SwiftData
@testable import TravelJournal

/// Phase 2 export flow: the over-20 carousel decision, stop picker gating, privacy and stamp persistence and result
/// routing, driven with fake renderers.
@MainActor
final class ExportFlowTests: XCTestCase {
    /// Two slices per visible stop, like a heavy journey. Records what it was asked.
    final class FakeRenderer: ExportRenderer {
        var estimated: [ExportOptions] = []
        var rendered: [ExportOptions] = []
        var result: ExportResult
        var error: Error?
        var slicesPerStop = 2

        init(result: ExportResult) { self.result = result }

        func estimateSlices(_ journey: Journey, options: ExportOptions) -> Int {
            estimated.append(options)
            return options.snapshot(for: journey).stops.count * slicesPerStop
        }

        func render(_ journey: Journey, options: ExportOptions, progress: ((Int, Int) -> Void)?) async throws -> ExportResult {
            rendered.append(options)
            progress?(0, 1)
            if let error { throw error }
            return result
        }
    }

    private var dir: URL!
    private var defaults: ExportPrivacyDefaults!
    private var suite: UserDefaults!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ExportFlowTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "ExportFlowTests-\(UUID().uuidString)"
        suite = UserDefaults(suiteName: name)
        defaults = ExportPrivacyDefaults(store: suite)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private struct Rig {
        let fixture: JourneyFixtures.Fixture
        let carousel: FakeRenderer
        let pdf: FakeRenderer
        let model: ExportFlowModel
    }

    private func rig(_ given: JourneyFixtures.Fixture? = nil, panel: Bool = false) -> Rig {
        let fixture = given ?? JourneyFixtures.twelveStops()
        let carousel = FakeRenderer(result: .images([dir.appendingPathComponent("01.jpg")]))
        let pdf = FakeRenderer(result: .pdf(dir.appendingPathComponent("Trip.pdf")))
        pdf.slicesPerStop = 1
        let pipeline = ExportPipeline(renderers: [.carousel: carousel, .pdf: pdf])
        let model = ExportFlowModel(journey: fixture.journey, pipeline: pipeline, defaults: defaults,
                                    presentationDelay: .zero, savesPDFWithPanel: panel)
        return Rig(fixture: fixture, carousel: carousel, pdf: pdf, model: model)
    }

    // MARK: Over-20 decision

    func testCarouselOverTheLimitAsksFirst() {
        let r = rig()
        r.model.present()
        XCTAssertEqual(r.model.step, .options)
        r.model.format = .carousel
        r.model.requestExport()
        XCTAssertEqual(r.model.step, .askingCarousel(slides: 24))
        XCTAssertTrue(r.carousel.rendered.isEmpty)
        XCTAssertTrue(r.pdf.rendered.isEmpty)
    }

    func testYesOpensThePickerWithEveryVisibleStopTicked() {
        let r = rig()
        r.model.present()
        r.model.format = .carousel
        r.model.requestExport()
        r.model.chooseCarouselAnyway()
        XCTAssertEqual(r.model.step, .picking)
        XCTAssertEqual(r.model.pickerSelection.count, 12)
        XCTAssertEqual(r.model.pickerCount, 24)
        XCTAssertFalse(r.model.canPickerExport)
    }

    func testNoExportsTheFullJourneyAsAPDFWithTheNote() async throws {
        let r = rig()
        r.model.present()
        r.model.format = .carousel
        r.model.requestExport()
        r.model.declineCarousel()
        await r.model.waitForExport()

        let asked = try XCTUnwrap(r.pdf.rendered.first)
        XCTAssertEqual(asked.format, .pdf)
        XCTAssertNil(asked.includedStopIDs, "the full journey, nothing dropped")
        XCTAssertTrue(r.carousel.rendered.isEmpty)
        XCTAssertEqual(r.model.note, "A PDF can be shared as a file but not posted as an Instagram carousel.")
        XCTAssertEqual(r.model.step, .pdfReady(dir.appendingPathComponent("Trip.pdf")))
    }

    func testCarouselAtOrUnderTheLimitExportsDirectly() async {
        let r = rig(JourneyFixtures.fourStops())   // 4 stops x 2 = 8 slides
        r.model.present()
        r.model.format = .carousel
        r.model.requestExport()
        await r.model.waitForExport()
        XCTAssertEqual(r.carousel.rendered.count, 1)
        XCTAssertEqual(r.model.step, .slides([dir.appendingPathComponent("01.jpg")]))
    }

    func testThePDFNeverAsks() async {
        let r = rig()   // 12 PDF pages is fine
        r.model.present()
        r.model.format = .pdf
        r.model.requestExport()
        await r.model.waitForExport()
        XCTAssertEqual(r.pdf.rendered.count, 1)
        XCTAssertTrue(r.carousel.estimated.isEmpty)
    }

    // MARK: Picker

    func testPickerGatesAtTwentyAndRecountsLive() async throws {
        let r = rig()
        r.model.present()
        r.model.format = .carousel
        r.model.requestExport()
        r.model.chooseCarouselAnyway()
        let stops = r.model.visibleStops

        r.model.togglePicked(stops[0])
        XCTAssertEqual(r.model.pickerCount, 22)
        XCTAssertFalse(r.model.canPickerExport)
        r.model.exportPicked()
        XCTAssertEqual(r.model.step, .picking, "over 20: Export does nothing")

        r.model.togglePicked(stops[1])
        XCTAssertEqual(r.model.pickerCount, 20)
        XCTAssertTrue(r.model.canPickerExport)

        r.model.togglePicked(stops[1])   // back on: 22
        XCTAssertEqual(r.model.pickerCount, 22)
        XCTAssertFalse(r.model.canPickerExport)
        r.model.togglePicked(stops[1])

        r.model.exportPicked()
        await r.model.waitForExport()
        let asked = try XCTUnwrap(r.carousel.rendered.first)
        XCTAssertEqual(asked.format, .carousel)
        XCTAssertEqual(asked.includedStopIDs, Set(stops.dropFirst(2).map(\.id)))
    }

    func testStopsHiddenByPrivacyDoNotCountTowardTheLimit() async {
        let r = rig()
        r.fixture.stops[0].exportHidden = true
        r.fixture.stops[1].exportHidden = true
        r.model.present()
        r.model.format = .carousel
        r.model.requestExport()   // 10 visible stops = 20 slides: allowed, no question
        await r.model.waitForExport()
        XCTAssertEqual(r.carousel.rendered.count, 1)
    }

    func testPickerHidesPrivacyHiddenStops() {
        let r = rig()
        r.fixture.stops[0].exportHidden = true
        r.model.present()
        r.model.format = .carousel
        r.model.requestExport()
        r.model.chooseCarouselAnyway()
        XCTAssertEqual(r.model.visibleStops.count, 11)
        XCTAssertFalse(r.model.visibleStops.contains { $0.id == r.fixture.stops[0].id })
        XCTAssertFalse(r.model.pickerSelection.contains(r.fixture.stops[0].id))
        XCTAssertEqual(r.model.pickerCount, 22)
    }

    // MARK: Estimates

    func testEstimateGetsTheFormatPrivacyAndStops() throws {
        let r = rig()
        r.model.present()
        r.model.format = .carousel
        r.model.setBrandStamp(false)
        r.model.requestExport()
        let asked = try XCTUnwrap(r.carousel.estimated.first)
        XCTAssertEqual(asked.format, .carousel)
        XCTAssertFalse(asked.privacy.showBrandStamp)
        XCTAssertNil(asked.includedStopIDs)
    }

    // MARK: Privacy persistence

    func testStampToggleCreatesTheJourneyOverrideAndKeepsOtherDefaults() {
        defaults.save(ExportPrivacy(hideStayStops: false, hideCosts: true))
        let r = rig()
        XCTAssertNil(r.fixture.journey.exportPrivacy)
        r.model.setBrandStamp(false)
        let saved = r.fixture.journey.exportPrivacy
        XCTAssertEqual(saved?.showBrandStamp, false)
        XCTAssertEqual(saved?.hideCosts, true, "the override starts from the defaults")
        XCTAssertEqual(saved?.hideStayStops, false)
        XCTAssertEqual(r.model.privacy.showBrandStamp, false)
        r.model.setBrandStamp(true)
        XCTAssertEqual(r.fixture.journey.exportPrivacy?.showBrandStamp, true)
    }

    func testStopToggleIsSavedOnTheStop() {
        let r = rig()
        let stop = r.fixture.stops[3]
        r.model.setStop(stop, shown: false)
        XCTAssertEqual(stop.exportHidden, true)
        XCTAssertEqual(r.model.visibleStops.count, 11)
        r.model.setStop(stop, shown: true)
        XCTAssertEqual(stop.exportHidden, false)
        XCTAssertEqual(r.model.visibleStops.count, 12)
    }

    // MARK: Results and errors

    func testImagesRouteToTheSlidePreview() async {
        let r = rig(JourneyFixtures.fourStops())
        r.model.present()
        r.model.format = .story
        let story = FakeRenderer(result: .images([dir.appendingPathComponent("01.jpg"), dir.appendingPathComponent("02.jpg")]))
        let model = ExportFlowModel(journey: r.fixture.journey, pipeline: ExportPipeline(renderers: [.story: story]),
                                    defaults: defaults, presentationDelay: .zero)
        model.present()
        model.format = .story
        model.requestExport()
        await model.waitForExport()
        XCTAssertEqual(model.step, .slides(story.result.urls))
        XCTAssertEqual(model.format, .story)
    }

    func testPDFWithThePanelWaitsThenOffersTheData() async throws {
        let url = dir.appendingPathComponent("Trip/Trip.pdf")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("%PDF-fake".utf8).write(to: url)
        let r = rig(JourneyFixtures.fourStops(), panel: true)
        r.pdf.result = .pdf(url)
        r.model.present()
        r.model.requestExport()
        await r.model.waitForExport()
        XCTAssertEqual(r.model.step, .pdfSave(data: Data("%PDF-fake".utf8), name: "Trip"))
        r.model.saveFinished(.success(url))
        XCTAssertEqual(r.model.step, .idle)
    }

    func testRendererErrorKeepsItsMessageAndReturnsToTheOptions() async {
        let r = rig(JourneyFixtures.fourStops())
        r.carousel.error = ExportPipelineError.notBuiltYet(.carousel)
        r.model.present()
        r.model.format = .carousel
        r.model.requestExport()
        await r.model.waitForExport()
        XCTAssertEqual(r.model.step, .options)
        XCTAssertEqual(r.model.errorMessage, "Instagram carousel export isn't available yet.")
    }

    func testCancelReturnsToTheOptionsWithoutAnError() async {
        let r = rig(JourneyFixtures.fourStops())
        r.pdf.error = CancellationError()
        r.model.present()
        r.model.requestExport()
        await r.model.waitForExport()
        XCTAssertEqual(r.model.step, .options)
        XCTAssertNil(r.model.errorMessage)
    }

    func testDismissEndsTheFlowOnce() {
        let r = rig()
        var finished = 0
        r.model.onFinish = { finished += 1 }
        r.model.present()
        r.model.dismiss()
        r.model.dismiss()
        XCTAssertEqual(r.model.step, .idle)
        XCTAssertEqual(finished, 1)
    }

    /// The sheet's thumbnail: the cover at each format's aspect, from the same snapshot an export uses.
    func testCoverThumbnailRendersAtEveryFormatsAspect() {
        let f = JourneyFixtures.fourStops()
        for format in ExportFormat.allCases {
            let spec = format.spec
            let snapshot = ExportOptions(format: format, privacy: ExportPrivacy()).snapshot(for: f.journey)
            let page = CoverPage(model: snapshot.coverModel,
                                 metrics: PageMetrics(size: spec.sliceSize, margin: spec.margins.left, mode: spec.mode))
            let image = SliceImageRenderer.thumbnail(page, size: spec.sliceSize, maxPixel: 700)
            XCTAssertNotNil(image, format.displayName)
            if let image {
                XCTAssertEqual(CGFloat(image.width) / CGFloat(image.height), spec.sliceSize.width / spec.sliceSize.height,
                               accuracy: 0.01, format.displayName)
            }
        }
    }

    func testJourneyWithoutStopsCannotStart() {
        let empty = Journey(title: "Empty")
        let model = ExportFlowModel(journey: empty, defaults: defaults)
        model.present()
        XCTAssertEqual(model.step, .idle)
    }
}
