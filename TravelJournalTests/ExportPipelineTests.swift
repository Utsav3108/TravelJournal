import XCTest
import SwiftUI
import SwiftData
import PDFKit
import ImageIO
import UniformTypeIdentifiers
@testable import TravelJournal

/// Wave 1 export foundation: spec values, stop selection, pipeline dispatch, slice rendering, privacy decoding,
/// fixtures and the test helpers themselves.
@MainActor
final class ExportPipelineTests: XCTestCase {
    private let showAll = ExportPrivacy(hideStayStops: false)

    // MARK: Specs

    func testA4SpecUnchanged() {
        let a4 = OutputSpec.a4PDF
        XCTAssertEqual(a4.sliceSize, CGSize(width: 595, height: 842))
        XCTAssertEqual(a4.flow, .vertical)
        XCTAssertEqual(a4.margins, .uniform(36))
        XCTAssertEqual(a4.renderScale, 1)
        XCTAssertEqual(a4.safeInsets, .none)
        XCTAssertNil(a4.maxSlices)
        XCTAssertNil(a4.gridCropWidth)
        XCTAssertNil(a4.gridCropRect)
        XCTAssertEqual(a4.safeContentRect, a4.contentRect)
    }

    func testCarouselSpec() throws {
        let c = OutputSpec.carousel
        XCTAssertEqual(c.sliceSize, CGSize(width: 540, height: 675))
        XCTAssertEqual(c.flow, .horizontal)
        XCTAssertEqual(c.renderScale, 2)
        XCTAssertEqual(c.pixelSize, CGSize(width: 1080, height: 1350))
        XCTAssertEqual(c.maxSlices, 20)
        XCTAssertEqual(c.safeInsets, .none)
        XCTAssertEqual(try XCTUnwrap(c.gridCropWidth), 506.25, accuracy: 0.001)
        let crop = try XCTUnwrap(c.gridCropRect)
        XCTAssertEqual(crop.midX, 270, accuracy: 0.001)
        XCTAssertEqual(crop.height, 675)
        XCTAssertEqual(crop.width / crop.height, 3.0 / 4.0, accuracy: 0.0001)
    }

    func testStorySpec() {
        let s = OutputSpec.story
        XCTAssertEqual(s.sliceSize, CGSize(width: 360, height: 640))
        XCTAssertEqual(s.flow, .vertical)
        XCTAssertEqual(s.renderScale, 3)
        XCTAssertEqual(s.pixelSize, CGSize(width: 1080, height: 1920))
        XCTAssertEqual(s.safeInsets.top, 89.6, accuracy: 0.001)
        XCTAssertEqual(s.safeInsets.bottom, 128, accuracy: 0.001)
        XCTAssertNil(s.maxSlices)
        XCTAssertNil(s.gridCropWidth)
        XCTAssertEqual(s.safeContentRect.minY, 89.6, accuracy: 0.001)
        XCTAssertEqual(s.safeContentRect.maxY, 512, accuracy: 0.001)
        XCTAssertEqual(ExportFormat.story.spec, .story)
        XCTAssertEqual(ExportFormat.carousel.spec, .carousel)
        XCTAssertEqual(ExportFormat.pdf.spec, .a4PDF)
    }

    // MARK: Stop selection

    func testIncludedStopIDsRemovesStopsAndMergesLegs() {
        let s = JourneyFixtures.eightStops().snapshot
        let keep: Set<UUID> = [s.stops[1].id, s.stops[4].id, s.stops[7].id]
        let out = ExportOptions(format: .carousel, privacy: showAll, includedStopIDs: keep).apply(to: s)

        XCTAssertEqual(out.stops.map(\.id), [s.stops[1].id, s.stops[4].id, s.stops[7].id])
        XCTAssertEqual(out.legs.count, 2)
        XCTAssertEqual(out.legs[0], PrivacyFilter.mergedLeg(Array(s.legs[1...3]), from: s.stops[1].id, to: s.stops[4].id))
        XCTAssertEqual(out.legs[1], PrivacyFilter.mergedLeg(Array(s.legs[4...6]), from: s.stops[4].id, to: s.stops[7].id))
        XCTAssertEqual(out.legs[0].km ?? -1, s.legs[1...3].compactMap(\.km).reduce(0, +), accuracy: 0.001)
        XCTAssertNil(out.legs[0].story)
        XCTAssertEqual(out.totals, JourneySnapshot.Totals(stops: out.stops, legs: out.legs))
        // The cover was stop 1's hero: it falls back to the first kept hero.
        XCTAssertEqual(s.coverPhotoID, s.stops[0].photos.first?.id)
        XCTAssertEqual(out.coverPhotoID, out.stops.compactMap(\.hero).first?.id)
    }

