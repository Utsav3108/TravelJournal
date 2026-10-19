import SwiftUI
import CoreText

/// Verified PostScript names (see Resources/Fonts; Lora/Caveat statics instanced from Google variable fonts).
nonisolated enum KraftFontName {
    static let allura = "Allura-Regular"
    static let lora = "Lora-Regular"
    static let loraItalic = "LoraItalic-Italic"
    static let loraSemiBold = "Lora-SemiBold"
    static let caveat = "CaveatRoman-Regular"
    static let caveatBold = "CaveatRoman-Bold"
    static let elite = "SpecialElite-Regular"
}

enum KraftFonts {
    private static let files = ["Allura-Regular", "Lora-Regular", "Lora-Italic", "Lora-SemiBold",
                                "Caveat-Regular", "Caveat-Bold", "SpecialElite-Regular"]

    /// Registers bundled fonts for this process. Safe to call repeatedly. Call before first view body.
    static func register() {
        _ = registered
    }

    private static let registered: Bool = {
        for f in files {
            guard let url = Bundle.main.url(forResource: f, withExtension: "ttf") else {
                assertionFailure("Missing font \(f).ttf")
                continue
            }
            var err: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &err)
        }
        return true
    }()
}

/// Type scale. `scaled` = honours Dynamic Type (editor); default fixed = story/PDF.
enum KraftFont {
    static func title(_ s: CGFloat = 44, scaled: Bool = false) -> Font { make(KraftFontName.allura, s, .largeTitle, scaled) }
    static func stopName(_ s: CGFloat = 30, scaled: Bool = false) -> Font { make(KraftFontName.allura, s, .title, scaled) }
    static func body(_ s: CGFloat = 16, scaled: Bool = false) -> Font { make(KraftFontName.lora, s, .body, scaled) }
    static func bodyItalic(_ s: CGFloat = 16, scaled: Bool = false) -> Font { make(KraftFontName.loraItalic, s, .body, scaled) }
    static func note(_ s: CGFloat = 18, scaled: Bool = false) -> Font { make(KraftFontName.caveat, s, .callout, scaled) }
    static func noteBold(_ s: CGFloat = 18, scaled: Bool = false) -> Font { make(KraftFontName.caveatBold, s, .callout, scaled) }
    static func label(_ s: CGFloat = 11, scaled: Bool = false) -> Font { make(KraftFontName.elite, s, .caption, scaled) }

    /// Body line height 24pt: Lora's natural line height is ~1.28em (20.5pt at 16).
    static let bodyLineSpacing: CGFloat = 3.5

    private static func make(_ name: String, _ size: CGFloat, _ style: Font.TextStyle, _ scaled: Bool) -> Font {
        scaled ? .custom(name, size: size, relativeTo: style) : .custom(name, fixedSize: size)
    }
}

extension View {
    /// Special Elite 11, uppercase, +1.5 tracking.
    func stampLabel(_ size: CGFloat = 11) -> some View {
        font(KraftFont.label(size)).textCase(.uppercase).tracking(1.5)
    }
    /// Lora 16 on 24pt lines.
    func storyBody() -> some View {
        font(KraftFont.body()).lineSpacing(KraftFont.bodyLineSpacing)
    }
}
