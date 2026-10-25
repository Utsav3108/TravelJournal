#if os(macOS)
import SwiftUI

/// File → Export… (⌘E) and Print… (⌘P), acting on the front journey window, or on the selected book when the shelf's bookcase has focus.
struct ExportCommands: Commands {
    @FocusedValue(\.exportActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button("Export…") { actions?.export() }
                .keyboardShortcut("e")
                .disabled(actions == nil || MacExportCoordinator.shared.isBusy)
            Button("Print…") { actions?.print() }
                .keyboardShortcut("p")
                .disabled(actions == nil || MacExportCoordinator.shared.isBusy)
        }
    }
}
#endif
