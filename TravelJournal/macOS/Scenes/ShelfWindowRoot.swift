#if os(macOS)
import SwiftUI

/// The single shelf window. Opens journeys in their own windows instead of pushing them.
struct ShelfWindowRoot: View {
    let store: StoreLoader
    let placeLookup: MapKitPlaceLookup

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        AppRootView(store: store, placeLookup: placeLookup)
            .environment(\.openJourney, { journey in openWindow(value: journey.id) })
            .syncStatusPresentation()
            .frame(minWidth: 720, minHeight: 480)
    }
}
#endif
