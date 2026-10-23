import Foundation

// MARK: Contracts

/// What the user exports.
nonisolated enum ExportFormat: String, Hashable, Sendable, CaseIterable, Identifiable {
    case pdf, carousel, story

    var id: String { rawValue }

    /// Name shown in the format picker.
    var displayName: String {
        switch self {
        case .pdf: "PDF"
        case .carousel: "Instagram carousel"
        case .story: "Instagram Story"
        }
    }

    /// The layout spec this format renders with.
    var spec: OutputSpec {
        switch self {
        case .pdf: .a4PDF
        case .carousel: .carousel
        case .story: .story
        }
    }

    /// True for formats that produce numbered JPEGs (`ExportResult.images`).
    var producesImages: Bool { self != .pdf }
}

/// One export request: the format, what to reveal, and which stops to include.
nonisolated struct ExportOptions: Hashable, Sendable {
    var format: ExportFormat
    var privacy: ExportPrivacy
    /// Stops to include, by `Stop.id`; nil = every stop. Applied after privacy (a hidden stop stays hidden even
    /// when listed). Used by the over-20 stop picker.
    var includedStopIDs: Set<UUID>?

    init(format: ExportFormat, privacy: ExportPrivacy, includedStopIDs: Set<UUID>? = nil) {
        self.format = format
        self.privacy = privacy
        self.includedStopIDs = includedStopIDs
    }

    /// `snapshot` with privacy applied, then stops outside `includedStopIDs` removed (legs merged, cover and
    /// totals fixed, exactly as for a hidden stop). Pure.
    func apply(to snapshot: JourneySnapshot) -> JourneySnapshot {
        PrivacyFilter.apply(snapshot, privacy).including(stopIDs: includedStopIDs)
    }

    /// The snapshot every renderer draws from.
    @MainActor
    func snapshot(for journey: Journey) -> JourneySnapshot {
        apply(to: JourneySnapshot(journey: journey))
    }
}

/// What an export produced. Files live in a fresh temporary folder owned by the caller.
nonisolated enum ExportResult: Hashable, Sendable {
    case pdf(URL)
    /// Slides / frames in order (`01.jpg`, `02.jpg`, ...).
    case images([URL])

    var urls: [URL] {
        switch self {
        case .pdf(let url): [url]
        case .images(let urls): urls
        }
    }
}

/// Renders one format. Implementations: `PDFExportRenderer`, `CarouselRenderer` (agent F), `StoryRenderer` (agent G).
@MainActor
protocol ExportRenderer {
    /// Pages / slides / frames `render` would produce for these options. Cheap (layout only, no images).
    func estimateSlices(_ journey: Journey, options: ExportOptions) -> Int
    /// `progress` gets (done, total); (0, total) fires first. Throws `CancellationError` when the task is cancelled,
    /// leaving no files behind.
    func render(_ journey: Journey, options: ExportOptions, progress: ((Int, Int) -> Void)?) async throws -> ExportResult
}

nonisolated enum ExportPipelineError: LocalizedError, Equatable {
    case notBuiltYet(ExportFormat)

    var errorDescription: String? {
        switch self {
        case .notBuiltYet(let f): "\(f.displayName) export isn't available yet."
        }
    }
}

// MARK: Stop selection

nonisolated extension JourneySnapshot {
    /// This snapshot keeping only the stops in `stopIDs` (nil = all). Removed stops' legs merge with
    /// `PrivacyFilter.mergedLeg`; the cover falls back like a hidden stop's; totals are recomputed.
    func including(stopIDs: Set<UUID>?) -> JourneySnapshot {
        guard let stopIDs else { return self }
        return PrivacyFilter.removingStops(self, where: stops.map { !stopIDs.contains($0.id) })
    }
}

// MARK: Pipeline

/// Picks the renderer for `options.format`. Inject renderers in tests (or to swap in the real carousel / Story
/// renderers at integration).
@MainActor
final class ExportPipeline {
    private let renderers: [ExportFormat: any ExportRenderer]

    /// `renderers` overrides the defaults per format; formats left out use `defaultRenderers()`.
    init(renderers: [ExportFormat: any ExportRenderer] = [:]) {
        self.renderers = Self.defaultRenderers().merging(renderers) { _, injected in injected }
    }

    /// PDF is real; carousel and Story are stubs until agents F and G land.
    static func defaultRenderers() -> [ExportFormat: any ExportRenderer] {
        [.pdf: PDFExportRenderer(),
         .carousel: UnbuiltExportRenderer(format: .carousel),
         .story: UnbuiltExportRenderer(format: .story)]
    }

    func renderer(for format: ExportFormat) -> any ExportRenderer {
        renderers[format] ?? UnbuiltExportRenderer(format: format)
    }

    func estimateSlices(_ journey: Journey, options: ExportOptions) -> Int {
        renderer(for: options.format).estimateSlices(journey, options: options)
    }

    func render(_ journey: Journey, options: ExportOptions,
                progress: ((Int, Int) -> Void)? = nil) async throws -> ExportResult {
        try await renderer(for: options.format).render(journey, options: options, progress: progress)
    }
}

// MARK: Renderers

/// The A4 PDF through `StoryPDFExporter`, honouring `options.privacy` and `options.includedStopIDs`.
@MainActor
struct PDFExportRenderer: ExportRenderer {
    var snapshots: MapSnapshotService = .shared
    var outputDirectory: URL?

    private func exporter() -> StoryPDFExporter {
        StoryPDFExporter(snapshots: snapshots, outputDirectory: outputDirectory)
    }

    func estimateSlices(_ journey: Journey, options: ExportOptions) -> Int {
        exporter().document(for: journey, privacy: options.privacy, includedStopIDs: options.includedStopIDs)
            .document.slices.count
    }

    func render(_ journey: Journey, options: ExportOptions, progress: ((Int, Int) -> Void)?) async throws -> ExportResult {
        let e = exporter()
        e.progress = progress
        return .pdf(try await e.export(journey, privacy: options.privacy, includedStopIDs: options.includedStopIDs))
    }
}

/// Placeholder for a format whose renderer isn't built yet: estimates 0 and throws `notBuiltYet`.
@MainActor
struct UnbuiltExportRenderer: ExportRenderer {
    let format: ExportFormat

    func estimateSlices(_ journey: Journey, options: ExportOptions) -> Int { 0 }

    func render(_ journey: Journey, options: ExportOptions, progress: ((Int, Int) -> Void)?) async throws -> ExportResult {
        throw ExportPipelineError.notBuiltYet(format)
    }
}
