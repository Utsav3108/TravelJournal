import Foundation
import CoreGraphics

/// Lays out a (privacy-filtered) journey for one output spec. Pure: same snapshot + spec gives the same document.
/// The composer owns ALL route geometry; blocks only draw themselves and report where the route attaches.
nonisolated protocol Composer {
    func compose(_ snapshot: JourneySnapshot, spec: OutputSpec) -> ComposedDocument
}

/// The composed output: slices in reading order (cover, map, stop pages..., closing).
nonisolated struct ComposedDocument: Hashable, Sendable {
    var slices: [ComposedSlice]
}

/// One cut piece of the canvas (an A4 page, a story frame, a carousel card). All geometry is in slice coordinates:
/// origin top-left, points, `0...size`.
nonisolated struct ComposedSlice: Hashable, Sendable, Identifiable {
    nonisolated enum Kind: String, Hashable, Sendable { case cover, map, stops, closing }

    var id: String { "\(kind.rawValue)-\(index)" }
    var index: Int                    // position in `ComposedDocument.slices`
    var kind: Kind
    var size: CGSize
    var blocks: [PlacedBlock]
    /// Route polyline pieces drawn on this slice, in order. Consecutive points are joined by straight lines.
    var route: [RouteSegment]
    /// Where the route enters this slice (on its leading edge); nil when the route starts on this slice or is absent.
    var routeEntry: CGPoint?
    /// Where the route leaves this slice (on its trailing edge); nil when the route ends here or is absent.
    /// Slice N's `routeExit` and slice N+1's `routeEntry` come from the same canvas cut point.
    var routeExit: CGPoint?
    var connectors: [LegConnectorPlacement]
}

/// A block placed on a slice. A block never splits across slices.
nonisolated struct PlacedBlock: Hashable, Sendable, Identifiable {
    nonisolated enum Content: Hashable, Sendable {
        case cover
        case routeMap
        /// Stop at `JourneySnapshot.stops[stopIndex]`. `photoBandScale` < 1 shrinks the photo band to fit a page.
        case stop(stopIndex: Int, photoBandScale: CGFloat)
        case closing
        /// "The End" stamp where the route finishes.
        case endMarker
    }

    var id: String                    // stable, e.g. "stop-<uuid>", "cover", "end"
    var content: Content
    var frame: CGRect
    /// Point where the route attaches to this block (stop blocks); nil for blocks the route doesn't touch.
    var routeAnchor: CGPoint?
}

/// One continuous run of the route on a slice.
nonisolated struct RouteSegment: Hashable, Sendable {
    var points: [CGPoint]
    /// The leg this run belongs to (`JourneySnapshot.legs[legIndex]`); nil for lead-in / lead-out runs (e.g. to the end marker).
    var legIndex: Int?
}

/// Where a leg's connector badge, label ("Auto · 20 min · 6 km") and leg story sit on a slice.
nonisolated struct LegConnectorPlacement: Hashable, Sendable {
    var legIndex: Int                 // `JourneySnapshot.legs[legIndex]`
    var center: CGPoint               // badge centre, on the route
    var labelFrame: CGRect?           // nil = no label drawn
    var storyFrame: CGRect?           // nil = no leg story drawn
}
