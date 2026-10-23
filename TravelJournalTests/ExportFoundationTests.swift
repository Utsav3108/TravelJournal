import XCTest
import SwiftData
@testable import TravelJournal

@MainActor
final class JourneySnapshotTests: XCTestCase {
    func testSnapshotCopiesStopsLegsPhotosAndTotals() throws {
        let f = JourneyFixtures.fourStops()
        f.stops[1].exportHidden = false
        let s = f.snapshot

        XCTAssertEqual(s.id, f.journey.id)
        XCTAssertEqual(s.timeZoneID, "Asia/Kolkata")
        XCTAssertEqual(s.stops.map(\.placeName), f.stops.map(\.placeName))
        XCTAssertEqual(s.stops.map(\.category), [.landmark, .food, .temple, .stay])
        XCTAssertEqual(s.stops.map(\.exportHidden), [nil, false, nil, nil])
        XCTAssertEqual(s.stops[1].cost, Cost(amount: 180, currency: "INR"))
        XCTAssertEqual(s.stops[0].timeOfDay, s.stops[0].arrivalTime.map { .exact($0) })
        XCTAssertNotNil(s.stops[0].arrivalTime)

        // Legs: n - 1, each joining neighbours.
        XCTAssertEqual(s.legs.count, 3)
        for (i, leg) in s.legs.enumerated() {
            XCTAssertEqual(leg.fromStopID, s.stops[i].id)
            XCTAssertEqual(leg.toStopID, s.stops[i + 1].id)
        }
        XCTAssertEqual(s.legs[0].mode, .taxi)
        XCTAssertEqual(s.legs[0].story, "Leg 1: the driver knew a shortcut.")
        XCTAssertNil(s.legs[1].story)

        // Photos: references only, hero first, real bytes behind them.
        XCTAssertEqual(s.stops.map(\.photos.count), [4, 0, 2, 1])
        XCTAssertTrue(s.stops[0].photos[0].isHero)
        XCTAssertEqual(s.stops[0].photos.filter(\.isHero).count, 1)
        XCTAssertEqual(s.stops[0].photos[1].pixelSize, CGSize(width: 1536, height: 2048))
        XCTAssertTrue(s.stops[0].photos.allSatisfy(\.hasImageData))
        XCTAssertEqual(s.coverPhotoID, s.stops[0].photos[0].id)

        // Totals follow JourneyStats.
        let stats = JourneyStats(journey: f.journey)
        XCTAssertEqual(s.totals.stops, stats.stops)
        XCTAssertEqual(s.totals.km, stats.km)
        XCTAssertEqual(s.totals.travelMinutes, stats.travelMinutes)
        XCTAssertEqual(s.totals.totalMinutes, stats.totalMinutes)
        XCTAssertEqual(s.totals.photos, stats.photos)
        XCTAssertEqual(s.totals.modes, stats.modes)
        XCTAssertEqual(s.totals.spent, [Cost(amount: 180, currency: "INR")])
        XCTAssertEqual(s.mapMode, .show)
    }

    func testSnapshotOfSampleJourneyAndSingleStop() {
        let container = AppContainer.make(inMemory: true)
        let s = JourneySnapshot(journey: SampleData.mumbai(in: ModelContext(container)))
        XCTAssertEqual(s.stops.count, 4)
        XCTAssertEqual(s.legs.map(\.mode), [.taxi, .taxi, .autoRickshaw])
        XCTAssertEqual(s.stops.last?.category, .stay)
        XCTAssertTrue(s.stops[0].photos.allSatisfy { !$0.hasImageData }, "sample photos are placeholders")

        let one = JourneyFixtures.oneStop().snapshot
        XCTAssertEqual(one.stops.count, 1)
        XCTAssertTrue(one.legs.isEmpty)
        XCTAssertNil(one.totals.km)
    }

    func testTotalsSumCostsPerCurrencyInFirstUseOrder() {
        let s = JourneyFixtures.eightStops().snapshot
        XCTAssertEqual(s.stops.count, 8)
        XCTAssertEqual(s.legs.count, 7)
        XCTAssertEqual(s.totals.spent, [Cost(amount: 630, currency: "INR"), Cost(amount: 5, currency: "USD")])
    }

