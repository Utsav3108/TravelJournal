import SwiftUI
import UIKit
import ImageIO

/// Supplies decoded photos to story pages. Synchronous on purpose: `ImageRenderer` (PDF export) cannot wait for async loads.
/// Returning nil means "draw `KraftPhotoPlaceholder`" (sample photos, missing or unreadable files).
protocol StoryImageProvider {
    func image(for photo: StoryPhoto, preferThumbnail: Bool) -> UIImage?
}

/// Default provider: reads from a `FilePhotoStore`, caches decoded images in an `NSCache`.
/// Thumbnails are preferred in interactive mode and fall back to the display file; print mode uses the display file
/// (downsampled to `printMaxPixel` so the PDF stays small) and falls back to the thumbnail.
final class FileStoryImageProvider: StoryImageProvider {
    static let printMaxPixel = 1600

    private let store: PhotoStoring
    private let cache = NSCache<NSString, UIImage>()
    private(set) var loadCount = 0

    init(store: PhotoStoring = FilePhotoStore(), cacheLimit: Int = 60) {
        self.store = store
        cache.countLimit = cacheLimit
    }

    func image(for photo: StoryPhoto, preferThumbnail: Bool) -> UIImage? {
        let candidates: [String?] = preferThumbnail ? [photo.thumbPath, photo.relativePath] : [photo.relativePath, photo.thumbPath]
        for case let path? in candidates where Self.isLoadable(path) {
            let key = path as NSString
            if let hit = cache.object(forKey: key) { return hit }
            if let img = load(path) {
                cache.setObject(img, forKey: key)
                return img
            }
        }
        return nil
    }

    /// "sample:" paths and empty strings never have files.
    nonisolated static func isLoadable(_ path: String) -> Bool { !path.isEmpty && !path.hasPrefix("sample:") }

    private func load(_ path: String) -> UIImage? {
        let url = store.url(for: path)
        guard FileManager.default.fileExists(atPath: url.path),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.printMaxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        loadCount += 1
        return UIImage(cgImage: cg)
    }
}

/// Always returns nil: every photo draws a placeholder (previews, tests).
struct PlaceholderImageProvider: StoryImageProvider {
    func image(for photo: StoryPhoto, preferThumbnail: Bool) -> UIImage? { nil }
}

private struct StoryImageProviderKey: EnvironmentKey {
    static let defaultValue: StoryImageProvider = FileStoryImageProvider()
}

extension EnvironmentValues {
    var storyImageProvider: StoryImageProvider {
        get { self[StoryImageProviderKey.self] }
        set { self[StoryImageProviderKey.self] = newValue }
    }
}
