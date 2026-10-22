import SwiftUI

enum KraftTarget { case screen, pdf }

/// Page metrics carried through the environment. Geometry never varies by target except margin.
struct KraftTheme: Equatable {
    var target: KraftTarget = .screen
    var margin: CGFloat = 24

    static let phone = KraftTheme(target: .screen, margin: 24)
    static let pdf = KraftTheme(target: .pdf, margin: 36)

    static let a4 = CGSize(width: 595.2, height: 841.8)
    static let rotationRange: ClosedRange<Double> = -4...4
    static let maxTapePerPhoto = 2
    static let maxSealPerPage = 1
}

private struct KraftThemeKey: EnvironmentKey {
    static let defaultValue = KraftTheme.phone
}

extension EnvironmentValues {
    var kraftTheme: KraftTheme {
        get { self[KraftThemeKey.self] }
        set { self[KraftThemeKey.self] = newValue }
    }
}

extension View {
    func kraftTheme(_ theme: KraftTheme) -> some View { environment(\.kraftTheme, theme) }

    /// Seeded tilt, clamped to the global +/-4 degrees (or a tighter per-component limit).
    func seededRotation(_ id: String, limit: Double = 4) -> some View {
        rotationEffect(.degrees(Seed.rotation(id: id, limit: limit)))
    }
}
