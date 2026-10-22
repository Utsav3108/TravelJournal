import SwiftUI
import SwiftData

// MARK: - Palette (own world, separate from Vintage Kraft)

private enum Wood {
    static let wall = Color(red: 0.93, green: 0.89, blue: 0.82)
    static let wallDark = Color(red: 0.84, green: 0.78, blue: 0.69)
    static let frameLight = Color(red: 0.55, green: 0.35, blue: 0.19)
    static let frameDark = Color(red: 0.36, green: 0.21, blue: 0.10)
    static let plankLight = Color(red: 0.66, green: 0.43, blue: 0.23)
    static let plankDark = Color(red: 0.45, green: 0.27, blue: 0.13)
    static let backLight = Color(red: 0.36, green: 0.22, blue: 0.12)
    static let backDark = Color(red: 0.22, green: 0.13, blue: 0.07)
    static let gold = Color(red: 0.96, green: 0.80, blue: 0.40)
    static let goldDeep = Color(red: 0.78, green: 0.60, blue: 0.22)
}

/// Deterministic hash (Swift's hashValue is seeded per launch, so it can't be used for stable looks).
private func stableHash(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
    return h
}

private struct SeededRNG {
    var state: UInt64
    init(_ seed: UInt64) { state = seed == 0 ? 0x9e3779b97f4a7c15 : seed }
    mutating func next() -> Double {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Double(state % 100_000) / 100_000
    }
}

// MARK: - Spine model

private struct SpineLook {
    let width: CGFloat
    let height: CGFloat
    let base: Color
    let band: Int          // 0 double band, 1 single wide, 2 thin triple
    let tilt: Double       // resting lean (degrees), rare

    private static let tones: [(Double, Double, Double)] = [
        (0.47, 0.13, 0.15), (0.13, 0.30, 0.25), (0.14, 0.22, 0.39), (0.55, 0.30, 0.13),
        (0.31, 0.16, 0.26), (0.33, 0.30, 0.15), (0.60, 0.20, 0.17), (0.20, 0.36, 0.42),
        (0.25, 0.17, 0.12), (0.40, 0.33, 0.52), (0.62, 0.50, 0.28), (0.18, 0.28, 0.18),
    ]

    init(journey: Journey) {
        let h = stableHash(journey.id.uuidString + journey.title)
        width = 30 + CGFloat(h % 17)
        height = 104 + CGFloat((h >> 8) % 36)
        let t = Self.tones[Int((h >> 16) % UInt64(Self.tones.count))]
        base = Color(red: t.0, green: t.1, blue: t.2)
        band = Int((h >> 24) % 3)
        tilt = (h >> 32) % 11 == 0 ? 4 : 0
    }
}

// MARK: - Layout

private enum Prop: Int { case plant, globe, stack }

private enum RowItem: Identifiable {
    case book(Journey)
    case prop(Prop, Int)
    var id: String {
        switch self {
        case .book(let j): j.id.uuidString
        case .prop(let p, let i): "prop\(p.rawValue)-\(i)"
        }
    }
}

private enum BookcaseMetrics {
    static let side: CGFloat = 20
    static let rowHeight: CGFloat = 160
    static let plank: CGFloat = 16
    static let gap: CGFloat = 2
    static let inset: CGFloat = 12
    static let propWidth: CGFloat = 54

    static func rows(for journeys: [Journey], innerWidth: CGFloat) -> [[RowItem]] {
        let avail = max(innerWidth - inset * 2, 80)
        var rows: [[RowItem]] = []
        var widths: [CGFloat] = []
        var cur: [RowItem] = []
        var used: CGFloat = 0
        for j in journeys {
            let w = SpineLook(journey: j).width
            if !cur.isEmpty && used + w + gap > avail {
                rows.append(cur); widths.append(used); cur = []; used = 0
            }
            cur.append(.book(j)); used += w + gap
        }
        if !cur.isEmpty { rows.append(cur); widths.append(used) }
        var out: [[RowItem]] = []
        for (i, var r) in rows.enumerated() {
            if avail - widths[i] >= propWidth + 8 { r.append(.prop(Prop(rawValue: i % 3)!, i)) }
            out.append(r)
        }
        while out.count < 3 {
            out.append([.prop(Prop(rawValue: out.count % 3)!, out.count)])
        }
        return out
    }
}

