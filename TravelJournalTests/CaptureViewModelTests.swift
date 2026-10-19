import XCTest
import SwiftData
@testable import TravelJournal

@MainActor
final class CaptureViewModelTests: XCTestCase {
    typealias F = MumbaiFixtures
    var container: ModelContainer!
    var tmp: URL!

    override func setUp() async throws {
        container = AppContainer.make(inMemory: true)
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("capture-\(UUID().uuidString)")
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: tmp) }

    private func make(_ photos: [PhotoMeta], lookup: PlaceLookup = MockPlaceLookup()) -> (CaptureViewModel, Journey, JourneyEditor) {
        let ctx = container.mainContext
        let j = Journey(title: "A Day in Mumbai", date: F.date(8, 0, day: 1))
        ctx.insert(j)
        let editor = JourneyEditor(context: ctx, photos: FilePhotoStore(baseURL: tmp))
        return (CaptureViewModel(importer: MockPhotoImporter(photos: photos), lookup: lookup), j, editor)
    }

    func testClusterLookupEditCommit() async {
        let (vm, journey, editor) = make(F.dayTrip())
        await vm.process(items: [])
        XCTAssertEqual(vm.step, .review)
        await vm.waitForLookups()
        XCTAssertEqual(vm.cards.map(\.name), ["Chhatrapati Shivaji Terminus", "Sardar Pav Bhaji",
                                              "Siddhivinayak Temple", "Hotel Marine Plaza"])
        XCTAssertEqual(vm.unplaced.map(\.id), ["bare"])

        // Edit: split a CST photo off and merge it back, rename the hotel, assign the bare photo to CST, drop nothing.
        vm.split(photoID: "p3", from: vm.cards[0].id)
        XCTAssertEqual(vm.cards.count, 5)
        vm.mergeWithPrevious(vm.cards[1].id)
        XCTAssertEqual(vm.cards.count, 4)
        vm.rename(vm.cards[3].id, to: "Taj Hotel")
        vm.assign(photoID: "bare", toCard: vm.cards[0].id)
        XCTAssertTrue(vm.unplaced.isEmpty)

        let summary = vm.commit(to: journey, editor: editor)
        XCTAssertEqual(summary.stopsCreated, 4)
        XCTAssertEqual(summary.photosSaved, 13)
        XCTAssertTrue(summary.skipped.isEmpty)
        let stops = journey.orderedStops
        XCTAssertEqual(stops.map(\.placeName), ["Chhatrapati Shivaji Terminus", "Sardar Pav Bhaji", "Siddhivinayak Temple", "Taj Hotel"])
        XCTAssertEqual(stops.map { $0.photos.count }, [4, 4, 3, 2])
        XCTAssertEqual(journey.orderedLegs.count, 3)
        XCTAssertTrue(LegSync.isConsistent(stops))
        XCTAssertEqual(stops[0].arrivalTime, F.date(9, 0))
        XCTAssertEqual(stops[1].timeSpentMinutes, 30)
        XCTAssertEqual(journey.city, "Mumbai")
        XCTAssertEqual(journey.date, Journey.defaultDate(photoDates: [F.date(9, 0)]))
        XCTAssertNotNil(stops[0].hero)
        if case .done(let s) = vm.step { XCTAssertEqual(s, summary) } else { XCTFail("expected done") }
    }

    func testMaxFourPhotosPerStopExtrasSkipped() async {
        let six = (1...6).map { F.photo("s\($0)", .cst, 9, $0, jpeg: F.jpeg(seed: $0)) }
        let (vm, journey, editor) = make(six)
        await vm.process(items: [])
        XCTAssertEqual(vm.cards.count, 1)
        let s = vm.commit(to: journey, editor: editor)
        XCTAssertEqual(journey.orderedStops[0].photos.count, 4)
        XCTAssertEqual(s.photosSaved, 4)
        XCTAssertEqual(s.skipped.map(\.id), ["s5", "s6"])
    }

    func testDropAndFindPlaceForGPSLessCard() async {
        let photos = [F.photo("a", .cst, 9, 0, jpeg: F.jpeg(seed: 1)), F.photo("b", nil, 12, 0, jpeg: F.jpeg(seed: 2)),
                      F.photo("c", .hotel, 17, 0, jpeg: F.jpeg(seed: 3))]
        let (vm, journey, editor) = make(photos)
        await vm.process(items: [])
        await vm.waitForLookups()
        XCTAssertEqual(vm.cards.count, 3)
        XCTAssertFalse(vm.cards[1].hasLocation)
        XCTAssertTrue(vm.cards[1].needsPlace)
        let found = await vm.search("pav", near: vm.cards[1].id)
        XCTAssertEqual(found.first?.name, "Sardar Pav Bhaji")
        vm.applyPlace(found[0], to: vm.cards[1].id)
        vm.drop(vm.cards[2].id)
        vm.commit(to: journey, editor: editor)
        XCTAssertEqual(journey.orderedStops.map(\.placeName), ["Chhatrapati Shivaji Terminus", "Sardar Pav Bhaji"])
        XCTAssertEqual(journey.orderedStops[1].latitude!, F.Place.pavBhaji.latitude, accuracy: 1e-6)
        XCTAssertEqual(journey.orderedLegs.count, 1)
    }

    func testLookupsRunSeriallyAndRespectCap() async {
        final class Spy: PlaceLookup, @unchecked Sendable {
            private let lock = NSLock()
            private var inFlight = 0, calls = 0, maxInFlight = 0
            var stats: (calls: Int, max: Int) { lock.lock(); defer { lock.unlock() }; return (calls, maxInFlight) }
            func place(near latitude: Double, longitude: Double) async -> PlaceCandidate? {
                lock.lock(); inFlight += 1; calls += 1; maxInFlight = max(maxInFlight, inFlight); lock.unlock()
                try? await Task.sleep(for: .milliseconds(20))
                lock.lock(); inFlight -= 1; lock.unlock()
                return PlaceCandidate(name: "P", address: nil, city: nil, latitude: latitude, longitude: longitude)
            }
            func search(_ q: String, nearLatitude: Double?, nearLongitude: Double?) async -> [PlaceCandidate] { [] }
        }
        let spy = Spy()
        let (vm, _, _) = make(F.dayTrip(withJPEG: false, includeUnplaced: false), lookup: spy)
        vm.maxLookups = 3
        await vm.process(items: [])
        await vm.waitForLookups()
        XCTAssertEqual(spy.stats.max, 1)
        XCTAssertEqual(spy.stats.calls, 3)
        XCTAssertEqual(vm.cards.filter { $0.lookup == .notFound }.count, 1)
    }

    func testEmptyImportReturnsToSource() async {
        let (vm, _, _) = make([])
        await vm.process(items: [])
        XCTAssertEqual(vm.step, .chooseSource)
        XCTAssertNotNil(vm.notice)
    }
}
