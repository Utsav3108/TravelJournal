import Foundation

/// The key-value store the iCloud mirror talks to. `NSUbiquitousKeyValueStore` in the app; an in-memory fake in tests.
protocol ExportPrivacyKeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: ExportPrivacyKeyValueStore {}

/// iCloud key-value mirror of the global export privacy defaults (`ExportPrivacyDefaults`).
/// Switched off by `enabled = false`, the same way `cloudKitEnabled` gates CloudKit: while off, every method is a no-op.
/// Per-journey choices already sync through SwiftData once CloudKit is on; this only mirrors the global defaults.
///
/// Skeleton (Wave 1). Agent H fills in: push on save, pull on launch and on external-change notifications.
final class ExportPrivacySync {
    static let enabled = false
    /// Same key as the local defaults, so the mirror holds the same JSON.
    static let key = ExportPrivacyDefaults.key

    let store: ExportPrivacyKeyValueStore
    let defaults: ExportPrivacyDefaults
    /// `enabled` by default; tests inject `true` to exercise the mirror with a fake store.
    let isEnabled: Bool

    init(store: ExportPrivacyKeyValueStore = NSUbiquitousKeyValueStore.default,
         defaults: ExportPrivacyDefaults = .standard, isEnabled: Bool = ExportPrivacySync.enabled) {
        self.store = store
        self.defaults = defaults
        self.isEnabled = isEnabled
    }

    /// Begin observing remote changes. No-op for now.
    func start() {}

    /// Mirror `privacy` to the store. No-op for now.
    func push(_ privacy: ExportPrivacy) {}

    /// Copy the store's value (if any) into the local defaults; returns what was applied. No-op (nil) for now.
    @discardableResult func pull() -> ExportPrivacy? { nil }
}