    func testIncludedStopIDsNilKeepsEverythingAndPrivacyStillApplies() {
        let s = JourneyFixtures.eightStops().snapshot
        XCTAssertEqual(s.including(stopIDs: nil), s)
        // Default privacy hides the hotel even when the selection lists it.
        let all = Set(s.stops.map(\.id))
        let out = ExportOptions(format: .pdf, privacy: ExportPrivacy(), includedStopIDs: all).apply(to: s)
        XCTAssertEqual(out, PrivacyFilter.apply(s, ExportPrivacy()))
        XCTAssertFalse(out.stops.contains { $0.category == .stay })
    }

    // MARK: Pipeline

    private final class FakeRenderer: ExportRenderer {
        let slices: Int
        let result: ExportResult
        var rendered: [ExportOptions] = []
        init(slices: Int, result: ExportResult) { self.slices = slices; self.result = result }
        func estimateSlices(_ journey: Journey, options: ExportOptions) -> Int { slices }
        func render(_ journey: Journey, options: ExportOptions, progress: ((Int, Int) -> Void)?) async throws -> ExportResult {
            rendered.append(options)
            progress?(slices, slices)
            return result
        }
    }

    func testPipelineDispatchesByFormat() async throws {
        let f = JourneyFixtures.oneStop()
        let pdf = FakeRenderer(slices: 4, result: .pdf(URL(fileURLWithPath: "/tmp/a.pdf")))
        let carousel = FakeRenderer(slices: 7, result: .images([URL(fileURLWithPath: "/tmp/01.jpg")]))
        let story = FakeRenderer(slices: 3, result: .images([]))
        let pipeline = ExportPipeline(renderers: [.pdf: pdf, .carousel: carousel, .story: story])

        XCTAssertEqual(pipeline.estimateSlices(f.journey, options: ExportOptions(format: .pdf, privacy: showAll)), 4)
        XCTAssertEqual(pipeline.estimateSlices(f.journey, options: ExportOptions(format: .carousel, privacy: showAll)), 7)
        XCTAssertEqual(pipeline.estimateSlices(f.journey, options: ExportOptions(format: .story, privacy: showAll)), 3)

        let options = ExportOptions(format: .carousel, privacy: showAll, includedStopIDs: [f.stops[0].id])
        var progress: [(Int, Int)] = []
        let result = try await pipeline.render(f.journey, options: options) { progress.append(($0, $1)) }
        XCTAssertEqual(result, .images([URL(fileURLWithPath: "/tmp/01.jpg")]))
        XCTAssertEqual(carousel.rendered, [options])
        XCTAssertTrue(pdf.rendered.isEmpty)
        XCTAssertTrue(story.rendered.isEmpty)
        XCTAssertEqual(progress.count, 1)
        XCTAssertEqual(result.urls.count, 1)
    }

    func testDefaultPipelineHasRealRenderersForEveryFormat() {
        let f = JourneyFixtures.oneStop()
        let pipeline = ExportPipeline()
        XCTAssertTrue(pipeline.renderer(for: .pdf) is PDFExportRenderer)
        XCTAssertTrue(pipeline.renderer(for: .carousel) is CarouselRenderer)
        XCTAssertTrue(pipeline.renderer(for: .story) is StoryRenderer)
        for format in ExportFormat.allCases {
            let options = ExportOptions(format: format, privacy: showAll)
            XCTAssertGreaterThan(pipeline.estimateSlices(f.journey, options: options), 0, "\(format)")
        }
    }

