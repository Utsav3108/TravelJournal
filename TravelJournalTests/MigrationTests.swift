import XCTest
import ImageIO
import SwiftData
import UniformTypeIdentifiers
@testable import TravelJournal

final class MigrationTests: XCTestCase {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mig-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func config(_ schema: Schema, _ url: URL) -> ModelConfiguration {
        ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
    }

    func testV1StoreMigratesToV3() throws {
        let url = try tempDir().appendingPathComponent("store.sqlite")
        let id: UUID

        do {
            let schema = Schema(versionedSchema: TJSchemaV1.self)
            let c = try ModelContainer(for: schema, configurations: [config(schema, url)])
            let ctx = ModelContext(c)
            let j = TJSchemaV1.Journey(title: "Old Trip", city: "Mumbai")
            id = j.id
            ctx.insert(j)
            try ctx.save()
        }

        let schema = Schema(versionedSchema: TJSchemaV3.self)
        let c = try ModelContainer(for: schema, migrationPlan: TJMigrationPlan.self, configurations: [config(schema, url)])
        let all = try ModelContext(c).fetch(FetchDescriptor<Journey>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, id)
        XCTAssertEqual(all.first?.title, "Old Trip")
        XCTAssertEqual(all.first?.city, "Mumbai")
        XCTAssertNil(all.first?.country)
    }

    func testV2PhotoFilesMoveIntoModelAndAreDeleted() throws {
        let dir = try tempDir()
        let base = dir.appendingPathComponent("support")
        let url = dir.appendingPathComponent("store.sqlite")

        let goodRel = "Photos/J/good.jpg", goodThumb = "Photos/J/thumbs/good.jpg"
        let badRel = "Photos/J/missing.jpg"
        try FilePhotoStore.write(try TestImages.jpeg(width: 3000, height: 2000), to: base.appendingPathComponent(goodRel))
        try FilePhotoStore.write(try TestImages.jpeg(width: 600, height: 400), to: base.appendingPathComponent(goodThumb))

        let journeyID: UUID, goodID: UUID, badID: UUID
        do {
            let schema = Schema(versionedSchema: TJSchemaV2.self)
            let c = try ModelContainer(for: schema, configurations: [config(schema, url)])
            let ctx = ModelContext(c)
            let j = TJSchemaV2.Journey(title: "Mumbai", city: "Mumbai", country: "India")
            let s = TJSchemaV2.Stop(placeName: "CST")
            s.story = "Arrived at dawn."
            s.journey = j
            let good = TJSchemaV2.StopPhoto()
            good.relativePath = goodRel; good.thumbRelativePath = goodThumb
            good.isHero = true; good.pixelWidth = 3000; good.pixelHeight = 2000; good.caption = "Platform"
            let bad = TJSchemaV2.StopPhoto()
            bad.relativePath = badRel; bad.orderIndex = 1
            j.stops.append(s); s.photos.append(good); s.photos.append(bad)
            ctx.insert(j)
            journeyID = j.id; goodID = good.id; badID = bad.id
            try ctx.save()
        }

        TJMigrationPlan.photoBaseURL = base
        defer { TJMigrationPlan.photoBaseURL = nil }
        let schema = Schema(versionedSchema: TJSchemaV3.self)
        let c = try ModelContainer(for: schema, migrationPlan: TJMigrationPlan.self, configurations: [config(schema, url)])
        let ctx = ModelContext(c)

        let journeys = try ctx.fetch(FetchDescriptor<Journey>())
        XCTAssertEqual(journeys.count, 1)
        XCTAssertEqual(journeys[0].id, journeyID)
        XCTAssertEqual(journeys[0].country, "India")
        XCTAssertEqual(journeys[0].stops.first?.story, "Arrived at dawn.")

        let photos = try ctx.fetch(FetchDescriptor<StopPhoto>())
        let good = try XCTUnwrap(photos.first { $0.id == goodID })
        let data = try XCTUnwrap(good.imageData)
        let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(PhotoEncoding.longEdge(of: src), PhotoLimits.displayMaxPixel)
        XCTAssertEqual(max(good.pixelWidth, good.pixelHeight), PhotoLimits.displayMaxPixel)
        XCTAssertTrue(good.isHero)
        XCTAssertEqual(good.caption, "Platform")
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent(goodRel).path), "original deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent(goodThumb).path), "thumb deleted")

        // An unreadable file never loses the row; it just has no data.
        let bad = try XCTUnwrap(photos.first { $0.id == badID })
        XCTAssertNil(bad.imageData)
        XCTAssertEqual(photos.count, 2)
    }

    @MainActor
    func testPhotoCacheRebuildsLocalFilesFromModel() throws {
        let base = try tempDir()
        let container = AppContainer.make(inMemory: true)
        let ctx = container.mainContext
        let j = Journey(title: "T"); ctx.insert(j)
        let s = Stop(placeName: "S"); j.stops.append(s)
        let store = FilePhotoStore(baseURL: base)
        let photo = try store.importPhoto(data: try TestImages.jpeg(width: 3000, height: 1500), into: s, journeyID: j.id)
        XCTAssertNotNil(photo.imageData)
        XCTAssertLessThanOrEqual(max(photo.pixelWidth, photo.pixelHeight), PhotoLimits.displayMaxPixel)

        // Simulate a fresh device (or post-migration): row + data synced, no files.
        try FileManager.default.removeItem(at: base.appendingPathComponent("Photos"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: photo.relativePath).path))
        XCTAssertEqual(PhotoCache.warm(context: ctx, store: store), 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: photo.relativePath).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: photo.thumbRelativePath).path))
        XCTAssertEqual(PhotoCache.warm(context: ctx, store: store), 0, "only missing files are written")
    }
}

final class PhotoEncodingTests: XCTestCase {
    func testOrientationIsBakedIntoPixels() throws {
        // Stored 300x100 landscape with EXIF orientation 6 (rotate 90° CW) displays as 100x300 portrait.
        let data = try TestImages.jpeg(width: 300, height: 100, orientation: 6)
        let enc = try XCTUnwrap(PhotoEncoding.reencoded(data, maxPixel: 2048))
        XCTAssertEqual(enc.width, 100)
        XCTAssertEqual(enc.height, 300)
        let src = try XCTUnwrap(CGImageSourceCreateWithData(enc.data as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 100)
        XCTAssertNotEqual(props[kCGImagePropertyOrientation] as? Int ?? 1, 6, "no leftover rotation tag")
    }

    func testDisplayP3ProfileIsKept() throws {
        let data = try TestImages.jpeg(width: 400, height: 300, colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!)
        let enc = try XCTUnwrap(PhotoEncoding.reencoded(data, maxPixel: 2048))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(enc.data as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        XCTAssertEqual(props[kCGImagePropertyProfileName] as? String, "Display P3")
    }

    func testNeverUpscalesAndCapsLongEdge() throws {
        let small = try XCTUnwrap(PhotoEncoding.reencoded(try TestImages.jpeg(width: 800, height: 600), maxPixel: 2048))
        XCTAssertEqual(small.width, 800)
        let big = try XCTUnwrap(PhotoEncoding.reencoded(try TestImages.jpeg(width: 4000, height: 3000), maxPixel: 2048))
        XCTAssertEqual(big.width, 2048)
        XCTAssertEqual(big.height, 1536)
    }
}

enum TestImages {
    static func jpeg(width: Int, height: Int, orientation: Int? = nil,
                     colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()) throws -> Data {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [0.8, 0.3, 0.2, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        var props: [CFString: Any] = [:]
        if let orientation { props[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(dest, try XCTUnwrap(ctx.makeImage()), props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return data as Data
    }
}
