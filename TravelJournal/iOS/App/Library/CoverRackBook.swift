import SwiftUI
import SwiftData

// MARK: - Palette

enum CoverRackLibPalette {
    static let text = Color(red: 0.13, green: 0.17, blue: 0.20)
    static let textSoft = Color(red: 0.34, green: 0.40, blue: 0.43)

    /// Muted cover colors as (hue, saturation, brightness). Indexed by `LibraryIndex.colorIndex(forCategory:)`.
    private static let base: [(Double, Double, Double)] = [
        (0.58, 0.42, 0.47), (0.40, 0.30, 0.42), (0.02, 0.45, 0.50), (0.10, 0.50, 0.70),
        (0.72, 0.30, 0.47), (0.55, 0.38, 0.33), (0.92, 0.30, 0.52), (0.30, 0.28, 0.44),
    ]

    /// FNV-1a over the UUID bytes: stable across launches (never `hashValue`).
    static func stableHash(_ id: UUID) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        withUnsafeBytes(of: id.uuid) { for b in $0 { h = (h ^ UInt32(b)) &* 16_777_619 } }
        return h
    }

    static func cover(category: String, id: UUID) -> Color {
        let i = abs(LibraryIndex.colorIndex(forCategory: category)) % base.count
        let (h, s, b) = base[i]
        let r = stableHash(id)
        let dh = (Double(r & 0xFF) / 255 - 0.5) * 0.03
        let ds = (Double((r >> 8) & 0xFF) / 255 - 0.5) * 0.10
        let db = (Double((r >> 16) & 0xFF) / 255 - 0.5) * 0.10
        return Color(hue: (h + dh + 1).truncatingRemainder(dividingBy: 1),
                     saturation: min(max(s + ds, 0), 1), brightness: min(max(b + db, 0), 1))
    }
}

// MARK: - Backdrop and plank

struct CoverRackLibWall: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.89, green: 0.93, blue: 0.94),
                                Color(red: 0.78, green: 0.84, blue: 0.86)],
                       startPoint: .top, endPoint: .bottom)
    }
}

struct CoverRackLibPlank: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Color(red: 0.80, green: 0.66, blue: 0.48), Color(red: 0.70, green: 0.55, blue: 0.38)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 24)
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.62, green: 0.47, blue: 0.31), Color(red: 0.50, green: 0.37, blue: 0.24)],
                               startPoint: .top, endPoint: .bottom)
                Rectangle().fill(.white.opacity(0.22)).frame(height: 1)
            }
            .frame(height: 14)
            LinearGradient(colors: [.black.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 22)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Book

struct CoverRackLibBook: View {
    let story: LibraryStory
    let width: CGFloat
    let height: CGFloat
    let tilt: Bool

    @State private var photo: CGImage?
    @Environment(\.displayScale) private var displayScale
    @Environment(\.modelContext) private var context

    private let spine: CGFloat = 11
    private let pages: CGFloat = 7

    private var category: String {
        if let c = story.country, !c.isEmpty { return c }
        if let c = story.city, !c.isEmpty { return c }
        return "Other"
    }

    var body: some View {
        ZStack(alignment: .top) {
            Ellipse()
                .fill(.black.opacity(0.35))
                .frame(width: width * 0.92, height: 14)
                .blur(radius: 6)
                .offset(y: height - 4)

            bookBody
                .scaleEffect(x: 1, y: -1, anchor: .bottom)
                .offset(y: height + 2)
                .mask(alignment: .top) {
                    LinearGradient(colors: [.black.opacity(0.2), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 36)
                        .offset(y: height + 2)
                }
                .allowsHitTesting(false)

            bookBody
                .rotation3DEffect(.degrees(tilt ? 5 : 0), axis: (1, 0, 0), anchor: .bottom, perspective: 0.6)
                .shadow(color: .black.opacity(0.18), radius: 6, x: 4, y: 4)
        }
        .frame(width: width, height: height, alignment: .top)
        .task(id: story.coverPhotoID) { await loadPhoto() }
    }

    /// Reads the cover's bytes here (the model context belongs to the main actor) and decodes them off it.
    private func loadPhoto() async {
        guard let id = story.coverPhotoID else { photo = nil; return }
        let maxPixel = ImageDecoding.maxPixel(forPoints: max(width, height), scale: displayScale)
        if let hit = StoredPhotos.cached(id: id, maxPixel: maxPixel) { photo = hit; return }
        guard let data = StoredPhotos.imageData(forPhotoID: id, in: context) else { photo = nil; return }
        photo = await Task.detached(priority: .userInitiated) { StoredPhotos.decode(data, id: id, maxPixel: maxPixel) }.value
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
                    ForEach(0..<max(Int(height / 3), 1), id: \.self) { _ in
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
        if let img = photo {
            Color.clear
                .overlay(Image(texture: img, scale: displayScale).resizable().scaledToFill())
                .clipped()
                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom))
                .overlay(alignment: .bottom) {
                    Text(story.title)
                        .font(.custom(KraftFontName.loraSemiBold, size: width * 0.095))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3).minimumScaleFactor(0.6)
                        .padding(.horizontal, 22).padding(.bottom, 22).padding(.leading, spine)
                }
        } else {
            ZStack {
                CoverRackLibPalette.cover(category: category, id: story.id)
                LinearGradient(colors: [.white.opacity(0.08), .clear, .black.opacity(0.10)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                    .padding(.leading, spine + 12).padding([.top, .bottom, .trailing], 12)
                VStack(spacing: 10) {
                    Text(story.title)
                        .font(.custom(KraftFontName.loraSemiBold, size: width * 0.105))
                        .foregroundStyle(.white.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .lineLimit(4).minimumScaleFactor(0.6)
                    Rectangle().fill(.white.opacity(0.6)).frame(width: 34, height: 1)
                    if let c = story.city, !c.isEmpty {
                        Text(c.uppercased())
                            .font(.custom(KraftFontName.lora, size: 10)).tracking(2)
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)
                    }
                }
                .padding(.leading, spine + 26).padding(.trailing, 26)
            }
        }
    }
}
