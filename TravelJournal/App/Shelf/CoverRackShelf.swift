import SwiftUI
import SwiftData

/// "Cover Rack": a bookstore front display. Covers face out on a slim wooden rail in a cover-flow carousel.
struct CoverRackShelfView: View {
    let context: ShelfStyleContext

    @State private var selectedID: UUID?
    @State private var liftedID: UUID?

    private var journeys: [Journey] { context.journeys }

    private var current: Journey? {
        journeys.first { $0.id == selectedID } ?? journeys.first
    }

    var body: some View {
        GeometryReader { geo in
            let itemW = min(geo.size.width * 0.58, 280)
            let itemH = itemW * 1.45
            ZStack(alignment: .top) {
                CoverRackWall().ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ZStack(alignment: .top) {
                        CoverRackRail()
                            .frame(height: 90)
                            .offset(y: itemH - 4)
                        carousel(width: geo.size.width, itemW: itemW, itemH: itemH)
                    }
                    .frame(height: itemH + 90, alignment: .top)

                    caption.padding(.top, 14)
                    Spacer(minLength: 0)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func carousel(width: CGFloat, itemW: CGFloat, itemH: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(journeys) { journey in
                    CoverRackBook(journey: journey, width: itemW, height: itemH,
                                  lifted: liftedID == journey.id)
                        .frame(width: itemW, height: itemH + 60, alignment: .top)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .rotation3DEffect(.degrees(-phase.value * 42), axis: (0, 1, 0), perspective: 0.5)
                                .scaleEffect(1 - abs(phase.value) * 0.16, anchor: .bottom)
                                .opacity(1 - abs(phase.value) * 0.28)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { tap(journey) }
                        .contextMenu {
                            Button(role: .destructive) { context.requestDelete(journey) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityText(journey))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(named: "Delete") { context.requestDelete(journey) }
                        .accessibilityIdentifier("coverRackBook")
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, (width - itemW) / 2, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selectedID, anchor: .center)
        .scrollDisabled(journeys.count <= 1)
        .frame(height: itemH + 60)
        .sensoryFeedback(.selection, trigger: selectedID)
    }

    private var caption: some View {
        VStack(spacing: 6) {
            if let j = current {
                Text(j.title)
                    .font(.custom(KraftFontName.loraSemiBold, size: 22))
                    .foregroundStyle(CoverRackPalette.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(subtitle(j))
                    .font(.custom(KraftFontName.lora, size: 14))
                    .foregroundStyle(CoverRackPalette.textSoft)
                    .lineLimit(1)
                if journeys.count > 1, let idx = journeys.firstIndex(where: { $0.id == j.id }) {
                    pageIndicator(index: idx).padding(.top, 6)
                }
            }
        }
        .padding(.horizontal, 28)
        .animation(.easeOut(duration: 0.2), value: current?.id)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func pageIndicator(index: Int) -> some View {
        if journeys.count <= 7 {
            HStack(spacing: 7) {
                ForEach(0..<journeys.count, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? CoverRackPalette.text : CoverRackPalette.textSoft.opacity(0.35))
                        .frame(width: i == index ? 16 : 6, height: 6)
                }
            }
            .animation(.spring(duration: 0.3), value: index)
        } else {
            Text("\(index + 1) of \(journeys.count)")
                .font(.custom(KraftFontName.lora, size: 12))
                .foregroundStyle(CoverRackPalette.textSoft)
                .monospacedDigit()
        }
    }

    private func subtitle(_ j: Journey) -> String {
        var s = j.date.formatted(.dateTime.day().month(.abbreviated).year())
        if let c = j.displayCity, !c.isEmpty { s += "  ·  " + c }
        return s
    }

    private func accessibilityText(_ j: Journey) -> String {
        var s = "\(j.title), \(j.date.formatted(date: .long, time: .omitted))"
        if let c = j.displayCity, !c.isEmpty { s += ", \(c)" }
        return s
    }

    private func tap(_ journey: Journey) {
        if journey.id == current?.id {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { liftedID = journey.id }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                context.open(journey)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { liftedID = nil }
            }
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { selectedID = journey.id }
        }
    }
}

// MARK: - Palette and backdrop

private enum CoverRackPalette {
    static let text = Color(red: 0.13, green: 0.17, blue: 0.20)
    static let textSoft = Color(red: 0.36, green: 0.42, blue: 0.45)
}

private struct CoverRackWall: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.88, green: 0.92, blue: 0.93),
                                Color(red: 0.79, green: 0.85, blue: 0.85)],
                       startPoint: .top, endPoint: .bottom)
            .overlay(
                RadialGradient(colors: [.white.opacity(0.45), .clear],
                               center: .init(x: 0.5, y: 0.3), startRadius: 10, endRadius: 360)
            )
    }
}

