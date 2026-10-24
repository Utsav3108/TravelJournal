import XCTest
import SwiftUI
import PDFKit
import Photos
import ImageIO
import UniformTypeIdentifiers
@testable import TravelJournal

// MARK: Slide preview

final class SlidePagerTests: XCTestCase {
    func testLabelAndClamping() {
        var p = SlidePager(count: 12)
        XCTAssertEqual(p.label, "1 / 12")
        XCTAssertFalse(p.canGoBack)
        XCTAssertTrue(p.canGoForward)
        p.previous()
        XCTAssertEqual(p.index, 0)
        p.select(2)
        XCTAssertEqual(p.label, "3 / 12")
        p.select(40)
        XCTAssertEqual(p.index, 11)
        XCTAssertFalse(p.canGoForward)
        p.next()
        XCTAssertEqual(p.index, 11)
        p.select(-3)
        XCTAssertEqual(p.index, 0)
        XCTAssertEqual(SlidePager(count: 5, index: 9).index, 4)
    }

    func testEmpty() {
        var p = SlidePager(count: 0)
        XCTAssertEqual(p.label, "")
        XCTAssertFalse(p.canGoBack)
        XCTAssertFalse(p.canGoForward)
        p.next()
        XCTAssertEqual(p.index, 0)
    }

    func testAspectMatchesInstagram() {
        XCTAssertEqual(SlidePager.aspectRatio(for: .carousel), 4.0 / 5.0, accuracy: 0.0001)
        XCTAssertEqual(SlidePager.aspectRatio(for: .story), 9.0 / 16.0, accuracy: 0.0001)
    }

    func testFittedSizeLetterboxes() {
        let wide = SlidePager.fittedSize(aspect: 0.8, in: CGSize(width: 1000, height: 500))
        XCTAssertEqual(wide.height, 500, accuracy: 0.001)
        XCTAssertEqual(wide.width, 400, accuracy: 0.001)
        let tall = SlidePager.fittedSize(aspect: 9.0 / 16.0, in: CGSize(width: 360, height: 2000))
        XCTAssertEqual(tall.width, 360, accuracy: 0.001)
        XCTAssertEqual(tall.height, 640, accuracy: 0.001)
        XCTAssertEqual(SlidePager.fittedSize(aspect: 0.8, in: .zero), .zero)
    }
}

// MARK: Folder export

final class FolderExporterTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("folder-export-\(UUID().uuidString)",
                                                                             isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("src"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("out"), withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func sources(_ n: Int) throws -> [URL] {
        try (1...n).map { i in
            let url = dir.appendingPathComponent("src/\(String(format: "%02d", i)).jpg")
            try Data("slide \(i)".utf8).write(to: url)
            return url
        }
    }

    func testNames() {
        XCTAssertEqual(FolderExporter.fileNames(title: "A Day in Mumbai", count: 3),
                       ["A Day in Mumbai 01.jpg", "A Day in Mumbai 02.jpg", "A Day in Mumbai 03.jpg"])
        XCTAssertEqual(FolderExporter.fileNames(title: "a/b:c", count: 1), ["a b c 01.jpg"])
        XCTAssertEqual(FolderExporter.fileNames(title: "  ", count: 1), ["Journey 01.jpg"])
        XCTAssertEqual(FolderExporter.fileNames(title: "T", count: 2, suffix: 3), ["T 3 01.jpg", "T 3 02.jpg"])
        XCTAssertEqual(FolderExporter.fileNames(title: "T", count: 120).last, "T 120.jpg")
        XCTAssertEqual(FolderExporter.fileNames(title: "T", count: 120).first, "T 001.jpg")
        XCTAssertTrue(FolderExporter.fileNames(title: "T", count: 0).isEmpty)
    }

    func testWritesInOrderWithoutOverwriting() throws {
        let out = dir.appendingPathComponent("out")
        let src = try sources(3)
        let first = try FolderExporter.export(src, title: "Mumbai", to: out)
        XCTAssertEqual(first.map(\.lastPathComponent), ["Mumbai 01.jpg", "Mumbai 02.jpg", "Mumbai 03.jpg"])
        XCTAssertEqual(try String(contentsOf: first[1], encoding: .utf8), "slide 2")

        // A second export of the same journey keeps the first set and gets the next suffix as a whole set.
        let second = try FolderExporter.export(src, title: "Mumbai", to: out)
        XCTAssertEqual(second.map(\.lastPathComponent), ["Mumbai 2 01.jpg", "Mumbai 2 02.jpg", "Mumbai 2 03.jpg"])

        // Only one name of the plain set taken: still a fresh set, nothing overwritten.
        let other = dir.appendingPathComponent("out2")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: other.appendingPathComponent("Mumbai 02.jpg"))
        let third = try FolderExporter.export(src, title: "Mumbai", to: other)
        XCTAssertEqual(third.first?.lastPathComponent, "Mumbai 2 01.jpg")
        XCTAssertEqual(try String(contentsOf: other.appendingPathComponent("Mumbai 02.jpg"), encoding: .utf8), "mine")
    }

    func testFailureRemovesPartialFiles() throws {
        let out = dir.appendingPathComponent("out")
        var src = try sources(2)
        src.append(dir.appendingPathComponent("src/missing.jpg"))
        XCTAssertThrowsError(try FolderExporter.export(src, title: "Mumbai", to: out))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.path), [])
        XCTAssertThrowsError(try FolderExporter.export([], title: "Mumbai", to: out)) {
            XCTAssertEqual($0 as? FolderExporter.Failure, .noImages)
        }
    }
}

