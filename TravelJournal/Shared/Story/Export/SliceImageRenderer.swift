import SwiftUI
import CoreGraphics

/// Renders a SwiftUI page view to a bitmap for image exports (carousel slides, Story frames, the Export sheet
/// thumbnail). The view is laid out at `size` points and drawn at `scale` pixels per point, then redrawn into an
/// sRGB bitmap so every output has the same, web-safe colour space whatever `ImageRenderer` picked.
///
/// Like the PDF, photos must be preloaded (`PDFImageProvider.preload`) before rendering: `ImageRenderer` is synchronous.
@MainActor
enum SliceImageRenderer {
    /// JPEG quality for exported slides and frames.
    static let jpegQuality: CGFloat = 0.9

    /// `view` at exactly `size` points, `scale` pixels per point (output: `size x scale`, rounded), sRGB.
    /// `background` fills first so transparent areas don't turn black in a JPEG; nil keeps transparency.
    static func render<V: View>(_ view: V, size: CGSize, scale: CGFloat,
                                background: CGColor? = ImageDrawing.color(white: 1)) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = scale
        guard let drawn = renderer.cgImage else { return nil }

        let w = max(1, Int((size.width * scale).rounded())), h = max(1, Int((size.height * scale).rounded()))
        let info = background == nil ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: ImageDrawing.sRGB, bitmapInfo: info.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        if let background {
            ctx.setFillColor(background)
            ctx.fill(rect)
        }
        ctx.interpolationQuality = .high
        ctx.draw(drawn, in: rect)
        return ctx.makeImage()
    }

    /// One slice of `spec` at its `renderScale` (e.g. carousel: 1080 x 1350 px).
    static func render<V: View>(_ view: V, spec: OutputSpec) -> CGImage? {
        render(view, size: spec.sliceSize, scale: spec.renderScale)
    }

    /// Small preview: `view` laid out at `size` points, drawn so its longest side is about `maxPixel` pixels.
    static func thumbnail<V: View>(_ view: V, size: CGSize, maxPixel: Int = 600) -> CGImage? {
        let longest = max(size.width, size.height, 1)
        return render(view, size: size, scale: CGFloat(maxPixel) / longest)
    }

    /// JPEG bytes with no metadata properties (no EXIF, GPS, TIFF or IPTC): only the pixels and quality are passed
    /// to ImageIO.
    nonisolated static func jpegData(_ image: CGImage, quality: CGFloat = 0.9) -> Data? {
        ImageDrawing.jpegData(image, quality: quality)
    }
}
