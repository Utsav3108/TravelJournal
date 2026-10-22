import SwiftUI

/// Supplies decoded photos to story pages. Synchronous on purpose: `ImageRenderer` (PDF export) cannot wait for async loads.
/// Returning nil means "draw `KraftPhotoPlaceholder`" (sample photos, missing or unreadable files).
/// Images are upright `CGImage`s (EXIF rotation baked in by `ImageDecoding`); show them with `.up` orientation.
protocol StoryImageProvider {
    /// `maxPixel` is the longest side the caller can use (points x display scale); providers may return less, never more.
    func image(for photo: StoryPhoto, preferThumbnail: Bool, maxPixel: Int) -> CGImage?
}

extension StoryImageProvider {
    /// Full-size request (print resolution).
    func image(for photo: StoryPhoto, preferThumbnail: Bool) -> CGImage? {
        image(for: photo, preferThumbnail: preferThumbnail, maxPixel: FileStoryImageProvider.printMaxPixel)
    }
}

/// Default provider: reads from a `FilePhotoStore`, caches decoded images in a cost-limited `DecodedImageCache`.
/// Thumbnails are preferred in interactive mode and fall back to the display file; print mode uses the display file
/// (downsampled to `printMaxPixel` so the PDF stays small) and falls back to the thumbnail.
final class FileStoryImageProvider: StoryImageProvider {
    static let printMaxPixel = 1600

    private let store: PhotoStoring
    private let cache: DecodedImageCache
    private(set) var loadCount = 0

    init(store: PhotoStoring = FilePhotoStore(), cacheCostLimit: Int = DecodedImageCache.defaultCostLimit) {
        self.store = store
        cache = DecodedImageCache(costLimit: cacheCostLimit)
    }

    func image(for photo: StoryPhoto, preferThumbnail: Bool, maxPixel: Int) -> CGImage? {
        let limit = min(max(maxPixel, 1), Self.printMaxPixel)
        let candidates: [String?] = preferThumbnail ? [photo.thumbPath, photo.relativePath] : [photo.relativePath, photo.thumbPath]
        for case let path? in candidates where Self.isLoadable(path) {
            let key = "\(path)@\(limit)"
            if let hit = cache.image(forKey: key) { return hit }
            if let img = load(path, maxPixel: limit) {
                cache.insert(img, forKey: key)
                return img
            }
        }
        return nil
    }

    /// "sample:" paths and empty strings never have files.
    nonisolated static func isLoadable(_ path: String) -> Bool { StoredPhotos.isLoadable(path) }

    private func load(_ path: String, maxPixel: Int) -> CGImage? {
        let url = store.url(for: path)
        guard FileManager.default.fileExists(atPath: url.path),
              let cg = ImageDecoding.cgImage(at: url, maxPixel: maxPixel) else { return nil }
        loadCount += 1
        return cg
    }
}

/// Always returns nil: every photo draws a placeholder (previews, tests).
struct PlaceholderImageProvider: StoryImageProvider {
    func image(for photo: StoryPhoto, preferThumbnail: Bool, maxPixel: Int) -> CGImage? { nil }
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
