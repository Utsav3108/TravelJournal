import SwiftUI

// MARK: - Palette & helpers

enum BookcasePalette {
    /// Fixed 8-color spine palette (base, darker edge).
    static let colors: [(Color, Color)] = [
        (Color(hex: 0x7A2E2A), Color(hex: 0x4E1B19)),  // oxblood
        (Color(hex: 0x2F5D50), Color(hex: 0x1B3A31)),  // forest
        (Color(hex: 0x264A6B), Color(hex: 0x16304A)),  // navy
        (Color(hex: 0xB07A2A), Color(hex: 0x7C5217)),  // ochre
        (Color(hex: 0x5B3A6B), Color(hex: 0x3A2347)),  // plum
        (Color(hex: 0x8C4A2F), Color(hex: 0x5C2D1A)),  // rust
        (Color(hex: 0x3E6B6A), Color(hex: 0x264544)),  // teal
        (Color(hex: 0x6B5B3A), Color(hex: 0x453A22)),  // olive-khaki
    ]
    static let walnutLight = Color(hex: 0x6B4429)
    static let walnut = Color(hex: 0x4A2E1B)
    static let walnutDark = Color(hex: 0x2E1B0F)
    static let gold = Color(hex: 0xD9B45B)

    /// Spine thickness in points for a story weight (stops count).
    static func thickness(weight: Int) -> CGFloat { min(44, max(18, 14 + CGFloat(weight) * 3)) }
}

/// Stable FNV-1a over bytes (never hashValue).
func bookcaseStableSeed(_ bytes: some Sequence<UInt8>) -> Int {
    var h: UInt32 = 2166136261
    for b in bytes { h = (h ^ UInt32(b)) &* 16777619 }
    return Int(h)
}

func bookcaseStableSeed(_ id: UUID) -> Int {
    withUnsafeBytes(of: id.uuid) { bookcaseStableSeed($0) }
}

// MARK: - Wood

/// Dark wood-grain interior, drawn once per shelf.
struct BookcaseGrain: View {
    var seed: Int
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [BookcasePalette.walnutDark, BookcasePalette.walnut.opacity(0.9)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            var s = UInt64(truncatingIfNeeded: seed) &+ 88172645463325252
            func next() -> CGFloat {
                s ^= s << 13; s ^= s >> 7; s ^= s << 17
                return CGFloat(s % 10_000) / 10_000
            }
            var y: CGFloat = 2
            while y < size.height {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addCurve(to: CGPoint(x: size.width, y: y + next() * 3),
                           control1: CGPoint(x: size.width * 0.3, y: y + next() * 4 - 2),
                           control2: CGPoint(x: size.width * 0.7, y: y + next() * 4 - 2))
                ctx.stroke(p, with: .color(.black.opacity(0.10 + next() * 0.12)), lineWidth: 0.6 + next() * 0.6)
                y += 3 + next() * 7
            }
        }
        .allowsHitTesting(false)
    }
}

/// The plank a row of spines stands on.
struct BookcasePlank: View {
    var height: CGFloat = 14
    var body: some View {
        LinearGradient(colors: [BookcasePalette.walnutLight, BookcasePalette.walnut, BookcasePalette.walnutDark],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.18)).frame(height: 1) }
            .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
    }
}

// MARK: - Label plate

struct BookcaseLabelPlate: View {
    let title: String
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(title) · \(count)")
                .font(.custom(KraftFontName.loraSemiBold, size: 13, relativeTo: .footnote))
                .foregroundStyle(Color(hex: 0x3B2A10))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0xE8CC82), Color(hex: 0xB8923F)],
                                             startPoint: .top, endPoint: .bottom))
                )
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(Color(hex: 0x7C5A1E).opacity(0.7), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                .padding(.vertical, 6)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count) stories, open cover rack")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Spine

struct BookcaseSpine: View {
    let story: LibraryStory
    let colorIndex: Int
    let scale: CGFloat
    let highlighted: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void

