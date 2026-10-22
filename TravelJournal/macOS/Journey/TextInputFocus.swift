#if os(macOS)
import AppKit

/// AppKit edge: SwiftUI can't tell whether a text field currently owns the keyboard. Arrow keys and Space must not
/// drive the story strip while the user is typing a story or a highlight.
enum TextInputFocus {
    @MainActor static var isEditing: Bool {
        NSApp.keyWindow?.firstResponder is NSText   // a focused text field's field editor is an NSTextView
    }
}
#endif
