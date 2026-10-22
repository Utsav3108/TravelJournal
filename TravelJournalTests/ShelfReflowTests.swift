import XCTest
import SwiftData
import CoreGraphics
@testable import TravelJournal

final class ShelfReflowTests: XCTestCase {
    private func layout(_ count: Int, _ w: CGFloat, _ h: CGFloat, expanded: Bool = false) -> BookcaseReflow {
        BookcaseReflow.layout(count: count, size: CGSize(width: w, height: h), expanded: expanded)
    }

    func testBooksPerShelfFollowsWidth() {
        XCTAssertEqual(layout(3, 720, 480).perShelf, 3)     // 656 usable: 3 * 160 + 2 * 28 = 536 fits, 4 = 724 does not
        XCTAssertEqual(layout(3, 1000, 480).perShelf, 5)
        XCTAssertEqual(layout(3, 1600, 480).perShelf, 8)
        XCTAssertEqual(layout(3, 100, 480).perShelf, 1)     // never below one
    }

    func testShelvesShownFollowHeight() {
        XCTAssertEqual(layout(3, 1000, 480).fitShelves, 1)
        XCTAssertEqual(layout(3, 1000, 600).fitShelves, 2)
        XCTAssertEqual(layout(3, 1000, 1000).fitShelves, 3)
    }

    func testEverythingFitsShowsNoTile() {
        let r = layout(10, 1000, 600)                       // 5 per shelf, 2 shelves
        XCTAssertEqual(r.items, (0..<10).map { .book($0) })
        XCTAssertFalse(r.canExpand)
    }

    func testOverflowReplacesTheLastSlotWithAPlusNTile() {
        let r = layout(25, 1000, 600)                       // capacity 10: nine books and the tile
        XCTAssertEqual(r.items.count, 10)
        XCTAssertEqual(r.items.last, .more(hidden: 16))     // 25 journeys - 9 shown
        XCTAssertEqual(r.items[8], .book(8))
        XCTAssertEqual(r.visibleBookCount, 9)
        XCTAssertTrue(r.canExpand)
    }

    func testExpandedShowsEveryBookThenShowLess() {
        let r = layout(25, 1000, 600, expanded: true)
        XCTAssertEqual(r.items.count, 26)
        XCTAssertEqual(r.items.last, .less)
        XCTAssertEqual(r.visibleBookCount, 25)
        XCTAssertEqual(r.rows, 6)                           // 26 slots, 5 per shelf
        XCTAssertEqual(r.contentHeight, 6 * BookcaseReflow.shelfHeight)
    }

    func testExactlyFullBookcaseHasNoTile() {
        XCTAssertEqual(layout(10, 1000, 600).items.last, .book(9))
        XCTAssertEqual(layout(11, 1000, 600).items.last, .more(hidden: 2))   // 11 - 9
    }

    func testNarrowWindowKeepsAtLeastTwoSlots() {
        let r = layout(5, 100, 200)                         // one per shelf, one shelf fits: forced to two shelves
        XCTAssertEqual(r.perShelf, 1)
        XCTAssertEqual(r.fitShelves, 2)
        XCTAssertEqual(r.items, [.book(0), .more(hidden: 4)])
    }

    func testEmptyLibraryStillDrawsPlanks() {
        let r = layout(0, 1000, 600)
        XCTAssertTrue(r.items.isEmpty)
        XCTAssertEqual(r.rows, 0)
        XCTAssertEqual(r.wallRows, 2)
    }

    func testSlotCentres() {
        let r = layout(10, 1000, 600)                       // 5 per shelf: row width 5 * 160 + 4 * 28 = 912, left 44
        let first = r.center(ofItem: 0, width: 1000)
        XCTAssertEqual(first.x, 44 + 80, accuracy: 0.001)
        XCTAssertEqual(first.y, BookcaseReflow.roomAbove + 110, accuracy: 0.001)
        let sixth = r.center(ofItem: 5, width: 1000)        // first book of the second shelf
        XCTAssertEqual(sixth.x, first.x, accuracy: 0.001)
        XCTAssertEqual(sixth.y, first.y + BookcaseReflow.shelfHeight, accuracy: 0.001)
        XCTAssertEqual(r.center(ofItem: 1, width: 1000).x - first.x, 188, accuracy: 0.001)
    }

