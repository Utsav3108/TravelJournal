#if os(macOS)
import SwiftUI

/// Only tabs that show real information. A General tab arrives with the first real setting.
struct MacSettingsView: View {
    var body: some View {
        TabView {
            Tab("iCloud", systemImage: "icloud") { ICloudSettings().frame(height: 160) }
            Tab("Export", systemImage: "square.and.arrow.up") { ExportSettings().frame(height: 540) }
        }
        .scenePadding()
        .frame(width: 480)
        .preferredColorScheme(.light)
    }
}

private struct ICloudSettings: View {
    @Environment(\.syncState) private var state

    var body: some View {
        Form {
            Text(SyncCopy.settingsLine(for: state))
        }
        .formStyle(.grouped)
    }
}

private struct ExportSettings: View {
    @State private var settings = ExportPrivacySettings()

    var body: some View {
        Form {
            ExportPrivacyForm(privacy: $settings.privacy)
            Section {
                LabeledContent("Page size", value: "A4")
                LabeledContent("Appearance", value: "Light")
                HStack {
                    Spacer()
                    Button("Reset to Defaults") { settings.resetToDefaults() }
                        .disabled(settings.isAtFactoryDefaults)
                        .accessibilityIdentifier("privacyResetDefaults")
                }
            } footer: {
                Text("Stories with their own export privacy keep it. Change those in the story's inspector.")
            }
        }
        .formStyle(.grouped)
        // The window stays open between visits; pick up anything saved while it was hidden.
        .onAppear { settings.reload() }
    }
}
#endif
