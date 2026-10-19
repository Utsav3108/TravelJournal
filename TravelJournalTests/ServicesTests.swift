import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
@testable import TravelJournal

// MARK: Synthetic JPEG

private func makeJPEG(width: Int = 400, height: Int = 200, exif: [CFString: Any]? = nil, gps: [CFString: Any]? = nil) -> Data {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.8, green: 0.5, blue: 0.2, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let img = ctx.makeImage()!
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)!
    var props: [CFString: Any] = [:]
    if let exif { props[kCGImagePropertyExifDictionary] = exif }
    if let gps { props[kCGImagePropertyGPSDictionary] = gps }
    CGImageDestinationAddImage(dest, img, props as CFDictionary)
    CGImageDestinationFinalize(dest)
    return out as Data
}

struct ExifReaderTests {
    @Test func readsGPSWithHemisphereSigns() {
        let data = makeJPEG(gps: [kCGImagePropertyGPSLatitude: 33.8688, kCGImagePropertyGPSLatitudeRef: "S",
                                  kCGImagePropertyGPSLongitude: 70.5, kCGImagePropertyGPSLongitudeRef: "W"])
        let m = ExifReader.read(data)
        #expect(abs((m.latitude ?? 0) - -33.8688) < 1e-6)
        #expect(abs((m.longitude ?? 0) - -70.5) < 1e-6)
    }

    @Test func readsNorthEast() {
        let data = makeJPEG(gps: [kCGImagePropertyGPSLatitude: 18.9398, kCGImagePropertyGPSLatitudeRef: "N",
                                  kCGImagePropertyGPSLongitude: 72.8355, kCGImagePropertyGPSLongitudeRef: "E"])
        let m = ExifReader.read(data)
        #expect(abs((m.latitude ?? 0) - 18.9398) < 1e-6)
        #expect(abs((m.longitude ?? 0) - 72.8355) < 1e-6)
    }

    @Test func dateWithOffset() throws {
        let data = makeJPEG(exif: [kCGImagePropertyExifDateTimeOriginal: "2026:10:19 09:00:00",
                                   "OffsetTimeOriginal" as CFString: "+05:30"])
        let m = ExifReader.read(data)
        let date = try #require(m.date)
        // 09:00 +05:30 == 03:30 UTC
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let c = cal.dateComponents([.hour, .minute], from: date)
        #expect(c.hour == 3 && c.minute == 30)
    }

    @Test func dateWithoutOffsetUsesFallbackZone() throws {
        let d = try #require(ExifReader.parseDate("2026:10:19 09:00:00", offset: nil, fallback: TimeZone(secondsFromGMT: 3600)!))
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
        #expect(cal.component(.hour, from: d) == 8)
    }

    @Test func noMetadata() {
        let m = ExifReader.read(makeJPEG())
        #expect(m.date == nil && m.latitude == nil && m.longitude == nil)
        #expect(ExifReader.read(Data([1, 2, 3])) == ExifMetadata())
    }

    @Test func badOffsetIgnored() {
        #expect(ExifReader.timeZone(fromOffset: "garbage") == nil)
        #expect(ExifReader.timeZone(fromOffset: "-04:00")?.secondsFromGMT() == -4 * 3600)
    }
}

struct PhotoMetaFactoryTests {
    @Test func downscalesAndKeepsMetadata() throws {
        let data = makeJPEG(width: 3000, height: 1500,
                            exif: [kCGImagePropertyExifDateTimeOriginal: "2026:10:19 09:00:00"],
                            gps: [kCGImagePropertyGPSLatitude: 10.0, kCGImagePropertyGPSLatitudeRef: "N",
                                  kCGImagePropertyGPSLongitude: 20.0, kCGImagePropertyGPSLongitudeRef: "E"])
        let meta = try #require(PhotoMetaFactory.make(data: data, maxPixel: 1000))
        #expect(meta.hasLocation && meta.date != nil)
        let src = try #require(CGImageSourceCreateWithData(meta.jpegData as CFData, nil))
        let p = try #require(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        let w = p[kCGImagePropertyPixelWidth] as? Int ?? 0, h = p[kCGImagePropertyPixelHeight] as? Int ?? 0
        #expect(max(w, h) <= 1000 && max(w, h) > 0)
        #expect(!meta.id.isEmpty)
    }

    @Test func assetValuesWin() throws {
        let data = makeJPEG(gps: [kCGImagePropertyGPSLatitude: 10.0, kCGImagePropertyGPSLatitudeRef: "N",
                                  kCGImagePropertyGPSLongitude: 20.0, kCGImagePropertyGPSLongitudeRef: "E"])
        let when = Date(timeIntervalSince1970: 1_000_000)
        let meta = try #require(PhotoMetaFactory.make(id: "A1", data: data, assetDate: when, assetLatitude: 1, assetLongitude: 2))
        #expect(meta.id == "A1" && meta.date == when && meta.latitude == 1 && meta.longitude == 2)
    }

    @Test func undecodableReturnsNil() {
        #expect(PhotoMetaFactory.make(data: Data([0, 1, 2])) == nil)
    }
}

// MARK: Place lookup throttle / cache

