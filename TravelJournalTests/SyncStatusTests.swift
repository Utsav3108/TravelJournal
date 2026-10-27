import XCTest
@testable import TravelJournal

@MainActor
final class SyncStatusTests: XCTestCase {
    private func state(enabled: Bool = true, account: SyncAccountStatus = .available, importing: Bool = false,
                       local: Bool = true, full: Bool = false) -> SyncState {
        SyncStatusReducer.reduce(SyncInputs(cloudKitEnabled: enabled, account: account, importInProgress: importing,
                                            hasLocalData: local, storageFull: full))
    }

    // MARK: Reducer

    func testDisabledBuildShowsNothingWhateverTheOtherInputs() {
        XCTAssertEqual(state(enabled: false, account: .noAccount, importing: true, local: false, full: true), .disabled)
    }

    func testSignedOutAndRestrictedAccountsShowTheSignedOutState() {
        XCTAssertEqual(state(account: .noAccount), .signedOut)
        XCTAssertEqual(state(account: .restricted), .signedOut)
    }

    func testUnknownAccountIsNotTreatedAsSignedOut() {
        XCTAssertEqual(state(account: .unknown), .upToDate)
    }

    func testFirstImportOnlyWhileThereIsNoLocalData() {
        XCTAssertEqual(state(importing: true, local: false), .importingFirstTime)
        XCTAssertEqual(state(importing: true, local: true), .upToDate)
        XCTAssertEqual(state(importing: false, local: false), .upToDate)
    }

    func testStorageFullShowsWhenSignedIn() {
        XCTAssertEqual(state(full: true), .storageFull)
        XCTAssertEqual(state(account: .noAccount, full: true), .signedOut)   // signed out wins
    }

    // MARK: Model

    func testModelStaysDisabledWithoutCloudKitEvenWithAProvider() {
        let fake = FakeSyncStatus(SyncInputs(cloudKitEnabled: true, account: .noAccount))
        let model = SyncStatusModel(cloudKitEnabled: false, provider: fake)
        XCTAssertEqual(model.state, .disabled)
        XCTAssertFalse(fake.started)
    }

    func testModelFollowsTheProviderWhenEnabled() {
        let fake = FakeSyncStatus(SyncInputs(cloudKitEnabled: true, account: .noAccount))
        let model = SyncStatusModel(cloudKitEnabled: true, provider: fake)
        XCTAssertEqual(model.state, .signedOut)
        fake.inputs = SyncInputs(cloudKitEnabled: true, account: .available, importInProgress: true, hasLocalData: false)
        XCTAssertEqual(model.state, .importingFirstTime)
        fake.inputs.storageFull = true
        XCTAssertEqual(model.state, .storageFull)
    }

    func testLiveModelIsDisabledWhileICloudIsOffInTheBuild() {
        XCTAssertFalse(AppContainer.cloudKitEnabled, "this test documents the free-account build")
        let model = SyncStatusModel.live(hasLocalData: { true }, arguments: [], environment: [:])
        XCTAssertEqual(model.state, .disabled)
    }

    // MARK: Banner and alert

    func testBannerIsVisibleOnlyWhenSignedOut() {
        XCTAssertTrue(SyncBanner.isVisible(for: .signedOut))
        for s in [SyncState.disabled, .importingFirstTime, .upToDate, .storageFull] {
            XCTAssertFalse(SyncBanner.isVisible(for: s), "\(s)")
        }
    }

    func testStorageFullAlertShowsOncePerOccurrence() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SyncStatusTests-\(UUID().uuidString)"))
        let tracker = StorageFullAlertTracker(defaults: defaults)
        XCTAssertFalse(tracker.shouldPresent(for: .upToDate))
        XCTAssertTrue(tracker.shouldPresent(for: .storageFull))
        XCTAssertFalse(tracker.shouldPresent(for: .storageFull))      // still full: not again
        XCTAssertFalse(tracker.shouldPresent(for: .upToDate))         // space freed: re-arms
        XCTAssertTrue(tracker.shouldPresent(for: .storageFull))       // full again: alert again
    }

    func testSettingsLineCoversEveryState() {
        for s in [SyncState.disabled, .signedOut, .importingFirstTime, .upToDate, .storageFull] {
            XCTAssertFalse(SyncCopy.settingsLine(for: s).isEmpty)
        }
    }
}
