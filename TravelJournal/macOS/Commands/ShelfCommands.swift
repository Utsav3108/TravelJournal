#if os(macOS)
import SwiftUI

/// Menu items for the shelf window (Phase 4a): Delete on the selected book.
struct ShelfCommands: Commands {
    @FocusedValue(\.shelfActions) private var shelfActions

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button("Delete") { shelfActions?.deleteSelected() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(shelfActions == nil)
        }
    }
}
#endif
