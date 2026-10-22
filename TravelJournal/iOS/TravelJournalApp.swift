#if os(iOS)
import SwiftUI

@main
struct TravelJournalApp: App {
    @State private var store = StoreLoader(factory: AppContainer.launchFactory())
    private let placeLookup = MapKitPlaceLookup()

    init() {
        KraftFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(store: store, placeLookup: placeLookup)
        }
    }
}
#endif
