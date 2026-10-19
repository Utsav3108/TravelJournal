import SwiftUI
import UIKit

// MARK: NoteCard

/// Torn-edge paper holding story text (Lora 16 / 24pt lines).
struct NoteCard<Content: View>: View {
    var variant: Int = 0
    var seed: String = "note"
    var inset: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                TornEdgeShape(variant: variant, seed: seed)
                    .fill(KraftColor.paperDeep)
                    .shadow(color: KraftColor.shadow, radius: 3, y: 1.5)
            )
    }
}

extension NoteCard where Content == Text {
    init(text: String, variant: Int = 0, seed: String = "note", inset: CGFloat = 16) {
        self.init(variant: variant, seed: seed, inset: inset) {
            Text(text)
        }
    }
}

/// Convenience: story-styled note card from plain text.
struct StoryNoteCard: View {
    var text: String
    var variant: Int = 0
    var seed: String = "note"

    var body: some View {
        NoteCard(variant: variant, seed: seed) {
            Text(text)
                .storyBody()
                .foregroundStyle(KraftColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: HighlightStrip

struct HighlightStrip: View {
    var text: String
    var seed: String = "highlight"
    var showsArrow: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(KraftFont.note())
                .foregroundStyle(KraftColor.ink)
                .lineLimit(2)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(MarkerBandShape(seed: seed).fill(KraftColor.highlight))
            if showsArrow {
                HandArrowShape()
                    .stroke(KraftColor.inkSoft, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 40, height: 24)
            }
        }
        .seededRotation(seed, limit: 2.5)
        .accessibilityLabel(text)
    }
}

// MARK: PlaceTicket

struct PlaceTicket: View {
    var number: Int
    var name: String
    var category: KraftCategory = .other
    var arrived: String? = nil
    var spentMinutes: Int? = nil
    var width: CGFloat = 280
    var height: CGFloat = 72
    var seed: String = "ticket"

    var body: some View {
        ZStack(alignment: .topLeading) {
            TicketShape(perforationX: 64)
                .fill(KraftColor.kraft)
                .shadow(color: KraftColor.shadow, radius: 2, y: 1)
            Path { p in
                p.move(to: CGPoint(x: 64, y: 12)); p.addLine(to: CGPoint(x: 64, y: height - 12))
            }
            .stroke(KraftColor.kraftDark, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            HStack(spacing: 0) {
                ZStack {
                    Circle().stroke(KraftColor.stampTeal, lineWidth: 1.5).frame(width: 40, height: 40)
                    CategoryIcon(category: category, size: 26)
                }
                .frame(width: 64, height: height)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(KraftFont.stopName())
                        .foregroundStyle(KraftColor.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    if let line = detail {
                        Text(line).stampLabel().foregroundStyle(KraftColor.inkSoft).lineLimit(1)
                    }
                }
                .padding(.horizontal, 12)
                Spacer(minLength: 0)
            }
            pin.offset(x: -8, y: -8)
        }
        .frame(width: width, height: height)
        .seededRotation(seed, limit: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stop \(number): \(name)")
    }

    private var pin: some View {
        Text("\(number)")
            .font(KraftFont.label(13))
            .foregroundStyle(KraftColor.polaroidWhite)
            .frame(width: 26, height: 26)
            .background(Circle().fill(KraftColor.route))
    }

    private var detail: String? {
        var parts: [String] = []
        if let a = arrived { parts.append("Arrived \(a)") }
        if let m = spentMinutes { parts.append("Spent \(m) min") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: Postmark

/// Round postmark. Arc text top and bottom, centre text; stampTeal at 85%.
struct Postmark: View {
    var top: String = "STOP 2"
    var bottom: String = "MUMBAI"
    var center: String = "12:40"
    var size: CGFloat = 84
    var wavyLines: Bool = false
    var seed: String = "postmark"

    var body: some View {
        let r = size / 2
        ZStack {
            Circle().stroke(KraftColor.stampTeal, lineWidth: 2)
            Circle().stroke(KraftColor.stampTeal, lineWidth: 1).padding(7)
            ArcText(text: top, radius: r - 13, fontSize: 9, bottom: false)
            ArcText(text: bottom, radius: r - 13, fontSize: 9, bottom: true)
            Text(center).font(KraftFont.label(size > 100 ? 17 : 15)).foregroundStyle(KraftColor.stampTeal)
            if wavyLines {
                WavyLines().stroke(KraftColor.stampTeal, lineWidth: 1.5)
                    .frame(width: size * 0.8, height: 20)
                    .offset(x: size * 0.9)
            }
        }
        .frame(width: size, height: size)
        .opacity(0.85)
        .seededRotation(seed, limit: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Postmark \(top) \(bottom) \(center)")
    }

    private struct WavyLines: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            for row in 0..<3 {
                let y = rect.minY + rect.height * (CGFloat(row) + 0.5) / 3
                p.move(to: CGPoint(x: rect.minX, y: y))
                var x = rect.minX
                while x < rect.maxX {
                    p.addQuadCurve(to: CGPoint(x: x + 10, y: y), control: CGPoint(x: x + 5, y: y + (Int(x / 10) % 2 == 0 ? -4 : 4)))
                    x += 10
                }
            }
            return p
        }
    }
}

/// Glyph-by-glyph text on a circular arc. Widths come from the bundled font so layout is deterministic.
struct ArcText: View {
    var text: String
    var radius: CGFloat
    var fontSize: CGFloat = 9
    var bottom: Bool = false
    var maxChars: Int = 28

    var body: some View {
        let chars = Array(String(text.uppercased().prefix(maxChars)))
        let tracking: CGFloat = 1.5
        let widths = chars.map { glyphWidth($0) + tracking }
        let total = widths.reduce(0, +)
        let toDeg = 180 / CGFloat.pi / radius
        var angles: [Double] = []
        var acc: CGFloat = -total / 2
        for w in widths {
            let mid = (acc + w / 2) * toDeg
            angles.append(Double(bottom ? -mid : mid))
            acc += w
        }
        return ZStack {
            ForEach(Array(chars.enumerated()), id: \.offset) { i, c in
                Text(String(c))
                    .font(KraftFont.label(fontSize))
                    .foregroundStyle(KraftColor.stampTeal)
                    .offset(y: bottom ? radius : -radius)
                    .rotationEffect(.degrees(angles[i]))
            }
        }
        // A real frame: a 0x0 frame makes ImageRenderer (PNG/PDF export) drop the glyphs.
        .frame(width: box, height: box)
    }

    private var box: CGFloat { 2 * (radius + fontSize + 4) }

    private func glyphWidth(_ c: Character) -> CGFloat {
        let f = UIFont(name: KraftFontName.elite, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
        return (String(c) as NSString).size(withAttributes: [.font: f]).width
    }
}

// MARK: RatingStamp

struct RatingStamp: View {
    var rating: Int
    var review: String? = nil
    var seed: String = "rating"

    var body: some View {
        let stars = max(0, min(5, rating))
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { i in
                    if i < stars {
                        StarShape().fill(KraftColor.stampTeal).frame(width: 18, height: 18)
                    } else {
                        StarShape().stroke(KraftColor.stampTeal, lineWidth: 1.2).frame(width: 18, height: 18)
                    }
                }
            }
            if let review, !review.isEmpty {
                Text(review).font(KraftFont.note()).foregroundStyle(KraftColor.inkSoft).lineLimit(2).multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 150, height: (review?.isEmpty ?? true) ? 64 : 84)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 6).stroke(KraftColor.stampTeal, lineWidth: 2)
                RoundedRectangle(cornerRadius: 6).stroke(KraftColor.stampTeal.opacity(0.6), lineWidth: 0.8).padding(3.5)
            }
        )
        .seededRotation(seed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating \(stars) of 5" + ((review?.isEmpty ?? true) ? "" : ": \(review ?? "")"))
    }
}

// MARK: WaxSeal

struct WaxSeal: View {
    var glyph: String = "T"
    var size: CGFloat = 56
    var seed: String = "seal"

    var body: some View {
        ZStack {
            SealShape(seed: seed)
                .fill(RadialGradient(colors: [KraftColor.sealRose.opacity(0.85), KraftColor.sealRose, Color(hex: 0x8E5F69)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: size * 0.7))
                .shadow(color: KraftColor.shadow, radius: 2.5, y: 1.5)
            Circle().stroke(Color(hex: 0x8E5F69).opacity(0.7), lineWidth: 1.5).padding(size * 0.14)
            Text(glyph)
                .font(KraftFont.stopName(size * 0.54))
                .foregroundStyle(KraftColor.polaroidWhite.opacity(0.7))
                .offset(y: -size * 0.02)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: PaperClip

struct PaperClip: View {
    var height: CGFloat = 54
    var body: some View {
        PaperClipShape()
            .stroke(LinearGradient(colors: [Color(hex: 0x8D8D8D), Color(hex: 0x5E5E5E)], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .frame(width: height * 14 / 30, height: height)
            .shadow(color: KraftColor.shadow, radius: 1.5, x: 1, y: 1)
            .accessibilityHidden(true)
    }
}

#Preview("Paper components") {
    ZStack {
        PaperBackground()
        ScrollView {
            VStack(spacing: 22) {
                StoryNoteCard(text: "We reached the terminal just after sunrise and the whole building glowed orange. A chai vendor pointed us toward the best dosa in town.", variant: 2, seed: "n")
                HighlightStrip(text: "Best dosa ever!", showsArrow: true)
                PlaceTicket(number: 2, name: "Sardar Pav Bhaji", category: .food, arrived: "12:40", spentMinutes: 45)
                HStack(spacing: 24) {
                    Postmark()
                    Postmark(top: "ARRIVED · 19 OCT 2026", bottom: "MUMBAI", center: "ARRIVED", size: 120)
                }
                RatingStamp(rating: 4, review: "Worth the queue")
                HStack(spacing: 30) { WaxSeal(); PaperClip() }
            }
            .padding(24)
        }
    }
}
