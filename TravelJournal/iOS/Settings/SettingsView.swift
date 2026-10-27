import SwiftUI

/// App settings on iPhone, presented in a sheet from the library's gear button. Holds only real settings:
/// today that is the export privacy defaults.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings: ExportPrivacySettings
    @State private var confirmReset = false

    init(defaults: ExportPrivacyDefaults = .standard) {
        _settings = State(initialValue: ExportPrivacySettings(defaults: defaults))
    }

    var body: some View {
        NavigationStack {
            Form {
                ExportPrivacyForm(privacy: $settings.privacy)
                Section {
                    Button("Reset to defaults", role: .destructive) { confirmReset = true }
                        .disabled(settings.isAtFactoryDefaults)
                        .accessibilityIdentifier("privacyResetDefaults")
                } footer: {
                    Text("Stories with their own export privacy keep it. Change those from the story's screen.")
                }
            }
            .foregroundStyle(KraftColor.ink)
            .calmForm()
            .navigationTitle("Settings")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("settingsDone")
                }
            }
            .confirmationDialog("Reset export privacy?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset to defaults", role: .destructive) { settings.resetToDefaults() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Stay stops will be hidden; costs, exact times and the map will be shown.")
            }
        }
        .tint(KraftColor.route)
        .preferredColorScheme(.light)
    }
}

#Preview("Settings") {
    SettingsView(defaults: ExportPrivacyDefaults(store: UserDefaults(suiteName: "preview.settings")!))
}