// MARK: Save to Photos

private final class FakePhotoLibrary: PhotoLibraryWriting, @unchecked Sendable {
    var access: PhotoLibraryAccess
    var error: Error?
    var saved: [[URL]] = []
    var requests = 0

    init(access: PhotoLibraryAccess, error: Error? = nil) {
        self.access = access
        self.error = error
    }

    func requestAddAccess() async -> PhotoLibraryAccess { requests += 1; return access }

    func addImages(at urls: [URL]) async throws {
        if let error { throw error }
        saved.append(urls)
    }
}

@MainActor
final class PhotosSaverTests: XCTestCase {
    let urls = (1...3).map { URL(fileURLWithPath: "/tmp/\($0).jpg") }

    func testSavesInOrderWhenAllowed() async {
        for access in [PhotoLibraryAccess.authorized, .limited] {
            let lib = FakePhotoLibrary(access: access)
            let saver = PhotosSaver(library: lib)
            await saver.save(urls)
            XCTAssertEqual(saver.state, .saved(3))
            XCTAssertEqual(lib.saved, [urls], "one batch, in slide order")
            XCTAssertEqual(saver.state.message, "Saved 3 slides to Photos.")
        }
    }

    func testDenied() async {
        for access in [PhotoLibraryAccess.denied, .restricted, .notDetermined] {
            let lib = FakePhotoLibrary(access: access)
            let saver = PhotosSaver(library: lib)
            await saver.save(urls)
            XCTAssertEqual(saver.state, .denied)
            XCTAssertTrue(lib.saved.isEmpty)
            XCTAssertNotNil(saver.state.message)
        }
    }

    func testErrorAndReset() async {
        struct Boom: LocalizedError { var errorDescription: String? { "Disk full." } }
        let saver = PhotosSaver(library: FakePhotoLibrary(access: .authorized, error: Boom()))
        await saver.save(urls)
        XCTAssertEqual(saver.state, .failed("Disk full."))
        XCTAssertTrue(saver.state.message?.contains("Disk full.") ?? false)
        saver.reset()
        XCTAssertEqual(saver.state, .idle)

        let empty = PhotosSaver(library: FakePhotoLibrary(access: .authorized))
        await empty.save([])
        if case .failed = empty.state {} else { XCTFail("no slides is an error, not a save") }
    }

    func testAccessMapping() {
        XCTAssertEqual(PhotoLibraryAccess(.authorized), .authorized)
        XCTAssertEqual(PhotoLibraryAccess(.limited), .limited)
        XCTAssertEqual(PhotoLibraryAccess(.denied), .denied)
        XCTAssertEqual(PhotoLibraryAccess(.restricted), .restricted)
        XCTAssertEqual(PhotoLibraryAccess(.notDetermined), .notDetermined)
    }
}

// MARK: Metadata

private struct DataPhotoSource: StoryPhotoSource {
    var photos: [String: Data]
    func imageData(forPhotoID id: String) -> Data? { photos[id] }
}

