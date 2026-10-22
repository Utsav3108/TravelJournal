#if os(macOS)
import SwiftUI

/// Mac scenes: one shelf window, one window per journey, Settings, and the menu bar commands.
@main
struct TravelJournalMacApp: App {
    @State private var store = StoreLoader(factory: AppContainer.launchFactory())
    @State private var newJourneyRequests = NewJourneyRequests()
    private let placeLookup = MapKitPlaceLookup()

    init() {
        KraftFonts.register()
    }

    var body: some Scene {
        Window("My Stories", id: MacWindowID.shelf) {
            ShelfWindowRoot(store: store, placeLookup: placeLookup)
                .environment(\.newJourneyRequests, newJourneyRequests)
        }
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands { AppCommands(newJourneyRequests: newJourneyRequests) }

        WindowGroup("Journey", for: UUID.self) { $journeyID in
            if let journeyID {
                JourneyWindowRoot(store: store, placeLookup: placeLookup, journeyID: journeyID)
            }
        }
        .defaultSize(width: 1100, height: 700)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)

        Settings { MacSettingsView() }
    }
}
#endif
