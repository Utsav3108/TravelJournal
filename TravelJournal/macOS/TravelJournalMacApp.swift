#if os(macOS)
import SwiftUI
import SwiftData

/// Mac scenes: one shelf window, one window per journey, Settings, and the menu bar commands.
@main
struct TravelJournalMacApp: App {
    @State private var store: StoreLoader
    @State private var sync: SyncStatusModel
    @State private var newJourneyRequests = NewJourneyRequests()
    private let placeLookup = MapKitPlaceLookup()

    init() {
        KraftFonts.register()
        ExportPrivacySync.shared.start()   // no-op while ExportPrivacySync.enabled is false
        let store = StoreLoader(factory: AppContainer.launchFactory())
        _store = State(initialValue: store)
        _sync = State(initialValue: SyncStatusModel.live(hasLocalData: {
            guard case .ready(let container) = store.state else { return false }
            return ((try? container.mainContext.fetchCount(FetchDescriptor<Journey>())) ?? 0) > 0
        }))
    }

    var body: some Scene {
        Window("My Journeys", id: MacWindowID.shelf) {
            ShelfWindowRoot(store: store, placeLookup: placeLookup)
                .environment(\.newJourneyRequests, newJourneyRequests)
                .environment(\.syncState, sync.state)
        }
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            AppCommands(newJourneyRequests: newJourneyRequests)
            ShelfCommands()
            JourneyCommands(newJourneyRequests: newJourneyRequests)
            ExportCommands()
        }

        WindowGroup("Journey", for: UUID.self) { $journeyID in
            if let journeyID {
                JourneyWindowRoot(store: store, placeLookup: placeLookup, journeyID: journeyID)
                    .environment(\.newJourneyRequests, newJourneyRequests)
                    .environment(\.syncState, sync.state)
            }
        }
        .defaultSize(width: 1100, height: 700)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)

        Settings { MacSettingsView().environment(\.syncState, sync.state) }
    }
}
#endif
