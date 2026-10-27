import Foundation
import CoreGraphics
import CoreText

// Pure, nonisolated helpers shared by the story page views. No SwiftUI view types here so tests can call them freely.

/// Same FNV-1a + splitmix64 constants as `Seed` / `SeededStream` in the DesignSystem (which are main-actor by module default),
/// duplicated here so layout code can stay nonisolated. A test pins the two together.
nonisolated enum PageSeed {
    static func fnv1a(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return h
    }

    static func mix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9e3779b97f4a7c15
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }

    /// Degrees in -limit...limit (limit clamped to 4); identical to `Seed.rotation(id:limit:)`.
    static func rotation(id: String, limit: Double = 4) -> Double {
        var s = Stream(id, "rot")
        return s.range(-min(limit, 4), min(limit, 4))
    }

    nonisolated struct Stream {
        private var state: UInt64
        init(_ id: String, _ salt: String) { state = PageSeed.mix(PageSeed.fnv1a(id + "|" + salt)) }
        mutating func next() -> UInt64 { state = PageSeed.mix(state); return state }
        mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
        mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * unit() }
    }
}

/// Deterministic text measurement with the bundled fonts (falls back to the system font when they are not registered).
/// Pure CoreText, so it behaves the same on every platform and needs no UIKit/AppKit font type.
nonisolated enum PageText {
    static func font(_ name: String, _ size: CGFloat) -> CTFont {
        let f = CTFontCreateWithName(name as CFString, size, nil)
        // CTFontCreateWithName silently substitutes Helvetica for unknown names; `UIFont(name:)` returned nil there.
        let postScript = CTFontCopyPostScriptName(f) as String, full = CTFontCopyFullName(f) as String
        if postScript == name || full == name { return f }
        return CTFontCreateUIFontForLanguage(.system, size, nil) ?? f
    }

    private static func attributed(_ text: String, _ font: CTFont) -> CFAttributedString {
        let attrs = [kCTFontAttributeName: font] as CFDictionary
        return CFAttributedStringCreate(nil, text as CFString, attrs)
    }

    /// Height of wrapped text; matches SwiftUI `Text` + `.lineSpacing(lineSpacing)` (line height = font line height + spacing).
    static func height(_ text: String, fontName: String, size: CGFloat, lineSpacing: CGFloat, width: CGFloat) -> CGFloat {
        guard !text.isEmpty, width > 1 else { return 0 }
        let f = font(fontName, size)
        // Hard line breaks start a new paragraph; an empty paragraph still takes one line.
        var lines = 0
        var total: CGFloat = 0
        for paragraph in text.components(separatedBy: "\n") {
            guard !paragraph.isEmpty else {
                total += lineHeight(of: f)
                lines += 1
                continue
            }
            let typesetter = CTTypesetterCreateWithAttributedString(attributed(paragraph, f))
            let length = (paragraph as NSString).length
            var start = 0
            while start < length {
                let count = max(1, CTTypesetterSuggestLineBreak(typesetter, start, Double(width)))
                let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
                var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
                _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
                total += ascent + descent + leading
                lines += 1
                start += count
            }
        }
        return ceil(total + lineSpacing * CGFloat(max(lines - 1, 0)))
    }

    private static func lineHeight(of f: CTFont) -> CGFloat {
        CTFontGetAscent(f) + CTFontGetDescent(f) + CTFontGetLeading(f)
    }

    /// Exact single-line advance, not rounded.
    static func advance(_ text: String, fontName: String, size: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let line = CTLineCreateWithAttributedString(attributed(text, font(fontName, size)))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// Single-line width including tracking, rounded up.
    static func width(_ text: String, fontName: String, size: CGFloat, tracking: CGFloat = 0) -> CGFloat {
        ceil(advance(text, fontName: fontName, size: size) + tracking * CGFloat(text.count))
    }
}

nonisolated enum PageFormat {
    static func time(_ d: Date?, timeZone: TimeZone? = nil) -> String? {
        guard let d else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        if let tz = timeZone { f.timeZone = tz }
        return f.string(from: d)
    }

    /// "ARRIVED · 19 OCT 2026 · MUMBAI" -> (center "ARRIVED", top "19 OCT 2026", bottom "MUMBAI").
    static func postmarkParts(_ s: String) -> (center: String, top: String, bottom: String) {
        let parts = s.components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let center = parts.first ?? ""
        let top = parts.count >= 2 ? parts[1] : ""
        let bottom = parts.count >= 3 ? parts[2...].joined(separator: " · ") : ""
        return (center, top, bottom)
    }

    static func numeral(_ v: Double?, decimals: Int = 1) -> String {
        guard let v else { return "–" }
        return String(format: "%.\(decimals)f", v)
    }
}
