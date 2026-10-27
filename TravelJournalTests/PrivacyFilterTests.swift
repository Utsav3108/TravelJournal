import XCTest
import SwiftData
@testable import TravelJournal

@MainActor
final class PrivacyFilterTests: XCTestCase {
    typealias Snap = JourneySnapshot
    typealias Leg = JourneySnapshot.LegSnapshot

    private let showAll = ExportPrivacy(hideStayStops: false)

    /// legs[i] joins stops[i] -> stops[i + 1].
    private func assertLegInvariant(_ s: Snap, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(s.legs.count, max(s.stops.count - 1, 0), file: file, line: line)
        for (i, leg) in s.legs.enumerated() {
            XCTAssertEqual(leg.fromStopID, s.stops[i].id, file: file, line: line)
            XCTAssertEqual(leg.toStopID, s.stops[i + 1].id, file: file, line: line)
        }
    }

    // MARK: Hidden stops

    func testHotelHiddenByDefaultLeavesNoTrace() {
        let f = JourneyFixtures.withStayStop()
        var s = f.snapshot
        let hotel = s.stops[1]
        s.coverPhotoID = hotel.photos[0].id
        let out = PrivacyFilter.apply(s, ExportPrivacy())

        XCTAssertEqual(out.stops.map(\.placeName), ["Gateway of India", "Leopold Cafe"])
        XCTAssertFalse(out.stops.contains { $0.id == hotel.id })
        assertLegInvariant(out)
        XCTAssertFalse(out.legs.contains { $0.fromStopID == hotel.id || $0.toStopID == hotel.id || $0.id == hotel.id })

        // Merged leg: taxi 2.5 km / 12 min + walk 3.5 km / 16 min.
        XCTAssertEqual(out.legs[0].km, 6.0)
        XCTAssertEqual(out.legs[0].minutes, 28)
        XCTAssertEqual(out.legs[0].mode, .walk)
        XCTAssertEqual(out.legs[0].id, s.legs[0].id)
        XCTAssertNil(out.legs[0].story, "a merged leg may describe the hidden stop")

        // Totals: no hotel stop, photo, minutes or cost.
        XCTAssertEqual(out.totals, Snap.Totals(stops: out.stops, legs: out.legs))
        XCTAssertEqual(out.totals.stops, 2)
        XCTAssertEqual(out.totals.km, 6.0)
        XCTAssertEqual(out.totals.travelMinutes, 28)
        XCTAssertEqual(out.totals.stopMinutes, 30 + 60)
        XCTAssertEqual(out.totals.photos, 2)
        XCTAssertEqual(out.totals.spent, [Cost(amount: 600, currency: "INR")])
        XCTAssertEqual(out.totals.modes, [.walk])

        // Cover falls back to the first visible hero, never the hotel's photo.
        XCTAssertEqual(out.coverPhotoID, out.stops[0].hero?.id)
        let hiddenPhotos = Set(hotel.photos.map(\.id))
        XCTAssertFalse(out.stops.flatMap(\.photos).contains { hiddenPhotos.contains($0.id) })
    }

    func testCoverOfVisibleStopIsKept() {
        var s = JourneyFixtures.withStayStop().snapshot
        s.coverPhotoID = s.stops[2].photos[0].id
        XCTAssertEqual(PrivacyFilter.apply(s, ExportPrivacy()).coverPhotoID, s.stops[2].photos[0].id)
    }

    func testPerStopOverrides() {
        let f = JourneyFixtures.withStayStop()
        f.stops[1].exportHidden = false                 // keep the hotel
        f.stops[2].exportHidden = true                  // hide the cafe
        let out = PrivacyFilter.apply(f.snapshot, ExportPrivacy())
        XCTAssertEqual(out.stops.map(\.placeName), ["Gateway of India", "Taj Mahal Palace"])
        assertLegInvariant(out)
        XCTAssertEqual(out.totals.spent, [Cost(amount: 24000, currency: "INR")])
    }

    func testNothingHiddenKeepsStopsAndLegs() {
        let s = JourneyFixtures.eightStops().snapshot
        let out = PrivacyFilter.apply(s, showAll)
        XCTAssertEqual(out.stops, s.stops)
        XCTAssertEqual(out.legs, s.legs)
        XCTAssertEqual(out.totals, s.totals)
    }

    func testHiddenMiddleStopInEightStops() {
        let s = JourneyFixtures.eightStops().snapshot
        let out = PrivacyFilter.apply(s, ExportPrivacy())
        XCTAssertEqual(out.stops.count, 7)
        XCTAssertFalse(out.stops.contains { $0.category == .stay })
        assertLegInvariant(out)
        // Legs 3 (auto, 4.5 km, 20 min) and 4 (local train, 5.5 km, 24 min) merge.
        XCTAssertEqual(out.legs[2].km, 10.0)
        XCTAssertEqual(out.legs[2].minutes, 44)
        XCTAssertEqual(out.legs[2].mode, .localTrain)
        XCTAssertNil(out.legs[2].story, "a merged leg may describe the hidden stop")
        XCTAssertEqual(Array(out.legs[0..<2]), Array(s.legs[0..<2]))
        XCTAssertEqual(Array(out.legs[3...]), Array(s.legs[4...]))
        XCTAssertEqual(out.totals.photos, s.totals.photos - 1)
        XCTAssertEqual(out.totals.km, s.totals.km)              // merged legs keep their distance
        XCTAssertEqual(out.totals.travelMinutes, s.totals.travelMinutes)
    }