    private var seed: Int { bookcaseStableSeed(story.id) }
    private var thickness: CGFloat { BookcasePalette.thickness(weight: story.weight) * scale }
    private var height: CGFloat { 106 + CGFloat(seed % 29) }
    private var tone: Double { Double((seed >> 5) % 21) / 100 - 0.10 }

    private var a11yLabel: String {
        let date = story.date.formatted(.dateTime.day().month(.wide).year())
        if let city = story.city, !city.isEmpty { return "\(story.title), \(city), \(date)" }
        return "\(story.title), \(date)"
    }

    var body: some View {
        let pal = BookcasePalette.colors[((colorIndex % 8) + 8) % 8]
        Button(action: onOpen) {
            ZStack {
                LinearGradient(colors: [pal.1, pal.0, pal.0, pal.1], startPoint: .leading, endPoint: .trailing)
                if tone > 0 { Color.white.opacity(tone * 0.5) } else { Color.black.opacity(-tone * 0.5) }
                VStack(spacing: 0) {
                    band.padding(.top, 8)
                    Spacer(minLength: 0)
                    band.padding(.bottom, 10)
                }
                Text(story.title)
                    .font(.custom(KraftFontName.lora, fixedSize: max(9, min(13, thickness * 0.36))))
                    .foregroundStyle(BookcasePalette.gold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: height - 44)
                    .rotationEffect(.degrees(-90))
                    .frame(width: thickness, height: height)
            }
            .frame(width: thickness, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.14)).frame(width: 1) }
            .shadow(color: highlighted ? Color(hex: 0xFFC965).opacity(0.85) : .black.opacity(0.35),
                    radius: highlighted ? 8 : 1.5, x: highlighted ? 0 : 1, y: highlighted ? 0 : 1)
            .offset(y: highlighted ? -6 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
        .accessibilityLabel(a11yLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var band: some View {
        VStack(spacing: 2) {
            Rectangle().fill(BookcasePalette.gold.opacity(0.85)).frame(height: 1.5)
            Rectangle().fill(BookcasePalette.gold.opacity(0.55)).frame(height: 1)
        }
    }
}

struct BookcaseMoreTile: View {
    let count: Int
    let shelfTitle: String
    let scale: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("+\(count)")
                .font(.custom(KraftFontName.loraSemiBold, fixedSize: 13))
                .foregroundStyle(Color(hex: 0x3B2A10))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(width: 34 * scale, height: 120)
                .background(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0xE3C987), Color(hex: 0xB8923F)], startPoint: .leading, endPoint: .trailing))
                )
                .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).stroke(Color(hex: 0x7C5A1E).opacity(0.6), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.35), radius: 1.5, x: 1, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(count) more stories from \(shelfTitle)")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Globe prop

struct BookcaseGlobeButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(RadialGradient(colors: [Color(hex: 0x6FA3A0), Color(hex: 0x2F5D6B)],
                                                 center: .topLeading, startRadius: 1, endRadius: 28))
                    Ellipse().stroke(BookcasePalette.gold.opacity(0.6), lineWidth: 0.8).frame(width: 14, height: 30)
                    Capsule().fill(Color(hex: 0x7BA05B).opacity(0.8)).frame(width: 10, height: 6).offset(x: -6, y: -4)
                    Capsule().fill(Color(hex: 0x7BA05B).opacity(0.8)).frame(width: 8, height: 10).offset(x: 7, y: 6)
                    Circle().stroke(BookcasePalette.gold, lineWidth: 1.5)
                }
                .frame(width: 34, height: 34)
                Rectangle().fill(BookcasePalette.gold).frame(width: 2, height: 4)
                Capsule().fill(BookcasePalette.walnutLight).frame(width: 20, height: 4)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Browse places")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Search field

struct BookcaseSearchField: View {
    @Binding var query: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(KraftColor.inkSoft)
            TextField("Search stories", text: $query)
                .font(.custom(KraftFontName.lora, size: 16, relativeTo: .body))
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(KraftColor.inkSoft)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, query.isEmpty ? 12 : 0)
        .frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KraftColor.polaroidWhite))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(KraftColor.paperEdge, lineWidth: 0.8))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
