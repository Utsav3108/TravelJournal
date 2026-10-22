import SwiftUI
import SwiftData

@main
struct TravelJournalApp: App {
    @State private var store = StoreLoader(factory: AppContainer.launchFactory())
    private let placeLookup = MapKitPlaceLookup()

    init() {
        KraftFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch store.state {
                case .ready(let container):
                    JourneyShelfView()
                        .environment(\.servicePlaceLookup, placeLookup)
                        .modelContainer(container)
                        .task { PhotoCache.warm(context: container.mainContext, store: FilePhotoStore()) }
                case .failed:
                    StoreFailureView(onRetry: { store.load() })
                }
            }
            .preferredColorScheme(.light)
        }
    }
}