// MARK: - Main view

struct WoodenBookcaseShelfView: View {
    let context: ShelfStyleContext

    init(context: ShelfStyleContext) { self.context = context }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                WallBackground().ignoresSafeArea()
                ScrollView {
                    BookcaseView(context: context, width: geo.size.width - 24)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                }
            }
        }
    }
}

private struct WallBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Wood.wall, Wood.wallDark], startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                var rng = SeededRNG(42)
                for _ in 0..<500 {
                    let x = rng.next() * size.width, y = rng.next() * size.height
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                             with: .color(.brown.opacity(0.05)))
                }
            }
            RadialGradient(colors: [.clear, .black.opacity(0.12)], center: .center, startRadius: 200, endRadius: 700)
        }
    }
}

private struct BookcaseView: View {
    let context: ShelfStyleContext
    let width: CGFloat

    var body: some View {
        let m = BookcaseMetrics.self
        let inner = max(width - m.side * 2, 100)
        let rows = m.rows(for: context.journeys, innerWidth: inner)
        HStack(spacing: 0) {
            WoodPanel(vertical: true).frame(width: m.side)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    ShelfRow(items: row, context: context)
                }
            }
            .frame(width: inner)
            WoodPanel(vertical: true).frame(width: m.side)
        }
        .overlay(alignment: .top) { crown.offset(y: -14) }
        .padding(.top, 14)
        .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 8)
    }

    private var crown: some View {
        WoodPanel(vertical: false)
            .frame(width: width + 8, height: 18)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.35)).frame(height: 1) }
    }
}

/// Procedural wood-grain panel.
private struct WoodPanel: View {
    var vertical: Bool
    var light: Color = Wood.frameLight
    var dark: Color = Wood.frameDark
    var seed: UInt64 = 7

    var body: some View {
        ZStack {
            LinearGradient(colors: vertical ? [dark, light, dark] : [light, dark],
                           startPoint: vertical ? .leading : .top,
                           endPoint: vertical ? .trailing : .bottom)
            Canvas { ctx, size in
                var rng = SeededRNG(seed &+ UInt64(max(size.width, 1) * 7) &+ UInt64(max(size.height, 1)))
                let count = Int((vertical ? size.width : size.height) / 2.5) + 6
                for _ in 0..<count {
                    var p = Path()
                    let amp = 0.6 + rng.next() * 1.6
                    let phase = rng.next() * 6.28
                    let freq = 0.01 + rng.next() * 0.02
                    if vertical {
                        let x0 = rng.next() * size.width
                        p.move(to: CGPoint(x: x0, y: 0))
                        var y: CGFloat = 0
                        while y < size.height {
                            y += 8
                            p.addLine(to: CGPoint(x: x0 + sin(Double(y) * freq + phase) * amp, y: y))
                        }
                    } else {
                        let y0 = rng.next() * size.height
                        p.move(to: CGPoint(x: 0, y: y0))
                        var x: CGFloat = 0
                        while x < size.width {
                            x += 10
                            p.addLine(to: CGPoint(x: x, y: y0 + sin(Double(x) * freq + phase) * amp))
                        }
                    }
                    let isDark = rng.next() > 0.35
                    let a = isDark ? 0.10 + rng.next() * 0.12 : 0.05
                    ctx.stroke(p, with: .color((isDark ? Color.black : Color.white).opacity(a)),
                               lineWidth: 0.5 + rng.next() * 0.9)
                }
            }
        }
        .clipped()
    }
}

// MARK: - One shelf row

private struct ShelfRow: View {
    let items: [RowItem]
    let context: ShelfStyleContext

