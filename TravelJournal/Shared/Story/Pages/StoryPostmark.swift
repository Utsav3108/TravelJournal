import SwiftUI

/// Postmark for story pages. Same look as the DesignSystem `Postmark`, but the arc text lives in a full-size frame:
/// the DesignSystem `ArcText` uses a 0x0 frame, which `ImageRenderer` (PDF/PNG export) drops, so its arcs never print.
struct StoryPostmark: View {
    var top: String
    var bottom: String
    var center: String
    var size: CGFloat = 84
    var seed: String = "postmark"

    var body: some View {
        let r = size / 2
        ZStack {
            Circle().stroke(KraftColor.stampTeal, lineWidth: 2)
            Circle().stroke(KraftColor.stampTeal, lineWidth: 1).padding(7)
            StoryArcText(text: top, radius: r - 13, box: size, bottom: false)
            StoryArcText(text: bottom, radius: r - 13, box: size, bottom: true)
            Text(center).font(KraftFont.label(size > 100 ? 17 : (size >= 80 ? 15 : 11))).foregroundStyle(KraftColor.stampTeal)
                .lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 16)
        }
        .frame(width: size, height: size)
        .opacity(0.85)
        .seededRotation(seed, limit: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Postmark \(top) \(bottom) \(center)")
    }
}

struct StoryArcText: View {
    var text: String
    var radius: CGFloat
    var box: CGFloat
    var fontSize: CGFloat = 9
    var bottom: Bool = false
    var maxChars: Int = 28

    var body: some View {
        let chars = Array(String(text.uppercased().prefix(maxChars)))
        let widths = chars.map { PageText.width(String($0), fontName: PageFont.elite, size: fontSize) + 1.5 }
        let angles = Self.angles(widths: widths, radius: radius, bottom: bottom)
        ZStack {
            ForEach(Array(chars.enumerated()), id: \.offset) { i, c in
                Text(String(c))
                    .font(KraftFont.label(fontSize))
                    .foregroundStyle(KraftColor.stampTeal)
                    .offset(y: bottom ? radius : -radius)
                    .rotationEffect(.degrees(angles[i]))
            }
        }
        .frame(width: box, height: box)
    }

    /// Per-glyph rotation (degrees) so the string is centred on the top (or bottom) of the circle.
    nonisolated static func angles(widths: [CGFloat], radius: CGFloat, bottom: Bool) -> [Double] {
        let total = widths.reduce(0, +)
        let toDeg = 180 / CGFloat.pi / max(radius, 1)
        var out: [Double] = []
        var acc = -total / 2
        for w in widths {
            let mid = (acc + w / 2) * toDeg
            out.append(Double(bottom ? -mid : mid))
            acc += w
        }
        return out
    }
}
