import XCTest
import SwiftData
@testable import TravelJournal

@MainActor
final class StoreFailureTests: XCTestCase {
    private struct Boom: Error {}

    func testFailingFactoryYieldsFailedStateAndNoContainer() {
        var calls = 0
        let loader = StoreLoader(factory: { calls += 1; throw Boom() })
        guard case .failed = loader.state else { return XCTFail("expected .failed, got a container") }
        XCTAssertEqual(calls, 1, "opened exactly once; no second (in-memory) attempt")
    }

    func testRetryRecoversWhenStoreOpensLater() throws {
        var fail = true
        let loader = StoreLoader(factory: { if fail { throw Boom() }; return try AppContainer.openInMemory() })
        guard case .failed = loader.state else { return XCTFail("expected .failed") }
        fail = false
        loader.load()
        guard case .ready = loader.state else { return XCTFail("expected .ready after retry") }
    }

    func testForceStoreFailureLaunchFlag() {
        let factory = AppContainer.launchFactory(arguments: ["-forceStoreFailure"], environment: [:])
        XCTAssertThrowsError(try factory())
        // The flag wins even together with -uitest.
        XCTAssertThrowsError(try AppContainer.launchFactory(arguments: ["-uitest", "-forceStoreFailure"], environment: [:])())
    }

    func testUITestFlagGivesInMemoryStore() throws {
        let c = try AppContainer.launchFactory(arguments: ["-uitest"], environment: [:])()
        XCTAssertTrue(c.configurations.allSatisfy { $0.isStoredInMemoryOnly })
    }
}
