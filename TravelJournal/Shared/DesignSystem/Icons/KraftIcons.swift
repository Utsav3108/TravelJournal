import SwiftUI

/// Tiny 24x24-grid path builder for the ink-line icons.
private struct Pen {
    var path = Path()
    let ox: CGFloat, oy: CGFloat, s: CGFloat

    init(_ rect: CGRect) {
        s = min(rect.width, rect.height) / 24
        ox = rect.midX - 12 * s
        oy = rect.midY - 12 * s
    }

    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }

    mutating func poly(_ pts: [(CGFloat, CGFloat)], close: Bool = false) {
        guard let f = pts.first else { return }
        path.move(to: pt(f.0, f.1))
        for q in pts.dropFirst() { path.addLine(to: pt(q.0, q.1)) }
        if close { path.closeSubpath() }
    }

    mutating func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
        path.addEllipse(in: CGRect(x: ox + (cx - r) * s, y: oy + (cy - r) * s, width: 2 * r * s, height: 2 * r * s))
    }

    mutating func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) {
        path.addRoundedRect(in: CGRect(x: ox + x * s, y: oy + y * s, width: w * s, height: h * s),
                            cornerSize: CGSize(width: r * s, height: r * s))
    }

    mutating func curve(_ from: (CGFloat, CGFloat), _ to: (CGFloat, CGFloat), _ c1: (CGFloat, CGFloat), _ c2: (CGFloat, CGFloat)) {
        path.move(to: pt(from.0, from.1))
        path.addCurve(to: pt(to.0, to.1), control1: pt(c1.0, c1.1), control2: pt(c2.0, c2.1))
    }
}

struct CategoryIconShape: Shape {
    var category: KraftCategory

    func path(in rect: CGRect) -> Path {
        var p = Pen(rect)
        switch category {
        case .food: // bowl with steam
            p.poly([(3, 12), (21, 12)])
            p.curve((3, 12), (21, 12), (4, 20), (20, 20))
            p.curve((9, 9), (9, 4), (7.5, 7), (10.5, 6))
            p.curve((15, 9), (15, 4), (13.5, 7), (16.5, 6))
        case .landmark: // pillared building
            p.poly([(3, 9), (12, 3), (21, 9)], close: true)
            for x: CGFloat in [6, 10, 14, 18] { p.poly([(x, 11), (x, 18)]) }
            p.poly([(3, 20.5), (21, 20.5)])
        case .temple: // dome and spire
            p.poly([(4, 20), (20, 20)])
            p.poly([(6, 20), (6, 12)])
            p.poly([(18, 20), (18, 12)])
            p.curve((6, 12), (12, 4.5), (6, 8), (10, 6.5))
            p.curve((18, 12), (12, 4.5), (18, 8), (14, 6.5))
            p.poly([(12, 4.5), (12, 1.5)])
            p.poly([(10, 20), (10, 16), (14, 16), (14, 20)])
        case .stay: // bed
            p.poly([(3, 7), (3, 19)])
            p.poly([(3, 15), (21, 15), (21, 19)])
            p.poly([(10, 15), (10, 11), (19, 11), (21, 13), (21, 15)])
            p.rrect(4.5, 9.5, 4.5, 3.5, 1.5)
        case .shopping: // bag
            p.poly([(5, 8), (19, 8), (20, 20), (4, 20)], close: true)
            p.curve((9, 8), (15, 8), (9, 2.5), (15, 2.5))
        case .nature: // leaf
            p.curve((5, 19), (19, 5), (5, 9), (12, 4))
            p.curve((19, 5), (5, 19), (20, 13), (15, 19))
            p.poly([(5, 19), (14, 10)])
        case .other: // generic pin
            p.circle(12, 9, 6)
            p.poly([(7.6, 13.2), (12, 21), (16.4, 13.2)])
            p.circle(12, 9, 2)
        }
        return p.path
    }
}

struct TransportIconShape: Shape {
    var mode: KraftTransport

