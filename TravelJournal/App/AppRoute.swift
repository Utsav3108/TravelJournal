import SwiftUI
import SwiftData

/// Typed navigation routes. Later phases add cases (viewer, export, leg editor...).
enum AppRoute: Hashable {
    case journeyDetail(PersistentIdentifier)
    case stopEditor(journey: PersistentIdentifier, stop: PersistentIdentifier?)
}

extension View {
    /// Attach once on the root of the NavigationStack.
    func appDestinations() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .journeyDetail(let id): JourneyDetailView(journeyID: id)
            case .stopEditor(let journey, let stop): StopEditorRouteView(journeyID: journey, stopID: stop)
            }
        }
    }
}
