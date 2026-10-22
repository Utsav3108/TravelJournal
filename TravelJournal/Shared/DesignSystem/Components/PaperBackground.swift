import SwiftUI

/// Subtle tileable paper noise generated in code (seeded, so identical every launch).
///
/// The tile is always 128 x 128 POINTS, but its pixel size follows the display (128 x scale), so the grain stays crisp
/// on 2x, 3x and 5K screens. The seed is the same for every scale; only the cell resolution changes. Pass the matching
/// `scale:` to `Image` (see `PaperGrainTexture`), otherwise the tile is drawn at the wrong size.
enum PaperGrain {
    static let points = 128
    private static var cache: [Int: CGImage] = [:]

    /// Whole display scales only (1, 2, 3): keeps the cache tiny and the tile edge on exact pixels.
    static func tile(scale: CGFloat) -> CGImage {
        let s = min(max(Int(scale.rounded()), 1), 4)
        if let hit = cache[s] { return hit }
        let n = points * s
        var rng = SeededStream("paper-grain", "v1")
        var px = [UInt8](repeating: 0, count: n * n * 4)
        for i in 0..<(n * n) {
            let a = rng.unit()
            // Mostly transparent; sparse darker flecks. Premultiplied ink-brown.
            let alpha = UInt8(a < 0.7 ? 0 : min(255, Int((a - 0.7) / 0.3 * 46)))
            px[i * 4 + 0] = UInt8(Int(0x6B) * Int(alpha) / 255)
            px[i * 4 + 1] = UInt8(Int(0x52) * Int(alpha) / 255)
            px[i * 4 + 2] = UInt8(Int(0x3A) * Int(alpha) / 255)
            px[i * 4 + 3] = alpha
        }
        let cg = CGDataProvider(data: Data(px) as CFData).flatMap {
            CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                    space: ImageDrawing.sRGB,   // the ink colour is authored in sRGB
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: $0, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        } ?? ImageDrawing.render(size: CGSize(width: 1, height: 1))!
        cache[s] = cg
        return cg
    }
}

/// The paper grain as a tiling image at the current display scale. Decorative: hidden from VoiceOver.
struct PaperGrainTexture: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let scale = CGFloat(min(max(Int(displayScale.rounded()), 1), 4))
        Image(texture: PaperGrain.tile(scale: scale), scale: scale)
            .resizable(resizingMode: .tile)
    }
}

/// Cream paper with grain, used as page and app background.
struct PaperBackground: View {
    var grainOpacity: Double = 0.55

    init(grainOpacity: Double = 0.55) {
        self.grainOpacity = grainOpacity
        KraftFonts.register() // idempotent; makes previews pick up bundled fonts
    }

    var body: some View {
        ZStack {
            KraftColor.paper
            PaperGrainTexture()
                .opacity(grainOpacity)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Stand-in for a photo in previews and empty states.
struct KraftPhotoPlaceholder: View {
    var hue: Double = 0.08
    var body: some View {
        LinearGradient(colors: [Color(hue: hue, saturation: 0.35, brightness: 0.85),
                                Color(hue: hue + 0.08, saturation: 0.45, brightness: 0.55)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Image(systemName: "photo").font(.system(size: 28)).foregroundStyle(.white.opacity(0.6)))
    }
}

#Preview("PaperBackground") {
    PaperBackground()
}
