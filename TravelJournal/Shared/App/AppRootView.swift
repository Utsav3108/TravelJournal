import SwiftUI
import SwiftData

/// What every platform's window shows: the shelf once the store opened, or the failure screen. No model container is
/// attached on failure, so no screen can read an empty stand-in for the user's data.
struct AppRootView: View {
    let store: StoreLoader
    let placeLookup: MapKitPlaceLookup

    var body: some View {
        Group {
            switch store.state {
            case .ready(let container):
                JourneyShelfView()
                    .environment(\.servicePlaceLookup, placeLookup)
                    .modelContainer(container)
            case .failed:
                StoreFailureView(onRetry: { store.load() })
            }
        }
        .preferredColorScheme(.light)
    }
}