    func testUnbuiltRendererThrowsAClearError() async {
        let f = JourneyFixtures.oneStop()
        let pipeline = ExportPipeline(renderers: [.carousel: UnbuiltExportRenderer(format: .carousel)])
        let options = ExportOptions(format: .carousel, privacy: showAll)
        XCTAssertEqual(pipeline.estimateSlices(f.journey, options: options), 0)
        do {
            _ = try await pipeline.render(f.journey, options: options)
            XCTFail("an unbuilt renderer should throw")
        } catch {
            XCTAssertEqual(error as? ExportPipelineError, .notBuiltYet(.carousel))
            XCTAssertTrue(error.localizedDescription.contains(ExportFormat.carousel.displayName))
        }
    }

    func testPDFRendererHonoursOptions() async throws {
        let f = JourneyFixtures.withStayStop()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("pipeline-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let maps = MapSnapshotService(cacheDirectory: base.appendingPathComponent("maps"))
        let pipeline = ExportPipeline(renderers: [.pdf: PDFExportRenderer(snapshots: maps,
                                                                         outputDirectory: base.appendingPathComponent("out"))])
        // Map hidden (no snapshot needed); only the last stop included.
        let privacy = ExportPrivacy(hideStayStops: false, mapMode: .hidden)
        let options = ExportOptions(format: .pdf, privacy: privacy, includedStopIDs: [f.stops[2].id])
        let all = ExportOptions(format: .pdf, privacy: ExportPrivacy(hideStayStops: false))
        let estimate = pipeline.estimateSlices(f.journey, options: options)
        XCTAssertEqual(estimate, 3, "cover, one stop page, closing")
        XCTAssertGreaterThan(pipeline.estimateSlices(f.journey, options: all), estimate)

        let result = try await pipeline.render(f.journey, options: options)
        guard case .pdf(let url) = result else { return XCTFail("expected a PDF") }
        let doc = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(doc.pageCount, estimate)
        let text = doc.string ?? ""
        XCTAssertTrue(text.contains("Leopold Cafe"))
        XCTAssertFalse(text.contains("Taj Mahal Palace"))
        XCTAssertFalse(text.contains("Gateway of India"))
    }

    // MARK: Slice images

    func testSliceImageRendererSizeColourSpaceAndPixels() throws {
        let view = Color(red: 1, green: 0, blue: 0)
        let img = try XCTUnwrap(SliceImageRenderer.render(view, size: CGSize(width: 100, height: 50), scale: 3))
        XCTAssertEqual(img.width, 300)
        XCTAssertEqual(img.height, 150)
        XCTAssertEqual(img.colorSpace?.name, CGColorSpace.sRGB)
        let p = TestImages.pixel(img, x: 150, y: 75)
        XCTAssertGreaterThan(p.r, 240); XCTAssertLessThan(p.g, 15); XCTAssertLessThan(p.b, 15)

        let slide = try XCTUnwrap(SliceImageRenderer.render(MadeWithStamp().frame(width: 540, height: 675),
                                                            spec: .carousel))
        XCTAssertEqual(slide.width, 1080)
        XCTAssertEqual(slide.height, 1350)

        let thumb = try XCTUnwrap(SliceImageRenderer.thumbnail(view, size: CGSize(width: 360, height: 640), maxPixel: 320))
        XCTAssertEqual(thumb.height, 320)
        XCTAssertEqual(thumb.width, 180)
    }

    func testSliceJPEGHasNoMetadata() throws {
        let img = try XCTUnwrap(SliceImageRenderer.render(MadeWithStamp(), size: MadeWithStamp.defaultSize, scale: 2))
        let data = try XCTUnwrap(SliceImageRenderer.jpegData(img))
        assertNoImageMetadata(data)
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(src) as String?, UTType.jpeg.identifier)
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(decoded.width, Int(MadeWithStamp.defaultSize.width * 2))
    }

