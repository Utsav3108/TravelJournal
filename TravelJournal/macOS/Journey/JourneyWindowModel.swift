#if os(macOS)
import SwiftUI

/// State shared by the journey window's sidebar and story strip: the strip items, which stop is selected or hovered,
/// the zoom, and requests to centre a page. Selecting a stop anywhere (sidebar row, map pin, strip page, arrow keys)
/// goes through `select`, which is what keeps the two sides linked.
@MainActor
@Observable
final class JourneyWindowModel {
    struct CenterRequest: Equatable {
        var pageID: String
        var token = UUID()
    }

    private(set) var items: [StripComposer.Item] = []
    private(set) var overview: OverviewModel?
    /// `Stop.id` string of the selected / hovered stop.
    var selectedStopID: String?
    var hoveredStopID: String?
    var zoom: CGFloat = StripComposer.defaultZoom
    /// Size of the strip's viewport, for "fit".
    var viewport: CGSize = .zero
    var centerRequest: CenterRequest?

    func rebuild(from journey: Journey) {
        let pages = StoryLayout().pages(for: journey)
        items = StripComposer.items(from: pages)
        overview = StripComposer.overview(from: pages)
        if StripComposer.index(ofStop: selectedStopID, in: items) == nil { selectedStopID = nil }
        if StripComposer.index(ofStop: hoveredStopID, in: items) == nil { hoveredStopID = nil }
    }

    var selectedIndex: Int? { StripComposer.index(ofStop: selectedStopID, in: items) }

    func select(_ stopID: String?, center: Bool = true) {
        selectedStopID = stopID
        guard center, let i = StripComposer.index(ofStop: stopID, in: items) else { return }
        centerRequest = CenterRequest(pageID: items[i].id)
    }

    /// ← / → and the Journey menu: previous or next stop, centred.
    func step(_ direction: Int) {
        guard let i = StripComposer.neighbourStop(from: selectedIndex, direction: direction, in: items) else { return }
        select(items[i].stopID)
    }

    func zoomIn() { zoom = StripComposer.zoomedIn(zoom) }
    func zoomOut() { zoom = StripComposer.zoomedOut(zoom) }
    func fit() { zoom = StripComposer.fitZoom(viewport: viewport, count: items.count) }

    func hover(_ stopID: String, isInside: Bool) {
        if isInside { hoveredStopID = stopID } else if hoveredStopID == stopID { hoveredStopID = nil }
    }
}
#endif
