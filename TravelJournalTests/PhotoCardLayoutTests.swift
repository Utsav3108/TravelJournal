#if os(macOS)
import XCTest
@testable import TravelJournal

final class PhotoCardLayoutTests: XCTestCase {
    func testCardFillsMostOfTheWindowButNeverExceedsTheCeiling() {
        XCTAssertEqual(PhotoCardLayout.size(viewport: CGSize(width: 1000, height: 700)), CGSize(width: 920, height: 620))
        XCTAssertEqual(PhotoCardLayout.size(viewport: CGSize(width: 3000, height: 2000)),
                       CGSize(width: PhotoCardLayout.maxWidth, height: PhotoCardLayout.maxHeight))
    }

    func testCardKeepsAFloorInATinyWindow() {
        XCTAssertEqual(PhotoCardLayout.size(viewport: CGSize(width: 300, height: 200)),
                       CGSize(width: PhotoCardLayout.minSide, height: PhotoCardLayout.minSide))
    }

    func testCardIsMuchBiggerThanTheLegCard() {
        let s = PhotoCardLayout.size(viewport: CGSize(width: 1200, height: 800))
        XCTAssertGreaterThan(s.width * s.height, 340 * 280 * 4)
    }
}
#endif
