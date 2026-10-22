import Foundation

/// Decides when to show the one-time "iCloud storage is full" alert: once per occurrence. The flag is remembered
/// across launches and cleared when the state leaves `.storageFull`, so a later full-storage episode alerts again.
struct StorageFullAlertTracker {
    static let defaultsKey = "syncStorageFullAlertShown"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Returns true when the alert should be presented for this state change.
    func shouldPresent(for state: SyncState) -> Bool {
        guard state == .storageFull else {
            defaults.removeObject(forKey: Self.defaultsKey)
            return false
        }
        if defaults.bool(forKey: Self.defaultsKey) { return false }
        defaults.set(true, forKey: Self.defaultsKey)
        return true
    }
}
