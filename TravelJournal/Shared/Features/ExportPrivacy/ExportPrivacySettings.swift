import Foundation
import Observation

/// The global export privacy defaults as an editable value: every change is saved to `ExportPrivacyDefaults`
/// at once, so there is no Save button and the choice survives a relaunch.
@MainActor
@Observable
final class ExportPrivacySettings {
    var privacy: ExportPrivacy {
        didSet { if privacy != oldValue { defaults.save(privacy) } }
    }

    @ObservationIgnored let defaults: ExportPrivacyDefaults

    init(defaults: ExportPrivacyDefaults = .standard) {
        self.defaults = defaults
        privacy = defaults.load()
    }

    /// True when the saved options match the built-in ones.
    var isAtFactoryDefaults: Bool { privacy == ExportPrivacy() }

    /// Back to the built-in options (Stay stops hidden, everything else shown).
    func resetToDefaults() {
        privacy = ExportPrivacy()
        defaults.reset()   // the didSet saved the built-in value; leave the key unset instead
    }

    /// Picks up a change saved elsewhere (the other platform's window, another settings screen).
    func reload() { privacy = defaults.load() }
}
