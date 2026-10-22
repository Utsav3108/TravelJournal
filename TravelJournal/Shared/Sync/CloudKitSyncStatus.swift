import Foundation
import CloudKit
import CoreData

/// Live sync inputs: the iCloud account status plus SwiftData's CloudKit import/export events (SwiftData mirrors
/// through `NSPersistentCloudKitContainer`, which posts these notifications). Only created when
/// `AppContainer.cloudKitEnabled`; it is never constructed on a build without the iCloud capability.
@MainActor
final class CloudKitSyncStatus: SyncStatusProviding {
    var onChange: ((SyncInputs) -> Void)?

    private var inputs = SyncInputs(cloudKitEnabled: true)
    private let hasLocalData: @MainActor () -> Bool
    private var observers: [NSObjectProtocol] = []

    init(hasLocalData: @escaping @MainActor () -> Bool) {
        self.hasLocalData = hasLocalData
    }

    func start() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refreshAccount() }
        })
        observers.append(center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification,
                                            object: nil, queue: .main) { [weak self] note in
            let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
            Task { @MainActor in self?.handle(event) }
        })
        Task { await refreshAccount() }
    }

    private func refreshAccount() async {
        let container = CKContainer(identifier: AppContainer.cloudKitContainerID)
        let status = try? await container.accountStatus()
        switch status {
        case .available: inputs.account = .available
        case .noAccount: inputs.account = .noAccount
        case .restricted: inputs.account = .restricted
        default: inputs.account = .unknown
        }
        publish()
    }

    private func handle(_ event: NSPersistentCloudKitContainer.Event?) {
        guard let event else { return }
        if event.type == .import { inputs.importInProgress = event.endDate == nil }
        if let error = event.error as? CKError {
            inputs.storageFull = error.code == .quotaExceeded
        } else if event.endDate != nil, event.succeeded {
            inputs.storageFull = false
        }
        publish()
    }

    private func publish() {
        inputs.hasLocalData = hasLocalData()
        onChange?(inputs)
    }
}
