import XCTest
import SwiftUI
import ImageIO
@testable import TravelJournal

/// `CarouselRenderer`: numbered 1080 x 1350 sRGB JPEGs without metadata, progress, cancellation, estimates, privacy,
/// the brand stamp and a stitched-panorama check of the route at the seams.
@MainActor
final class CarouselRendererTests: XCTestCase {
    private var base: URL!

    override func setUp() async throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("carousel-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func renderer(out: String = "out") -> CarouselRenderer {
        let maps = MapSnapshotService(cacheDirectory: base.appendingPathComponent("maps"))
        maps.timeout = .seconds(3)
        return CarouselRenderer(snapshots: maps, outputDirectory: base.appendingPathComponent(out))
    }

    private let options = ExportOptions(format: .carousel, privacy: ExportPrivacy())

    private func image(_ url: URL) throws -> CGImage {
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
    }

    // MARK: Files

    func testFourStopCarouselFiles() async throws {
        let f = JourneyFixtures.fourStops()
        let r = renderer()
        let expected = r.estimateSlices(f.journey, options: options)
        var ticks: [(Int, Int)] = []
        let result = try await r.render(f.journey, options: options) { ticks.append(($0, $1)) }
        guard case .images(let urls) = result else { return XCTFail("expected images") }
        XCTAssertEqual(urls.count, expected)
        XCTAssertEqual(urls.map(\.lastPathComponent), (1...expected).map { String(format: "%02d.jpg", $0) })
        XCTAssertEqual(ticks.first?.0, 0)
        XCTAssertEqual(ticks.first?.1, expected)
        XCTAssertEqual(ticks.last?.0, expected)
        XCTAssertEqual(ticks.count, expected + 1)

        var total = 0
        for url in urls {
            let data = try Data(contentsOf: url)
            total += data.count
            assertNoImageMetadata(data, url.lastPathComponent)
            XCTAssertLessThan(data.count, 1_500_000, "\(url.lastPathComponent) is \(data.count) bytes")
            let img = try image(url)
            XCTAssertEqual(img.width, 1080, url.lastPathComponent)
            XCTAssertEqual(img.height, 1350, url.lastPathComponent)
            XCTAssertEqual(img.colorSpace?.name as String?, CGColorSpace.sRGB as String, "\(url.lastPathComponent) colour space")
        }
        print("CAROUSEL_BYTES fourStops slides=\(urls.count) total=\(total) max=\(try urls.map { try Data(contentsOf: $0).count }.max() ?? 0)")
    }

    func testEstimateMatchesTheComposerAndHonoursSelection() {
        let f = JourneyFixtures.eightStops()
        let r = renderer()
        let all = r.estimateSlices(f.journey, options: options)
        XCTAssertEqual(all, HorizontalComposer.slideCount(for: options.snapshot(for: f.journey)))
        // A Stay stop is hidden by default; showing it adds slides.
        let withStay = ExportOptions(format: .carousel, privacy: ExportPrivacy(hideStayStops: false))
        XCTAssertGreaterThan(r.estimateSlices(f.journey, options: withStay), all)
        // The stop picker: fewer stops, fewer slides.
        let keep = Set(f.stops.prefix(3).map(\.id))
        let picked = ExportOptions(format: .carousel, privacy: ExportPrivacy(), includedStopIDs: keep)
        XCTAssertLessThan(r.estimateSlices(f.journey, options: picked), all)
    }

    func testMapSlideOmittedWhenHidden() async throws {
        let f = JourneyFixtures.fourStops()
        let shown = renderer().estimateSlices(f.journey, options: options)
        let hidden = ExportOptions(format: .carousel, privacy: ExportPrivacy(mapMode: .hidden))
        XCTAssertEqual(renderer().estimateSlices(f.journey, options: hidden), shown - 1)
        let result = try await renderer(out: "hidden").render(f.journey, options: hidden, progress: nil)
        XCTAssertEqual(result.urls.count, shown - 1)
    }

    func testHiddenStayStopIsAbsentFromTheOutput() async throws {
        let f = JourneyFixtures.withStayStop()
        let r = renderer()
        XCTAssertLessThan(r.estimateSlices(f.journey, options: options),
                          r.estimateSlices(f.journey, options: ExportOptions(format: .carousel, privacy: ExportPrivacy(hideStayStops: false))))
        let result = try await r.render(f.journey, options: options, progress: nil)
        XCTAssertEqual(result.urls.count, r.estimateSlices(f.journey, options: options))
    }

