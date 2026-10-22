import SwiftUI
import ImageIO
import CoreGraphics

/// Platform-neutral photo decoding. Everything that used to go through `UIImage` goes through here instead:
/// file or `Data` in, downsampled `CGImage` out.
///
/// Rules the callers rely on (each is pinned by a test in `ImageDecodingTests`):
/// - Rotation: EXIF orientation is baked into the pixels (`...WithTransform`), so the result is always upright and
///   views must pass `.up` to `Image`.
/// - Scale: callers size the decode as points x `displayScale` (`maxPixel(forPoints:scale:)`) and pass the same scale to `Image`.
/// - Colour: ImageIO keeps the source profile (Display P3 stays P3); nothing here redraws into sRGB.
/// - A decode never upsizes: the longest side is clamped to the source's own pixel size.
nonisolated enum ImageDecoding {
    /// Longest side in pixels for a view of `points` at `scale` (never below 1).
    static func maxPixel(forPoints points: CGFloat, scale: CGFloat) -> Int {
        max(1, Int((max(points, 1) * max(scale, 1)).rounded(.up)))
    }

    static func cgImage(at url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return decode(src, maxPixel: maxPixel)
    }

    static func cgImage(from data: Data, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return decode(src, maxPixel: maxPixel)
    }

    /// Pixel size of the stored (unrotated) image without decoding it.
    static func pixelSize(at url: URL) -> CGSize? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return pixelSize(of: src)
    }

    /// Memory the decoded bitmap occupies; the `NSCache` cost.
    static func cost(of image: CGImage) -> Int { image.width * image.height * 4 }

    private static func decode(_ src: CGImageSource, maxPixel: Int) -> CGImage? {
        var limit = max(1, maxPixel)
        if let size = pixelSize(of: src) { limit = min(limit, Int(max(size.width, size.height))) }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    private static func pixelSize(of src: CGImageSource) -> CGSize? {
        guard let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: w, height: h)
    }
}

/// Decoded-image cache that knows what an image weighs. `NSCache` has no idea how big a `CGImage` is, so every insert
/// carries `width x height x 4` as its cost, and `totalCostLimit` is what actually makes it evict.
nonisolated final class DecodedImageCache: @unchecked Sendable {
    private let cache = NSCache<NSString, CGImage>()

    /// Default budget: 1/16 of physical memory, between 48 and 128 MB.
    static var defaultCostLimit: Int {
        let ram = Int(clamping: ProcessInfo.processInfo.physicalMemory)
        return min(max(ram / 16, 48 << 20), 128 << 20)
    }

    init(costLimit: Int = DecodedImageCache.defaultCostLimit) {
        cache.totalCostLimit = costLimit
    }

    func image(forKey key: String) -> CGImage? { cache.object(forKey: key as NSString) }

    func insert(_ image: CGImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString, cost: ImageDecoding.cost(of: image))
    }

    func removeAll() { cache.removeAllObjects() }
}

/// Shared, cached loader for stored photos (covers, thumbnails) used by the shelf and editors.
/// Keyed by path and decode size, so a 600 px thumbnail request and a 1600 px request never collide.
nonisolated enum StoredPhotos {
    static let cache = DecodedImageCache()

    /// "sample:" paths and empty strings never have files.
    static func isLoadable(_ path: String?) -> Bool {
        guard let path else { return false }
        return !path.isEmpty && !path.hasPrefix("sample:")
    }

    static func image(path: String?, maxPixel: Int, store: PhotoStoring = FilePhotoStore()) -> CGImage? {
        guard let path, isLoadable(path) else { return nil }
        let key = "\(path)@\(maxPixel)"
        if let hit = cache.image(forKey: key) { return hit }
        let url = store.url(for: path)
        guard FileManager.default.fileExists(atPath: url.path),
              let img = ImageDecoding.cgImage(at: url, maxPixel: maxPixel) else { return nil }
        cache.insert(img, forKey: key)
        return img
    }
}

extension Image {
    /// A photo the user should hear about: `label` is read by VoiceOver.
    init(photo: CGImage, scale: CGFloat, label: String) {
        self.init(photo, scale: scale, orientation: .up, label: Text(label))
    }

    /// Paper, tape and other pure decoration: hidden from VoiceOver.
    init(texture: CGImage, scale: CGFloat) {
        self.init(decorative: texture, scale: scale, orientation: .up)
    }
}
