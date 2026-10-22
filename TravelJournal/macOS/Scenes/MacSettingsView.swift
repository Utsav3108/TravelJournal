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
    @Environment(\.syncState) private var state

    var body: some View {
        Form {
            Text(SyncCopy.settingsLine(for: state))
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
