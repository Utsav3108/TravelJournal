import Foundation

/// iCloud account state as far as the UI cares.
enum SyncAccountStatus: Equatable, Sendable {
    case available
    case noAccount          // signed out, or iCloud Drive off
    case restricted
    case unknown            // could not determine / temporarily unavailable: show nothing rather than guess
}

/// Everything the sync UI is derived from. A value type so the mapping is a pure, testable function.
struct SyncInputs: Equatable, Sendable {
    var cloudKitEnabled: Bool
    var account: SyncAccountStatus = .unknown
    var importInProgress = false
    var hasLocalData = false
    var storageFull = false
}

/// Maps inputs to the one state the UI shows. Precedence: disabled build, signed out, storage full,
/// first import (only while the device has no journeys of its own), otherwise up to date.
enum SyncStatusReducer {
    static func reduce(_ i: SyncInputs) -> SyncState {
        guard i.cloudKitEnabled else { return .disabled }
        if i.account == .noAccount || i.account == .restricted { return .signedOut }
        if i.storageFull { return .storageFull }
        if i.importInProgress && !i.hasLocalData { return .importingFirstTime }
        return .upToDate
    }
}
