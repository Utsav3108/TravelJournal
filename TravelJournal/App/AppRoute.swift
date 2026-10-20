import SwiftUI
import SwiftData

/// Typed navigation routes. Later phases add cases (viewer, export, leg editor...).
enum AppRoute: Hashable {
    case journeyDetail(PersistentIdentifier)
    case stopEditor(journey: PersistentIdentifier, stop: PersistentIdentifier?)
    case story(PersistentIdentifier)
    case coverRack(scope: StoryScope, startStoryID: UUID)
}

extension View {
    /// Attach once on the root of the NavigationStack.
    func appDestinations() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .journeyDetail(let id): JourneyDetailView(journeyID: id)
            case .stopEditor(let journey, let stop): StopEditorRouteView(journeyID: journey, stopID: stop)
            case .story(let id): StoryViewerView(journeyID: id)
            case .coverRack: Text("Cover Rack") // TODO(integration): host wires LibraryCoverRackView
            }
        }
    }
}
