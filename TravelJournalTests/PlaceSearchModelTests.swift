import XCTest
@testable import TravelJournal

private struct FakeLookup: PlaceLookup {
    /// Answers per query, with an optional delay so a slow answer can arrive after a newer one.
    var answers: [String: [PlaceCandidate]] = [:]
    var delays: [String: Duration] = [:]

    func place(near latitude: Double, longitude: Double) async -> PlaceCandidate? { nil }
    func search(_ query: String, nearLatitude: Double?, nearLongitude: Double?) async -> [PlaceCandidate] {
        if let d = delays[query] { try? await Task.sleep(for: d) }
        return answers[query] ?? []
    }
}

@MainActor
final class PlaceSearchModelTests: XCTestCase {
    private let taj = PlaceCandidate(name: "Taj Mahal Palace", address: "Apollo Bunder", city: "Mumbai",
                                     latitude: 18.922, longitude: 72.833)
    private let gate = PlaceCandidate(name: "Gateway of India", address: nil, city: "Mumbai",
                                      latitude: 18.921, longitude: 72.834)

    private func model(_ lookup: FakeLookup, query: String = "") -> PlaceSearchModel {
        PlaceSearchModel(lookup: lookup, latitude: nil, longitude: nil, query: query, debounce: .milliseconds(20))
    }

    private func wait(_ m: PlaceSearchModel, until done: (PlaceSearchModel) -> Bool) async {
        for _ in 0..<200 where !done(m) { try? await Task.sleep(for: .milliseconds(5)) }
    }

    func testStartsIdleWithAPrompt() {
        let m = model(FakeLookup())
        XCTAssertEqual(m.state, .idle)
        XCTAssertEqual(m.message, "Type a place name to search.")
    }

    func testTypingSearchesAfterAPause() async {
        let m = model(FakeLookup(answers: ["taj hotel": [taj]]))
        m.query = "taj hotel"
        m.queryChanged()
        XCTAssertEqual(m.state, .idle, "nothing runs until the pause")
        await wait(m) { $0.state == .results }
        XCTAssertEqual(m.results, [taj])
        XCTAssertNil(m.message)
    }

    func testSubmitSearchesAtOnce() async {
        let m = model(FakeLookup(answers: ["gateway": [gate]]), query: "gateway")
        m.submit()
        await wait(m) { $0.state == .results }
        XCTAssertEqual(m.results, [gate])
    }

    func testNoMatchesShowsTheConnectionHint() async {
        let m = model(FakeLookup(), query: "zzz")
        m.submit()
        await wait(m) { $0.state == .empty }
        XCTAssertEqual(m.message, "No places found. Searching needs an internet connection.")
    }

    func testANewerQueryDropsAnOlderSlowAnswer() async {
        let lookup = FakeLookup(answers: ["taj": [taj], "gateway": [gate]], delays: ["taj": .milliseconds(150)])
        let m = model(lookup)
        m.query = "taj"; m.submit()
        try? await Task.sleep(for: .milliseconds(20))
        m.query = "gateway"; m.submit()
        await wait(m) { $0.state == .results }
        try? await Task.sleep(for: .milliseconds(250))   // the slow "taj" answer lands now and must be ignored
        XCTAssertEqual(m.results, [gate])
    }

    func testClearingTheQueryResetsTheResults() async {
        let m = model(FakeLookup(answers: ["taj": [taj]]), query: "taj")
        m.submit()
        await wait(m) { $0.state == .results }
        m.query = "  "
        m.queryChanged()
        XCTAssertEqual(m.state, .idle)
        XCTAssertTrue(m.results.isEmpty)
    }
}

#if os(macOS)
import SwiftUI
import AppKit

@MainActor
final class PlaceSearchSheetLayoutTests: XCTestCase {
    /// A Mac sheet sizes itself to its content; the results list must not collapse to nothing.
    func testSheetHasRoomForResultsOnTheMac() {
        let stop = Stop(placeName: "Taj Hotel")
        let hosting = NSHostingController(rootView: PlaceSearchSheet(stop: stop))
        let size = hosting.sizeThatFits(in: CGSize(width: 2000, height: 2000))
        XCTAssertGreaterThanOrEqual(size.width, 460)
        XCTAssertGreaterThanOrEqual(size.height, 380)
    }
}
#endif
