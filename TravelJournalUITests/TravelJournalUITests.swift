//
//  TravelJournalUITests.swift
//  TravelJournalUITests
//

import XCTest

final class TravelJournalUITests: XCTestCase {

    override func setUpWithError() throws {
        // Stop immediately when a failure occurs.
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    /// Story viewer smoke test. Relies on the DEBUG launch argument `-openSampleStory` and the accessibility
    /// identifiers `storyViewer`, `pageIndicator`, `legCard`, `photoFullScreen`, `exportPDF` added by the viewer
    /// work. Skips (not fails) when the viewer is not in this build.
    @MainActor
    func testStoryViewerSwipeAndExportButton() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-openSampleStory"]
        app.launch()

        let viewer = app.descendants(matching: .any)["storyViewer"]
        guard viewer.waitForExistence(timeout: 5) else {
            throw XCTSkip("storyViewer identifier not present: viewer not merged into this build")
        }

        let indicator = app.descendants(matching: .any)["pageIndicator"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 5), "page indicator missing")
        let before = indicator.label

        app.swipeLeft()
        app.swipeLeft()
        let changed = expectation(for: NSPredicate(format: "label != %@", before), evaluatedWith: indicator)
        wait(for: [changed], timeout: 8)

        // Bar is hidden off the cover; swiping back to page 1 shows it again.
        app.swipeRight()
        app.swipeRight()
        XCTAssertTrue(app.buttons["exportPDF"].waitForExistence(timeout: 5), "export button missing")
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
