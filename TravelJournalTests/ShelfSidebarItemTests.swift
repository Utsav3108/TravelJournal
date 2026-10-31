#if os(macOS)
import XCTest
import MapKit
@testable import TravelJournal

final class ShelfSidebarItemTests: XCTestCase {
    func testOrderAndAvailability() {
        XCTAssertEqual(ShelfSidebarItem.allCases.map(\.title), ["Journey", "Map", "Calendar", "Settings"])
        XCTAssertEqual(ShelfSidebarItem.allCases.filter(\.isAvailable), [.journey, .map])
    }

    func testRowSubtitleAndTitleFallback() {
        let row = StoryPinRow(id: UUID(), title: "  ", date: Date(timeIntervalSince1970: 0), city: " Paris ")
        XCTAssertEqual(row.displayTitle, "Untitled")
        XCTAssertTrue(row.subtitle.hasSuffix("· Paris") || row.subtitle.hasSuffix("· Paris "))
        XCTAssertFalse(StoryPinRow(id: UUID(), title: "A", date: .now, city: nil).subtitle.contains("·"))
    }

    func testRegionFitsAllPoints() {
        XCTAssertNil(StoryMapLogic.region(fitting: []))
        let pts = [CLLocationCoordinate2D(latitude: 10, longitude: 20), CLLocationCoordinate2D(latitude: 30, longitude: 60)]
        let r = StoryMapLogic.region(fitting: pts)!
        XCTAssertEqual(r.center.latitude, 20, accuracy: 0.001)
        XCTAssertGreaterThan(r.span.latitudeDelta, 20)
        XCTAssertGreaterThan(r.span.longitudeDelta, 40)
        XCTAssertGreaterThanOrEqual(StoryMapLogic.region(fitting: [pts[0]])!.span.latitudeDelta, 0.2)
    }
}
#endif
