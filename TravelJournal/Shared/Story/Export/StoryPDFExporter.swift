import SwiftUI
import SwiftData
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum StoryPDFExportError: LocalizedError {
    case noStops
    case cannotCreateFile

    var errorDescription: String? {
        switch self {
        case .noStops: "Add at least one stop before exporting a PDF."
        case .cannotCreateFile: "The PDF file could not be created."
        }
    }
}

/// Renders a journey to ONE multi-page A4 PDF (595x842 pt, print mode). Text and shapes stay vector.
/// Order matters: the overview map is awaited and all photos are decoded BEFORE rendering because
/// `ImageRenderer` renders synchronously and cannot wait for async loads.
@MainActor
final class StoryPDFExporter {
    static let appName = "TravelJournal"

    private let layout = StoryLayout()
    private let snapshots: MapSnapshotService
    private let outputDirectory: URL?
    /// Called with (pagesRendered, totalPages). (0, n) fires before the first page.
    var progress: ((Int, Int) -> Void)?

    init(snapshots: MapSnapshotService = .shared, outputDirectory: URL? = nil) {
        self.snapshots = snapshots
        self.outputDirectory = outputDirectory
    }

    /// "A Day in Mumbai" -> "A Day in Mumbai.pdf". Strips path/control characters; empty -> "Journey".
    nonisolated static func fileName(forTitle title: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|%").union(.controlCharacters).union(.newlines)
        var s = title.unicodeScalars.map { bad.contains($0) ? " " : String($0) }.joined()
        s = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if s.isEmpty { s = "Journey" }
        if s.count > 80 { s = String(s.prefix(80)).trimmingCharacters(in: .whitespaces) }
        return s + ".pdf"
    }

    /// Throws `CancellationError` (leaving no file) if the surrounding task is cancelled.
    func export(_ journey: Journey) async throws -> URL {
        guard !journey.orderedStops.isEmpty else { throw StoryPDFExportError.noStops }
        let pages = layout.pages(for: journey)
        let total = pages.count
        progress?(0, total)

        // 1. Overview map (never throws; falls back to the drawn map offline).
        var snap: MapSnap?
        for case .overview(let model) in pages {
            snap = await snapshots.snapshot(for: model, size: MapSnapshotService.mapSize(for: .a4), scale: 3)
        }
        try Task.checkCancellation()

        // 2. Preload every photo so the synchronous render finds it cached (downsampled to 1600 px).
        let provider = PDFImageProvider(source: journey.modelContext.map(ModelPhotoSource.init(context:)))
        for page in pages {
            for photo in Self.photos(of: page) {
                _ = provider.image(for: photo, preferThumbnail: false)
            }
            try Task.checkCancellation()
            await Task.yield()
        }

        // 3. Render.
        let dir = outputDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("TravelJournalExport", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(Self.fileName(forTitle: journey.title))
        try? FileManager.default.removeItem(at: url)

        var box = CGRect(origin: .zero, size: PageMetrics.a4.size)
        let info: [String: Any] = [
            kCGPDFContextTitle as String: journey.title,
            kCGPDFContextAuthor as String: Self.appName,
            kCGPDFContextCreator as String: Self.appName,
            kCGPDFContextSubject as String: journey.city ?? "Travel journal",
        ]
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else {
            throw StoryPDFExportError.cannotCreateFile
        }
        do {
            for (i, page) in pages.enumerated() {
                try Task.checkCancellation()
                let view = StoryPageView(page: page, metrics: .a4, overviewSnap: snap,
                                         entryY: StopLayout.entryY(at: i, in: pages, metrics: .a4))
                    .environment(\.storyImageProvider, provider)
                    .frame(width: box.width, height: box.height)
                let renderer = ImageRenderer(content: view)
                renderer.proposedSize = ProposedViewSize(box.size)
                renderer.render { _, draw in
                    ctx.beginPDFPage(nil)
                    draw(ctx)
                    ctx.endPDFPage()
                }
                progress?(i + 1, total)
                await Task.yield()
            }
        } catch {
            ctx.closePDF()
            try? FileManager.default.removeItem(at: dir)
            throw error
        }
        ctx.closePDF()
        if Task.isCancelled {
            try? FileManager.default.removeItem(at: dir)
            throw CancellationError()
        }
        return url
    }

    private static func photos(of page: StoryPage) -> [StoryPhoto] {
        switch page {
        case .cover(let m): m.heroPhotos
        case .stop(let m): m.photos
        case .overview, .closing: []
        }
    }
}

/// Print-time photo provider. Downsamples to 1600 px, re-encodes as JPEG and hands back an image backed by
/// the JPEG data, so Core Graphics embeds it in the PDF as DCT (JPEG) instead of a Flate-compressed bitmap
/// (which made an 8-photo PDF ~19 MB). Preloaded before rendering; `image(for:)` is a cache lookup.
@MainActor
final class PDFImageProvider: StoryImageProvider {
    static let maxPixel = ModelStoryImageProvider.printMaxPixel
    static let quality: CGFloat = 0.8

    private let source: StoryPhotoSource?
    private let cache = DecodedImageCache()

    /// `source` is nil for a journey that isn't in a context (nothing to read, so every photo is a placeholder).
    init(source: StoryPhotoSource?) { self.source = source }

    /// Print always uses the full print resolution, whatever the caller asked for.
    nonisolated func image(for photo: StoryPhoto, preferThumbnail: Bool, maxPixel: Int) -> CGImage? {
        MainActor.assumeIsolated { lookup(photo) }
    }

    private func lookup(_ photo: StoryPhoto) -> CGImage? {
        if let hit = cache.image(forKey: photo.id) { return hit }
        guard let data = source?.imageData(forPhotoID: photo.id), let img = load(data) else { return nil }
        cache.insert(img, forKey: photo.id)
        return img
    }

    /// Downsample, JPEG-encode, decode the JPEG back. The encode keeps the source colour space (Display P3 stays P3),
    /// so the DCT data embedded in the PDF carries the same profile as the photo.
    private func load(_ data: Data) -> CGImage? {
        guard let cg = ImageDecoding.cgImage(from: data, maxPixel: Self.maxPixel) else { return nil }
        guard let data = ImageDrawing.jpegData(cg, quality: Self.quality),
              let jsrc = CGImageSourceCreateWithData(data as CFData, nil),
              let jpegBacked = CGImageSourceCreateImageAtIndex(jsrc, 0, nil) else { return cg }
        return jpegBacked
    }
}
