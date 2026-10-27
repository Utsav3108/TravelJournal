import SwiftUI
import SwiftData
import CoreGraphics

/// Instagram Story frames: 1080 x 1920 px JPEGs (`01.jpg`, `02.jpg`, ...), one stop per frame.
///
/// Pipeline: `ExportOptions.snapshot(for:)` (privacy + stop selection) -> `VerticalComposer` with `OutputSpec.story`
/// (cover, one frame per stop, closing; no map frame) -> photos preloaded at 1080 px -> `SliceImageRenderer` at 3x ->
/// sRGB JPEG with no metadata, written to a fresh temporary folder. The brand stamp comes from the closing frame via
/// `\.exportBrandStamp`, kept inside the safe area.
@MainActor
struct StoryRenderer: ExportRenderer {
    let spec = OutputSpec.story
    var outputDirectory: URL?

    /// Photos are decoded no larger than the frame's pixel width.
    static let photoMaxPixel = 1080
    static let photoQuality: CGFloat = 0.85

    init(outputDirectory: URL? = nil) { self.outputDirectory = outputDirectory }

    func estimateSlices(_ journey: Journey, options: ExportOptions) -> Int {
        let snapshot = options.snapshot(for: journey)
        guard !snapshot.stops.isEmpty else { return 0 }
        return VerticalComposer().compose(snapshot, spec: spec).slices.count
    }

    func render(_ journey: Journey, options: ExportOptions, progress: ((Int, Int) -> Void)?) async throws -> ExportResult {
        guard !journey.orderedStops.isEmpty else { throw StoryPDFExportError.noStops }
        let snapshot = options.snapshot(for: journey)
        guard !snapshot.stops.isEmpty else { throw StoryPDFExportError.allStopsHidden }
        let slices = VerticalComposer().compose(snapshot, spec: spec).slices
        let total = slices.count
        progress?(0, total)

        let provider = PDFImageProvider(source: journey.modelContext.map(ModelPhotoSource.init(context:)),
                                        maxPixel: Self.photoMaxPixel, quality: Self.photoQuality)
        try await provider.preload(slices.map { StoryPDFExporter.photos(of: $0, in: snapshot) })

        let dir = (outputDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("TravelJournalExport", isDirectory: true))
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var urls: [URL] = []
        do {
            for (i, slice) in slices.enumerated() {
                try Task.checkCancellation()
                let view = ComposedPageView(slice: slice, snapshot: snapshot, spec: spec)
                    .environment(\.storyImageProvider, provider)
                    .environment(\.exportBrandStamp, options.privacy.showBrandStamp)
                guard let image = SliceImageRenderer.render(view, spec: spec),
                      let data = SliceImageRenderer.jpegData(image, quality: SliceImageRenderer.jpegQuality) else {
                    throw StoryPDFExportError.cannotCreateFile
                }
                let url = dir.appendingPathComponent(String(format: "%02d.jpg", i + 1))
                try data.write(to: url, options: .atomic)
                urls.append(url)
                progress?(i + 1, total)
                await Task.yield()
            }
            try Task.checkCancellation()
        } catch {
            try? FileManager.default.removeItem(at: dir)
            throw error
        }
        return .images(urls)
    }
}
