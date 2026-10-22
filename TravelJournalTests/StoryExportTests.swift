import XCTest
import SwiftData
import PDFKit
@testable import TravelJournal

@MainActor
final class StoryExportTests: XCTestCase {
    static let scratch = "/private/tmp/claude-501/-Users-utsav-Documents-Projects-TravelJournal/8161a91e-c450-4f0d-8adb-8fc11249eb44/scratchpad/export"
    var container: ModelContainer!
    var context: ModelContext!
    var base: URL!
    var snapshots: MapSnapshotService!

    override func setUp() async throws {
        container = AppContainer.make(inMemory: true)
        context = ModelContext(container)
        base = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base.appendingPathComponent("Photos"), withIntermediateDirectories: true)
        snapshots = MapSnapshotService(cacheDirectory: base.appendingPathComponent("maps"))
        snapshots.timeout = .seconds(3)
        try? FileManager.default.createDirectory(atPath: Self.scratch, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: base)
    }

    // MARK: Helpers

    private func exporter() -> StoryPDFExporter {
        StoryPDFExporter(snapshots: snapshots,
                         outputDirectory: base.appendingPathComponent("out-\(UUID().uuidString)"))
    }

    /// Photo-like JPEG at the app's stored display size (2400 px long edge): gradient plus shapes plus grain.
    private func jpeg(seed: Int, size: CGSize = CGSize(width: 2400, height: 1800)) -> Data {
        var rng = SystemRandomNumberGenerator()
        let img = ImageDrawing.render(size: size, opaque: true) { c in
            let hue = Double(seed % 7) / 7
            let g = CGGradient(colorsSpace: ImageDrawing.sRGB,
                               colors: [ImageDrawing.color(hue: hue, saturation: 0.5, brightness: 0.9),
                                        ImageDrawing.color(hue: hue + 0.1, saturation: 0.7, brightness: 0.4)] as CFArray,
                               locations: [0, 1])!
            c.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            for _ in 0..<1500 {
                c.setFillColor(ImageDrawing.color(hue: .random(in: 0...1, using: &rng), saturation: 0.6,
                                                  brightness: .random(in: 0.3...1, using: &rng), alpha: 0.5))
                c.fillEllipse(in: CGRect(x: .random(in: 0...size.width, using: &rng), y: .random(in: 0...size.height, using: &rng),
                                         width: .random(in: 4...60, using: &rng), height: .random(in: 4...60, using: &rng)))
            }
        }!
        return ImageDrawing.jpegData(img, quality: 0.85)!
    }

    /// Gives the sample (placeholder) photos real JPEG bytes in the model.
    @discardableResult
    private func attachRealPhotos(_ j: Journey) throws -> Int {
        var total = 0
        for s in j.orderedStops {
            for (i, p) in s.orderedPhotos.enumerated() {
                let portrait = i % 2 == 1
                p.imageData = jpeg(seed: total, size: portrait ? CGSize(width: 1800, height: 2400) : CGSize(width: 2400, height: 1800))
                total += 1
            }
        }
        return total
    }

    private func pdf(_ url: URL) throws -> PDFDocument { try XCTUnwrap(PDFDocument(url: url)) }

    private func writePNGs(_ doc: PDFDocument, prefix: String) {
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let img = TestImages.image(of: page, size: CGSize(width: 1190, height: 1684))
            TestImages.writePNG(img, to: URL(fileURLWithPath: "\(Self.scratch)/\(prefix)-page\(i + 1).png"))
        }
    }

    // MARK: Tests

    func testMumbaiExportWithRealPhotos() async throws {
        let j = SampleData.mumbai(in: context)
        let photoCount = try attachRealPhotos(j)
        XCTAssertGreaterThan(photoCount, 0)
        let expected = StoryLayout().pages(for: j).count
        XCTAssertEqual(expected, 7)

        var ticks: [(Int, Int)] = []
        let ex = exporter()
        ex.progress = { ticks.append(($0, $1)) }
        let url = try await ex.export(j)

        XCTAssertEqual(url.lastPathComponent, "A Day in Mumbai.pdf")
        XCTAssertEqual(ticks.first?.0, 0)
        XCTAssertEqual(ticks.last?.0, 7)
        XCTAssertEqual(ticks.last?.1, 7)

        let doc = try pdf(url)
        XCTAssertEqual(doc.pageCount, expected)
        for i in 0..<doc.pageCount {
            let box = try XCTUnwrap(doc.page(at: i)).bounds(for: .mediaBox)
            XCTAssertEqual(box.width, 595, accuracy: 0.5, "page \(i)")
            XCTAssertEqual(box.height, 842, accuracy: 0.5, "page \(i)")
        }
        let text = doc.string ?? ""
        XCTAssertTrue(text.localizedCaseInsensitiveContains("A Day in Mumbai"), "title text must stay vector/extractable")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("Chhatrapati") || text.localizedCaseInsensitiveContains("Shivaji"),
                      "stop name extractable")
        let attrs = doc.documentAttributes ?? [:]
        XCTAssertEqual(attrs[PDFDocumentAttribute.titleAttribute] as? String, "A Day in Mumbai")
        XCTAssertEqual(attrs[PDFDocumentAttribute.authorAttribute] as? String, "TravelJournal")

        let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        print("EXPORT_SIZE_BYTES=\(size) photos=\(photoCount) pages=\(doc.pageCount)")
        XCTAssertLessThan(size, 8_000_000, "Mumbai PDF with \(photoCount) 2400px JPEGs must stay under 8 MB (was \(size))")

        try? FileManager.default.removeItem(atPath: Self.scratch + "/Mumbai.pdf")
        try? FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: Self.scratch + "/Mumbai.pdf"))
        writePNGs(doc, prefix: "mumbai")
    }

    func testMumbaiExportWithSamplePlaceholders() async throws {
        let j = SampleData.mumbai(in: context)
        let url = try await exporter().export(j)
        let doc = try pdf(url)
        XCTAssertEqual(doc.pageCount, 7)
        XCTAssertTrue((doc.string ?? "").contains("Mumbai"))
    }

    func testCancellationLeavesNoFile() async throws {
        let j = SampleData.mumbai(in: context)
        let out = base.appendingPathComponent("cancel-out")
        let ex = StoryPDFExporter(snapshots: snapshots, outputDirectory: out)
        let task = Task { @MainActor in try await ex.export(j) }
        ex.progress = { done, _ in if done == 2 { task.cancel() } }
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
        }
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: out.path)) ?? []
        XCTAssertTrue(leftovers.isEmpty, "no partial PDF may remain: \(leftovers)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
    }

    func testCancelBeforeStart() async throws {
        let j = SampleData.mumbai(in: context)
        let ex = exporter()
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ex.export(j)
        }
        do { _ = try await task.value; XCTFail("expected cancellation") } catch is CancellationError {}
    }

    func testOneStopJourney() async throws {
        let j = Journey(title: "Just One", city: "Pune"); context.insert(j)
        let editor = JourneyEditor(context: context, photos: NoopPhotoStore())
        let s = Stop(placeName: "Shaniwar Wada", story: "Old stone, new selfies.")
        s.latitude = 18.519; s.longitude = 73.855
        editor.addStop(s, to: j)
        let url = try await exporter().export(j)
        let doc = try pdf(url)
        XCTAssertEqual(doc.pageCount, 4)   // cover, overview, stop, closing
        XCTAssertTrue((doc.string ?? "").contains("Shaniwar Wada"))
        XCTAssertEqual(url.lastPathComponent, "Just One.pdf")
    }

    func testNoPhotoJourneyAndMissingMode() async throws {
        let j = Journey(title: "No Photos", city: "Goa"); context.insert(j)
        let editor = JourneyEditor(context: context, photos: NoopPhotoStore())
        let a = Stop(placeName: "Anjuna", story: "Sunset."); a.latitude = 15.57; a.longitude = 73.74
        editor.addStop(a, to: j)
        let b = Stop(placeName: "Vagator", story: "More sunset."); b.latitude = 15.6; b.longitude = 73.74
        editor.addStop(b, to: j)
        let doc = try pdf(try await exporter().export(j))
        XCTAssertEqual(doc.pageCount, 5)
        XCTAssertTrue((doc.string ?? "").contains("Vagator"))
    }

    func testEmptyJourneyThrows() async throws {
        let j = Journey(title: "Empty"); context.insert(j)
        do { _ = try await exporter().export(j); XCTFail("expected error") }
        catch StoryPDFExportError.noStops {}
    }

    func testFileNameSanitising() {
        let f = StoryPDFExporter.fileName(forTitle:)
        XCTAssertEqual(f("A Day in Mumbai"), "A Day in Mumbai.pdf")
        XCTAssertEqual(f("Goa/Trip: \"2026\"?"), "Goa Trip 2026.pdf")
        XCTAssertEqual(f("  ../../etc/passwd  "), "etc passwd.pdf")
        XCTAssertEqual(f(""), "Journey.pdf")
        XCTAssertEqual(f("///"), "Journey.pdf")
        XCTAssertEqual(f("Line\nBreak\tTab"), "Line Break Tab.pdf")
        XCTAssertEqual(f("Café Zürich 東京"), "Café Zürich 東京.pdf")
        XCTAssertLessThanOrEqual(f(String(repeating: "a", count: 300)).count, 84)
    }
}