    func testArrowKeysMoveSelection() {
        func move(_ i: Int?, _ d: BookcaseReflow.Direction) -> Int? {
            BookcaseReflow.moveSelection(from: i, direction: d, perShelf: 4, bookCount: 10)
        }
        XCTAssertEqual(move(nil, .right), 0)
        XCTAssertEqual(move(99, .left), 0)                  // selection no longer visible
        XCTAssertEqual(move(0, .left), 0)
        XCTAssertEqual(move(9, .right), 9)
        XCTAssertEqual(move(3, .right), 4)                  // wraps onto the next shelf in reading order
        XCTAssertEqual(move(5, .up), 1)
        XCTAssertEqual(move(1, .up), 1)
        XCTAssertEqual(move(1, .down), 5)
        XCTAssertEqual(move(6, .down), 9)                   // last shelf is short: land on the last book
        XCTAssertEqual(move(9, .down), 9)
        XCTAssertNil(BookcaseReflow.moveSelection(from: nil, direction: .right, perShelf: 4, bookCount: 0))
    }
}

final class ShelfQueryTests: XCTestCase {
    private func story(_ title: String, _ day: Int, city: String? = nil, search: String = "") -> LibraryStory {
        LibraryStory(id: UUID(), title: title, date: Date(timeIntervalSince1970: Double(day) * 86_400),
                     dateText: "d\(day)", city: city, country: nil, weight: 1, coverPhotoID: nil, searchText: search)
    }

    func testSortOrders() {
        let a = story("Banff", 1), b = story("Agra", 3), c = story("Cairo", 2)
        let all = [a, b, c]
        XCTAssertEqual(ShelfQuery.apply(all, query: "", sort: .newest).map(\.title), ["Agra", "Cairo", "Banff"])
        XCTAssertEqual(ShelfQuery.apply(all, query: "", sort: .oldest).map(\.title), ["Banff", "Cairo", "Agra"])
        XCTAssertEqual(ShelfQuery.apply(all, query: "", sort: .title).map(\.title), ["Agra", "Banff", "Cairo"])
    }

    func testSearchMatchesTitleCityStopNamesAndStoryText() {
        let temple = story("A Day in Kyoto", 1, city: "Kyoto", search: "Fushimi Inari\nWe walked the temple steps")
        let other = story("Rain over Lisbon", 2, city: "Lisbon", search: "Pastel de nata")
        let all = [temple, other]
        XCTAssertEqual(ShelfQuery.apply(all, query: "temple", sort: .newest).map(\.title), ["A Day in Kyoto"])
        XCTAssertEqual(ShelfQuery.apply(all, query: "inari", sort: .newest).map(\.title), ["A Day in Kyoto"])
        XCTAssertEqual(ShelfQuery.apply(all, query: "lisbon", sort: .newest).map(\.title), ["Rain over Lisbon"])
        XCTAssertEqual(ShelfQuery.apply(all, query: "nata lisbon", sort: .newest).count, 1)   // every word must match
        XCTAssertTrue(ShelfQuery.apply(all, query: "volcano", sort: .newest).isEmpty)
        XCTAssertEqual(ShelfQuery.apply(all, query: "  ", sort: .newest).count, 2)             // blank query keeps everything
    }

    func testSearchIgnoresCaseAndDiacritics() {
        let s = story("Zürich", 1, search: "Café Sprüngli")
        XCTAssertEqual(ShelfQuery.apply([s], query: "ZURICH cafe", sort: .newest).count, 1)
    }

    @MainActor
    func testJourneySnapshotCarriesStopNamesAndStoryText() throws {
        let container = AppContainer.make(inMemory: true)
        let context = ModelContext(container)
        let journey = Journey(title: "Mumbai")
        journey.introNote = "A long day"
        journey.closingNote = "Home by midnight"
        context.insert(journey)
        let stop = Stop(placeName: "Sardar Pav Bhaji")
        stop.story = "The butter was unreasonable"
        JourneyEditor(context: context, photos: NoopPhotoStore()).addStop(stop, to: journey)

        let snapshot = LibraryStory(journey)
        for expected in ["A long day", "Sardar Pav Bhaji", "unreasonable", "midnight"] {
            XCTAssertTrue(snapshot.searchText.contains(expected), "searchText should contain \(expected)")
        }
        XCTAssertTrue(ShelfQuery.matches(snapshot, query: "butter"))
    }
}
