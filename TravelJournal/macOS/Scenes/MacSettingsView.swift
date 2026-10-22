#if os(macOS)
import SwiftUI

/// Only tabs that show real information. A General tab arrives with the first real setting.
struct MacSettingsView: View {
    var body: some View {
        TabView {
            Tab("iCloud", systemImage: "icloud") { ICloudSettings() }
            Tab("Export", systemImage: "square.and.arrow.up") { ExportSettings() }
        }
        .scenePadding()
        .frame(width: 440, height: 220)
        .preferredColorScheme(.light)
    }
}

private struct ICloudSettings: View {
    var body: some View {
        Form {
            if AppContainer.cloudKitEnabled {
                Text("Your journeys sync through iCloud.")
            } else {
                Text("Journeys stay on this device. Sign in to iCloud to sync.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct ExportSettings: View {
    var body: some View {
        Form {
            LabeledContent("Page size", value: "A4")
            LabeledContent("Appearance", value: "Light")
        }
        .formStyle(.grouped)
    }
}
#endif