    func testConsecutiveHiddenStopsMergeThreeLegs() {
        let f = JourneyFixtures.eightStops()
        f.stops[4].exportHidden = true                  // temple, right after the hotel
        let s = f.snapshot
        let out = PrivacyFilter.apply(s, ExportPrivacy())
        XCTAssertEqual(out.stops.count, 6)
        assertLegInvariant(out)
        let merged = out.legs[2]
        XCTAssertEqual(merged.id, s.legs[2].id)
        XCTAssertEqual(merged.km, 4.5 + 5.5 + 6.5)
        XCTAssertEqual(merged.minutes, 20 + 24 + 28)
        XCTAssertEqual(merged.mode, .bus)
        XCTAssertNil(merged.story, "a merged leg may describe the hidden stop")
    }

    func testHiddenFirstStopDropsItsLeg() {
        let f = JourneyFixtures.fourStops()
        f.stops[0].exportHidden = true
        let s = f.snapshot
        let out = PrivacyFilter.apply(s, showAll)
        XCTAssertEqual(out.stops.map(\.id), Array(s.stops.dropFirst().map(\.id)))
        XCTAssertEqual(out.legs, Array(s.legs.dropFirst()))
        assertLegInvariant(out)
        // The cover was the first stop's hero: it moves to the next visible hero.
        XCTAssertEqual(s.coverPhotoID, s.stops[0].photos[0].id)
        XCTAssertEqual(out.coverPhotoID, s.stops[2].photos[0].id)  // stop 1 has no photos
    }

    func testHiddenLastStopDropsItsLeg() {
        let s = JourneyFixtures.fourStops().snapshot     // ends at the hotel
        let out = PrivacyFilter.apply(s, ExportPrivacy())
        XCTAssertEqual(out.stops.map(\.id), Array(s.stops.dropLast().map(\.id)))
        XCTAssertEqual(out.legs, Array(s.legs.dropLast()))
        assertLegInvariant(out)
        XCTAssertEqual(out.totals.stops, 3)
    }

    func testAllHidden() {
        let f = JourneyFixtures.withStayStop()
        for stop in f.stops { stop.exportHidden = true }
        let out = PrivacyFilter.apply(f.snapshot, ExportPrivacy())
        XCTAssertTrue(out.stops.isEmpty)
        XCTAssertTrue(out.legs.isEmpty)
        XCTAssertNil(out.coverPhotoID)
        XCTAssertEqual(out.totals.stops, 0)
        XCTAssertNil(out.totals.km)
        XCTAssertEqual(out.totals.photos, 0)
        XCTAssertTrue(out.totals.spent.isEmpty)
        XCTAssertEqual(out.title, f.journey.title)
    }

    func testEmptySnapshot() {
        let s = hand(stops: [], legs: [])
        XCTAssertTrue(PrivacyFilter.apply(s, ExportPrivacy()).stops.isEmpty)
    }

    // MARK: Leg merge rules

    func testMergeModeAndNilHandling() {
        let a = UUID(), b = UUID()
        func leg(_ mode: TransportMode?, _ km: Double?, _ min: Int?, _ story: String? = nil) -> Leg {
            Leg(id: UUID(), fromStopID: UUID(), toStopID: UUID(), mode: mode, km: km, minutes: min, story: story)
        }
        // Tie on minutes: the earlier part's mode.
        XCTAssertEqual(PrivacyFilter.mergedLeg([leg(.taxi, 1, 10), leg(.bus, 2, 10)], from: a, to: b).mode, .taxi)
        // The longest leg without a mode does not win; the longest with one does.
        let m = PrivacyFilter.mergedLeg([leg(.walk, nil, 5), leg(nil, nil, 50), leg(.metro, nil, 8)], from: a, to: b)
        XCTAssertEqual(m.mode, .metro)
        XCTAssertNil(m.km)
        XCTAssertEqual(m.minutes, 63)
        XCTAssertEqual(m.fromStopID, a)
        XCTAssertEqual(m.toStopID, b)
        // No modes, no minutes, partial km, stories dropped.
        let n = PrivacyFilter.mergedLeg([leg(nil, 2, nil, "One."), leg(nil, nil, nil, "  "), leg(nil, nil, nil, "Two.")],
                                        from: a, to: b)
        XCTAssertNil(n.mode)
        XCTAssertEqual(n.km, 2)
        XCTAssertNil(n.minutes)
        XCTAssertNil(n.story)
    }

    // MARK: Costs, times, map

    func testHideCosts() {
        let s = JourneyFixtures.eightStops().snapshot
        XCTAssertFalse(s.totals.spent.isEmpty)
        let out = PrivacyFilter.apply(s, ExportPrivacy(hideStayStops: false, hideCosts: true))
        XCTAssertTrue(out.stops.allSatisfy { $0.cost == nil })
        XCTAssertTrue(out.totals.spent.isEmpty)
        XCTAssertEqual(out.stops.count, 8)
    }

