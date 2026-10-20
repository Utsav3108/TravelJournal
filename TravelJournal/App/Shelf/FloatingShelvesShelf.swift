import SwiftUI
import SwiftData

/// "Floating Shelves": a dark gallery wall at night with brass ledges, LED under-glow and
/// cover-out books. Self-contained look, independent of the Vintage Kraft story theme.
struct FloatingShelvesShelfView: View {
    let context: ShelfStyleContext
    @State private var liftedID: UUID?

    private let perLedge = 2
    private let minLedges = 3

    private var rows: [[Journey]] {
        let chunks = stride(from: 0, to: context.journeys.count, by: perLedge).map {
            Array(context.journeys[$0..<min($0 + perLedge, context.journeys.count)])
        }
        return chunks + Array(repeating: [], count: max(0, minLedges - chunks.count))
    }

    var body: some View {
        ZStack {
            FSWall().ignoresSafeArea()
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        let list = rows
                        ForEach(Array(list.enumerated()), id: \.offset) { idx, row in
                            FSLedgeRow(
                                journeys: row, width: geo.size.width, stagger: idx % 2 == 1,
                                liftedID: liftedID,
                                tap: lift, delete: context.requestDelete)
                                .zIndex(row.contains { $0.id == liftedID } ? 1 : 0)
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 48)
                }
            }
        }
    }

    private func lift(_ j: Journey) {
        guard liftedID == nil else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.62)) { liftedID = j.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            context.open(j)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { liftedID = nil }
            }
        }
    }
}

// MARK: - Wall

private struct FSWall: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.17),
                                    Color(red: 0.07, green: 0.08, blue: 0.11)],
                           startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                var rng = SystemRandomNumberGenerator()
                for _ in 0..<900 {
                    let p = CGPoint(x: .random(in: 0..<size.width, using: &rng),
                                    y: .random(in: 0..<size.height, using: &rng))
                    ctx.fill(Path(CGRect(x: p.x, y: p.y, width: 1, height: 1)),
                             with: .color(.white.opacity(.random(in: 0.01...0.05, using: &rng))))
                }
            }
            RadialGradient(colors: [.clear, .black.opacity(0.55)],
                           center: .center, startRadius: 150, endRadius: 560)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Ledge

private struct FSLedgeRow: View {
    let journeys: [Journey]
    let width: CGFloat
    let stagger: Bool
    let liftedID: UUID?
    let tap: (Journey) -> Void
    let delete: (Journey) -> Void

    private var bookW: CGFloat { max(60, min(150, (width - 96) / 2)) }
    private var bookH: CGFloat { bookW * 1.36 }
    private let brass = Color(red: 0.78, green: 0.62, blue: 0.36)

    var body: some View {
        let slotW = bookW + 12
        ZStack(alignment: .top) {
            // LED glow cast down the wall
            Ellipse()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.72, blue: 0.4).opacity(0.28), .clear],
                                     center: .center, startRadius: 4, endRadius: width * 0.5))
                .frame(width: width * 1.1, height: 150)
                .offset(y: bookH + 40)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 24) {
                    ForEach(0..<2, id: \.self) { i in
                        Group {
                            if i < journeys.count {
                                FSBookButton(journey: journeys[i], w: bookW, h: bookH,
                                             lifted: liftedID == journeys[i].id,
                                             tap: tap, delete: delete)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: slotW, height: bookH + 6, alignment: .bottom)
                    }
                }
                .padding(.leading, stagger ? 28 : 0)
                .padding(.trailing, stagger ? 0 : 28)
                .frame(maxWidth: .infinity)

                // ledge
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: [brass.opacity(0.95), brass.opacity(0.55), Color(red: 0.35, green: 0.25, blue: 0.12)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(height: 9)
                        .shadow(color: .black.opacity(0.6), radius: 5, y: 3)
                    Rectangle().fill(.white.opacity(0.35)).frame(height: 1).padding(.horizontal, 3)
                    Capsule()
                        .fill(Color(red: 1, green: 0.8, blue: 0.5))
                        .frame(height: 2)
                        .padding(.horizontal, 10)
                        .offset(y: 11)
                        .blur(radius: 1.2)
                }
                .padding(.horizontal, 14)

                // label plates
                HStack(alignment: .top, spacing: 24) {
                    ForEach(0..<2, id: \.self) { i in
                        Group {
                            if i < journeys.count { FSLabel(journey: journeys[i]) } else { Color.clear }
                        }
                        .frame(width: slotW, alignment: .leading)
                    }
                }
                .padding(.leading, stagger ? 28 : 0)
                .padding(.trailing, stagger ? 0 : 28)
                .padding(.top, 14)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64, alignment: .top)
            }
        }
        .padding(.top, 22)
        .padding(.bottom, 18)
    }
}

