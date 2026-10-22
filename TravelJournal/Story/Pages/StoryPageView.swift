import SwiftUI

/// Interaction hooks. All nil in print mode (the pager view supplies them in interactive mode).
struct StoryPageCallbacks {
    var onPhotoTap: ((StoryPhoto) -> Void)?
    var onLegTap: ((StoryLeg) -> Void)?
    var onEdit: ((String) -> Void)?
    var onPinTap: ((String) -> Void)?
    var onSavePDF: (() -> Void)?

    static let none = StoryPageCallbacks()
}

/// Dispatches a `StoryPage` to its view. Pages lay out from `metrics.size`; geometry never depends on `metrics.mode`
/// (mode only toggles interaction and the printed leg-story card).
struct StoryPageView: View {
    var page: StoryPage
    var metrics: PageMetrics
    var callbacks: StoryPageCallbacks = .none
    /// Pre-fetched map for print/PDF rendering (ImageRenderer is synchronous); nil = loader (interactive) or drawn fallback.
    var overviewSnap: MapSnap?
    /// Absolute y where the previous page's route exits (see `StopLayout.entryY`); stop pages only.
    var entryY: CGFloat?

    init(page: StoryPage, metrics: PageMetrics, callbacks: StoryPageCallbacks = .none, overviewSnap: MapSnap? = nil, entryY: CGFloat? = nil) {
        self.entryY = entryY
        self.page = page
        self.metrics = metrics
        self.callbacks = callbacks
        self.overviewSnap = overviewSnap
        KraftFonts.register()
    }

    var body: some View {
        Group {
            switch page {
            case .cover(let m): CoverPage(model: m, metrics: metrics)
            case .overview(let m):
                if metrics.mode == .interactive && overviewSnap == nil {
                    RouteOverviewPageLoader(model: m, metrics: metrics, onPinTap: callbacks.onPinTap, onLegTap: callbacks.onLegTap)
                } else {
                    RouteOverviewPage(model: m, metrics: metrics, snap: overviewSnap, isLoading: false,
                                      onPinTap: callbacks.onPinTap, onLegTap: callbacks.onLegTap)
                }
            case .stop(let m): StopPage(model: m, metrics: metrics, callbacks: callbacks, entryY: entryY)
            case .closing(let m): ClosingPage(model: m, metrics: metrics, onSavePDF: metrics.mode == .interactive ? callbacks.onSavePDF : nil)
            }
        }
        .environment(\.colorScheme, .light)
        .dynamicTypeSize(.large)
        .transaction { $0.animation = nil }
    }
}


// MARK: Shared helpers

extension View {
    /// Centre this view in `rect` (page coordinates) inside a top-leading ZStack of the page's size.
    func placed(_ rect: CGRect, alignment: Alignment = .center) -> some View {
        frame(width: rect.width, height: rect.height, alignment: alignment)
            .position(x: rect.midX, y: rect.midY)
    }
}

/// Loads a `StoryPhoto` through the environment provider (nil -> placeholder drawn by the component).
struct StoryPhotoLoader {
    var provider: StoryImageProvider
    var interactive: Bool
    /// From `@Environment(\.displayScale)`: decode size and `Image` scale both use it, so photos are neither soft nor oversized.
    var displayScale: CGFloat = 1

    /// `points` is the on-page width the photo will be drawn at; interactive pages decode only what that needs.
    /// Print mode (PDF) always asks for print resolution. `label` is what VoiceOver reads for the photo.
    func image(_ photo: StoryPhoto?, label: String = "Photo", points: CGFloat? = nil) -> Image? {
        guard let photo else { return nil }
        let maxPixel = interactive && points != nil
            ? ImageDecoding.maxPixel(forPoints: points!, scale: displayScale)
            : FileStoryImageProvider.printMaxPixel
        guard let cg = provider.image(for: photo, preferThumbnail: interactive, maxPixel: maxPixel) else { return nil }
        return Image(photo: cg, scale: displayScale, label: label.isEmpty ? "Photo" : label)
    }
}
