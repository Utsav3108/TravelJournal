import SwiftUI
import SwiftData

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
        image(for: photo, preferThumbnail: preferThumbnail, maxPixel: ModelStoryImageProvider.printMaxPixel)
    }
}

/// Where story photos' bytes come from, looked up by `StoryPhoto.id` (the `StopPhoto.id` UUID string).
/// Story pages only carry ids; the bytes stay in the model until a page actually draws the photo.
protocol StoryPhotoSource {
    func imageData(forPhotoID id: String) -> Data?
}

/// Reads `StopPhoto.imageData` through a model context. Ids that aren't a known photo (sample data) give nil.
struct ModelPhotoSource: StoryPhotoSource {
    let context: ModelContext

    func imageData(forPhotoID id: String) -> Data? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return StoredPhotos.imageData(forPhotoID: uuid, in: context)
    }
}

/// Default provider: decodes each photo's stored image at the size asked for and caches it in a cost-limited
/// `DecodedImageCache`. A photo has one stored image, so "thumbnail" vs "full" is just the requested `maxPixel`
/// (interactive pages ask for what their frame needs; print asks for `printMaxPixel`).
final class ModelStoryImageProvider: StoryImageProvider {
    static let printMaxPixel = 1600

    private let source: StoryPhotoSource
    private let cache: DecodedImageCache
    private(set) var loadCount = 0

    init(source: StoryPhotoSource, cacheCostLimit: Int = DecodedImageCache.defaultCostLimit) {
        self.source = source
        cache = DecodedImageCache(costLimit: cacheCostLimit)
    }

    func image(for photo: StoryPhoto, preferThumbnail: Bool, maxPixel: Int) -> CGImage? {
        let limit = min(max(maxPixel, 1), Self.printMaxPixel)
        let key = "\(photo.id)@\(limit)"
        if let hit = cache.image(forKey: key) { return hit }
        guard let data = source.imageData(forPhotoID: photo.id),
              let img = ImageDecoding.cgImage(from: data, maxPixel: limit) else { return nil }
        loadCount += 1
        cache.insert(img, forKey: key)
        return img
    }
}

/// Always returns nil: every photo draws a placeholder (previews, tests).
struct PlaceholderImageProvider: StoryImageProvider {
    func image(for photo: StoryPhoto, preferThumbnail: Bool, maxPixel: Int) -> CGImage? { nil }
}

private struct StoryImageProviderKey: EnvironmentKey {
    static let defaultValue: StoryImageProvider = PlaceholderImageProvider()
}

extension EnvironmentValues {
    var storyImageProvider: StoryImageProvider {
        get { self[StoryImageProviderKey.self] }
        set { self[StoryImageProviderKey.self] = newValue }
    }
}

/// Gives the views below it a provider that reads photos from the model, with one cache that lives as long as the view.
struct StoryPhotosFromModel: ViewModifier {
    @Environment(\.modelContext) private var context
    @State private var holder = Holder()

    /// Reference type so the provider (and its cache) is created once, not on every body pass.
    final class Holder {
        private var provider: ModelStoryImageProvider?
        func provider(for context: ModelContext) -> ModelStoryImageProvider {
            if let provider { return provider }
            let made = ModelStoryImageProvider(source: ModelPhotoSource(context: context))
            provider = made
            return made
        }
    }

    func body(content: Content) -> some View {
        content.environment(\.storyImageProvider, holder.provider(for: context))
    }
}

extension View {
    func storyPhotosFromModel() -> some View { modifier(StoryPhotosFromModel()) }
}
