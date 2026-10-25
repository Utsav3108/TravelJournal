import SwiftUI

/// Toolbar "Export" button. It opens the Export sheet; the sheet and everything after it are attached once by the
/// owner with `.exportFlowPresentations(_:)`. The accessibility id stays `exportPDF` for the UI tests.
struct StoryPDFExportButton: View {
    let model: ExportFlowModel

    var body: some View {
        Button {
            model.present()
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .disabled(!model.hasStops || model.isActive)
        .accessibilityIdentifier("exportPDF")
        .accessibilityHint(model.hasStops ? "Choose a format and export this journey" : "Add at least one stop to export")
    }
}
