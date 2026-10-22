import Foundation
import Observation

/// A source of sync inputs. The live one talks to CloudKit; tests and previews use `FakeSyncStatus`.
@MainActor
protocol SyncStatusProviding: AnyObject {
    /// Called with the latest inputs whenever anything changes (and once on `start`).
    var onChange: ((SyncInputs) -> Void)? { get set }
    func start()
}

/// Test and preview source: push inputs by hand.
@MainActor
final class FakeSyncStatus: SyncStatusProviding {
    var onChange: ((SyncInputs) -> Void)?
    private(set) var started = false
    var inputs: SyncInputs { didSet { if started { onChange?(inputs) } } }

    init(_ inputs: SyncInputs) { self.inputs = inputs }

    func start() { started = true; onChange?(inputs) }
}

/// Holds the state the scenes read through `\.syncState`. Without a provider (iCloud off) it stays `.disabled`.
@MainActor
@Observable
final class SyncStatusModel {
    private(set) var state: SyncState

    private var provider: (any SyncStatusProviding)?

    init(cloudKitEnabled: Bool, provider: (any SyncStatusProviding)? = nil) {
        self.provider = cloudKitEnabled ? provider : nil
        self.state = cloudKitEnabled ? .upToDate : .disabled
        self.provider?.onChange = { [weak self] inputs in self?.state = SyncStatusReducer.reduce(inputs) }
        self.provider?.start()
    }

    /// The Mac app's model: live CloudKit status only when the build can sync and the process is not a test or UI-test run.
    static func live(hasLocalData: @escaping @MainActor () -> Bool,
                     arguments: [String] = ProcessInfo.processInfo.arguments,
                     environment: [String: String] = ProcessInfo.processInfo.environment) -> SyncStatusModel {
        let underTest = environment["XCTestConfigurationFilePath"] != nil
        let enabled = AppContainer.cloudKitEnabled && !underTest
            && !arguments.contains("-disableCloudKit") && !arguments.contains("-uitest")
        return SyncStatusModel(cloudKitEnabled: enabled,
                               provider: enabled ? CloudKitSyncStatus(hasLocalData: hasLocalData) : nil)
    }
}
