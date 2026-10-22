#if os(macOS)
import SwiftUI

/// Minimal Mac entry for Phase 2: the existing UI in one window. The real scenes (shelf window, journey windows,
/// Settings, menu commands) arrive in Phase 3.
@main
struct TravelJournalMacApp: App {
    @State private var store = StoreLoader(factory: AppContainer.launchFactory())
    private let placeLookup = MapKitPlaceLookup()

    init() {
        KraftFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(store: store, placeLookup: placeLookup)
                .frame(minWidth: 720, minHeight: 480)
        }
    }
}
#endif
