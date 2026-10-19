import SwiftUI

// MARK: Polaroid

/// Hero polaroid. Square window, side/top pad 5% of width, bottom strip 22% of width.
struct Polaroid: View {
    var photo: Image?
    var caption: String = ""
    var width: CGFloat = 230
    var seed: String = "polaroid"

    var body: some View {
        let pad = width * 0.05
        let window = width - pad * 2
        let strip = width * 0.22
        VStack(spacing: 0) {
            Group {
                if let photo { photo.resizable().scaledToFill() } else { KraftPhotoPlaceholder() }
            }
            .frame(width: window, height: window)
            .clipped()
            .overlay(Rectangle().stroke(KraftColor.kraftDark.opacity(0.3), lineWidth: 0.5))
            Text(caption)
                .font(KraftFont.note())
                .foregroundStyle(KraftColor.inkSoft)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: window, height: strip)
        }
        .padding(.horizontal, pad)
        .padding(.top, pad)
        .background(Rectangle().fill(KraftColor.polaroidWhite))
        .shadow(color: KraftColor.shadow, radius: 4, y: 2)
        .seededRotation(seed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption.isEmpty ? "Photo" : "Photo: \(caption)")
    }
}

// MARK: Washi tape

enum WashiVariant: Int, CaseIterable {
    case kraft, pinkGrid, floral

    static func seeded(_ seed: String) -> WashiVariant {
        var s = SeededStream(seed, "tape")
        return allCases[s.int(allCases.count)]
    }
}

struct WashiTape: View {
    var variant: WashiVariant = .kraft
    var size: CGSize = CGSize(width: 64, height: 22)

    var body: some View {
        WashiShape()
            .fill(fill)
            .overlay(pattern.clipShape(WashiShape()))
            .frame(width: size.width, height: size.height)
            .opacity(0.85)
            .shadow(color: KraftColor.shadow.opacity(0.5), radius: 1, y: 1)
            .accessibilityHidden(true)
    }

    private var fill: Color {
        switch variant {
        case .kraft: return KraftColor.kraft
        case .pinkGrid: return KraftColor.sealRose.opacity(0.45)
        case .floral: return KraftColor.paperDeep
        }
    }

    @ViewBuilder private var pattern: some View {
        switch variant {
        case .kraft:
            Image(uiImage: PaperGrain.tile).resizable(resizingMode: .tile).opacity(0.8)
        case .pinkGrid:
            Canvas { ctx, sz in
                var p = Path()
                var x: CGFloat = 0
                while x < sz.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: sz.height)); x += 6 }
                var y: CGFloat = 0
                while y < sz.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: sz.width, y: y)); y += 6 }
                ctx.stroke(p, with: .color(KraftColor.polaroidWhite.opacity(0.7)), lineWidth: 0.5)
            }
        case .floral:
            Canvas { ctx, sz in
                var cx: CGFloat = 6
                var row = 0
                while cx < sz.width {
                    let cy = row % 2 == 0 ? sz.height * 0.32 : sz.height * 0.68
                    for k in 0..<5 {
                        let a = Double(k) * 2 * .pi / 5
                        let r: CGFloat = 1.8
                        let petal = CGRect(x: cx + 2.2 * CGFloat(cos(a)) - r, y: cy + 2.2 * CGFloat(sin(a)) - r, width: 2 * r, height: 2 * r)
                        ctx.fill(Path(ellipseIn: petal), with: .color(KraftColor.stampTeal.opacity(0.45)))
                    }
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - 1, y: cy - 1, width: 2, height: 2)), with: .color(KraftColor.highlight))
                    cx += 11; row += 1
                }
            }
        }
    }
}

// MARK: Taped photo

/// Unframed print with a 4pt white border and 1-2 washi strips. Max 2 tapes.
struct TapedPhoto: View {
    var photo: Image?
    var size: CGSize = CGSize(width: 150, height: 112)
    var tapes: Int = 1
    var seed: String = "taped"

    var body: some View {
        let count = max(0, min(KraftTheme.maxTapePerPhoto, tapes))
        let rot = Seed.rotation(id: seed)
        ZStack {
            Group {
                if let photo { photo.resizable().scaledToFill() } else { KraftPhotoPlaceholder(hue: 0.55) }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .padding(4)
            .background(KraftColor.polaroidWhite)
            .shadow(color: KraftColor.shadow, radius: 3, y: 1.5)
            .overlay(alignment: count == 1 ? .top : .topLeading) {
                if count >= 1 { tape(1).offset(x: count == 1 ? 0 : -14, y: -8) }
            }
            .overlay(alignment: .bottomTrailing) {
                if count >= 2 { tape(2).offset(x: 14, y: 8) }
            }
        }
        .rotationEffect(.degrees(rot))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Photo")
    }

    private func tape(_ i: Int) -> some View {
        let jitter = Seed.rotation(id: seed + "/tape\(i)", limit: 4)
        let clamped = max(-4, min(4, Seed.rotation(id: seed) + jitter)) - Seed.rotation(id: seed)
        return WashiTape(variant: WashiVariant.seeded(seed + "/tape\(i)"))
            .rotationEffect(.degrees(clamped))
    }
}

#Preview("Polaroid + Taped") {
    ZStack {
        PaperBackground()
        VStack(spacing: 30) {
            Polaroid(photo: nil, caption: "Gateway of India", width: 220, seed: "a")
            HStack(spacing: 24) {
                TapedPhoto(photo: nil, tapes: 1, seed: "b")
                TapedPhoto(photo: nil, size: CGSize(width: 112, height: 150), tapes: 2, seed: "c")
            }
            HStack { ForEach(WashiVariant.allCases, id: \.rawValue) { WashiTape(variant: $0) } }
        }
    }
}
