import SwiftUI
import UIKit

/// Subtle tileable paper noise generated in code (seeded, so identical every launch).
enum PaperGrain {
    static let tile: UIImage = {
        let n = 128
        var s = SeededStream("paper-grain", "v1")
        var px = [UInt8](repeating: 0, count: n * n * 4)
        for i in 0..<(n * n) {
            let a = s.unit()
            // Mostly transparent; sparse darker flecks. Premultiplied ink-brown.
            let alpha = UInt8(a < 0.7 ? 0 : min(255, Int((a - 0.7) / 0.3 * 46)))
            px[i * 4 + 0] = UInt8(Int(0x6B) * Int(alpha) / 255)
            px[i * 4 + 1] = UInt8(Int(0x52) * Int(alpha) / 255)
            px[i * 4 + 2] = UInt8(Int(0x3A) * Int(alpha) / 255)
            px[i * 4 + 3] = alpha
        }
        let data = Data(px)
        guard let provider = CGDataProvider(data: data as CFData),
              let cg = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return UIImage() }
        return UIImage(cgImage: cg)
    }()
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
            Image(uiImage: PaperGrain.tile)
                .resizable(resizingMode: .tile)
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
