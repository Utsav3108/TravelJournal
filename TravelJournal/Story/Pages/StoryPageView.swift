import SwiftUI
import UIKit

/// Interaction hooks. All nil in print mode (the pager view supplies them in interactive mode).
struct StoryPageCallbacks {
    var onPhotoTap: ((StoryPhoto) -> Void)?
    var onLegTap: ((StoryLeg) -> Void)?
    var onEdit: ((String) -> Void)?

    static let none = StoryPageCallbacks()
}

/// Dispatches a `StoryPage` to its view. Pages lay out from `metrics.size`; geometry never depends on `metrics.mode`
/// (mode only toggles interaction and the printed leg-story card).
struct StoryPageView: View {
    var page: StoryPage
    var metrics: PageMetrics
    var callbacks: StoryPageCallbacks = .none

    init(page: StoryPage, metrics: PageMetrics, callbacks: StoryPageCallbacks = .none) {
        self.page = page
        self.metrics = metrics
        self.callbacks = callbacks
        KraftFonts.register()
    }

    var body: some View {
        Group {
            switch page {
            case .cover(let m): CoverPage(model: m, metrics: metrics)
            case .overview(let m): OverviewPagePlaceholder(model: m, metrics: metrics)
            case .stop(let m): StopPage(model: m, metrics: metrics, callbacks: callbacks)
            case .closing(let m): ClosingPage(model: m, metrics: metrics)
            }
        }
        .environment(\.colorScheme, .light)
        .dynamicTypeSize(.large)
        .transaction { $0.animation = nil }
    }
}

/// TEMPORARY placeholder for the route overview page. Agent B3 (Story/Map) replaces this with `RouteOverviewPage`
/// at merge time; the dispatcher above is the only call site.
struct OverviewPagePlaceholder: View {
    var model: OverviewModel
    var metrics: PageMetrics

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 10) {
                Text("PLACEHOLDER").stampLabel().foregroundStyle(KraftColor.route)
                Text("Route overview").font(KraftFont.title(30)).foregroundStyle(KraftColor.ink)
                Text("\(model.stops.count) stops · replaced by RouteOverviewPage")
                    .stampLabel().foregroundStyle(KraftColor.inkSoft)
            }
            .padding(24)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(KraftColor.route, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        }
        .frame(width: metrics.size.width, height: metrics.size.height)
        .clipped()
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

    func image(_ photo: StoryPhoto?) -> Image? {
        guard let photo, let ui = provider.image(for: photo, preferThumbnail: interactive) else { return nil }
        return Image(uiImage: ui)
    }
}