    var body: some View {
        let m = BookcaseMetrics.self
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                WoodPanel(vertical: true, light: Wood.backLight, dark: Wood.backDark, seed: 99)
                    .overlay {
                        LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45))
                    }
                    .overlay {
                        HStack {
                            LinearGradient(colors: [.black.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 16)
                            Spacer()
                            LinearGradient(colors: [.clear, .black.opacity(0.4)], startPoint: .leading, endPoint: .trailing).frame(width: 16)
                        }
                    }
                HStack(alignment: .bottom, spacing: m.gap) {
                    ForEach(items) { item in
                        switch item {
                        case .book(let j): SpineButton(journey: j, context: context)
                        case .prop(let p, _): PropView(prop: p).padding(.leading, 6)
                        }
                    }
                }
                .padding(.horizontal, m.inset)
            }
            .frame(height: m.rowHeight)
            .zIndex(1)
            WoodPanel(vertical: false, light: Wood.plankLight, dark: Wood.plankDark, seed: 31)
                .frame(height: m.plank)
                .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.28)).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.4)).frame(height: 1.5) }
        }
    }
}

// MARK: - Spine

private struct SpineButton: View {
    let journey: Journey
    let context: ShelfStyleContext
    @State private var pulled = false

    var body: some View {
        let look = SpineLook(journey: journey)
        SpineView(title: journey.title, look: look)
            .rotationEffect(.degrees(pulled ? 0 : look.tilt), anchor: .bottom)
            .rotation3DEffect(.degrees(pulled ? -24 : 0), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
            .scaleEffect(pulled ? 1.12 : 1, anchor: .bottom)
            .offset(y: pulled ? 8 : 0)
            .shadow(color: .black.opacity(pulled ? 0.55 : 0.3), radius: pulled ? 9 : 2, x: pulled ? 0 : 2, y: pulled ? 8 : 0)
            .zIndex(pulled ? 1 : 0)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.6)) { pulled = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    context.open(journey)
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.4)) { pulled = false }
                }
            }
            .contextMenu {
                Button(role: .destructive) { context.requestDelete(journey) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("Opens the story")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Delete") { context.requestDelete(journey) }
    }

    private var accessibilityText: String {
        var s = journey.title + ", " + journey.date.formatted(date: .long, time: .omitted)
        if let c = journey.city, !c.isEmpty { s += ", " + c }
        return s
    }
}

private struct SpineView: View {
    let title: String
    let look: SpineLook

    var body: some View {
        let w = look.width, h = look.height
        let shape = UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 1, bottomTrailingRadius: 1, topTrailingRadius: 3)
        ZStack {
            shape
                .fill(look.base)
                .overlay {
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.38), location: 0),
                        .init(color: .white.opacity(0.14), location: 0.28),
                        .init(color: .clear, location: 0.55),
                        .init(color: .black.opacity(0.42), location: 1),
                    ], startPoint: .leading, endPoint: .trailing)
                }
                .overlay {
                    Canvas { ctx, size in
                        var rng = SeededRNG(UInt64(w * 31 + h))
                        for _ in 0..<Int(size.height / 2.2) {
                            let y = rng.next() * size.height
                            ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.5)),
                                     with: .color(.black.opacity(0.07)))
                        }
                    }
                }
                .clipShape(shape)

            VStack(spacing: 0) {
                bandGroup.padding(.top, 10)
                Spacer()
                bandGroup.padding(.bottom, 10)
            }

            Text(title)
                .font(.custom(KraftFontName.loraSemiBold, size: w > 38 ? 13 : 11.5))
                .foregroundStyle(LinearGradient(colors: [Wood.gold, Wood.goldDeep], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.5), radius: 0.5, x: 0.4, y: 0.6)
                .lineLimit(w > 40 ? 2 : 1)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.55)
                .frame(width: h - 56, height: w - 6)
                .rotationEffect(.degrees(-90))
                .frame(width: w, height: h)
        }
        .frame(width: w, height: h)
    }

    @ViewBuilder private var bandGroup: some View {
        switch look.band {
        case 0: VStack(spacing: 2) { gold(2.5); gold(1) }
        case 1: gold(5)
        default: VStack(spacing: 2) { gold(1); gold(1); gold(1) }
        }
    }

    private func gold(_ t: CGFloat) -> some View {
        Rectangle()
            .fill(LinearGradient(colors: [Wood.gold, Wood.goldDeep], startPoint: .leading, endPoint: .trailing))
            .frame(height: t)
            .opacity(0.9)
    }
}

// MARK: - Props

