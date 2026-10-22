import SwiftUI
import SwiftData

/// "Desk Stack": books lying flat in a hand-stacked pile on a study desk, spines facing the viewer.
struct DeskStackShelfView: View {
    let context: ShelfStyleContext
    @State private var slidingID: UUID?

    private let bookWidth: CGFloat = 292

    init(context: ShelfStyleContext) { self.context = context }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                DeskWall().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 24)
                        pile(width: geo.size.width)
                        DeskSurface()
                    }
                    .frame(minHeight: geo.size.height + geo.safeAreaInsets.top, alignment: .bottom)
                }
                .defaultScrollAnchor(.bottom)
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder
    private func pile(width: CGFloat) -> some View {
        let sorted = context.journeys.sorted { $0.date > $1.date } // newest on top
        let cols = max(1, min(3, Int((width - 20) / (bookWidth + 30))))
        if sorted.isEmpty {
            Color.clear.frame(height: 40)
        } else {
            HStack(alignment: .bottom, spacing: cols > 1 ? -24 : 0) {
                ForEach(0..<cols, id: \.self) { c in
                    VStack(spacing: -2) {
                        ForEach(Array(sorted.enumerated()).filter { $0.offset % cols == c }, id: \.element.id) { item in
                            DeskBook(journey: item.element, width: bookWidth, isSliding: slidingID == item.element.id)
                                .onTapGesture { slide(item.element) }
                                .contextMenu {
                                    Button(role: .destructive) { context.requestDelete(item.element) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(DeskBook.label(for: item.element))
                                .accessibilityAddTraits(.isButton)
                                .zIndex(slidingID == item.element.id ? 10 : 0)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, -14) // rest on the desk
            .zIndex(1)
        }
    }

    private func slide(_ journey: Journey) {
        guard slidingID == nil else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { slidingID = journey.id }
        Task {
            try? await Task.sleep(for: .milliseconds(260))
            context.open(journey)
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { slidingID = nil }
        }
    }
}

// MARK: - Book

private struct DeskBook: View {
    let journey: Journey
    let width: CGFloat
    let isSliding: Bool
    @State private var cover: CGImage?
    @Environment(\.displayScale) private var displayScale

    static func label(for j: Journey) -> String {
        var s = "\(j.title), \(j.date.formatted(date: .long, time: .omitted))"
        if let c = j.displayCity { s += ", \(c)" }
        return s
    }

    private var seed: UInt64 { DeskHash.fnv(journey.id.uuidString) }
    private var cloth: DeskCloth { DeskCloth.palette[Int(seed % UInt64(DeskCloth.palette.count))] }
    private var height: CGFloat { 54 + CGFloat((seed >> 8) % 14) }
    private var bookWidth: CGFloat { width - CGFloat((seed >> 16) % 40) }
    private var xOffset: CGFloat { CGFloat(Int((seed >> 24) % 29)) - 14 }
    private var tilt: Double { Double(Int((seed >> 32) % 31)) / 10 - 1.5 }

    private var dateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM yyyy"
        f.timeZone = TimeZone(identifier: journey.timeZoneID) ?? .current
        return f.string(from: journey.date).uppercased()
    }

    var body: some View {
        HStack(spacing: 0) {
            pageEnd(leading: true)
            spine
            pageEnd(leading: false)
        }
        .frame(width: bookWidth, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 3)
        .rotationEffect(.degrees(tilt))
        .offset(x: xOffset + (isSliding ? 420 : 0))
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .task(id: journey.id) { cover = Self.loadCover(journey, scale: displayScale) }
    }

    private func pageEnd(leading: Bool) -> some View {
        ZStack {
            cloth.dark
            VStack(spacing: 0) {
                Color.clear.frame(height: 5)
                ZStack {
                    Color(red: 0.95, green: 0.91, blue: 0.80)
                    VStack(spacing: 2) {
                        ForEach(0..<Int(max(4, (height - 10) / 3.5)), id: \.self) { _ in
                            Rectangle().fill(Color(red: 0.74, green: 0.66, blue: 0.5).opacity(0.55)).frame(height: 0.7)
                            Spacer(minLength: 0)
                        }
                    }
                }
                Color.clear.frame(height: 5)
            }
            .padding(.leading, leading ? 1 : 0)
            .padding(.trailing, leading ? 0 : 1)
        }
        .frame(width: 13)
    }

    private var spine: some View {
        ZStack {
            LinearGradient(colors: [cloth.light, cloth.base, cloth.dark], startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                var x: CGFloat = 0
                while x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: 0, width: 0.5, height: size.height)), with: .color(.black.opacity(0.07)))
                    x += 3
                }
            }
            // raised bands near each end
            HStack(spacing: 0) {
                band.padding(.leading, 5)
                Spacer()
                band.padding(.trailing, 5)
            }
            HStack(spacing: 0) {
                if let cover {
                    Image(texture: cover, scale: displayScale).resizable().scaledToFill()
                        .frame(width: height - 22, height: height - 22).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(DeskCloth.gold, lineWidth: 0.8))
                        .padding(.leading, 18)
                }
                VStack(spacing: 3) {
                    Text(journey.title)
                        .font(KraftFont.title(height > 62 ? 30 : 27))
                        .foregroundStyle(DeskCloth.goldGradient)
                        .shadow(color: .black.opacity(0.5), radius: 0, x: 0, y: 0.8)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    HStack(spacing: 5) {
                        Text(dateText)
                        if let c = journey.displayCity { Text("·"); Text(c.uppercased()).lineLimit(1) }
                    }
                    .font(KraftFont.label(8)).tracking(1.2)
                    .foregroundStyle(DeskCloth.gold.opacity(0.85))
                    .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
            }
            VStack { Color.white.opacity(0.18).frame(height: 1); Spacer(); Color.black.opacity(0.35).frame(height: 1.5) }
        }
    }

    private var band: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(LinearGradient(colors: [cloth.light.opacity(0.9), cloth.dark], startPoint: .leading, endPoint: .trailing))
            .overlay(RoundedRectangle(cornerRadius: 1.5).stroke(DeskCloth.gold.opacity(0.7), lineWidth: 0.6))
            .frame(width: 5)
    }

    private static func loadCover(_ journey: Journey, scale: CGFloat) -> CGImage? {
        StoredPhotos.image(path: journey.coverThumbPath ?? journey.coverPhotoPath,
                           maxPixel: ImageDecoding.maxPixel(forPoints: 64, scale: scale))
    }
}