    func testExactTimesKeptByDefault() {
        let s = JourneyFixtures.fourStops().snapshot
        let out = PrivacyFilter.apply(s, showAll)
        XCTAssertEqual(out.stops.map(\.arrivalTime), s.stops.map(\.arrivalTime))
        XCTAssertEqual(out.stops.map(\.timeOfDay), s.stops.map(\.timeOfDay))
    }

    func testHideExactTimesBucketsInJourneyTimeZone() {
        // 08:00, 09:30 ... 18:30 IST.
        let s = JourneyFixtures.eightStops().snapshot
        let out = PrivacyFilter.apply(s, ExportPrivacy(hideStayStops: false, hideExactTimes: true))
        XCTAssertTrue(out.stops.allSatisfy { $0.arrivalTime == nil })
        XCTAssertEqual(out.stops.map(\.timeOfDay),
                       [.morning, .morning, .morning, .afternoon, .afternoon, .afternoon, .evening, .evening]
                           .map { .bucket($0) })
    }

    func testDayPartBoundariesInKolkata() {
        let tz = TimeZone(identifier: "Asia/Kolkata")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        func at(_ h: Int, _ m: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: h, minute: m))! }
        let cases: [(Int, Int, Snap.DayPart)] = [
            (0, 0, .evening), (4, 59, .evening), (5, 0, .morning), (11, 59, .morning),
            (12, 0, .afternoon), (16, 59, .afternoon), (17, 0, .evening), (23, 59, .evening),
        ]
        for (h, m, part) in cases {
            XCTAssertEqual(PrivacyFilter.dayPart(for: at(h, m), in: tz), part, "\(h):\(m)")
        }
        // 11:30 IST is 06:00 UTC: bucketed in the journey's zone (morning), not by the UTC hour.
        XCTAssertEqual(PrivacyFilter.dayPart(for: at(11, 30), in: TimeZone(identifier: "UTC")!), .morning)
        XCTAssertEqual(PrivacyFilter.dayPart(for: at(12, 30), in: TimeZone(identifier: "UTC")!), .morning)
        XCTAssertEqual(PrivacyFilter.dayPart(for: at(12, 30), in: tz), .afternoon)

        // Through apply: the snapshot's own zone is used; a stop with no time stays nil.
        let stop = { (t: Date?) in self.stop(arrival: t) }
        let s = hand(stops: [stop(at(16, 59)), stop(at(17, 0)), stop(nil)], timeZoneID: "Asia/Kolkata")
        let out = PrivacyFilter.apply(s, ExportPrivacy(hideExactTimes: true))
        XCTAssertEqual(out.stops.map(\.timeOfDay), [.bucket(.afternoon), .bucket(.evening), nil])
    }

    func testMapModePassthrough() {
        let s = JourneyFixtures.oneStop().snapshot
        for mode in ExportPrivacy.MapMode.allCases {
            XCTAssertEqual(PrivacyFilter.apply(s, ExportPrivacy(mapMode: mode)).mapMode, mode)
        }
    }

    func testJourneyLevelFieldsUntouched() {
        let s = JourneyFixtures.withStayStop().snapshot
        let out = PrivacyFilter.apply(s, ExportPrivacy(hideCosts: true, hideExactTimes: true, mapMode: .hidden))
        XCTAssertEqual(out.id, s.id)
        XCTAssertEqual(out.title, s.title)
        XCTAssertEqual(out.date, s.date)
        XCTAssertEqual(out.city, s.city)
        XCTAssertEqual(out.postmark, s.postmark)
        XCTAssertEqual(out.introNote, s.introNote)
        XCTAssertEqual(out.closingNote, s.closingNote)
    }

    // MARK: Hand-built snapshots

    private func stop(arrival: Date?, category: StopCategory = .landmark) -> Snap.StopSnapshot {
        Snap.StopSnapshot(id: UUID(), placeName: "Stop", story: "", highlight: nil, rating: nil, review: nil,
                          category: category, latitude: nil, longitude: nil, cityHint: nil, arrivalTime: arrival,
                          timeOfDay: arrival.map { .exact($0) }, timeSpentMinutes: nil, cost: nil, exportHidden: nil,
                          photos: [])
    }

    private func hand(stops: [Snap.StopSnapshot], legs: [Leg]? = nil, timeZoneID: String = "Asia/Kolkata") -> Snap {
        let legs = legs ?? stops.indices.dropLast().map { i in
            Leg(id: UUID(), fromStopID: stops[i].id, toStopID: stops[i + 1].id, mode: nil, km: nil, minutes: nil,
                story: nil)
        }
        return Snap(id: UUID(), title: "Hand", date: Date(timeIntervalSince1970: 0), timeZoneID: timeZoneID,
                    city: nil, country: nil, postmark: "ARRIVED", coverPhotoID: nil, introNote: nil, closingNote: nil,
                    stops: stops, legs: legs)
    }
}
