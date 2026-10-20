import SwiftUI
import SwiftData

/// Navigation destination for `AppRoute.coverRack`: maps the stored journeys to snapshots and hosts the rack.
/// Opening a cover pushes the story's detail screen on the same stack.
struct CoverRackRouteView: View {
    let scope: StoryScope
    let startStoryID: UUID

    @Query(sort: \Journey.date, order: .reverse) private var journeys: [Journey]
    @State private var opened: PersistentIdentifier?

    var body: some View {
        // Mapped in body (one cheap pass) so the rack's first render already has data and honours the start story.
        LibraryCoverRackView(scope: scope, stories: journeys.libraryStories, startStoryID: startStoryID) { story in
            opened = journeys.first { $0.id == story.id }?.persistentModelID
        }
        .navigationTitle(scope.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $opened) { JourneyDetailView(journeyID: $0) }
    }
}