private struct FSLabel: View {
    let journey: Journey
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(journey.title.isEmpty ? "Untitled" : journey.title)
                .font(.system(.footnote, design: .serif).weight(.semibold))
                .foregroundStyle(Color(white: 0.92))
                .lineLimit(2)
            Text(journey.date.formatted(.dateTime.month(.abbreviated).year()).uppercased()
                 + (journey.displayCity.map { "  ·  \($0.uppercased())" } ?? ""))
                .font(.system(.caption2).weight(.medium))
                .tracking(0.8)
                .foregroundStyle(Color(white: 0.92).opacity(0.55))
                .lineLimit(2)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(red: 0.78, green: 0.62, blue: 0.36).opacity(0.35), lineWidth: 0.5))
    }
}

// MARK: - Book

private struct FSBookButton: View {
    let journey: Journey
    let w: CGFloat
    let h: CGFloat
    let lifted: Bool
    let tap: (Journey) -> Void
    let delete: (Journey) -> Void

    var body: some View {
        Button { tap(journey) } label: {
            FSBook(journey: journey, w: w, h: h)
                .scaleEffect(lifted ? 1.22 : 1, anchor: .bottom)
                .offset(y: lifted ? -14 : 0)
                .shadow(color: .black.opacity(lifted ? 0.7 : 0), radius: 18, y: 12)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { delete(journey) } label: { Label("Delete", systemImage: "trash") }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([journey.title, journey.date.formatted(date: .abbreviated, time: .omitted), journey.displayCity]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }
}

private struct FSBook: View {
    let journey: Journey
    let w: CGFloat
    let h: CGFloat
    private let spine: CGFloat = 7
    private let pages: CGFloat = 5

    private var image: UIImage? {
        guard let path = journey.coverThumbPath ?? journey.coverPhotoPath, !path.hasPrefix("sample:") else { return nil }
        return UIImage(contentsOfFile: FilePhotoStore().url(for: path).path)
    }

    private var tone: Color {
        var hash: UInt64 = 5381
        for b in journey.id.uuidString.utf8 { hash = (hash &* 33) &+ UInt64(b) }
        let tones: [(Double, Double, Double)] = [
            (0.12, 0.30, 0.34), (0.40, 0.14, 0.20), (0.15, 0.24, 0.40),
            (0.20, 0.34, 0.26), (0.38, 0.28, 0.12), (0.30, 0.18, 0.38)]
        let t = tones[Int(hash % UInt64(tones.count))]
        return Color(red: t.0, green: t.1, blue: t.2)
    }

    var body: some View {
        let coverW = w - spine - pages
        ZStack(alignment: .bottomLeading) {
            Ellipse().fill(.black.opacity(0.7)).frame(width: w * 0.95, height: 9).blur(radius: 4).offset(y: 5)

            HStack(spacing: 0) {
                ZStack {
                    tone
                    LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .leading, endPoint: .trailing)
                }
                .frame(width: spine)
                cover.frame(width: coverW, height: h).clipped()
                ZStack {
                    LinearGradient(colors: [Color(white: 0.78), Color(white: 0.93)], startPoint: .leading, endPoint: .trailing)
                    VStack(spacing: 2) {
                        ForEach(0..<max(0, Int(h / 3)), id: \.self) { _ in
                            Rectangle().fill(.black.opacity(0.08)).frame(height: 0.5)
                        }
                    }
                }
                .frame(width: pages)
            }
            .frame(width: w, height: h)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2, bottomTrailingRadius: 1, topTrailingRadius: 1))
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.2)).frame(height: 0.7) }
            .rotation3DEffect(.degrees(6), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
            .shadow(color: .black.opacity(0.5), radius: 6, x: 3, y: 2)
        }
        .frame(width: w, height: h)
    }

    @ViewBuilder private var cover: some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFill()
                .overlay(LinearGradient(colors: [.black.opacity(0.25), .clear, .black.opacity(0.15)], startPoint: .leading, endPoint: .trailing))
        } else {
            ZStack {
                LinearGradient(colors: [tone, tone.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RoundedRectangle(cornerRadius: 2).stroke(Color(red: 0.85, green: 0.72, blue: 0.48).opacity(0.7), lineWidth: 0.8).padding(8)
                Text(journey.title.isEmpty ? "Untitled" : journey.title)
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(red: 0.93, green: 0.84, blue: 0.62))
                    .shadow(color: .black.opacity(0.6), radius: 0, x: 0, y: 1)
                    .minimumScaleFactor(0.6)
                    .padding(18)
            }
        }
    }
}

#Preview("Floating shelves") {
    let container = AppContainer.make(inMemory: true)
    SampleData.mumbai(in: container.mainContext)
    for (t, c) in [("Lisbon Light", "Lisbon"), ("Kyoto in Rain", "Kyoto"), ("Patagonia", nil), ("Marrakech Nights", "Marrakech")] {
        container.mainContext.insert(Journey(title: t, city: c))
    }
    let js = (try? container.mainContext.fetch(FetchDescriptor<Journey>())) ?? []
    return FloatingShelvesShelfView(context: ShelfStyleContext(journeys: js, open: { _ in }, requestDelete: { _ in }))
        .modelContainer(container)
}

#Preview("Floating shelves empty") {
    FloatingShelvesShelfView(context: ShelfStyleContext(journeys: [], open: { _ in }, requestDelete: { _ in }))
}
