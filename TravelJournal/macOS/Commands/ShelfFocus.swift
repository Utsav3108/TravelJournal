#if os(macOS)
import SwiftUI

/// What the shelf window offers the menu bar. Published only while the bookcase itself has keyboard focus, so
/// ⌘⌫ keeps its text-editing meaning in the search field.
struct ShelfActions {
    var deleteSelected: () -> Void
}

private struct ShelfActionsKey: FocusedValueKey { typealias Value = ShelfActions }

extension FocusedValues {
    var shelfActions: ShelfActions? {
        get { self[ShelfActionsKey.self] }
        set { self[ShelfActionsKey.self] = newValue }
    }
}
#endif
