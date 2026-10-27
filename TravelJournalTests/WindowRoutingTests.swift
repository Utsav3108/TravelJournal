import XCTest
import SwiftData
@testable import TravelJournal

@MainActor
final class WindowRoutingTests: XCTestCase {
    func testMakeUntitledSavesAnEmptyUntitledJourney() throws {
        let container = AppContainer.make(inMemory: true)
        let context = ModelContext(container)
        let journey = Journey.makeUntitled(in: context)

        XCTAssertEqual(journey.title, "Untitled")
        XCTAssertTrue(journey.orderedStops.isEmpty)
        let found = try context.fetch(FetchDescriptor<Journey>(predicate: Journey.matching(id: journey.id)))
        XCTAssertEqual(found.count, 1)
    }

    func testPredicateFindsOnlyTheJourneyWithThatID() throws {
        let container = AppContainer.make(inMemory: true)
        let context = ModelContext(container)
        let a = Journey(title: "A"), b = Journey(title: "B")
        context.insert(a); context.insert(b)
        try context.save()

        let found = try context.fetch(FetchDescriptor<Journey>(predicate: Journey.matching(id: b.id)))
        XCTAssertEqual(found.map(\.title), ["B"])
    }

    func testPredicateFindsNothingForAnUnknownOrDeletedJourney() throws {
        let container = AppContainer.make(inMemory: true)
        let context = ModelContext(container)
        let j = Journey(title: "Gone")
        context.insert(j)
        try context.save()
        let id = j.id

        XCTAssertTrue(try context.fetch(FetchDescriptor<Journey>(predicate: Journey.matching(id: UUID()))).isEmpty)
        context.delete(j)
        try context.save()
        XCTAssertTrue(try context.fetch(FetchDescriptor<Journey>(predicate: Journey.matching(id: id))).isEmpty)
    }

    func testNewJourneyRequestStartsClearedAndIsConsumable() {
        let requests = NewJourneyRequests()
        XCTAssertFalse(requests.pending)
        requests.pending = true
        XCTAssertTrue(requests.pending)
    }
}
