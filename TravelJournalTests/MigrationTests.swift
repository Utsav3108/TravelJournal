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

    private func writeFile(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private func config(_ schema: Schema, _ url: URL) -> ModelConfiguration {
        ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
    }

    func testV1StoreMigratesToV5() throws {
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

        let schema = Schema(versionedSchema: TJSchemaV5.self)
        let c = try ModelContainer(for: schema, migrationPlan: TJMigrationPlan.self, configurations: [config(schema, url)])
        let all = try ModelContext(c).fetch(FetchDescriptor<Journey>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, id)
        XCTAssertEqual(all.first?.title, "Old Trip")
        XCTAssertEqual(all.first?.city, "Mumbai")
        XCTAssertNil(all.first?.country)
    }

    func testV3StoreMigratesToV5WithNoPrivacyOverrides() throws {
        let url = try tempDir().appendingPathComponent("store.sqlite")
        let stopID: UUID
        do {
            let schema = Schema(versionedSchema: TJSchemaV3.self)
            let c = try ModelContainer(for: schema, configurations: [config(schema, url)])
            let ctx = ModelContext(c)
            let j = TJSchemaV3.Journey(title: "V3 Trip", city: "Mumbai")
            let s = TJSchemaV3.Stop(placeName: "Hotel")
            s.categoryRaw = StopCategory.stay.rawValue
            s.journey = j
            j.stopsStorage = [s]
            ctx.insert(j)
            stopID = s.id
            try ctx.save()
        }

        let schema = Schema(versionedSchema: TJSchemaV5.self)
        let c = try ModelContainer(for: schema, migrationPlan: TJMigrationPlan.self, configurations: [config(schema, url)])
        let ctx = ModelContext(c)
        let j = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Journey>()).first)
        XCTAssertEqual(j.title, "V3 Trip")
        XCTAssertNil(j.exportPrivacyData)
        XCTAssertNil(j.exportPrivacy)
        let s = try XCTUnwrap(j.stops.first)
        XCTAssertEqual(s.id, stopID)
        XCTAssertEqual(s.category, .stay)
        XCTAssertNil(s.exportHidden)
    }

    @MainActor
    func testV4StoreMigratesToV5WithNoMapStop() throws {
        let url = try tempDir().appendingPathComponent("store.sqlite")
        let stopID: UUID
        do {
            let schema = Schema(versionedSchema: TJSchemaV4.self)
            let c = try ModelContainer(for: schema, configurations: [config(schema, url)])
            let ctx = ModelContext(c)
            let j = TJSchemaV4.Journey(title: "V4 Trip", city: "Goa")
            j.exportPrivacyData = Data([1, 2, 3])
            let s = TJSchemaV4.Stop(placeName: "Beach")
            s.latitude = 15.5; s.longitude = 73.8
            s.journey = j
            j.stopsStorage = [s]
            ctx.insert(j)
            stopID = s.id
            try ctx.save()
        }

        let schema = Schema(versionedSchema: TJSchemaV5.self)
        let c = try ModelContainer(for: schema, migrationPlan: TJMigrationPlan.self, configurations: [config(schema, url)])
        let j = try XCTUnwrap(try ModelContext(c).fetch(FetchDescriptor<Journey>()).first)
        XCTAssertEqual(j.title, "V4 Trip")
        XCTAssertEqual(j.exportPrivacyData, Data([1, 2, 3]))
        XCTAssertNil(j.mapStopID)
        XCTAssertEqual(j.stops.first?.id, stopID)
        XCTAssertEqual(StoryMapPins.mapStop(for: j)?.id, stopID)
    }

    func testV2PhotoFilesMoveIntoModelAndAreDeleted() throws {
        let dir = try tempDir()
        let base = dir.appendingPathComponent("support")
        let url = dir.appendingPathComponent("store.sqlite")

        let goodRel = "Photos/J/good.jpg", goodThumb = "Photos/J/thumbs/good.jpg"
        let badRel = "Photos/J/missing.jpg"
        try writeFile(try MigrationImages.jpeg(width: 3000, height: 2000), to: base.appendingPathComponent(goodRel))
        try writeFile(try MigrationImages.jpeg(width: 600, height: 400), to: base.appendingPathComponent(goodThumb))

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
        let schema = Schema(versionedSchema: TJSchemaV5.self)
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
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("MigrationStaging").path),
                       "the staging copies are cleaned up")

        // An unreadable file never loses the row; it just has no data.
        let bad = try XCTUnwrap(photos.first { $0.id == badID })
        XCTAssertNil(bad.imageData)
        XCTAssertEqual(photos.count, 2)
    }
}

final class PhotoEncodingTests: XCTestCase {
    func testOrientationIsBakedIntoPixels() throws {
        // Stored 300x100 landscape with EXIF orientation 6 (rotate 90° CW) displays as 100x300 portrait.
        let data = try MigrationImages.jpeg(width: 300, height: 100, orientation: 6)
        let enc = try XCTUnwrap(PhotoEncoding.reencoded(data, maxPixel: 2048))
        XCTAssertEqual(enc.width, 100)
        XCTAssertEqual(enc.height, 300)
        let src = try XCTUnwrap(CGImageSourceCreateWithData(enc.data as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 100)
        XCTAssertNotEqual(props[kCGImagePropertyOrientation] as? Int ?? 1, 6, "no leftover rotation tag")
    }

    func testDisplayP3ProfileIsKept() throws {
        let data = try MigrationImages.jpeg(width: 400, height: 300, colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!)
        let enc = try XCTUnwrap(PhotoEncoding.reencoded(data, maxPixel: 2048))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(enc.data as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        XCTAssertEqual(props[kCGImagePropertyProfileName] as? String, "Display P3")
    }

    func testNeverUpscalesAndCapsLongEdge() throws {
        let small = try XCTUnwrap(PhotoEncoding.reencoded(try MigrationImages.jpeg(width: 800, height: 600), maxPixel: 2048))
        XCTAssertEqual(small.width, 800)
        let big = try XCTUnwrap(PhotoEncoding.reencoded(try MigrationImages.jpeg(width: 4000, height: 3000), maxPixel: 2048))
        XCTAssertEqual(big.width, 2048)
        XCTAssertEqual(big.height, 1536)
    }
}

enum MigrationImages {
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