    func path(in rect: CGRect) -> Path {
        var p = Pen(rect)
        switch mode {
        case .walk:
            p.circle(13, 4, 1.8)
            p.poly([(12, 8), (11, 14)])
            p.poly([(11, 14), (8, 20)])
            p.poly([(11, 14), (14, 17), (14, 21)])
            p.poly([(8, 11), (12, 9), (16, 12)])
        case .autoRickshaw:
            p.poly([(3, 13), (3, 7), (14, 7), (19, 13)])
            p.poly([(3, 13), (21, 13), (21, 17), (3, 17)], close: true)
            p.poly([(8, 7), (8, 13)])
            p.circle(7, 18.5, 2.3)
            p.circle(18, 18.5, 2.3)
        case .taxi:
            p.poly([(3, 17), (3, 12), (5.5, 12), (8, 8), (16, 8), (18.5, 12), (21, 12), (21, 17), (3, 17)], close: true)
            p.rrect(9.5, 4.5, 5, 2.5, 0.8)
            p.circle(7.5, 17.5, 2)
            p.circle(16.5, 17.5, 2)
        case .bus:
            p.rrect(4, 3.5, 16, 14, 3)
            p.poly([(4, 11), (20, 11)])
            p.poly([(7, 17.5), (7, 20)])
            p.poly([(17, 17.5), (17, 20)])
            p.circle(8, 14.2, 0.6)
            p.circle(16, 14.2, 0.6)
        case .train:
            p.rrect(5, 3, 14, 15, 4)
            p.rrect(8, 6, 8, 5, 1)
            p.poly([(8, 18), (6, 21)])
            p.poly([(16, 18), (18, 21)])
            p.circle(9, 14.5, 0.7)
            p.circle(15, 14.5, 0.7)
        case .metro:
            p.rrect(4, 5, 16, 12, 5)
            p.rrect(7, 8, 10, 4, 1)
            p.poly([(9, 2), (15, 2)])
            p.poly([(12, 2), (12, 5)])
            p.poly([(7, 17), (6, 21)])
            p.poly([(17, 17), (18, 21)])
            p.circle(8.5, 14.5, 0.6)
            p.circle(15.5, 14.5, 0.6)
        case .bike:
            p.circle(6, 16, 4)
            p.circle(18, 16, 4)
            p.poly([(6, 16), (10, 9)])
            p.poly([(10, 9), (11, 16)])
            p.poly([(11, 16), (15, 9)])
            p.poly([(10, 9), (15, 9)])
            p.poly([(15, 9), (18, 16)])
            p.poly([(15, 9), (14, 6.5), (17, 6.5)])
            p.poly([(8.5, 7.5), (11.5, 7.5)])
        case .ferry:
            p.poly([(3, 14), (21, 14), (18, 19), (6, 19)], close: true)
            p.rrect(7, 9, 10, 5, 1)
            p.rrect(10.5, 5, 3, 4, 0.5)
            p.curve((2, 21.5), (22, 21.5), (7, 19.5), (17, 23.5))
        }
        return p.path
    }
}

/// Ink-line category icon (hand-drawn style, stroke only).
struct CategoryIcon: View {
    var category: KraftCategory
    var size: CGFloat = 24
    var color: Color = KraftColor.stampTeal

    var body: some View {
        CategoryIconShape(category: category)
            .stroke(color, style: StrokeStyle(lineWidth: max(1.2, size / 16), lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityLabel(category.rawValue)
    }
}

/// Ink-line transport icon.
struct TransportIcon: View {
    var mode: KraftTransport
    var size: CGFloat = 24
    var color: Color = KraftColor.ink

    var body: some View {
        TransportIconShape(mode: mode)
            .stroke(color, style: StrokeStyle(lineWidth: max(1.2, size / 16), lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityLabel(mode.rawValue)
    }
}

#Preview("Icons") {
    VStack(spacing: 16) {
        HStack(spacing: 12) { ForEach(KraftCategory.allCases) { CategoryIcon(category: $0, size: 40) } }
        HStack(spacing: 8) { ForEach(KraftTransport.allCases) { TransportIcon(mode: $0, size: 36) } }
    }
    .padding()
    .background(KraftColor.paper)
}
