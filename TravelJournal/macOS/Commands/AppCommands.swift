#if os(macOS)
import SwiftUI

/// Menu bar items that work today. Items for later phases (export, print, zoom, inspector, undo wiring...) are added
/// by the phase that makes them work; nothing is left in the menus as a disabled stub.
struct AppCommands: Commands {
    let newJourneyRequests: NewJourneyRequests

    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.journeyActions) private var journeyActions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Journey") {
                newJourneyRequests.pending = true
                openWindow(id: MacWindowID.shelf)
            }
            .keyboardShortcut("n")

            Button("Add Stop") { journeyActions?.addStop() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(journeyActions == nil)
        }
    }
}

enum MacWindowID {
    static let shelf = "shelf"
}
#endif
