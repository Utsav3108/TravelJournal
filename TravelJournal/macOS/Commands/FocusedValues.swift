#if os(macOS)
import SwiftUI

/// What the front journey window is showing. Published as a scene value so menu commands (and later the inspector
/// and keyboard navigation) can act on the journey whichever control has focus.
struct JourneyWindowSelection: Equatable {
    var journeyID: UUID
    var selectedStopID: UUID?
}

/// Actions the front journey window offers to the menu bar. Later phases add inspector, sidebar, zoom and
/// move-stop here as they become real.
struct JourneyActions {
    var addStop: () -> Void
}

private struct JourneyWindowSelectionKey: FocusedValueKey { typealias Value = JourneyWindowSelection }
private struct JourneyActionsKey: FocusedValueKey { typealias Value = JourneyActions }

extension FocusedValues {
    var journeySelection: JourneyWindowSelection? {
        get { self[JourneyWindowSelectionKey.self] }
        set { self[JourneyWindowSelectionKey.self] = newValue }
    }

    var journeyActions: JourneyActions? {
        get { self[JourneyActionsKey.self] }
        set { self[JourneyActionsKey.self] = newValue }
    }
}
#endif
