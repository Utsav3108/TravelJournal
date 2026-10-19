import SwiftUI

// STUB owned by agent B2 (PDF export). B1's viewer only references `StoryPDFExportButton(journey:)`.
// Contract: accessibility identifier "exportPDF".
struct StoryPDFExportButton: View {
    let journey: Journey
    var body: some View {
        Button("Export PDF") {}.accessibilityIdentifier("exportPDF")
    }
}