@MainActor
final class ExportMetadataTests: XCTestCase {
    /// A camera-like JPEG: GPS position, camera make/model and capture date in its EXIF.
    private func photoWithGPS() -> Data {
        let image = ImageDrawing.render(size: CGSize(width: 64, height: 48), opaque: true) { c in
            c.setFillColor(ImageDrawing.color(hue: 0.1, saturation: 0.7, brightness: 0.8))
            c.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        }!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 18.94, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 72.83, kCGImagePropertyGPSLongitudeRef: "E"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:19 08:00:00"],
        ] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    func testDocumentInfo() {
        let plain = StoryPDFExporter.documentInfo(title: "A Day in Mumbai", privacy: ExportPrivacy())
        XCTAssertEqual(plain[kCGPDFContextTitle as String], "A Day in Mumbai")
        XCTAssertEqual(plain[kCGPDFContextCreator as String], "TravelJournal")
        XCTAssertEqual(plain[kCGPDFContextSubject as String], "Travel journal")
        XCTAssertNil(plain[kCGPDFContextAuthor as String], "no author unless the user adds one")
        XCTAssertNil(StoryPDFExporter.documentInfo(title: "T", privacy: ExportPrivacy(authorName: "   "))[kCGPDFContextAuthor as String])
        XCTAssertEqual(StoryPDFExporter.documentInfo(title: "T", privacy: ExportPrivacy(authorName: " Utsav "))[kCGPDFContextAuthor as String],
                       "Utsav")
    }

    func testAuthorFieldNormalisation() {
        XCTAssertNil(ExportPrivacy.normalizedAuthorName(""))
        XCTAssertNil(ExportPrivacy.normalizedAuthorName("  \n"))
        XCTAssertEqual(ExportPrivacy.normalizedAuthorName("Utsav "), "Utsav ", "kept as typed while editing")
    }

