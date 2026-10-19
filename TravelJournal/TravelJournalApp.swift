import SwiftUI
import SwiftData

@main
struct TravelJournalApp: App {
    private let container: ModelContainer
    private let placeLookup = MapKitPlaceLookup()

    init() {
        KraftFonts.register()
        let uiTest = ProcessInfo.processInfo.arguments.contains("-uitest")
        container = AppContainer.make(inMemory: uiTest)
    }

    var body: some Scene {
        WindowGroup {
            JourneyShelfView()
                .preferredColorScheme(.light)
                .environment(\.servicePlaceLookup, placeLookup)
        }
        .modelContainer(container)
    }
}