private actor FakeBackend: PlaceBackend {
    var poiCalls = 0, reverseCalls = 0, searchCalls = 0
    var poiResult: [PlaceCandidate] = []
    var reverseResult: PlaceCandidate?
    var failFirst = 0

    func set(poi: [PlaceCandidate] = [], reverse: PlaceCandidate? = nil, failFirst: Int = 0) {
        poiResult = poi; reverseResult = reverse; self.failFirst = failFirst
    }
    private func maybeFail() throws {
        if failFirst > 0 { failFirst -= 1; throw URLError(.notConnectedToInternet) }
    }
    func pointsOfInterest(latitude: Double, longitude: Double, radius: Double) async throws -> [PlaceCandidate] {
        poiCalls += 1; try maybeFail(); return poiResult
    }
    func reverseGeocode(latitude: Double, longitude: Double) async throws -> PlaceCandidate? {
        reverseCalls += 1; try maybeFail(); return reverseResult
    }
    func search(_ query: String, centerLatitude: Double?, centerLongitude: Double?) async throws -> [PlaceCandidate] {
        searchCalls += 1; try maybeFail(); return [PlaceCandidate(name: query, latitude: 1, longitude: 1)]
    }
}

private actor SleepLog {
    var values: [TimeInterval] = []
    func add(_ v: TimeInterval) { values.append(v) }
}

struct PlaceLookupTests {
    let cst = PlaceCandidate(name: "CST", address: nil, city: "Mumbai", latitude: 18.9398, longitude: 72.8355)

    @Test func poiThenCache() async {
        let b = FakeBackend(); await b.set(poi: [cst])
        let l = ThrottledPlaceLookup(backend: b, minInterval: 0, sleep: { _ in })
        let r1 = await l.place(near: 18.93981, longitude: 72.83551)
        let r2 = await l.place(near: 18.93982, longitude: 72.83552)   // same 4-decimal key
        #expect(r1?.name == "CST" && r2?.name == "CST")
        #expect(await b.poiCalls == 1)
    }

    @Test func fallsBackToReverseAndCachesNegative() async {
        let b = FakeBackend()
        let l = ThrottledPlaceLookup(backend: b, minInterval: 0, sleep: { _ in })
        #expect(await l.place(near: 10, longitude: 10) == nil)
        #expect(await l.place(near: 10, longitude: 10) == nil)
        #expect(await b.poiCalls == 1)
        #expect(await b.reverseCalls == 1)
        await b.set(reverse: PlaceCandidate(name: "Marine Drive", latitude: 11, longitude: 11))
        #expect(await l.place(near: 11, longitude: 11)?.name == "Marine Drive")
    }

    @Test func farPoiIsIgnored() async {
        let b = FakeBackend(); await b.set(poi: [cst], reverse: PlaceCandidate(name: "Area", latitude: 0, longitude: 0))
        let l = ThrottledPlaceLookup(backend: b, minInterval: 0, sleep: { _ in })
        #expect(await l.place(near: 19.5, longitude: 72.8)?.name == "Area")
    }

    @Test func errorsReturnNilAndAreNotCached() async {
        let b = FakeBackend(); await b.set(poi: [cst], failFirst: 100)
        let l = ThrottledPlaceLookup(backend: b, minInterval: 0, maxRetries: 2, sleep: { _ in })
        #expect(await l.place(near: 18.9398, longitude: 72.8355) == nil)
        #expect(await b.poiCalls == 3)           // 1 + 2 retries
        #expect(await l.cachedCount == 0)
        await b.set(poi: [cst], failFirst: 0)
        #expect(await l.place(near: 18.9398, longitude: 72.8355)?.name == "CST")
    }

    @Test func backoffAndSpacing() async {
        let log = SleepLog()
        let b = FakeBackend(); await b.set(poi: [cst], failFirst: 2)
        let l = ThrottledPlaceLookup(backend: b, minInterval: 1, maxRetries: 2, sleep: { await log.add($0) })
        #expect(await l.place(near: 18.9398, longitude: 72.8355)?.name == "CST")
        let v = await log.values
        #expect(v.contains(2) && v.contains(4))   // exponential backoff 2s, 4s
    }

    @Test func searchGracefulAndEmptyQuery() async {
        let b = FakeBackend()
        let l = ThrottledPlaceLookup(backend: b, minInterval: 0, sleep: { _ in })
        #expect(await l.search("  ", nearLatitude: nil, nearLongitude: nil).isEmpty)
        #expect(await l.search("cafe", nearLatitude: 1, nearLongitude: 2).count == 1)
        await b.set(failFirst: 100)
        #expect(await l.search("cafe", nearLatitude: nil, nearLongitude: nil).isEmpty)
    }

    @Test func noopLookup() async {
        let n = NoopPlaceLookup()
        #expect(await n.place(near: 0, longitude: 0) == nil)
        #expect(await n.search("x", nearLatitude: nil, nearLongitude: nil).isEmpty)
    }
}

// MARK: Mock importer

struct ServicesMockImporter: PhotoImporting {
    var photos: [PhotoMeta]
    func importItems(_ items: [AnyHashable]) async -> [PhotoMeta] { Array(photos.prefix(items.count)) }
}

struct MockImporterTests {
    @Test func returnsOnePerItem() async {
        let p = PhotoMeta(id: "1", date: nil, latitude: nil, longitude: nil, jpegData: Data())
        let m = ServicesMockImporter(photos: [p, p])
        #expect(await m.importItems(["a" as AnyHashable]).count == 1)
        #expect(await PhotoLibraryImporter().importItems(["not a picker item" as AnyHashable]).isEmpty)
    }
}