private struct PropView: View {
    let prop: Prop
    var body: some View {
        switch prop {
        case .plant: PlantProp()
        case .globe: GlobeProp()
        case .stack: StackProp()
        }
    }
}

private struct PlantProp: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(0..<5, id: \.self) { i in
                Ellipse()
                    .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.55, blue: 0.28), Color(red: 0.18, green: 0.36, blue: 0.18)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 14, height: 46 - CGFloat(abs(i - 2)) * 6)
                    .offset(y: -22)
                    .rotationEffect(.degrees(Double(i - 2) * 24), anchor: .bottom)
            }
            .offset(y: -4)
            UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 8, bottomTrailingRadius: 8, topTrailingRadius: 2)
                .fill(LinearGradient(colors: [Color(red: 0.80, green: 0.45, blue: 0.30), Color(red: 0.55, green: 0.27, blue: 0.17)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 34, height: 26)
        }
        .frame(width: 48, height: 100, alignment: .bottom)
        .shadow(color: .black.opacity(0.35), radius: 2, x: 1, y: 1)
        .accessibilityHidden(true)
    }
}

private struct GlobeProp: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(red: 0.45, green: 0.66, blue: 0.72), Color(red: 0.12, green: 0.30, blue: 0.40)],
                                             center: UnitPoint(x: 0.35, y: 0.3), startRadius: 2, endRadius: 30))
                Ellipse().fill(Color(red: 0.55, green: 0.65, blue: 0.40).opacity(0.85))
                    .frame(width: 16, height: 22).offset(x: -8, y: -3)
                Ellipse().fill(Color(red: 0.55, green: 0.65, blue: 0.40).opacity(0.85))
                    .frame(width: 12, height: 14).offset(x: 10, y: 8)
                Circle().stroke(Wood.goldDeep, lineWidth: 1.5)
            }
            .frame(width: 44, height: 44)
            Rectangle().fill(Wood.goldDeep).frame(width: 3, height: 10)
            Capsule().fill(Wood.frameDark).frame(width: 30, height: 7)
        }
        .frame(width: 48, alignment: .bottom)
        .shadow(color: .black.opacity(0.4), radius: 2, x: 1, y: 1)
        .accessibilityHidden(true)
    }
}

/// A few books lying flat.
private struct StackProp: View {
    var body: some View {
        VStack(spacing: 0) {
            flat(Color(red: 0.20, green: 0.30, blue: 0.40), w: 40)
            flat(Color(red: 0.55, green: 0.25, blue: 0.20), w: 46)
            flat(Color(red: 0.30, green: 0.36, blue: 0.22), w: 42)
        }
        .frame(width: 48, alignment: .bottom)
        .shadow(color: .black.opacity(0.35), radius: 2, x: 1, y: 1)
        .accessibilityHidden(true)
    }

    private func flat(_ c: Color, w: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(c)
            .overlay(LinearGradient(colors: [.white.opacity(0.18), .clear, .black.opacity(0.3)], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color(red: 0.93, green: 0.88, blue: 0.75)).frame(width: w * 0.8, height: 5).padding(.trailing, 1)
            }
            .frame(width: w, height: 13)
    }
}

// MARK: - Previews

#Preview("Bookcase sample") {
    let container = AppContainer.make(inMemory: true)
    SampleData.mumbai(in: container.mainContext)
    let ctx = container.mainContext
    for (i, t) in ["Lisbon Weekend", "Kyoto in Spring", "Road to Hana", "Iceland Ring Road", "Cairo", "Oslo", "A Very Long Journey Title Across the Alps"].enumerated() {
        ctx.insert(Journey(title: t, date: .now.addingTimeInterval(Double(i) * -86400 * 30), city: "City \(i)"))
    }
    let journeys = (try? ctx.fetch(FetchDescriptor<Journey>())) ?? []
    return WoodenBookcaseShelfView(context: .init(journeys: journeys, open: { _ in }, requestDelete: { _ in }))
        .modelContainer(container)
}

#Preview("Bookcase empty") {
    WoodenBookcaseShelfView(context: .init(journeys: [], open: { _ in }, requestDelete: { _ in }))
}
