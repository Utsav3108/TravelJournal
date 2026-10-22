import SwiftUI

/// The height of the status bar / Dynamic Island area, measured once at the root, OUTSIDE the navigation stack.
///
/// Inside a navigation stack the top safe area also contains the navigation bar, so it changes when the bar hides or shows.
/// The story viewer needs the constant part (so pages never move when the bar toggles). This replaces reading
/// `UIApplication.shared.connectedScenes...keyWindow.safeAreaInsets.top`.
private struct StatusBarInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var statusBarInset: CGFloat {
        get { self[StatusBarInsetKey.self] }
        set { self[StatusBarInsetKey.self] = newValue }
    }
}

private struct StatusBarInsetReader: ViewModifier {
    @State private var inset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .environment(\.statusBarInset, inset)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { inset = proxy.safeAreaInsets.top }
                        .onChange(of: proxy.safeAreaInsets.top) { _, new in inset = new }
                }
            }
    }
}

extension View {
    /// Apply once at the root, above the `NavigationStack`; descendants read `@Environment(\.statusBarInset)`.
    func measuringStatusBarInset() -> some View { modifier(StatusBarInsetReader()) }
}
