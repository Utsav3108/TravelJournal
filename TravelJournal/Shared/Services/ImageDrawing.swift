import SwiftUI
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// CoreGraphics drawing and encoding helpers. They replace `UIGraphicsImageRenderer` / `UIColor` / `UIImage.jpegData`.
///
/// Content drawn here is authored in sRGB (brand colours, generated maps), so the bitmap is explicitly sRGB.
/// Photos never go through these helpers' drawing path; they keep their own profile via `ImageDecoding`.
nonisolated enum ImageDrawing {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// Draws into a bitmap of `size` points at `scale` (pixels = points x scale) and returns it.
    /// The context uses a top-left origin and point units, like `UIGraphicsImageRenderer`, so existing drawing code ports unchanged.
    static func render(size: CGSize, scale: CGFloat = 1, opaque: Bool = false, draw: (CGContext) -> Void = { _ in }) -> CGImage? {
        let w = max(1, Int((size.width * scale).rounded())), h = max(1, Int((size.height * scale).rounded()))
        let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: sRGB, bitmapInfo: info) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        draw(ctx)
        return ctx.makeImage()
    }

    static func jpegData(_ image: CGImage, quality: CGFloat) -> Data? {
        encode(image, type: .jpeg, options: [kCGImageDestinationLossyCompressionQuality: quality])
    }

    static func pngData(_ image: CGImage) -> Data? { encode(image, type: .png, options: [:]) }

    private static func encode(_ image: CGImage, type: UTType, options: [CFString: Any]) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    /// sRGB colour from hue/saturation/brightness (0...1), the `UIColor(hue:saturation:brightness:alpha:)` replacement.
    static func color(hue: Double, saturation: Double, brightness: Double, alpha: Double = 1) -> CGColor {
        let c = hsbToRGB(hue: hue, saturation: saturation, brightness: brightness)
        return CGColor(colorSpace: sRGB, components: [c.r, c.g, c.b, alpha]) ?? CGColor(gray: brightness, alpha: alpha)
    }

    static func color(red: Double, green: Double, blue: Double, alpha: Double = 1) -> CGColor {
        CGColor(colorSpace: sRGB, components: [red, green, blue, alpha]) ?? CGColor(gray: 0.5, alpha: alpha)
    }

    static func color(white: Double, alpha: Double = 1) -> CGColor {
        CGColor(colorSpace: sRGB, components: [white, white, white, alpha]) ?? CGColor(gray: white, alpha: alpha)
    }

    static func hsbToRGB(hue: Double, saturation s: Double, brightness v: Double) -> (r: Double, g: Double, b: Double) {
        let h = (hue - hue.rounded(.down)) * 6
        let i = Int(h) % 6, f = h - Double(Int(h))
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}
