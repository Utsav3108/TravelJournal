import SwiftUI
import SwiftData
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum StoryPDFExportError: LocalizedError {
    case noStops
    case allStopsHidden
    case cannotCreateFile

    var errorDescription: String? {
        switch self {
        case .noStops: "Add at least one stop before exporting a PDF."
        case .allStopsHidden: "Every stop is hidden from public exports. Show at least one stop under Export privacy."
        case .cannotCreateFile: "The PDF file could not be created."
        }
    }
}

/// Renders a journey to ONE multi-page A4 PDF (595x842 pt, print mode). Text and shapes stay vector.
///
/// Pipeline: `JourneySnapshot(journey:)` -> `ExportPrivacy.resolved(for:)` -> `PrivacyFilter.apply` ->
/// `VerticalComposer` (`.a4PDF`) -> one PDF page per composed slice, drawn at exactly the slice size.
/// Order matters: the overview map is awaited and all photos are decoded BEFORE rendering because
/// `ImageRenderer` renders synchronously and cannot wait for async loads.
@MainActor
final class StoryPDFExporter {
    static let appName = "TravelJournal"

    let spec = OutputSpec.a4PDF
    private let composer = VerticalComposer()
    private let snapshots: MapSnapshotService
    private let outputDirectory: URL?
    private let privacyDefaults: ExportPrivacyDefaults
    /// Called with (pagesRendered, totalPages). (0, n) fires before the first page.
    var progress: ((Int, Int) -> Void)?

    init(snapshots: MapSnapshotService = .shared, outputDirectory: URL? = nil,
         privacyDefaults: ExportPrivacyDefaults = .standard) {
        self.snapshots = snapshots
        self.outputDirectory = outputDirectory
        self.privacyDefaults = privacyDefaults
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

    /// The privacy-filtered snapshot the PDF is drawn from.
    func snapshot(for journey: Journey) -> JourneySnapshot {
        let privacy = ExportPrivacy.resolved(for: journey, defaults: privacyDefaults)
        return PrivacyFilter.apply(JourneySnapshot(journey: journey), privacy)
    }

    /// The composed pages for `journey` (cover, map, stop pages, closing).
    func document(for journey: Journey) -> (snapshot: JourneySnapshot, document: ComposedDocument) {
        let s = snapshot(for: journey)
        return (s, composer.compose(s, spec: spec))
    }

    /// Throws `CancellationError` (leaving no file) if the surrounding task is cancelled.
    func export(_ journey: Journey) async throws -> URL {
        guard !journey.orderedStops.isEmpty else { throw StoryPDFExportError.noStops }
        let (snapshot, document) = document(for: journey)
        guard !snapshot.stops.isEmpty else { throw StoryPDFExportError.allStopsHidden }
        let slices = document.slices
        let total = slices.count
        progress?(0, total)
        let metrics = spec.pageMetrics

        // 1. Overview map (never throws; falls back to the drawn map offline). Skipped when the map is hidden.
        var snap: MapSnap?
        if slices.contains(where: { $0.kind == .map }) {
            // 2.5x (180 dpi), embedded as JPEG: as a Flate bitmap at 3x the map alone was ~2 MB.
            var map = await snapshots.snapshot(for: snapshot.overviewModel, size: MapSnapshotService.mapSize(for: metrics),
                                               scale: 2.5, mapMode: snapshot.mapMode)
            map.image = PDFImageProvider.jpegBacked(map.image, quality: 0.8)
            snap = map
        }
        try Task.checkCancellation()

        // 2. Preload every photo so the synchronous render finds it cached (downsampled to 1200 px).
        let provider = PDFImageProvider(source: journey.modelContext.map(ModelPhotoSource.init(context:)))
        for slice in slices {
            for photo in Self.photos(of: slice, in: snapshot) {
                _ = provider.image(for: photo, preferThumbnail: false)
            }
            try Task.checkCancellation()
            await Task.yield()
        }

        // 3. Render each slice at exactly its size (pages never grow).
        let dir = outputDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("TravelJournalExport", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(Self.fileName(forTitle: journey.title))
        try? FileManager.default.removeItem(at: url)

        var box = CGRect(origin: .zero, size: spec.sliceSize)
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
            for (i, slice) in slices.enumerated() {
                try Task.checkCancellation()
                let view = ComposedPageView(slice: slice, snapshot: snapshot, spec: spec, mapSnap: snap)
                    .environment(\.storyImageProvider, provider)
                    .frame(width: slice.size.width, height: slice.size.height)
                let renderer = ImageRenderer(content: view)
                renderer.proposedSize = ProposedViewSize(slice.size)
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

    /// Photos a slice draws: the cover collage, or each stop block's first four (hero first).
    static func photos(of slice: ComposedSlice, in snapshot: JourneySnapshot) -> [StoryPhoto] {
        switch slice.kind {
        case .cover: return snapshot.coverModel.heroPhotos
        case .stops:
            return slice.blocks.flatMap { b -> [StoryPhoto] in
                guard case .stop(let i, _) = b.content, i < snapshot.stops.count else { return [] }
                return snapshot.stopPageModel(i).photos
            }
        case .map, .closing: return []
        }
    }
}

/// Print-time photo provider. Downsamples to 1200 px, re-encodes as JPEG and hands back an image backed by
/// the JPEG data, so Core Graphics embeds it in the PDF as DCT (JPEG) instead of a Flate-compressed bitmap
/// (which made an 8-photo PDF ~19 MB). Preloaded before rendering; `image(for:)` is a cache lookup.
/// 1200 px still prints the largest photo (the 300 pt cover polaroid) at about 290 dpi, and keeps an 8-stop PDF
/// (20 embedded photos, cover heroes repeat) under 4.4 MB.
@MainActor
final class PDFImageProvider: StoryImageProvider {
    static let maxPixel = 1200
    static let quality: CGFloat = 0.75

    /// The same image backed by JPEG data, so the PDF embeds it as DCT rather than a Flate bitmap (the route map
    /// snapshot was ~2 MB as Flate). Returns `cg` unchanged when encoding fails.
    nonisolated static func jpegBacked(_ cg: CGImage, quality: CGFloat = 0.8) -> CGImage {
        guard let data = ImageDrawing.jpegData(cg, quality: quality),
              let jsrc = CGImageSourceCreateWithData(data as CFData, nil),
              let jpeg = CGImageSourceCreateImageAtIndex(jsrc, 0, nil) else { return cg }
        return jpeg
    }

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
        return Self.jpegBacked(cg, quality: Self.quality)
    }
}
