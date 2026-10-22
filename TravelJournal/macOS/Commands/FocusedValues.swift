#if os(macOS)
import SwiftUI

/// What the front journey window is showing. Published as a scene value so menu commands (and later the inspector
/// and keyboard navigation) can act on the journey whichever control has focus.
struct JourneyWindowSelection: Equatable {
    var journeyID: UUID
    var selectedStopID: UUID?
}

/// Actions the front journey window offers to the menu bar. Optional closures are nil when they don't apply
/// (nothing selected, already first or last), so the menu items grey out.
struct JourneyActions {
    var addStop: () -> Void
    var importPhotos: () -> Void
    var showDetails: () -> Void
    var toggleInspector: () -> Void
    var inspectorShown: Bool
    var deleteSelectedStop: (() -> Void)?
    var moveSelectedStopEarlier: (() -> Void)?
    var moveSelectedStopLater: (() -> Void)?
}

/// What the journey window offers while it shows the story strip (nil while editing, so these menu items grey out).
/// Separate from `JourneyActions` because the list editor sets that value from deeper in the view tree.
struct StripActions {
    var zoomIn: () -> Void
    var zoomOut: () -> Void
    var fit: () -> Void
    var previousStop: () -> Void
    var nextStop: () -> Void
}

private struct JourneyWindowSelectionKey: FocusedValueKey { typealias Value = JourneyWindowSelection }
private struct JourneyActionsKey: FocusedValueKey { typealias Value = JourneyActions }
private struct StripActionsKey: FocusedValueKey { typealias Value = StripActions }

extension FocusedValues {
    var journeySelection: JourneyWindowSelection? {
        get { self[JourneyWindowSelectionKey.self] }
        set { self[JourneyWindowSelectionKey.self] = newValue }
    }

    var journeyActions: JourneyActions? {
        get { self[JourneyActionsKey.self] }
        set { self[JourneyActionsKey.self] = newValue }
    }

    var stripActions: StripActions? {
        get { self[StripActionsKey.self] }
        set { self[StripActionsKey.self] = newValue }
    }
}
#endif
