import XCTest
@testable import TravelJournal

final class LibraryIndexTests: XCTestCase {
    private func story(_ n: Int, title: String = "T", city: String? = "X", country: String? = "Y",
                       dateText: String = "1 Jan 2026") -> LibraryStory {
        LibraryStory(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!,
                     title: title, date: Date(timeIntervalSince1970: 1_700_000_000 - Double(n) * 86_400),
                     dateText: dateText, city: city, country: country, weight: 1, coverPath: nil)
    }
    private func fx(_ n: Int, single: Bool = false, noCountryEvery: Int? = nil) -> [LibraryStory] {
        LibraryFixtures.stories(count: n, singleCountry: single, noCountryEvery: noCountryEvery)
    }
    private func spines(_ s: LibraryShelf) -> Int {
        s.slots.filter { if case .spine = $0 { return true } else { return false } }.count
    }

    func testSlotRule() {
        let s10 = LibraryIndex.shelves(from: (1...10).map { story($0) })
        XCTAssertEqual(s10.count, 1)   // 10 stories: no Recent
        XCTAssertEqual(spines(s10[0]), 10)
        XCTAssertEqual(s10[0].slots.count, 10)

        let c11 = LibraryIndex.shelves(from: (1...11).map { story($0) }).first { $0.id == "city:X" }!
        XCTAssertEqual(c11.slots.count, 10)
        XCTAssertEqual(c11.slots.last, .more(count: 2, firstHiddenIndex: 9))

        let s19 = LibraryIndex.shelves(from: (1...19).map { story($0) }).first { $0.id == "city:X" }!
        XCTAssertEqual(spines(s19), 9)
        XCTAssertEqual(s19.slots.last, .more(count: 10, firstHiddenIndex: 9))
    }

    func testNewestFirstInsideShelves() {
        for sh in LibraryIndex.shelves(from: fx(19).shuffled()) {
            XCTAssertEqual(sh.stories.map(\.date), sh.stories.map(\.date).sorted(by: >))
        }
    }

    func testShelfOrderingByNewestStory() {
        let shelves = LibraryIndex.shelves(from: fx(9))
        XCTAssertEqual(Array(shelves.map(\.title).prefix(3)), ["India", "Japan", "France"])
        XCTAssertFalse(shelves.contains { $0.id == "recent" })
    }