private enum DeskHash {
    static func fnv(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }
}

private struct DeskCloth {
    let base: Color, light: Color, dark: Color
    init(_ r: Double, _ g: Double, _ b: Double) {
        base = Color(red: r, green: g, blue: b)
        light = Color(red: min(1, r * 1.22 + 0.03), green: min(1, g * 1.22 + 0.03), blue: min(1, b * 1.22 + 0.03))
        dark = Color(red: r * 0.62, green: g * 0.62, blue: b * 0.62)
    }
    static let palette = [
        DeskCloth(0.45, 0.13, 0.15), DeskCloth(0.13, 0.30, 0.25), DeskCloth(0.14, 0.22, 0.40),
        DeskCloth(0.50, 0.30, 0.14), DeskCloth(0.30, 0.17, 0.33), DeskCloth(0.22, 0.24, 0.26),
        DeskCloth(0.55, 0.20, 0.10), DeskCloth(0.33, 0.36, 0.17),
    ]
    static let gold = Color(red: 0.89, green: 0.74, blue: 0.40)
    static let goldGradient = LinearGradient(
        colors: [Color(red: 0.97, green: 0.86, blue: 0.55), Color(red: 0.82, green: 0.64, blue: 0.28)],
        startPoint: .top, endPoint: .bottom)
}

// MARK: - Scene

private struct DeskWall: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.31, green: 0.43, blue: 0.40), Color(red: 0.43, green: 0.54, blue: 0.48)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(red: 1.0, green: 0.88, blue: 0.55).opacity(0.55), .clear],
                           center: UnitPoint(x: 0.88, y: 0.1), startRadius: 4, endRadius: 360)
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: "lamp.desk.fill")
                        .font(.system(size: 46)).foregroundStyle(Color(red: 0.18, green: 0.2, blue: 0.19))
                        .shadow(color: Color(red: 1, green: 0.85, blue: 0.45).opacity(0.8), radius: 18)
                        .padding(.trailing, 22).padding(.top, 70)
                }
                Spacer()
            }
        }
    }
}

