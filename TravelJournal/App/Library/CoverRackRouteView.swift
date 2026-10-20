import SwiftUI
import SwiftData

/// Navigation destination for `AppRoute.coverRack`: maps the stored journeys to snapshots and hosts the rack.
/// Opening a cover pushes the story's detail screen on the same stack.
struct CoverRackRouteView: View {
    let scope: StoryScope
    let startStoryID: UUID

    @Query(sort: \Journey.date, order: .reverse) private var journeys: [Journey]
    @State private var stories: [LibraryStory] = []
    @State private var opened: PersistentIdentifier?

    var body: some View {
        LibraryCoverRackView(scope: scope, stories: stories, startStoryID: startStoryID) { story in
            opened = journeys.first { $0.id == story.id }?.persistentModelID
        }
        .navigationTitle(scope.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $opened) { JourneyDetailView(journeyID: $0) }
        .onAppear { stories = journeys.libraryStories }
        .onChange(of: journeys) { stories = journeys.libraryStories }
    }
}
