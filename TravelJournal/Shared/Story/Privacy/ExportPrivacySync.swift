import Foundation

/// The key-value store the iCloud mirror talks to. `NSUbiquitousKeyValueStore` in the app; an in-memory fake in tests.
protocol ExportPrivacyKeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    /// Any value under `key` (nil only when the key is absent). Defaults to `data(forKey:)`.
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension ExportPrivacyKeyValueStore {
    func object(forKey key: String) -> Any? { data(forKey: key) }
}

extension NSUbiquitousKeyValueStore: ExportPrivacyKeyValueStore {}

/// iCloud key-value mirror of the global export privacy defaults (`ExportPrivacyDefaults`).
/// Switched off by `enabled = false`, the same way `cloudKitEnabled` gates CloudKit: while off, every method is a no-op
/// and the store is never touched.
/// Per-journey choices already sync through SwiftData once CloudKit is on; this only mirrors the global defaults.
///
/// - Local saves (`ExportPrivacySettings`) call `push`, which writes the same JSON the defaults hold (nil = reset).
/// - `start()` (at launch) observes `didChangeExternallyNotification` and pulls once; a change from another device
///   replaces the local defaults (last writer wins). Unreadable remote data is ignored.
final class ExportPrivacySync {
    static let enabled = false
    /// Same key as the local defaults, so the mirror holds the same JSON.
    static let key = ExportPrivacyDefaults.key
    /// Posted (object: the sync) after a remote value was applied to the local defaults.
    static let didApplyRemoteChange = Notification.Name("ExportPrivacySync.didApplyRemoteChange")

    /// The app's mirror (iCloud store, standard defaults, `enabled`).
    static let shared = ExportPrivacySync()

    let store: ExportPrivacyKeyValueStore
    let defaults: ExportPrivacyDefaults
    /// `enabled` by default; tests inject `true` to exercise the mirror with a fake store.
    let isEnabled: Bool
    private var observer: NSObjectProtocol?

    init(store: ExportPrivacyKeyValueStore = NSUbiquitousKeyValueStore.default,
         defaults: ExportPrivacyDefaults = .standard, isEnabled: Bool = ExportPrivacySync.enabled) {
        self.store = store
        self.defaults = defaults
        self.isEnabled = isEnabled
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Begin observing remote changes, then pull what the store already holds. Safe to call more than once.
    func start() {
        guard isEnabled, observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main
        ) { [weak self] note in
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            MainActor.assumeIsolated { self?.handleExternalChange(changedKeys: keys) }
        }
        store.synchronize()
        pull()
    }

    /// Mirror `privacy` to the store; nil (back to the built-in defaults) removes the key.
    func push(_ privacy: ExportPrivacy?) {
        guard isEnabled else { return }
        if let privacy {
            guard let data = try? JSONEncoder().encode(privacy) else { return }
            store.set(data, forKey: Self.key)
        } else {
            store.removeObject(forKey: Self.key)
        }
        store.synchronize()
    }

    /// Copy the store's value (if any, and readable) into the local defaults; returns what was applied.
    /// A missing key leaves the local defaults alone (a store that never synced must not reset them).
    @discardableResult func pull() -> ExportPrivacy? {
        guard isEnabled, let data = store.data(forKey: Self.key),
              let remote = try? JSONDecoder().decode(ExportPrivacy.self, from: data) else { return nil }
        if defaults.store.data(forKey: Self.key) != data || defaults.load() != remote {
            defaults.save(remote)
            NotificationCenter.default.post(name: Self.didApplyRemoteChange, object: self)
        }
        return remote
    }

    /// Another device changed the store. `changedKeys` nil = unknown (pull anyway). A removed key means that
    /// device reset to the built-in defaults, so the local defaults reset too.
    func handleExternalChange(changedKeys: [String]?) {
        guard isEnabled else { return }
        if let changedKeys, !changedKeys.contains(Self.key) { return }
        if store.object(forKey: Self.key) == nil {
            guard defaults.store.data(forKey: Self.key) != nil else { return }
            defaults.reset()
            NotificationCenter.default.post(name: Self.didApplyRemoteChange, object: self)
        } else {
            pull()
        }
    }
}
