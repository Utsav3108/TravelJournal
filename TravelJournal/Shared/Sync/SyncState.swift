import SwiftUI

/// What the iCloud sync UI should show. `.disabled` is a build without CloudKit (`AppContainer.cloudKitEnabled`
/// false): nothing sync-related appears at all. Produced by the sync status source, read by the shelf and journey scenes.
enum SyncState: Equatable, Sendable {
    case disabled
    case signedOut
    case importingFirstTime
    case upToDate
    case storageFull
}

private struct SyncStateKey: EnvironmentKey {
    static let defaultValue: SyncState = .disabled
}

extension EnvironmentValues {
    var syncState: SyncState {
        get { self[SyncStateKey.self] }
        set { self[SyncStateKey.self] = newValue }
    }
}
