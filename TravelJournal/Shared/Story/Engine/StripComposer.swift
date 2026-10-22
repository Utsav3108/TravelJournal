import Foundation
import CoreGraphics

/// Lays the story pages out as one horizontal strip for wide windows: cover, stop 1, stop 2 ... closing. The overview
/// page is left out (the journey window's sidebar map replaces it). Pages keep the phone components and sit edge to edge,
/// so the route (which always leaves a page on its right and enters the next on its left at the same height) reads as
/// one continuous line. Pure functions: sizes, scroll offsets, zoom and stop-to-stop stepping are unit-tested.
nonisolated enum StripComposer {
    struct Item: Hashable, Sendable, Identifiable {
        var page: StoryPage
        var id: String { page.id }
        /// `StopPageModel.stopID` (the `Stop.id` string) for stop pages, nil for the cover and closing card.
        var stopID: String? {
            if case .stop(let m) = page { return m.stopID }
            return nil
        }
    }

    /// Page width / page height.
    static let pageAspect: CGFloat = 0.62
    static let zoomRange: ClosedRange<CGFloat> = 0.3...1.5
    static let defaultZoom: CGFloat = 1
    static let zoomStep: CGFloat = 1.25

    /// Strip order: everything except the overview page.
    static func items(from pages: [StoryPage]) -> [Item] {
        pages.compactMap { page in
            if case .overview = page { return nil }
            return Item(page: page)
        }
    }

    static func overview(from pages: [StoryPage]) -> OverviewModel? {
        for case .overview(let m) in pages { return m }
        return nil
    }

    /// `OverviewStop.id` is "stop-<uuid>"; the strip and the sidebar share the bare `Stop.id` string.
    static func stopID(ofPageID id: String) -> String {
        id.hasPrefix("stop-") ? String(id.dropFirst("stop-".count)) : id
    }

    // MARK: Sizing

    /// One page at `zoom` (1 = the page is as tall as the viewport).
    static func pageSize(viewportHeight: CGFloat, zoom: CGFloat) -> CGSize {
        let h = max(viewportHeight * clamped(zoom), 1)
        return CGSize(width: h * pageAspect, height: h)
    }

    static func contentWidth(count: Int, pageWidth: CGFloat) -> CGFloat { CGFloat(max(count, 0)) * pageWidth }

    static func clamped(_ zoom: CGFloat) -> CGFloat { min(max(zoom, zoomRange.lowerBound), zoomRange.upperBound) }
    static func zoomedIn(_ zoom: CGFloat) -> CGFloat { clamped(zoom * zoomStep) }
    static func zoomedOut(_ zoom: CGFloat) -> CGFloat { clamped(zoom / zoomStep) }

    /// The zoom at which all `count` pages fit the viewport width (never above actual size).
    static func fitZoom(viewport: CGSize, count: Int) -> CGFloat {
        guard count > 0, viewport.width > 0, viewport.height > 0 else { return defaultZoom }
        let fit = viewport.width / (CGFloat(count) * pageAspect * viewport.height)
        return clamped(min(fit, defaultZoom))
    }

    // MARK: Scrolling

    /// Horizontal offset that centres page `index` in the viewport, kept inside the scrollable range.
    static func centeredOffset(index: Int, pageWidth: CGFloat, viewportWidth: CGFloat, count: Int) -> CGFloat {
        let target = CGFloat(index) * pageWidth + pageWidth / 2 - viewportWidth / 2
        let maxOffset = max(0, contentWidth(count: count, pageWidth: pageWidth) - viewportWidth)
        return min(max(target, 0), maxOffset)
    }

    // MARK: Stops

    static func index(ofStop stopID: String?, in items: [Item]) -> Int? {
        guard let stopID else { return nil }
        return items.firstIndex { $0.stopID == stopID }
    }

    /// The stop page one step from `current` (an index into `items`, nil = nothing selected). From nothing, forward goes
    /// to the first stop and backward to the last. Returns nil when there is no stop in that direction.
    static func neighbourStop(from current: Int?, direction: Int, in items: [Item]) -> Int? {
        let stops = items.indices.filter { items[$0].stopID != nil }
        guard !stops.isEmpty, direction != 0 else { return nil }
        guard let current else { return direction > 0 ? stops.first : stops.last }
        return direction > 0 ? stops.first { $0 > current } : stops.last { $0 < current }
    }
}