    func testMetadataAssertionCatchesGPSAndCamera() {
        let image = ImageDrawing.render(size: CGSize(width: 8, height: 8), opaque: true)!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 18.92, kCGImagePropertyGPSLatitudeRef: "N"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:19 08:00:00"],
        ] as CFDictionary)
        CGImageDestinationFinalize(dest)
        XCTExpectFailure("GPS and camera fields must be reported") {
            assertNoImageMetadata(data as Data)
        }
    }

    func testMadeWithStampDrawsInk() throws {
        let img = try XCTUnwrap(TestImages.render(MadeWithStamp(), proposed: ProposedViewSize(MadeWithStamp.defaultSize)))
        XCTAssertGreaterThan(TestImages.opaquePixelCount(img), 200)
    }

    // MARK: Privacy

    func testOldPrivacyJSONDecodesWithNewDefaults() throws {
        let old = #"{"hideStayStops":false,"hideCosts":true,"hideExactTimes":true,"mapMode":"zoomedOut"}"#
        let p = try JSONDecoder().decode(ExportPrivacy.self, from: Data(old.utf8))
        XCTAssertEqual(p, ExportPrivacy(hideStayStops: false, hideCosts: true, hideExactTimes: true, mapMode: .zoomedOut))
        XCTAssertTrue(p.showBrandStamp)
        XCTAssertNil(p.authorName)

        let suite = "export-pipeline-\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        store.set(Data(old.utf8), forKey: ExportPrivacyDefaults.key)
        XCTAssertEqual(ExportPrivacyDefaults(store: store).load(), p)
    }

    func testNewPrivacyFieldsRoundTrip() throws {
        let p = ExportPrivacy(showBrandStamp: false, authorName: "Utsav")
        XCTAssertEqual(try JSONDecoder().decode(ExportPrivacy.self, from: JSONEncoder().encode(p)), p)
        XCTAssertNotEqual(p, ExportPrivacy())
    }

    private final class FakeKeyValueStore: ExportPrivacyKeyValueStore {
        var values: [String: Any] = [:]
        func data(forKey key: String) -> Data? { values[key] as? Data }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
        func removeObject(forKey key: String) { values[key] = nil }
        func synchronize() -> Bool { true }
    }

    func testPrivacySyncIsOffAndInert() throws {
        XCTAssertFalse(ExportPrivacySync.enabled)
        let kv = FakeKeyValueStore()
        let suite = "export-sync-\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        let sync = ExportPrivacySync(store: kv, defaults: ExportPrivacyDefaults(store: store))
        XCTAssertFalse(sync.isEnabled)
        sync.start()
        sync.push(ExportPrivacy(hideCosts: true))
        XCTAssertNil(sync.pull())
        XCTAssertTrue(kv.values.isEmpty)
    }

    // MARK: Fixtures and helpers

    func testNewFixtures() {
        let twelve = JourneyFixtures.twelveStops().snapshot
        XCTAssertEqual(twelve.stops.count, 12)
        XCTAssertEqual(PrivacyFilter.apply(twelve, ExportPrivacy()).stops.count, 12, "default privacy keeps all twelve")
        XCTAssertTrue(twelve.stops.allSatisfy { $0.photos.count >= 3 })

        let stress = JourneyFixtures.storyStressStop().snapshot.stops[0]
        XCTAssertEqual(WordLimit.count(stress.story), 100)
        XCTAssertEqual(stress.photos.count, 4)
        XCTAssertNotNil(stress.highlight)
        XCTAssertGreaterThan(stress.placeName.count, 50)
    }

    func testSliceEdgeHelper() {
        let doc = VerticalComposer().compose(JourneyFixtures.eightStops().snapshot, spec: .a4PDF)
        assertNoSliceEdgeCrossings(doc, axis: .vertical)
        XCTAssertTrue(SliceChecks.edgeCrossings(doc, axis: .horizontal).isEmpty)
        // A band narrower than the full cover block reports it.
        let narrow = SliceChecks.edgeCrossings(doc, axis: .vertical) { _ in 100...700 }
        XCTAssertTrue(narrow.contains { $0.hasPrefix("cover-0") })
    }
}
