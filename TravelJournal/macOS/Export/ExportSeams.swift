#if os(macOS)
import SwiftUI

// Phase 5 seams: the journey toolbar, the journey window's presentations and the shelf book's context menu call these.
// Phase 5b replaces the bodies, so no other part has to edit those views.

/// Export and Share items for a journey window's toolbar.
struct JourneyExportToolbar: ToolbarContent {
    let journey: Journey
    var body: some ToolbarContent { }
}

/// Progress sheet, save panel and error alert for exporting or printing a journey.
extension View {
    func journeyExportPresentations(journey: Journey) -> some View { self }
}

/// Export as PDF… and Print… for a book in the shelf's context menu.
struct ExportContextMenuItems: View {
    let journey: Journey
    var body: some View { EmptyView() }
}
#endif
