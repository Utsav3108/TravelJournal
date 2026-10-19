import SwiftUI

private struct EditorPhotoStoreKey: EnvironmentKey {
    static let defaultValue: any PhotoStoring = FilePhotoStore()
}

extension EnvironmentValues {
    var editorPhotoStore: any PhotoStoring {
        get { self[EditorPhotoStoreKey.self] }
        set { self[EditorPhotoStoreKey.self] = newValue }
    }
}

/// Calm editor chrome shared by the three screens.
extension View {
    func calmForm() -> some View {
        scrollContentBackground(.hidden)
            .background(KraftColor.paper.ignoresSafeArea())
            .tint(KraftColor.route)
    }
}

struct WordCounter: View {
    let text: String
    var limit: Int = WordLimit.stopStory
    var body: some View {
        let state = EditorLogic.counterState(text, limit: limit)
        Text(EditorLogic.counterText(text, limit: limit))
            .font(KraftFont.label(12, scaled: true))
            .foregroundStyle(state == .atLimit ? KraftColor.route : KraftColor.inkSoft)
            .accessibilityLabel("\(WordLimit.count(text)) of \(limit) words")
    }
}
