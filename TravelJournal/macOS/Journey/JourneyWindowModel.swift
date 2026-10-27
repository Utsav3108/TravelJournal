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
    /// `StoryLeg.id` ("leg-<Leg.id>") of the leg selected for the inspector. A leg and a stop are never both selected.
    var selectedLegID: String?
    var inspectorShown = false
    /// A stop that was just added: its inspector focuses the name field.
    var justAddedStopID: String?

    /// What the inspector edits: a selected leg, else a selected stop, else the journey itself.
    enum InspectorTarget: Equatable {
        case journey
        case stop(String)
        case leg(String)
    }

    var inspectorTarget: InspectorTarget {
        if let selectedLegID { return .leg(selectedLegID) }
        if let selectedStopID { return .stop(selectedStopID) }
        return .journey
    }
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

    /// Where a new stop goes: right after the selected stop, else at the end.
    nonisolated static func insertionIndex(selectedStopID: String?, stopIDs: [String]) -> Int {
        guard let selectedStopID, let i = stopIDs.firstIndex(of: selectedStopID) else { return stopIDs.count }
        return i + 1
    }

    var selectedIndex: Int? { StripComposer.index(ofStop: selectedStopID, in: items) }

    func select(_ stopID: String?, center: Bool = true) {
        selectedStopID = stopID
        if stopID != nil { selectedLegID = nil }
        guard center, let i = StripComposer.index(ofStop: stopID, in: items) else { return }
        centerRequest = CenterRequest(pageID: items[i].id)
    }

    /// A leg connector was clicked with the inspector open: the inspector edits that leg.
    func selectLeg(_ legID: String) {
        selectedLegID = legID
        selectedStopID = nil
    }

    /// ⌘I: the inspector shows the journey itself.
    func showJourneyDetails() {
        selectedLegID = nil
        selectedStopID = nil
        inspectorShown = true
    }

    /// Everything the strip shows, as a comparable value, so the window can rebuild the strip after any edit
    /// (typing in the inspector, undo, a finished import) without the editors having to tell it.
    struct Signature: Equatable {
        struct Leg: Equatable { var id: UUID; var content: LegContent }
        struct Stop: Equatable {
            var id: UUID
            var order: Int
            var content: StopContent
            var photos: [String]
            var leg: Leg?
        }
        var journey: JourneyContent
        var stops: [Stop]
    }

    @MainActor
    static func signature(of journey: Journey) -> Signature {
        Signature(
            journey: JourneyContent(journey),
            stops: journey.orderedStops.map { s in
                .init(id: s.id, order: s.orderIndex, content: StopContent(s),
                      photos: s.orderedPhotos.map { "\($0.id)|\($0.orderIndex)|\($0.isHero)|\($0.imageData?.count ?? 0)" },
                      leg: s.outgoingLeg.map { .init(id: $0.id, content: LegContent($0)) })
            })
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
