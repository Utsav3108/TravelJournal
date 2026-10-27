#if os(macOS)
import SwiftUI

/// Menu items for the journey window: import, inspector, sidebar, zoom, previous/next stop, move and delete stop.
/// They act on the front journey window through `JourneyActions` / `StripActions` and grey out when they don't apply
/// (shelf in front, nothing selected). The arrow keys themselves are handled by the strip, so they cannot fire while
/// a text field has focus; ⌘⌫ falls back to its text meaning when a field is being edited.
struct JourneyCommands: Commands {
    let newJourneyRequests: NewJourneyRequests

    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.stripActions) private var strip
    @FocusedValue(\.journeyActions) private var journey

    var body: some Commands {
        SidebarCommands()   // View > Show/Hide Sidebar (⌃⌘S)

        CommandGroup(after: .newItem) {
            Divider()
            Button("Import Photos…") { journey?.importPhotos() }
                .disabled(journey == nil)
            Button("New Journey from Photos…") {
                newJourneyRequests.fromPhotos = true
                newJourneyRequests.pending = true
                openWindow(id: MacWindowID.shelf)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandGroup(after: .toolbar) {
            Divider()
            Button(journey?.inspectorShown == true ? "Hide Inspector" : "Show Inspector") { journey?.toggleInspector() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(journey == nil)
            Divider()
            Button("Zoom In") { strip?.zoomIn() }
                .keyboardShortcut("+")
                .disabled(strip == nil)
            Button("Zoom Out") { strip?.zoomOut() }
                .keyboardShortcut("-")
                .disabled(strip == nil)
            Button("Fit Journey to Window") { strip?.fit() }
                .keyboardShortcut("0")
                .disabled(strip == nil)
        }

        CommandMenu("Journey") {
            Button("Previous Stop") { strip?.previousStop() }
                .disabled(strip == nil)
            Button("Next Stop") { strip?.nextStop() }
                .disabled(strip == nil)
            Divider()
            Button("Move Stop Earlier") { journey?.moveSelectedStopEarlier?() }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(journey?.moveSelectedStopEarlier == nil)
            Button("Move Stop Later") { journey?.moveSelectedStopLater?() }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(journey?.moveSelectedStopLater == nil)
            Divider()
            Button("Edit Journey Details") { journey?.showDetails() }
                .keyboardShortcut("i")
                .disabled(journey == nil)
            Button("Delete Stop…") {
                if TextInputFocus.isEditing { TextInputFocus.deleteToBeginningOfLine() } else { journey?.deleteSelectedStop?() }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(journey?.deleteSelectedStop == nil)
        }
    }
}
#endif
