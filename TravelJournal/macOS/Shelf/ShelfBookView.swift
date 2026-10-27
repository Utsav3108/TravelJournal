#if os(macOS)
import SwiftUI

/// One journey standing face-out: cover photo, title in Allura, standing upright on the shelf.
struct ShelfBookView: View {
    let journey: Journey
    let selected: Bool

    @Environment(\.displayScale) private var displayScale
    @State private var hovering = false

    private static let corners = UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4,
                                                        bottomTrailingRadius: 10, topTrailingRadius: 10)

    private var cover: CGImage? {
        StoredPhotos.image(photo: journey.coverPhoto,
                           maxPixel: ImageDecoding.maxPixel(forPoints: BookcaseReflow.bookSize.width, scale: displayScale))
    }

    var body: some View {
        ZStack {
            KraftColor.kraft
            if let cover {
                GeometryReader { geo in
                    Image(photo: cover, scale: displayScale, label: "Cover of \(journey.title)").resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                }
                .overlay(LinearGradient(colors: [.clear, KraftColor.ink.opacity(0.55)], startPoint: .center, endPoint: .bottom))
            }
            Text(journey.title)
                .font(KraftFont.stopName(30))
                .foregroundStyle(cover == nil ? KraftColor.ink : KraftColor.paper)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .padding(14)
                .frame(maxHeight: .infinity, alignment: cover == nil ? .center : .bottom)
        }
        .frame(width: BookcaseReflow.bookSize.width, height: BookcaseReflow.bookSize.height)
        .clipShape(Self.corners)
        .overlay(alignment: .leading) { Rectangle().fill(KraftColor.kraftDark.opacity(0.35)).frame(width: 6) }
        // Selection is a book pulled forward from the shelf, not an outline.
        .shadow(color: .black.opacity(selected ? 0.45 : hovering ? 0.4 : 0.28),
                radius: selected ? 10 : hovering ? 8 : 5, x: 0, y: selected ? 8 : hovering ? 6 : 4)
        .offset(y: selected ? -8 : hovering ? -4 : 0)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.15), value: selected)
        .onHover { hovering = $0 }
        .pointerStyle(.link)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens the story")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var accessibilityText: String {
        var s = journey.title + ", " + journey.date.formatted(date: .long, time: .omitted)
        if let c = journey.city, !c.isEmpty { s += ", " + c }
        return s
    }
}

/// The last slot of a collapsed bookcase ("+10 books") and the end of an expanded one ("Show less").
struct ShelfTileView: View {
    let title: String
    let hint: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(KraftFont.stopName(30))
                .foregroundStyle(KraftColor.ink)
                .multilineTextAlignment(.center)
                .frame(width: BookcaseReflow.bookSize.width, height: BookcaseReflow.bookSize.height)
                .background(KraftColor.kraft.opacity(hovering ? 0.55 : 0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(KraftColor.kraftDark.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerStyle(.link)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }
}

/// The wall behind the books: paper, with a wooden plank under every shelf.
struct ShelfWall: View {
    let rows: Int
    var topInset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: topInset)
            ForEach(0..<rows, id: \.self) { row in
                Color.clear
                    .frame(height: BookcaseReflow.shelfHeight - BookcaseReflow.plankHeight)
                BookcasePlank(height: BookcaseReflow.plankHeight)
                    .background(BookcaseGrain(seed: 100 + row))
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
#endif