/// Slim wooden ledge with a front lip.
private struct CoverRackRail: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Color(red: 0.80, green: 0.66, blue: 0.48), Color(red: 0.70, green: 0.55, blue: 0.38)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 26)
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.62, green: 0.47, blue: 0.31), Color(red: 0.50, green: 0.37, blue: 0.24)],
                               startPoint: .top, endPoint: .bottom)
                Rectangle().fill(.white.opacity(0.22)).frame(height: 1)
            }
            .frame(height: 16)
            LinearGradient(colors: [.black.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 26)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Book

private struct CoverRackBook: View {
    let journey: Journey
    let width: CGFloat
    let height: CGFloat
    let lifted: Bool

    @Environment(\.displayScale) private var displayScale

    private var coverImage: CGImage? {
        StoredPhotos.image(path: journey.coverThumbPath ?? journey.coverPhotoPath,
                           maxPixel: ImageDecoding.maxPixel(forPoints: max(width, height), scale: displayScale))
    }

    private var cloth: Color {
        let sum = journey.id.uuidString.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & 0xFFFF }
        let palette: [Color] = [
            Color(red: 0.24, green: 0.38, blue: 0.47), Color(red: 0.33, green: 0.45, blue: 0.38),
            Color(red: 0.55, green: 0.29, blue: 0.27), Color(red: 0.76, green: 0.58, blue: 0.30),
            Color(red: 0.32, green: 0.31, blue: 0.47), Color(red: 0.20, green: 0.27, blue: 0.33),
        ]
        return palette[sum % palette.count]
    }

    private let spine: CGFloat = 11
    private let pages: CGFloat = 7

    var body: some View {
        ZStack(alignment: .top) {
            Ellipse()
                .fill(.black.opacity(0.35))
                .frame(width: width * 0.92, height: 14)
                .blur(radius: 6)
                .offset(y: height - 4)
                .opacity(lifted ? 0.5 : 1)

            bookBody
                .scaleEffect(x: 1, y: -1, anchor: .bottom)
                .offset(y: height + 2)
                .mask(alignment: .top) {
                    LinearGradient(colors: [.black.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 40)
                        .offset(y: height + 2)
                }
                .allowsHitTesting(false)

            bookBody
                .rotation3DEffect(.degrees(5), axis: (1, 0, 0), anchor: .bottom, perspective: 0.6)
                .offset(y: lifted ? -16 : 0)
                .shadow(color: .black.opacity(lifted ? 0.3 : 0.18), radius: lifted ? 14 : 6, x: 4, y: lifted ? 14 : 4)
        }
        .frame(width: width, height: height, alignment: .top)
    }

    private var bookBody: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                cover
                LinearGradient(colors: [.black.opacity(0.35), .white.opacity(0.12), .black.opacity(0.12), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: spine)
                Rectangle().fill(.black.opacity(0.25)).frame(width: 1).offset(x: spine + 1)
                Rectangle().fill(.white.opacity(0.12)).frame(width: 1).offset(x: spine + 2)
            }
            .frame(width: width - pages, height: height)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3,
                                              bottomTrailingRadius: 1, topTrailingRadius: 1))
            ZStack {
                Color(red: 0.96, green: 0.94, blue: 0.89)
                VStack(spacing: 2) {
                    ForEach(0..<Int(height / 3), id: \.self) { _ in
                        Rectangle().fill(.black.opacity(0.06)).frame(height: 0.5)
                    }
                }
                LinearGradient(colors: [.black.opacity(0.2), .clear], startPoint: .leading, endPoint: .trailing)
            }
            .frame(width: pages, height: height - 4)
            .clipped()
        }
        .frame(width: width, height: height)
    }

    @ViewBuilder
    private var cover: some View {
        if let img = coverImage {
            Color.clear
                .overlay(Image(texture: img, scale: displayScale).resizable().scaledToFill())
                .clipped()
                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom))
                .overlay(alignment: .bottom) {
                    Text(journey.title)
                        .font(.custom(KraftFontName.loraSemiBold, size: width * 0.095))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3).minimumScaleFactor(0.6)
                        .padding(.horizontal, 22).padding(.bottom, 22).padding(.leading, spine)
                }
                .overlay(sheen)
        } else {
            ZStack {
                cloth
                LinearGradient(colors: [.white.opacity(0.10), .clear, .black.opacity(0.12)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(.white.opacity(0.55), lineWidth: 1)
                    .padding(.leading, spine + 12).padding([.top, .bottom, .trailing], 12)
                VStack(spacing: 10) {
                    Text(journey.title)
                        .font(.custom(KraftFontName.loraSemiBold, size: width * 0.105))
                        .foregroundStyle(.white.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .lineLimit(4).minimumScaleFactor(0.6)
                    Rectangle().fill(.white.opacity(0.6)).frame(width: 34, height: 1)
                    if let c = journey.displayCity, !c.isEmpty {
                        Text(c.uppercased())
                            .font(.custom(KraftFontName.lora, size: 10)).tracking(2)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .padding(.leading, spine + 26).padding(.trailing, 26)
            }
            .overlay(sheen)
        }
    }

    private var sheen: some View {
        LinearGradient(colors: [.white.opacity(0.16), .clear, .clear], startPoint: .topTrailing, endPoint: .center)
    }
}

// MARK: - Previews

#Preview("Cover Rack, many") {
    let container = AppContainer.make(inMemory: true)
    SampleData.mumbai(in: container.mainContext)
    for (t, c) in [("Lisbon in Spring", "Lisbon"), ("Kyoto Autumn", "Kyoto"), ("Patagonia", nil), ("Iceland Ring Road", "Reykjavik")] as [(String, String?)] {
        container.mainContext.insert(Journey(title: t, date: .now.addingTimeInterval(Double.random(in: -9e6...0)), city: c))
    }
    let all = (try? container.mainContext.fetch(FetchDescriptor<Journey>())) ?? []
    return CoverRackShelfView(context: .init(journeys: all, open: { _ in }, requestDelete: { _ in }))
        .modelContainer(container)
}

#Preview("Cover Rack, one") {
    let container = AppContainer.make(inMemory: true)
    let j = Journey(title: "Mumbai Monsoon", city: "Mumbai")
    container.mainContext.insert(j)
    return CoverRackShelfView(context: .init(journeys: [j], open: { _ in }, requestDelete: { _ in }))
        .modelContainer(container)
}
