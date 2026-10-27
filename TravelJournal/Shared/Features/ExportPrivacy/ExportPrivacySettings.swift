import Foundation
import Observation

/// The global export privacy defaults as an editable value: every change is saved to `ExportPrivacyDefaults`
/// at once, so there is no Save button and the choice survives a relaunch.
@MainActor
@Observable
final class ExportPrivacySettings {
    var privacy: ExportPrivacy {
        didSet {
            guard privacy != oldValue else { return }
            defaults.save(privacy)
            sync?.push(privacy)
        }
    }

    @ObservationIgnored let defaults: ExportPrivacyDefaults
    /// iCloud mirror of the defaults (a no-op while `ExportPrivacySync.enabled` is off). nil = no mirroring.
    @ObservationIgnored let sync: ExportPrivacySync?

    /// `sync` defaults to the app's mirror only for the standard defaults; an injected suite (tests, previews)
    /// never mirrors unless a sync is passed.
    init(defaults: ExportPrivacyDefaults = .standard, sync: ExportPrivacySync? = nil) {
        self.defaults = defaults
        self.sync = sync ?? (defaults.store === UserDefaults.standard ? ExportPrivacySync.shared : nil)
        privacy = defaults.load()
    }

    /// True when the saved options match the built-in ones.
    var isAtFactoryDefaults: Bool { privacy == ExportPrivacy() }

    /// Back to the built-in options (Stay stops hidden, everything else shown).
    func resetToDefaults() {
        privacy = ExportPrivacy()
        defaults.reset()   // the didSet saved the built-in value; leave the key unset instead
        sync?.push(nil)
    }

    /// Picks up a change saved elsewhere (the other platform's window, another settings screen).
    func reload() { privacy = defaults.load() }
}
