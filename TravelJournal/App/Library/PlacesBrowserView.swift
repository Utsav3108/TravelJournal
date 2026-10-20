import SwiftUI

/// CONTRACT STUB: Agent E replaces this file. Signature is frozen.
/// Presented in a sheet by the host. Calls `onSelect` with a country or city scope, then the host dismisses and pushes the rack.
struct PlacesBrowserView: View {
    let stories: [LibraryStory]
    let onSelect: (StoryScope) -> Void

    var body: some View { Text("Places") }
}