    func testFixtures() {
        XCTAssertEqual(WordLimit.count(JourneyFixtures.hundredWordStory), 100)
        XCTAssertEqual(JourneyFixtures.hundredWordStop().stops[0].story, JourneyFixtures.hundredWordStory)
        XCTAssertTrue(JourneyFixtures.noPhotosStop().stops[0].photos.isEmpty)
        let four = JourneyFixtures.fourPhotosStop().stops[0].photos
        XCTAssertEqual(four.count, 4)
        // Photo-like bytes: a 2048 px JPEG of noise compresses to hundreds of KB, not a flat-colour few KB.
        XCTAssertTrue(four.allSatisfy { ($0.imageData?.count ?? 0) > 200_000 })
        XCTAssertEqual(JourneyFixtures.jpeg(seed: 3), JourneyFixtures.jpeg(seed: 3))
        XCTAssertEqual(JourneyFixtures.withStayStop().stops.map(\.category), [.landmark, .stay, .food])
    }
}

@MainActor
final class ExportPrivacyTests: XCTestCase {
    private func suite() -> UserDefaults {
        let name = "export-privacy-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return d
    }

    func testDefaultsRoundTrip() {
        let store = suite()
        let defaults = ExportPrivacyDefaults(store: store)
        XCTAssertEqual(defaults.load(), ExportPrivacy())
        XCTAssertTrue(defaults.load().hideStayStops, "Stay stops hidden by default")

        let custom = ExportPrivacy(hideStayStops: false, hideCosts: true, hideExactTimes: true, mapMode: .zoomedOut)
        defaults.save(custom)
        XCTAssertEqual(ExportPrivacyDefaults(store: store).load(), custom, "a fresh reader (relaunch) sees the save")

        defaults.reset()
        XCTAssertEqual(defaults.load(), ExportPrivacy())
    }

    func testDecodingFillsMissingKeysWithDefaults() throws {
        let p = try JSONDecoder().decode(ExportPrivacy.self, from: Data(#"{"hideCosts":true,"mapMode":"bogus"}"#.utf8))
        XCTAssertEqual(p, ExportPrivacy(hideStayStops: true, hideCosts: true, hideExactTimes: false, mapMode: .show))
    }

    func testResolvedUsesJourneyOverrideElseDefaults() {
        let defaults = ExportPrivacyDefaults(store: suite())
        defaults.save(ExportPrivacy(hideCosts: true))
        let j = JourneyFixtures.withStayStop().journey

        XCTAssertNil(j.exportPrivacy)
        XCTAssertEqual(ExportPrivacy.resolved(for: j, defaults: defaults), ExportPrivacy(hideCosts: true))

        let override = ExportPrivacy(hideStayStops: false, mapMode: .hidden)
        j.exportPrivacy = override
        XCTAssertNotNil(j.exportPrivacyData)
        XCTAssertEqual(ExportPrivacy.resolved(for: j, defaults: defaults), override)

        j.exportPrivacy = nil
        XCTAssertNil(j.exportPrivacyData)
        XCTAssertEqual(ExportPrivacy.resolved(for: j, defaults: defaults), ExportPrivacy(hideCosts: true))
    }

    func testStopHiddenRule() {
        let f = JourneyFixtures.withStayStop()
        let on = ExportPrivacy(), off = ExportPrivacy(hideStayStops: false)
        XCTAssertEqual(f.stops.map(on.isHidden), [false, true, false])
        XCTAssertEqual(f.stops.map(off.isHidden), [false, false, false])

        f.stops[0].exportHidden = true      // per-stop override wins either way
        f.stops[1].exportHidden = false
        XCTAssertEqual(f.stops.map(on.isHidden), [true, false, false])
        XCTAssertEqual(f.snapshot.stops.map(on.isHidden), [true, false, false])
    }

    func testPrivacyFilterStubReturnsInput() {
        let s = JourneyFixtures.fourStops().snapshot
        XCTAssertEqual(PrivacyFilter.apply(s, ExportPrivacy()).stops.count, s.stops.count)
    }
}
