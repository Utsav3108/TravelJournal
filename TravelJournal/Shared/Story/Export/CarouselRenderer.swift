import SwiftUI
import SwiftData
import CoreGraphics

nonisolated enum CarouselExportError: LocalizedError, Equatable {
    case noStops
    case allStopsHidden
    case cannotRender
    case cannotWriteFile

    var errorDescription: String? {
        switch self {
        case .noStops: "Add at least one stop before exporting an Instagram carousel."
        case .allStopsHidden: "Every stop is hidden from public exports. Show at least one stop under Export privacy."
        case .cannotRender: "A carousel slide could not be drawn."
        case .cannotWriteFile: "The carousel images could not be saved."
        }
    }
}

/// Renders a journey to numbered 1080 x 1350 px sRGB JPEGs (`01.jpg`...`NN.jpg`) for an Instagram carousel.
///
/// Pipeline: `ExportOptions.snapshot(for:)` (privacy, then `includedStopIDs`) -> `HorizontalComposer` (`.carousel`) -> map
/// snapshot + photo preload (`ImageRenderer` is synchronous, so everything async happens first) -> one
/// `SliceImageRenderer` pass per slide -> JPEG with no metadata. The layout is fixed: `estimateSlices` only counts.
@MainActor
struct CarouselRenderer: ExportRenderer {
    var snapshots: MapSnapshotService = .shared
    /// nil = a fresh folder under the temporary directory.
    var outputDirectory: URL?

    static let spec = OutputSpec.carousel
    /// Photos are downsampled to this long edge: the largest frame (the 300 pt cover polaroid) is 600 px wide at 2x.
    nonisolated static let photoMaxPixel = 800
    nonisolated static let photoQuality: CGFloat = 0.8

    func estimateSlices(_ journey: Journey, options: ExportOptions) -> Int {
        HorizontalComposer.slideCount(for: options.snapshot(for: journey), spec: Self.spec)
    }

    func render(_ journey: Journey, options: ExportOptions, progress: ((Int, Int) -> Void)?) async throws -> ExportResult {
        guard !journey.orderedStops.isEmpty else { throw CarouselExportError.noStops }
        let snapshot = options.snapshot(for: journey)
        guard !snapshot.stops.isEmpty else { throw CarouselExportError.allStopsHidden }
        let spec = Self.spec
        let doc = HorizontalComposer().compose(snapshot, spec: spec)
        let slices = doc.slices
        let offsets = HorizontalComposer.routeOffsets(doc)
        let total = slices.count
        progress?(0, total)

        // 1. Route map (never throws; falls back to the drawn map offline). Skipped when the map is hidden.
        var snap: MapSnap?
        if slices.contains(where: { $0.kind == .map }) {
            snap = await snapshots.snapshot(for: snapshot.overviewModel, size: MapSnapshotService.mapSize(for: spec.pageMetrics),
                                            scale: spec.renderScale, mapMode: snapshot.mapMode)
        }
        try Task.checkCancellation()

        // 2. Photos, decoded once (slides repeat the cover heroes).
        let provider = PDFImageProvider(source: journey.modelContext.map(ModelPhotoSource.init(context:)),
                                        maxPixel: Self.photoMaxPixel, quality: Self.photoQuality)
        try await provider.preload(slices.map { StoryPDFExporter.photos(of: $0, in: snapshot) })

        // 3. One slide at a time into a fresh folder.
        let dir = outputDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("TravelJournalExport", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var urls: [URL] = []
        do {
            for (i, slice) in slices.enumerated() {
                try Task.checkCancellation()
                let view = CarouselSliceView(slice: slice, snapshot: snapshot, spec: spec, mapSnap: snap,
                                             routeOffset: offsets[i], showsBrandStamp: options.privacy.showBrandStamp)
                    .environment(\.storyImageProvider, provider)
                guard let image = SliceImageRenderer.render(view, spec: spec),
                      let data = SliceImageRenderer.jpegData(image, quality: SliceImageRenderer.jpegQuality) else {
                    throw CarouselExportError.cannotRender
                }
                let url = dir.appendingPathComponent(Self.fileName(index: i + 1, of: total))
                do { try data.write(to: url, options: .atomic) } catch { throw CarouselExportError.cannotWriteFile }
                urls.append(url)
                progress?(i + 1, total)
                await Task.yield()
            }
        } catch {
            try? FileManager.default.removeItem(at: dir)
            throw error
        }
        if Task.isCancelled {
            try? FileManager.default.removeItem(at: dir)
            throw CancellationError()
        }
        return .images(urls)
    }

    /// "01.jpg"... (zero-padded to at least two digits, so files sort in slide order).
    nonisolated static func fileName(index: Int, of total: Int) -> String {
        let width = max(2, String(total).count)
        return String(format: "%0\(width)d.jpg", index)
    }
}
