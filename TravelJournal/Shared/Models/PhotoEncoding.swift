import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ImageIO helpers shared by the photo store and the V2→V3 migration. Orientation is baked into the pixels
/// (`...WithTransform`) and the source colour space is kept (nothing is redrawn into sRGB), so Display P3 photos stay P3.
nonisolated enum PhotoEncoding {
    struct Encoded {
        var data: Data
        var width: Int
        var height: Int
    }

    /// Longest side in pixels, as stored (EXIF rotation never changes the long edge).
    static func longEdge(of src: CGImageSource) -> Int? {
        guard let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return max(w, h)
    }

    /// Upright image with long edge <= `maxPixel`; never upscales.
    static func downscaled(_ src: CGImageSource, maxPixel: Int) -> CGImage? {
        let cap = min(maxPixel, longEdge(of: src) ?? maxPixel)
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: cap,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    static func jpegData(_ image: CGImage, quality: Double = 0.85) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// Decode, bake orientation, cap the long edge and re-encode as JPEG.
    static func reencoded(_ data: Data, maxPixel: Int) -> Encoded? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = downscaled(src, maxPixel: maxPixel),
              let out = jpegData(img) else { return nil }
        return Encoded(data: out, width: img.width, height: img.height)
    }
}