    func testFewStoriesSingleAllShelf() {
        let s = LibraryIndex.shelves(from: fx(6))
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].title, "All Stories")
        XCTAssertEqual(s[0].scope.kind, .all)
        XCTAssertEqual(s[0].id, "all")
    }

    func testRecentOnlyWhenOverTen() {
        XCTAssertFalse(LibraryIndex.shelves(from: fx(10)).contains { $0.id == "recent" })
        let s = LibraryIndex.shelves(from: fx(11))
        XCTAssertEqual(s.first?.id, "recent")
        XCTAssertEqual(s.first?.stories.count, 10)
        XCTAssertEqual(s.first?.scope.kind, .recent)
    }

    func testSingleCountryGroupsByCity() {
        let s = LibraryIndex.shelves(from: fx(12, single: true))
        XCTAssertTrue(s.dropFirst().allSatisfy { $0.id.hasPrefix("city:") })
        XCTAssertEqual(Set(s.dropFirst().map(\.title)), ["Mumbai", "Delhi", "Goa", "Jaipur"])
    }

    func testMissingCountryOtherLast() {
        let s = LibraryIndex.shelves(from: fx(12, noCountryEvery: 4))
        XCTAssertEqual(s.last?.id, "other")
        XCTAssertEqual(s.last?.scope.kind, .other)
        XCTAssertEqual(s.last?.stories.count, 3)
        var xs = fx(8); xs[0].country = "  "
        XCTAssertEqual(LibraryIndex.shelves(from: xs).last?.id, "other")
    }

    func testStableColors() {
        XCTAssertEqual(LibraryIndex.colorIndex(forCategory: "India"), 4)
        XCTAssertEqual(LibraryIndex.colorIndex(forCategory: "Japan"), 3)
        XCTAssertEqual(LibraryIndex.colorIndex(forCategory: "France"), 2)
        XCTAssertEqual(LibraryIndex.colorIndex(forCategory: "Other"), 5)
    }

    func testSearchFields() {
        let a = story(1, title: "Chai stop", city: "Mumbai", country: "India", dateText: "19 Oct 2026")
        XCTAssertTrue(LibraryIndex.matches(a, query: "chai"))
        XCTAssertTrue(LibraryIndex.matches(a, query: "mumbai"))
        XCTAssertTrue(LibraryIndex.matches(a, query: "india"))
        XCTAssertTrue(LibraryIndex.matches(a, query: "19 oct"))
        XCTAssertTrue(LibraryIndex.matches(a, query: "mumbai oct"))
        XCTAssertFalse(LibraryIndex.matches(a, query: "mumbai nov"))
        XCTAssertTrue(LibraryIndex.matches(a, query: "   "))
    }

    func testDiacritics() {
        let a = story(1, city: "São Paulo"), b = story(2, city: "Zürich")
        XCTAssertTrue(LibraryIndex.matches(a, query: "sao paulo"))
        XCTAssertTrue(LibraryIndex.matches(b, query: "zurich"))
        XCTAssertTrue(LibraryIndex.matches(b, query: "ZÜRICH"))
    }

    func testEmptyResultAndZeroOne() {
        XCTAssertEqual(LibraryIndex.shelves(from: fx(19), query: "zzzqqq"), [])
        XCTAssertEqual(LibraryIndex.shelves(from: []), [])
        let one = LibraryIndex.shelves(from: fx(1))
        XCTAssertEqual(one.count, 1)
        XCTAssertEqual(one[0].slots.count, 1)
    }

    func testQueryKeepsGroupingFromFullLibrary() {
        let xs = fx(12)
        let s = LibraryIndex.shelves(from: xs, query: xs[0].title)
        XCTAssertFalse(s.isEmpty)
        XCTAssertTrue(s.allSatisfy { $0.id == "recent" || $0.id.hasPrefix("country:") })
        XCTAssertTrue(s.allSatisfy { sh in sh.stories.allSatisfy { LibraryIndex.matches($0, query: xs[0].title) } })
        // a 12-story library queried down to a few matches is still country-grouped (not "All Stories")
        XCTAssertFalse(s.contains { $0.id == "all" })
    }

    func testStoriesInScopeAndCities() {
        let xs = fx(30)
        let japan = LibraryIndex.stories(in: StoryScope(kind: .country("Japan"), title: "Japan"), from: xs)
        XCTAssertTrue(japan.allSatisfy { $0.country == "Japan" })
        XCTAssertEqual(japan.count, xs.filter { $0.country == "Japan" }.count)
        let kyoto = LibraryIndex.stories(in: StoryScope(kind: .city("Kyoto"), title: "Kyoto"), from: xs)
        XCTAssertFalse(kyoto.isEmpty)
        XCTAssertTrue(kyoto.allSatisfy { $0.city == "Kyoto" })
        XCTAssertEqual(LibraryIndex.stories(in: StoryScope(kind: .recent, title: "Recent"), from: xs).count, 10)
        XCTAssertEqual(LibraryIndex.stories(in: StoryScope(kind: .all, title: "All"), from: xs).count, 30)
        let q = LibraryIndex.stories(in: StoryScope(kind: .country("Japan"), title: "Japan", query: "kyoto"), from: xs)
        XCTAssertTrue(q.allSatisfy { $0.city == "Kyoto" })

        let cs = LibraryIndex.cities(in: japan)
        XCTAssertEqual(cs.map(\.count), cs.map(\.count).sorted(by: >))
        XCTAssertEqual(cs.reduce(0) { $0 + $1.count }, japan.count)
    }

    func testOtherScopeRules() {
        let multi = fx(14, noCountryEvery: 5)
        let o = LibraryIndex.stories(in: StoryScope(kind: .other, title: "Other"), from: multi)
        XCTAssertTrue(o.allSatisfy { $0.country == nil })
        XCTAssertEqual(o.count, LibraryIndex.shelves(from: multi).last?.stories.count)
        var single = fx(12, single: true); single[3].city = nil; single[5].city = nil
        let o2 = LibraryIndex.stories(in: StoryScope(kind: .other, title: "Other"), from: single)
        XCTAssertEqual(o2.count, 2)
        let shelf = LibraryIndex.shelves(from: single).last!
        XCTAssertEqual(shelf.id, "other")
        XCTAssertEqual(Set(shelf.stories.map(\.id)), Set(o2.map(\.id)))
    }

    func testCountriesAndSixtyFixture() {
        let xs = fx(60, noCountryEvery: 9)
        for sh in LibraryIndex.shelves(from: xs) { XCTAssertLessThanOrEqual(sh.slots.count, 10) }
        let cs = LibraryIndex.countries(from: xs)
        XCTAssertEqual(cs.reduce(0) { $0 + $1.count }, xs.filter { $0.country != nil }.count)
        XCTAssertEqual(cs.first?.name, "India")
        XCTAssertFalse(cs.contains { $0.name == "Other" })
        for c in cs { XCTAssertEqual(c.cities.reduce(0) { $0 + $1.count }, c.count) }
    }
}