private struct DeskSurface: View {
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.42, green: 0.26, blue: 0.15), Color(red: 0.26, green: 0.15, blue: 0.09)],
                           startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                for i in 0..<14 {
                    let y = CGFloat(i) * 11 + 6
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addCurve(to: CGPoint(x: size.width, y: y + 4),
                               control1: CGPoint(x: size.width * 0.3, y: y - 4),
                               control2: CGPoint(x: size.width * 0.7, y: y + 8))
                    ctx.stroke(p, with: .color(.black.opacity(0.10)), lineWidth: 0.8)
                }
            }
            LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.35))
            Rectangle().fill(Color(red: 0.62, green: 0.42, blue: 0.25)).frame(height: 2)
            HStack(alignment: .top) {
                DeskPlant().offset(y: -50)
                Spacer()
                DeskCup().offset(y: -36)
            }
            .padding(.horizontal, 18)
            Image(systemName: "pencil")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color(red: 0.9, green: 0.7, blue: 0.2))
                .rotationEffect(.degrees(-8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 90).padding(.top, 52)
        }
        .frame(height: 150)
        .frame(maxWidth: .infinity)
        .zIndex(0)
    }
}

private struct DeskPlant: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(0..<5, id: \.self) { i in
                Capsule().fill(Color(red: 0.22, green: 0.42 + Double(i) * 0.03, blue: 0.25))
                    .frame(width: 9, height: 34)
                    .rotationEffect(.degrees(Double(i - 2) * 26), anchor: .bottom)
                    .offset(y: -26)
            }
            UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 8, bottomTrailingRadius: 8, topTrailingRadius: 2)
                .fill(Color(red: 0.72, green: 0.38, blue: 0.24)).frame(width: 34, height: 28)
        }
        .frame(width: 60, height: 70)
    }
}

private struct DeskCup: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse().fill(.black.opacity(0.3)).frame(width: 48, height: 10).offset(y: 3)
            Circle().trim(from: 0.55, to: 0.95).stroke(Color(red: 0.93, green: 0.9, blue: 0.84), lineWidth: 4)
                .frame(width: 22, height: 22).rotationEffect(.degrees(-50)).offset(x: 16, y: -10)
            UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 2)
                .fill(LinearGradient(colors: [Color(red: 0.97, green: 0.95, blue: 0.9), Color(red: 0.82, green: 0.78, blue: 0.7)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 32, height: 30)
                .overlay(alignment: .top) { Ellipse().fill(Color(red: 0.3, green: 0.17, blue: 0.1)).frame(width: 28, height: 7).offset(y: 1) }
            Image(systemName: "water.waves").font(.system(size: 14)).foregroundStyle(.white.opacity(0.55)).offset(y: -34)
        }
        .frame(width: 56, height: 70)
    }
}

#Preview("Desk stack: many") {
    let container = AppContainer.make(inMemory: true)
    let titles = ["Mumbai", "Lisbon Lights", "Kyoto in Rain", "Patagonia", "Marrakech", "Iceland Ring Road", "Hanoi", "Cape Town", "Oslo"]
    for (i, t) in titles.enumerated() {
        container.mainContext.insert(Journey(title: t, date: .now.addingTimeInterval(Double(-i) * 86400 * 40), city: i % 2 == 0 ? t : nil))
    }
    let js = (try? container.mainContext.fetch(FetchDescriptor<Journey>())) ?? []
    return DeskStackShelfView(context: ShelfStyleContext(journeys: js, open: { _ in }, requestDelete: { _ in }))
        .modelContainer(container)
}

#Preview("Desk stack: one") {
    let container = AppContainer.make(inMemory: true)
    container.mainContext.insert(Journey(title: "Mumbai", city: "Mumbai"))
    let js = (try? container.mainContext.fetch(FetchDescriptor<Journey>())) ?? []
    return DeskStackShelfView(context: ShelfStyleContext(journeys: js, open: { _ in }, requestDelete: { _ in }))
}
