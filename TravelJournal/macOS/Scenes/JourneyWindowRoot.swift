#if os(macOS)
import SwiftUI
import SwiftData

/// One window per journey, keyed by `Journey.id`. Shares the shelf's store, so an edit in either shows in both.
struct JourneyWindowRoot: View {
    let store: StoreLoader
    let placeLookup: MapKitPlaceLookup
    let journeyID: UUID

    var body: some View {
        Group {
            switch store.state {
            case .ready(let container):
                JourneyWindowContent(journeyID: journeyID)
                    .environment(\.servicePlaceLookup, placeLookup)
                    .modelContainer(container)
            case .failed:
                StoreFailureView(onRetry: { store.load() })
            }
        }
        .preferredColorScheme(.light)
    }
}

private struct JourneyWindowContent: View {
    let journeyID: UUID

    @Environment(\.dismiss) private var dismiss
    @Query private var matches: [Journey]

    init(journeyID: UUID) {
        self.journeyID = journeyID
        _matches = Query(filter: Journey.matching(id: journeyID))
    }

    var body: some View {
        Group {
            if let journey = matches.first {
                NavigationStack {
                    JourneyDetailView(journeyID: journey.persistentModelID)
                        .appDestinations()
                }
                .measuringStatusBarInset()
                .tint(KraftColor.route)
                .focusedSceneValue(\.journeySelection, JourneyWindowSelection(journeyID: journeyID))
            } else {
                ContentUnavailableView("Story not found", systemImage: "book.closed")
            }
        }
        .frame(minWidth: 1000, minHeight: 640)
        // Deleting the journey (from the shelf, or here) closes its window.
        .onChange(of: matches.isEmpty) { _, gone in if gone { dismiss() } }
    }
}
#endif
