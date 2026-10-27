import XCTest
import CoreGraphics
import ImageIO
@testable import TravelJournal

/// `StoryRenderer`: 1080x1920 sRGB JPEGs without metadata, numbered in order, progress, cancellation, privacy.
@MainActor
final class StoryRendererTests: XCTestCase {
    private var base: URL!
    private let showAll = ExportPrivacy(hideStayStops: false)

    override func setUp() {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("story-renderer-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: base)
    }

    private func urls(_ r: ExportResult) throws -> [URL] {
        guard case .images(let urls) = r else { throw XCTSkip("not images") }
        return urls
    }

    func testEveryFrameIsA1080x1920SRGBJPEGWithoutMetadata() async throws {
        let f = JourneyFixtures.fourStops()
        let renderer = StoryRenderer(outputDirectory: base)
        let options = ExportOptions(format: .story, privacy: showAll)
        let expected = renderer.estimateSlices(f.journey, options: options)
        var ticks: [[Int]] = []
        let result = try await renderer.render(f.journey, options: options) { ticks.append([$0, $1]) }
        let files = try urls(result)
        XCTAssertEqual(files.count, expected)
        XCTAssertEqual(expected, 2 + 4, "cover + 4 stops + closing (no map)")
        XCTAssertEqual(files.map(\.lastPathComponent), (1...files.count).map { String(format: "%02d.jpg", $0) })
        XCTAssertEqual(ticks.first, [0, files.count])
        XCTAssertEqual(ticks.last, [files.count, files.count])
        for url in files {
            let data = try Data(contentsOf: url)
            assertNoImageMetadata(data, url.lastPathComponent)
            let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            XCTAssertEqual(CGImageSourceGetType(src) as String?, "public.jpeg")
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
            XCTAssertEqual(image.width, 1080, url.lastPathComponent)
            XCTAssertEqual(image.height, 1920, url.lastPathComponent)
            let name = image.colorSpace?.name as String?
            XCTAssertTrue(name == (CGColorSpace.sRGB as String) || name == (CGColorSpace.extendedSRGB as String),
                          "\(url.lastPathComponent): \(name ?? "nil")")
            XCTAssertLessThan(data.count, 1_500_000, "\(url.lastPathComponent) is \(data.count) bytes")
        }
    }

    func testStressStopRenders() async throws {
        let f = JourneyFixtures.storyStressStop()
        let result = try await StoryRenderer(outputDirectory: base)
            .render(f.journey, options: ExportOptions(format: .story, privacy: showAll), progress: nil)
        XCTAssertEqual(try urls(result).count, 3)
    }

    func testHiddenStayStopGetsNoFrame() async throws {
        let f = JourneyFixtures.withStayStop()
        let renderer = StoryRenderer(outputDirectory: base)
        let hidden = ExportOptions(format: .story, privacy: ExportPrivacy())
        XCTAssertEqual(renderer.estimateSlices(f.journey, options: hidden), 4)
        XCTAssertEqual(renderer.estimateSlices(f.journey, options: ExportOptions(format: .story, privacy: showAll)), 5)
        let files = try urls(try await renderer.render(f.journey, options: hidden, progress: nil))
        XCTAssertEqual(files.count, 4)
    }

    func testIncludedStopIDsSelectFrames() async throws {
        let f = JourneyFixtures.fourStops()
        let keep = Set(f.stops.prefix(2).map(\.id))
        let options = ExportOptions(format: .story, privacy: showAll, includedStopIDs: keep)
        XCTAssertEqual(StoryRenderer(outputDirectory: base).estimateSlices(f.journey, options: options), 4)
    }

    func testCancellationLeavesNoFiles() async throws {
        let f = JourneyFixtures.fourStops()
        let renderer = StoryRenderer(outputDirectory: base)
        let task = Task { @MainActor in
            try await renderer.render(f.journey, options: ExportOptions(format: .story, privacy: self.showAll), progress: nil)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
        }
        let left = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
        for dir in left {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: base.appendingPathComponent(dir).path)) ?? []
            XCTAssertTrue(files.isEmpty, "left \(files)")
        }
    }

    func testAllStopsHiddenThrows() async throws {
        let f = JourneyFixtures.withStayStop()
        for s in f.stops { s.exportHidden = true }
        do {
            _ = try await StoryRenderer(outputDirectory: base)
                .render(f.journey, options: ExportOptions(format: .story, privacy: showAll), progress: nil)
            XCTFail("expected an error")
        } catch let error as StoryPDFExportError {
            XCTAssertEqual(error, .allStopsHidden)
        }
    }

    func testBrandStampOnlyWhenEnabled() async throws {
        // The closing frame differs with the stamp on and off, and the stamp sits above the bottom clear band.
        let f = JourneyFixtures.oneStop()
        func closing(_ stamp: Bool) async throws -> Data {
            var p = showAll
            p.showBrandStamp = stamp
            let files = try urls(try await StoryRenderer(outputDirectory: base)
                .render(f.journey, options: ExportOptions(format: .story, privacy: p), progress: nil))
            return try Data(contentsOf: try XCTUnwrap(files.last))
        }
        let on = try await closing(true), off = try await closing(false)
        XCTAssertNotEqual(on, off)
        let s = f.snapshot
        let layout = StoryClosingLayout.make(s.closingModel, spec: .story, showsStamp: true)
        XCTAssertLessThanOrEqual(layout.stamp?.maxY ?? 9999, OutputSpec.story.safeContentRect.maxY)
        XCTAssertGreaterThanOrEqual(layout.heading.minY, OutputSpec.story.safeContentRect.minY)
        XCTAssertNil(StoryClosingLayout.make(s.closingModel, spec: .story, showsStamp: false).stamp)
    }
}
