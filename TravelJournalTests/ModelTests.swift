import XCTest
import SwiftData
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import TravelJournal

@MainActor
final class ModelTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var editor: JourneyEditor!

    override func setUp() async throws {
        container = AppContainer.make(inMemory: true)
        context = ModelContext(container)
        editor = JourneyEditor(context: context, photos: NoopPhotoStore())
    }

    private func makeJourney(_ names: [String]) -> (Journey, [Stop]) {
        let j = Journey(title: "T")
        context.insert(j)
        let stops = names.map { Stop(placeName: $0) }
        for s in stops { editor.addStop(s, to: j) }
        return (j, stops)
    }

    private func names(_ j: Journey) -> [String] { j.orderedStops.map(\.placeName) }

    func testAddKeepsDenseOrderAndLegs() {
        let (j, _) = makeJourney(["A", "B", "C"])
        XCTAssertEqual(j.orderedStops.map(\.orderIndex), [0, 1, 2])
        XCTAssertTrue(LegSync.isConsistent(j.orderedStops))
        XCTAssertEqual(j.orderedLegs.count, 2)
        editor.addStop(Stop(placeName: "X"), to: j, at: 1)
        XCTAssertEqual(names(j), ["A", "X", "B", "C"])
        XCTAssertEqual(j.orderedStops.map(\.orderIndex), [0, 1, 2, 3])
        XCTAssertTrue(LegSync.isConsistent(j.orderedStops))
    }

    func testReorderKeepsStillAdjacentLegs() {
        let (j, s) = makeJourney(["A", "B", "C", "D"])
        s[0].outgoingLeg?.story = "ab"
        s[2].outgoingLeg?.story = "cd"
        // Move D before C: A B D C ; A->B stays, C->D lost
        editor.moveStops(in: j, from: IndexSet(integer: 3), to: 2)
        XCTAssertEqual(names(j), ["A", "B", "D", "C"])
        XCTAssertTrue(LegSync.isConsistent(j.orderedStops))
        XCTAssertEqual(s[0].outgoingLeg?.story, "ab")
        XCTAssertNil(s[2].outgoingLeg?.story)
        XCTAssertNil(s[2].incomingLeg?.story)
        XCTAssertEqual(j.orderedLegs.count, 3)
    }

    func testReconcileIsIdempotent() throws {
        let (j, _) = makeJourney(["A", "B", "C"])
        let ids = j.orderedLegs.map(\.id)
        LegSync.reconcile(stops: j.orderedStops, context: context)
        LegSync.reconcile(stops: j.orderedStops, context: context)
        XCTAssertEqual(j.orderedLegs.map(\.id), ids)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Leg>()), 2)
    }

    func testDeleteMiddleStopYieldsOneBlankLeg() throws {
        let (j, s) = makeJourney(["A", "B", "C"])
        s[0].outgoingLeg?.story = "x"
        s[1].outgoingLeg?.story = "y"
        editor.deleteStop(s[1], in: j)
        XCTAssertEqual(names(j), ["A", "C"])
        XCTAssertEqual(j.orderedStops.map(\.orderIndex), [0, 1])
        XCTAssertTrue(LegSync.isConsistent(j.orderedStops))
        XCTAssertEqual(j.orderedLegs.count, 1)
        XCTAssertNil(j.orderedLegs[0].story)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Leg>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Stop>()), 2)
    }

    func testDeleteFirstAndLastStop() {
        let (j, s) = makeJourney(["A", "B", "C"])
        s[1].outgoingLeg?.story = "bc"
        editor.deleteStop(s[0], in: j)
        XCTAssertEqual(names(j), ["B", "C"])
        XCTAssertEqual(s[1].outgoingLeg?.story, "bc")
        editor.deleteStop(s[2], in: j)
        XCTAssertEqual(names(j), ["B"])
        XCTAssertTrue(LegSync.isConsistent(j.orderedStops))
        XCTAssertEqual(j.orderedLegs.count, 0)
    }

    func testWordLimit() {
        XCTAssertEqual(WordLimit.count("don't 180 times, please!"), 4)
        let hundred = (1...100).map { "w\($0)" }.joined(separator: " ")
        XCTAssertEqual(WordLimit.count(hundred), 100)
        XCTAssertTrue(WordLimit.isWithin(hundred))
        let over = hundred + " extra words"
        XCTAssertEqual(WordLimit.count(over), 102)
        XCTAssertEqual(WordLimit.truncated(over), hundred)
        XCTAssertEqual(WordLimit.truncated("short text"), "short text")
        XCTAssertEqual(WordLimit.remaining("one two"), 98)
    }

    func testEnumFallbacks() {
        let s = Stop(placeName: "P")
        s.categoryRaw = "mystery"
        XCTAssertEqual(s.category, .other)
        s.category = .food
        XCTAssertEqual(s.categoryRaw, "food")
        let l = Leg()
        l.modeRaw = "hoverboard"
        XCTAssertEqual(l.mode, .walk)
        s.rating = 9
        XCTAssertEqual(s.rating, 5)
    }

    func testSampleDataAndStats() throws {
        let j = SampleData.mumbai(in: context)
        try context.save()
        XCTAssertEqual(names(j), ["Chhatrapati Shivaji Terminus", "Sardar Pav Bhaji", "Siddhivinayak Temple", "Hotel check-in"])
        XCTAssertEqual(j.orderedStops.map { $0.photos.count }, [4, 3, 1, 0])
        XCTAssertTrue(LegSync.isConsistent(j.orderedStops))
        let st = JourneyStats(journey: j)
        XCTAssertEqual(st.stops, 4)
        XCTAssertEqual(st.photos, 8)
        XCTAssertEqual(st.km, 15.2, accuracy: 0.001)
        XCTAssertEqual(st.travelMinutes, 63)
        XCTAssertEqual(st.spentMinutes, 135)
        XCTAssertEqual(st.totalMinutes, 198)
        XCTAssertEqual(st.money, ["INR": 180])
        XCTAssertEqual(st.modes, [.taxi, .autoRickshaw])
        XCTAssertEqual(j.displayCity, "Mumbai")
        XCTAssertEqual(j.coverPhoto?.id, j.orderedStops.first?.hero?.id, "cover is the first stop's hero")
        XCTAssertEqual(j.postmarkText, "ARRIVED · 19 OCT 2026 · MUMBAI")
    }

    func testStatsMissingDataAndMultiCurrency() {
        let (j, s) = makeJourney(["A", "B"])
        s[0].cost = Cost(amount: 10, currency: "USD")
        s[1].cost = Cost(amount: 5, currency: "USD")
        var st = JourneyStats(journey: j)
        XCTAssertFalse(st.hasKm)
        XCTAssertEqual(st.money, ["USD": 15])
        XCTAssertTrue(st.modes.isEmpty)
        s[1].cost = Cost(amount: 100, currency: "INR")
        st = JourneyStats(journey: j)
        XCTAssertEqual(st.money.count, 2)
    }

    func testDerivedDefaults() {
        let d1 = Date(timeIntervalSince1970: 1_800_000_000)
        let d2 = d1.addingTimeInterval(3600)
        XCTAssertEqual(Journey.defaultDate(photoDates: [d2, d1]), Calendar.current.startOfDay(for: d1))
        let (j, s) = makeJourney(["A"])
        s[0].cityHint = "Pune"
        XCTAssertEqual(j.displayCity, "Pune")
        j.city = "Goa"
        XCTAssertEqual(j.displayCity, "Goa")
        XCTAssertNil(j.coverPhoto)
    }

    func testHeroPromotionAndPhotoLimit() throws {
        let store = ModelPhotoStore()
        let (_, s) = makeJourney(["A"])
        let jpeg = try Self.makeJPEG(width: 3000, height: 1500)
        for _ in 0..<4 { try store.importPhoto(data: jpeg, into: s[0]) }
        XCTAssertThrowsError(try store.importPhoto(data: jpeg, into: s[0])) {
            XCTAssertEqual($0 as? PhotoStoreError, .limitReached)
        }
        let photos = s[0].orderedPhotos
        XCTAssertEqual(photos.map(\.isHero), [true, false, false, false])
        XCTAssertEqual(max(photos[0].pixelWidth, photos[0].pixelHeight), 2048)
        let stored = try XCTUnwrap(photos[0].imageData, "the display JPEG lives on the model, so it syncs")
        let src = try XCTUnwrap(CGImageSourceCreateWithData(stored as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 2048)

        store.removePhoto(photos[0], from: s[0])
        XCTAssertEqual(s[0].photos.count, 3)
        XCTAssertEqual(s[0].photos.filter(\.isHero).count, 1)
        XCTAssertTrue(s[0].orderedPhotos[0].isHero)
    }

    /// Photo bytes are part of the rows, so deleting a stop or a journey removes them with no files left to clean up.
    func testDeletingStopAndJourneyRemovesPhotoRows() throws {
        let store = ModelPhotoStore()
        let (j, s) = makeJourney(["A", "B"])
        let jpeg = try Self.makeJPEG(width: 800, height: 600)
        try store.importPhoto(data: jpeg, into: s[0])
        try store.importPhoto(data: jpeg, into: s[1])
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<StopPhoto>()), 2)

        editor.deleteStop(s[0], in: j)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<StopPhoto>()), 1, "the stop's photo goes with it")

        editor.deleteJourney(j)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<StopPhoto>()), 0)
    }

    private static func makeJPEG(width: Int, height: Int) throws -> Data {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return data as Data
    }
}
