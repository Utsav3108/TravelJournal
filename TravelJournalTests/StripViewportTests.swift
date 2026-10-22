import XCTest
import CoreGraphics
@testable import TravelJournal

/// A journey window restored at launch is laid out before its viewport is measured; drawing pages at that size made
/// SwiftUI log "Invalid frame dimension (negative or non-finite)" on every run.
final class StripViewportTests: XCTestCase {
    func testUnmeasuredViewportsAreNotDrawn() {
        XCTAssertFalse(StripComposer.isMeasured(.zero))
        XCTAssertFalse(StripComposer.isMeasured(CGSize(width: 900, height: 0)))
        XCTAssertFalse(StripComposer.isMeasured(CGSize(width: 0, height: 640)))
        XCTAssertFalse(StripComposer.isMeasured(CGSize(width: 900, height: StripComposer.minViewportHeight - 1)))
        XCTAssertFalse(StripComposer.isMeasured(CGSize(width: CGFloat.nan, height: 640)))
        XCTAssertFalse(StripComposer.isMeasured(CGSize(width: 900, height: CGFloat.infinity)))
    }

    func testRealWindowSizesAreMeasured() {
        // The journey window's minimum content is 1000 x 640; the strip is narrower (sidebar) but never this short.
        XCTAssertTrue(StripComposer.isMeasured(CGSize(width: 520, height: 520)))
        XCTAssertTrue(StripComposer.isMeasured(CGSize(width: 1400, height: 900)))
        XCTAssertTrue(StripComposer.isMeasured(CGSize(width: 300, height: StripComposer.minViewportHeight)))
    }
}
