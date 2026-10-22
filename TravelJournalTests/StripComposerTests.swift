import XCTest
import SwiftData
@testable import TravelJournal

@MainActor
final class StripComposerTests: XCTestCase {
    private func sampleItems() -> (items: [StripComposer.Item], stops: Int) {
        let container = AppContainer.make(inMemory: true)
        let journey = SampleData.mumbai(in: ModelContext(container))
        let pages = StoryLayout().pages(for: journey)
        return (StripComposer.items(from: pages), journey.stops.count)
    }

    func testOrderIsCoverStopsClosingWithoutOverview() {
        let (items, stops) = sampleItems()
        XCTAssertEqual(items.count, stops + 2)
        guard case .cover = items.first?.page, case .closing = items.last?.page else { return XCTFail("cover first, closing last") }
        XCTAssertFalse(items.contains { if case .overview = $0.page { true } else { false } })
        XCTAssertEqual(items.compactMap(\.stopID).count, stops)
    }

    func testOverviewIsExtractedAndStopIDsMatch() throws {
        let container = AppContainer.make(inMemory: true)
        let journey = SampleData.mumbai(in: ModelContext(container))
        let pages = StoryLayout().pages(for: journey)
        let overview = try XCTUnwrap(StripComposer.overview(from: pages))
        let items = StripComposer.items(from: pages)
        XCTAssertEqual(overview.stops.map { StripComposer.stopID(ofPageID: $0.id) }, items.compactMap(\.stopID))
    }

    func testPageSizeFollowsViewportHeightAndZoom() {
        XCTAssertEqual(StripComposer.pageSize(viewportHeight: 500, zoom: 1).height, 500)
        XCTAssertEqual(StripComposer.pageSize(viewportHeight: 500, zoom: 1).width, 500 * StripComposer.pageAspect, accuracy: 0.001)
        XCTAssertEqual(StripComposer.pageSize(viewportHeight: 500, zoom: 0.5).height, 250)
        XCTAssertEqual(StripComposer.pageSize(viewportHeight: 500, zoom: 99).height, 500 * StripComposer.zoomRange.upperBound)
    }

    func testZoomStepsAreClamped() {
        XCTAssertEqual(StripComposer.zoomedIn(1), 1.25, accuracy: 0.0001)
        XCTAssertEqual(StripComposer.zoomedOut(1), 0.8, accuracy: 0.0001)
        XCTAssertEqual(StripComposer.zoomedIn(StripComposer.zoomRange.upperBound), StripComposer.zoomRange.upperBound)
        XCTAssertEqual(StripComposer.zoomedOut(StripComposer.zoomRange.lowerBound), StripComposer.zoomRange.lowerBound)
    }

    func testFitZoomMakesAllPagesFitTheWidth() {
        let viewport = CGSize(width: 1000, height: 600)
        let zoom = StripComposer.fitZoom(viewport: viewport, count: 8)
        let size = StripComposer.pageSize(viewportHeight: viewport.height, zoom: zoom)
        XCTAssertLessThanOrEqual(StripComposer.contentWidth(count: 8, pageWidth: size.width), viewport.width + 0.5)
        XCTAssertLessThan(zoom, 1)
        // A short journey that already fits stays at actual size.
        XCTAssertEqual(StripComposer.fitZoom(viewport: viewport, count: 2), 1)
        XCTAssertEqual(StripComposer.fitZoom(viewport: .zero, count: 5), StripComposer.defaultZoom)
    }

    func testCenteredOffsetCentresAndClamps() {
        let w: CGFloat = 300, vp: CGFloat = 900
        XCTAssertEqual(StripComposer.centeredOffset(index: 5, pageWidth: w, viewportWidth: vp, count: 10), 5 * w + w / 2 - vp / 2)
        XCTAssertEqual(StripComposer.centeredOffset(index: 0, pageWidth: w, viewportWidth: vp, count: 10), 0)
        XCTAssertEqual(StripComposer.centeredOffset(index: 9, pageWidth: w, viewportWidth: vp, count: 10), 10 * w - vp)
        XCTAssertEqual(StripComposer.centeredOffset(index: 1, pageWidth: w, viewportWidth: vp, count: 2), 0, "content narrower than the viewport never scrolls")
    }

    func testNeighbourStopSkipsCoverAndClosing() {
        let (items, stops) = sampleItems()
        XCTAssertEqual(StripComposer.neighbourStop(from: nil, direction: 1, in: items), 1)
        XCTAssertEqual(StripComposer.neighbourStop(from: nil, direction: -1, in: items), stops)
        XCTAssertEqual(StripComposer.neighbourStop(from: 0, direction: 1, in: items), 1, "from the cover, next is the first stop")
        XCTAssertNil(StripComposer.neighbourStop(from: 0, direction: -1, in: items))
        XCTAssertNil(StripComposer.neighbourStop(from: stops, direction: 1, in: items), "no stop after the last one")
        if stops > 1 {
            XCTAssertEqual(StripComposer.neighbourStop(from: 1, direction: 1, in: items), 2)
            XCTAssertEqual(StripComposer.neighbourStop(from: 2, direction: -1, in: items), 1)
        }
    }

    func testIndexOfStop() {
        let (items, _) = sampleItems()
        XCTAssertEqual(StripComposer.index(ofStop: items[1].stopID, in: items), 1)
        XCTAssertNil(StripComposer.index(ofStop: "nope", in: items))
        XCTAssertNil(StripComposer.index(ofStop: nil, in: items))
    }
}