    func testFixtureReallyHasGPS() throws {
        let src = try XCTUnwrap(CGImageSourceCreateWithData(photoWithGPS() as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        XCTAssertNotNil(props[kCGImagePropertyGPSDictionary])
    }

    /// A source photo with GPS/camera EXIF loses it on the way through the photo provider and the slice renderer.
    func testGPSPhotoLeavesNoMetadataInOutputs() async throws {
        let gps = photoWithGPS()
        // What PDFImageProvider embeds: downsampled, re-encoded with no properties.
        let decoded = try XCTUnwrap(ImageDecoding.cgImage(from: gps, maxPixel: 1200))
        assertNoImageMetadata(try XCTUnwrap(ImageDrawing.jpegData(decoded, quality: PDFImageProvider.quality)), "PDF photo")

        let provider = PDFImageProvider(source: DataPhotoSource(photos: ["p": gps]), maxPixel: 2160, quality: 0.9)
        let photo = StoryPhoto(id: "p", isHero: true)
        try await provider.preload([[photo]])
        let cg = try XCTUnwrap(provider.image(for: photo, preferThumbnail: false, maxPixel: 0))

        // The slice path: a view drawing the photo, rendered and encoded like a carousel slide.
        let view = Image(decorative: cg, scale: 1).resizable().frame(width: 540, height: 675)
        let slide = try XCTUnwrap(SliceImageRenderer.render(view, spec: .carousel))
        let jpeg = try XCTUnwrap(SliceImageRenderer.jpegData(slide))
        assertNoImageMetadata(jpeg, "carousel slide")
        let story = try XCTUnwrap(SliceImageRenderer.render(view, spec: .story))
        assertNoImageMetadata(try XCTUnwrap(SliceImageRenderer.jpegData(story)), "story frame")
    }

    // MARK: PDF info and stamp, end to end

    private func exportPDF(_ privacy: ExportPrivacy) async throws -> PDFDocument {
        let f = JourneyFixtures.fourStops()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("meta-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        let snapshots = MapSnapshotService(cacheDirectory: base.appendingPathComponent("maps"))
        snapshots.timeout = .seconds(3)
        let exporter = StoryPDFExporter(snapshots: snapshots, outputDirectory: base.appendingPathComponent("out"))
        let url = try await exporter.export(f.journey, privacy: privacy)
        return try XCTUnwrap(PDFDocument(url: url))
    }

    private func closingText(_ doc: PDFDocument) -> String {
        doc.page(at: doc.pageCount - 1)?.string ?? ""
    }

    func testPDFInfoAndStampDefaults() async throws {
        let doc = try await exportPDF(ExportPrivacy(mapMode: .hidden))
        let attrs = doc.documentAttributes ?? [:]
        XCTAssertEqual(attrs[PDFDocumentAttribute.titleAttribute] as? String, "A Day in Mumbai")
        XCTAssertEqual(attrs[PDFDocumentAttribute.creatorAttribute] as? String, "TravelJournal")
        XCTAssertEqual(attrs[PDFDocumentAttribute.subjectAttribute] as? String, "Travel journal")
        XCTAssertNil(attrs[PDFDocumentAttribute.authorAttribute], "no author by default")
        XCTAssertTrue(closingText(doc).localizedCaseInsensitiveContains("Made with TravelJournal"),
                      "stamp on the closing page: \(closingText(doc))")
        for i in 0..<(doc.pageCount - 1) {
            XCTAssertFalse((doc.page(at: i)?.string ?? "").localizedCaseInsensitiveContains("Made with"), "page \(i)")
        }
    }

    func testPDFAuthorAndStampOff() async throws {
        let doc = try await exportPDF(ExportPrivacy(mapMode: .hidden, showBrandStamp: false, authorName: "Utsav"))
        XCTAssertEqual(doc.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String, "Utsav")
        XCTAssertFalse(closingText(doc).localizedCaseInsensitiveContains("Made with"))
    }

    // MARK: Closing page stamp

    func testStampOnlyInPrintModeWhenEnabled() {
        XCTAssertTrue(ClosingPage.showsBrandStamp(mode: .print, enabled: true))
        XCTAssertFalse(ClosingPage.showsBrandStamp(mode: .print, enabled: false))
        XCTAssertFalse(ClosingPage.showsBrandStamp(mode: .interactive, enabled: true))
    }

    func testClosingPageStampSnapshot() throws {
        let metrics = PageMetrics.a4
        let page = ClosingPage(model: StoryPageSamples.closing, metrics: metrics)
        let off = try XCTUnwrap(TestImages.render(page, proposed: ProposedViewSize(metrics.size)))
        let on = try XCTUnwrap(TestImages.render(page.environment(\.exportBrandStamp, true),
                                                 proposed: ProposedViewSize(metrics.size)))
        // The stamp sits in the bottom band, centred; nothing else changes.
        var changedTop = 0, changedBottom = 0
        for y in stride(from: 0, to: on.height, by: 3) {
            for x in stride(from: 0, to: on.width, by: 3) {
                let a = TestImages.pixel(on, x: x, y: y), b = TestImages.pixel(off, x: x, y: y)
                if abs(Int(a.r) - Int(b.r)) + abs(Int(a.g) - Int(b.g)) + abs(Int(a.b) - Int(b.b)) > 30 {
                    if y > on.height - 140 { changedBottom += 1 } else { changedTop += 1 }
                }
            }
        }
        XCTAssertGreaterThan(changedBottom, 50, "stamp drawn near the bottom")
        XCTAssertEqual(changedTop, 0, "nothing else moves")

        let name = "closing-a4-brandstamp"
        #if os(macOS)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("composed-snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        TestImages.writePNG(on, to: dir.appendingPathComponent("\(name)-macos.png"))
        guard FileManager.default.fileExists(atPath: Snapshots.referenceURL(named: name).path) else {
            throw XCTSkip("No macOS reference for \(name); copy it from the test host's tmp/composed-snapshots.")
        }
        #endif
        assertSnapshot(on, named: name, tolerance: 0.002)
    }
}

// MARK: Privacy defaults sync

private final class FakeKVStore: ExportPrivacyKeyValueStore {
    var values: [String: Any] = [:]
    var syncs = 0
    func data(forKey key: String) -> Data? { values[key] as? Data }
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
    func synchronize() -> Bool { syncs += 1; return true }
}

@MainActor
final class ExportPrivacySyncTests: XCTestCase {
    var suite: String!
    var local: ExportPrivacyDefaults!
    fileprivate var kv: FakeKVStore!

    override func setUpWithError() throws {
        suite = "privacy-sync-\(UUID().uuidString)"
        local = ExportPrivacyDefaults(store: try XCTUnwrap(UserDefaults(suiteName: suite)))
        kv = FakeKVStore()
    }

    override func tearDown() { UserDefaults().removePersistentDomain(forName: suite) }

    private func remote(_ p: ExportPrivacy) { kv.values[ExportPrivacySync.key] = try! JSONEncoder().encode(p) }

    private func postExternalChange(keys: [String]?) {
        let info: [AnyHashable: Any]? = keys.map { [NSUbiquitousKeyValueStoreChangedKeysKey: $0] }
        NotificationCenter.default.post(name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                        object: kv, userInfo: info)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))   // observer runs on the main queue
    }

    func testShippedSwitchIsOff() {
        XCTAssertFalse(ExportPrivacySync.enabled)
        XCTAssertFalse(ExportPrivacySync.shared.isEnabled)
    }

    func testDisabledIsInert() {
        let sync = ExportPrivacySync(store: kv, defaults: local, isEnabled: false)
        remote(ExportPrivacy(hideCosts: true))
        sync.start()
        sync.push(ExportPrivacy(hideExactTimes: true))
        XCTAssertNil(sync.pull())
        postExternalChange(keys: [ExportPrivacySync.key])
        sync.handleExternalChange(changedKeys: nil)
        XCTAssertEqual(local.load(), ExportPrivacy(), "local untouched")
        XCTAssertEqual(kv.syncs, 0)
        XCTAssertEqual(try JSONDecoder().decode(ExportPrivacy.self, from: kv.data(forKey: ExportPrivacySync.key)!),
                       ExportPrivacy(hideCosts: true), "store untouched")
    }

    func testPushMirrorsAndResetRemoves() throws {
        let sync = ExportPrivacySync(store: kv, defaults: local, isEnabled: true)
        let p = ExportPrivacy(hideCosts: true, showBrandStamp: false, authorName: "Utsav")
        sync.push(p)
        XCTAssertEqual(try JSONDecoder().decode(ExportPrivacy.self, from: try XCTUnwrap(kv.data(forKey: ExportPrivacyDefaults.key))), p)
        sync.push(nil)
        XCTAssertNil(kv.values[ExportPrivacyDefaults.key])
    }

    func testStartPullsAndObservesRemoteChanges() {
        let sync = ExportPrivacySync(store: kv, defaults: local, isEnabled: true)
        sync.start()
        XCTAssertEqual(local.load(), ExportPrivacy(), "an empty store leaves the local defaults alone")
        XCTAssertNil(local.store.data(forKey: ExportPrivacyDefaults.key))

        remote(ExportPrivacy(mapMode: .zoomedOut))
        postExternalChange(keys: [ExportPrivacySync.key])
        XCTAssertEqual(local.load(), ExportPrivacy(mapMode: .zoomedOut))

        // Unrelated keys are ignored.
        remote(ExportPrivacy(hideCosts: true))
        postExternalChange(keys: ["something.else"])
        XCTAssertEqual(local.load(), ExportPrivacy(mapMode: .zoomedOut))

        // Unknown key list: pull anyway (last writer wins).
        postExternalChange(keys: nil)
        XCTAssertEqual(local.load(), ExportPrivacy(hideCosts: true))

        // Removed on the other device = reset there.
        kv.values[ExportPrivacySync.key] = nil
        postExternalChange(keys: [ExportPrivacySync.key])
        XCTAssertNil(local.store.data(forKey: ExportPrivacyDefaults.key))
        XCTAssertEqual(local.load(), ExportPrivacy())
    }

    func testStartAppliesExistingRemoteValue() {
        remote(ExportPrivacy(hideExactTimes: true))
        let sync = ExportPrivacySync(store: kv, defaults: local, isEnabled: true)
        let applied = expectation(forNotification: ExportPrivacySync.didApplyRemoteChange, object: sync)
        sync.start()
        wait(for: [applied], timeout: 1)
        XCTAssertEqual(local.load(), ExportPrivacy(hideExactTimes: true))
        XCTAssertGreaterThan(kv.syncs, 0)
    }

    func testMalformedRemoteDataIsIgnored() {
        local.save(ExportPrivacy(hideCosts: true))
        kv.values[ExportPrivacySync.key] = Data("not json".utf8)
        let sync = ExportPrivacySync(store: kv, defaults: local, isEnabled: true)
        XCTAssertNil(sync.pull())
        sync.handleExternalChange(changedKeys: [ExportPrivacySync.key])
        XCTAssertEqual(local.load(), ExportPrivacy(hideCosts: true))
        kv.values[ExportPrivacySync.key] = 42   // wrong type
        sync.handleExternalChange(changedKeys: [ExportPrivacySync.key])
        XCTAssertEqual(local.load(), ExportPrivacy(hideCosts: true))
    }

    func testSettingsPushOnSaveAndReset() {
        let sync = ExportPrivacySync(store: kv, defaults: local, isEnabled: true)
        let settings = ExportPrivacySettings(defaults: local, sync: sync)
        settings.privacy.showBrandStamp = false
        settings.privacy.authorName = "Utsav"
        let mirrored = kv.data(forKey: ExportPrivacySync.key).flatMap { try? JSONDecoder().decode(ExportPrivacy.self, from: $0) }
        XCTAssertEqual(mirrored, ExportPrivacy(showBrandStamp: false, authorName: "Utsav"))
        XCTAssertEqual(local.load(), mirrored)
        settings.resetToDefaults()
        XCTAssertNil(kv.values[ExportPrivacySync.key])

        // An injected suite never mirrors to the app's store unless a sync is passed.
        XCTAssertNil(ExportPrivacySettings(defaults: local).sync)
    }
}
