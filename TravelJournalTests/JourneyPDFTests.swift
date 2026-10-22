import XCTest
import SwiftData
import PDFKit
@testable import TravelJournal

@MainActor
final class JourneyPDFTests: XCTestCase {
    var container: ModelContainer!
    var base: URL!
    var snapshots: MapSnapshotService!

    override func setUp() async throws {
        container = AppContainer.make(inMemory: true)
        base = FileManager.default.temporaryDirectory.appendingPathComponent("jpdf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        snapshots = MapSnapshotService(cacheDirectory: base.appendingPathComponent("maps"))
        snapshots.timeout = .seconds(3)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func exporter() -> StoryPDFExporter {
        StoryPDFExporter(snapshots: snapshots, outputDirectory: base.appendingPathComponent("out-\(UUID().uuidString)"))
    }

    private func sampleJourney() throws -> Journey {
        let journey = SampleData.mumbai(in: container.mainContext)
        try container.mainContext.save()
        return journey
    }

    func testRenderGivesTheSamePDFAsTheExporter() async throws {
        let journey = try sampleJourney()
        let pdf = try XCTUnwrap(JourneyPDF(journey))

        let viaTransferable = try await pdf.render(exporter: exporter())
        let direct = try await exporter().export(journey)

        XCTAssertEqual(viaTransferable.lastPathComponent, direct.lastPathComponent)
        XCTAssertEqual(viaTransferable.lastPathComponent, StoryPDFExporter.fileName(forTitle: journey.title))
        let a = try XCTUnwrap(PDFDocument(url: viaTransferable))
        let b = try XCTUnwrap(PDFDocument(url: direct))
        XCTAssertEqual(a.pageCount, b.pageCount)
        XCTAssertEqual(a.pageCount, StoryLayout().pages(for: journey).count)
    }

    func testRenderReportsProgressToTheLastPage() async throws {
        let journey = try sampleJourney()
        let pdf = try XCTUnwrap(JourneyPDF(journey))
        var last: (Int, Int)?
        _ = try await pdf.render(exporter: exporter()) { last = ($0, $1) }
        let done = try XCTUnwrap(last)
        XCTAssertEqual(done.0, done.1)
    }

    func testJourneyWithoutStopsCannotBeRendered() async throws {
        let empty = Journey(title: "Empty")
        container.mainContext.insert(empty)
        try container.mainContext.save()
        let pdf = try XCTUnwrap(JourneyPDF(empty))
        do {
            _ = try await pdf.render(exporter: exporter())
            XCTFail("expected noStops")
        } catch let error as StoryPDFExportError {
            XCTAssertEqual(error.errorDescription, StoryPDFExportError.noStops.errorDescription)
        }
    }

    func testJourneyOutsideAContextHasNoPDF() {
        XCTAssertNil(JourneyPDF(Journey(title: "Loose")))
    }

    #if os(macOS)
    private func waitUntil(_ timeout: Duration = .seconds(30), _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(50)) }
    }

    private func makeCoordinator() -> MacExportCoordinator {
        let c = MacExportCoordinator()
        c.makeExporter = { [self] in exporter() }
        return c
    }

    func testSaveHandsTheSavePanelAPDFNamedAfterTheJourney() async throws {
        let journey = try sampleJourney()
        let c = makeCoordinator()
        c.start(journey, purpose: .save, origin: .shelf)
        XCTAssertTrue(c.isBusy)
        await waitUntil { c.isPresentingSave }

        XCTAssertTrue(c.isPresentingSave)
        XCTAssertEqual(c.documentName, "A Day in Mumbai")
        XCTAssertTrue(try XCTUnwrap(c.document).data.starts(with: Data("%PDF".utf8)))

        c.saveFinished(.success(base))
        XCTAssertFalse(c.isPresentingSave)
        XCTAssertNil(c.document)
        XCTAssertFalse(c.isBusy)
    }

    func testCancellingTheSavePanelIsNotAnError() {
        let c = makeCoordinator()
        c.saveFinished(.failure(CocoaError(.userCancelled)))
        XCTAssertNil(c.errorMessage)
        c.saveFinished(.failure(CocoaError(.fileWriteNoPermission)))
        XCTAssertNotNil(c.errorMessage)
    }

    func testPrintSendsThePDFToThePrintHandler() async throws {
        let journey = try sampleJourney()
        let c = makeCoordinator()
        var printed: (Data, String)?
        c.printHandler = { printed = ($0, $1) }
        c.start(journey, purpose: .print, origin: .journey(journey.id))
        await waitUntil { printed != nil }

        let sent = try XCTUnwrap(printed)
        XCTAssertTrue(sent.0.starts(with: Data("%PDF".utf8)))
        XCTAssertEqual(sent.1, journey.title)
        await waitUntil { !c.isBusy }
        XCTAssertFalse(c.isBusy)
    }

    func testJourneyWithoutStopsDoesNotStartAJob() throws {
        let empty = Journey(title: "Empty")
        container.mainContext.insert(empty)
        try container.mainContext.save()
        let c = makeCoordinator()
        XCTAssertFalse(MacExportCoordinator.canExport(empty))
        c.start(empty, purpose: .save, origin: .shelf)
        XCTAssertFalse(c.isBusy)
        XCTAssertFalse(c.isExporting)
    }

    func testASecondJobIsIgnoredWhileOneRuns() async throws {
        let journey = try sampleJourney()
        let c = makeCoordinator()
        c.start(journey, purpose: .save, origin: .shelf)
        c.start(journey, purpose: .print, origin: .journey(journey.id))
        XCTAssertEqual(c.origin, .shelf)
        await waitUntil { c.isPresentingSave }
        c.saveFinished()
    }
    #endif
}