    func testAllStopsHiddenThrows() async {
        let f = JourneyFixtures.make([JourneyFixtures.StopSpec(name: "Taj Mahal Palace", category: .stay, photos: 1)])
        do {
            _ = try await renderer().render(f.journey, options: options, progress: nil)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? CarouselExportError, .allStopsHidden)
        }
    }

    func testCancellationLeavesNoFiles() async throws {
        let f = JourneyFixtures.fourStops()
        let r = renderer(out: "cancelled")
        let task = Task { try await r.render(f.journey, options: options, progress: nil) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("cancelled").path))
    }

    // MARK: Brand stamp

    func testBrandStampOnTheClosingSlideOnly() async throws {
        let f = JourneyFixtures.oneStop()
        let on = try await renderer(out: "stamp-on").render(f.journey, options: options, progress: nil).urls
        let off = try await renderer(out: "stamp-off")
            .render(f.journey, options: ExportOptions(format: .carousel, privacy: ExportPrivacy(showBrandStamp: false)), progress: nil).urls
        XCTAssertEqual(on.count, off.count)
        for k in on.indices {
            let same = try Data(contentsOf: on[k]) == Data(contentsOf: off[k])
            if k == on.count - 1 { XCTAssertFalse(same, "closing slide differs with the stamp") }
            else if k != 1 { XCTAssertTrue(same, "slide \(k + 1) is the same with or without the stamp") }   // slide 2 is the map
        }
    }

    // MARK: Stitched panorama

    /// Slides placed side by side must continue the dashed route across each seam: along the lane row the dash pattern
    /// repeats with the 16 pt period on both sides of the edge.
    func testRouteDashesContinueAcrossSeams() async throws {
        let f = CarouselFixtures.heavyStops(3)
        let r = renderer()
        let urls = try await r.render(f.journey, options: options, progress: nil).urls
        let s = options.snapshot(for: f.journey)
        let doc = HorizontalComposer().compose(s, spec: .carousel)
        let laneRow = Int(StopPanelLayout.Metrics(spec: .carousel).laneY * 2)
        let period = Int(PageRouteGeometry.period * 2)          // 32 px
        var checked = 0
        for k in 0..<(doc.slices.count - 1) where doc.slices[k].routeExit != nil {
            let left = try image(urls[k]), right = try image(urls[k + 1])
            // Panorama row of 2 * 96 px around the seam.
            let band = 96
            func ink(_ cg: CGImage, _ x: Int) -> Bool {
                let p = TestImages.pixel(cg, x: x, y: laneRow)
                // The route is dark red on cream paper: red clearly above blue.
                return Int(p.r) - Int(p.b) > 60
            }
            let strip = (0..<band).map { ink(left, 1080 - band + $0) } + (0..<band).map { ink(right, $0) }
            XCTAssertTrue(strip.contains(true), "slides \(k + 1)/\(k + 2): route visible near the seam")
            var agree = 0, total = 0
            for x in 0..<(strip.count - period) {
                total += 1
                if strip[x] == strip[x + period] { agree += 1 }
            }
            func agreement(_ shift: Int, _ range: Range<Int>) -> Double {
                let xs = range.filter { $0 + shift < strip.count }
                return Double(xs.filter { strip[$0] == strip[$0 + shift] }.count) / Double(max(xs.count, 1))
            }
            let across = agreement(period, 0..<strip.count), within = agreement(period, 0..<(band - period))
            let wrong = agreement(period / 2, 0..<strip.count)
            print("CAROUSEL_DASH seam \(k) across=\(across) within=\(within) halfPeriod=\(wrong) agree=\(Double(agree) / Double(total))")
            XCTAssertGreaterThan(across, 0.8, "slides \(k + 1)/\(k + 2): dash pattern continues across the seam")
            XCTAssertGreaterThan(across, wrong + 0.3, "slides \(k + 1)/\(k + 2): pattern is periodic, not shifted by half a period")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0)
    }

    /// The lane meets the edges at the same row in both neighbouring files (pixel columns at the seam).
    func testRouteMeetsTheEdgeAtTheSameRow() async throws {
        let f = JourneyFixtures.fourStops()
        let urls = try await renderer().render(f.journey, options: options, progress: nil).urls
        let doc = HorizontalComposer().compose(options.snapshot(for: f.journey), spec: .carousel)
        for k in 0..<(doc.slices.count - 1) where doc.slices[k].routeExit != nil {
            let left = try image(urls[k]), right = try image(urls[k + 1])
            func inkRows(_ cg: CGImage, x: Int) -> [Int] {
                (0..<cg.height).filter { y in
                    let p = TestImages.pixel(cg, x: x, y: y)
                    return Int(p.r) - Int(p.b) > 60
                }
            }
            // Look a few px in from each edge, where a dash is always inked within one period.
            let l = (1070..<1080).flatMap { inkRows(left, x: $0) }, rr = (0..<10).flatMap { inkRows(right, x: $0) }
            XCTAssertFalse(l.isEmpty && rr.isEmpty, "seam \(k): the route is inked near the edge")
            let rows = Set(l + rr)
            if let lo = rows.min(), let hi = rows.max() {
                XCTAssertLessThanOrEqual(hi - lo, 12, "seam \(k): route rows near the seam are one line (\(lo)...\(hi))")
                XCTAssertEqual(Double(lo + hi) / 2, Double(doc.slices[k].routeExit!.y * 2), accuracy: 4)
            }
        }
    }
}
