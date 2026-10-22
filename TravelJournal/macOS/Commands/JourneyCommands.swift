#if os(macOS)
import SwiftUI

/// Menu items for the journey window: sidebar, zoom, previous/next stop. They act on the front journey window through
/// `StripActions` and grey out when it is not showing the strip (shelf in front, or the list editor open).
/// The arrow keys themselves are handled by the strip, so they cannot fire while a text field has focus.
struct JourneyCommands: Commands {
    @FocusedValue(\.stripActions) private var strip

    var body: some Commands {
        SidebarCommands()   // View > Show/Hide Sidebar (⌃⌘S)

        CommandGroup(after: .toolbar) {
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
        }
    }
}
#endif
