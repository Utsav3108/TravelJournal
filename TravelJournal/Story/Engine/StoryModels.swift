import Foundation
import CoreGraphics

// Phase 3 shared page-model contract. FROZEN: agents must not edit this file.
// Plain Sendable value types: no SwiftData objects cross into page views.
// Raw-string fields use the same raw values as Models.StopCategory / Models.TransportMode / KraftCategory / KraftTransport.

nonisolated enum PageEdge: String, Hashable, Sendable { case left, right, top, bottom
    var opposite: PageEdge { switch self { case .left: .right; case .right: .left; case .top: .bottom; case .bottom: .top } }
}

/// Where the route crosses a page edge. `t` is 0...1 along that edge (left/right: from top; top/bottom: from left).
nonisolated struct RoutePoint: Hashable, Sendable { var edge: PageEdge; var t: Double }

nonisolated struct StoryPhoto: Hashable, Sendable, Identifiable {
    var id: String
    var relativePath: String      // FilePhotoStore-relative; "sample:" prefix = no file, draw placeholder
    var thumbPath: String?
    var isHero: Bool
}

nonisolated struct StoryLeg: Hashable, Sendable, Identifiable {
    var id: String
    var modeRaw: String?          // nil = no mode chosen (still renders distance/time)
    var km: Double?
    var minutes: Int?
    var story: String?
}

nonisolated enum StopTemplate: Int, Hashable, Sendable { case t0 = 0, t1, t2, t3, t4 }   // by photo count

nonisolated struct StopPageModel: Hashable, Sendable, Identifiable {
    var id: String                // "stop-<uuid>"
    var stopID: String
    var index: Int                // 0-based
    var total: Int
    var name: String
    var story: String
    var highlight: String?
    var rating: Int?              // 1...5
    var review: String?
    var categoryRaw: String
    var arrival: Date?
    var spentMinutes: Int?
    var costText: String?         // e.g. "₹180"
    var photos: [StoryPhoto]      // 0...4, hero first
    var template: StopTemplate
    var seed: UInt64              // deterministic from stop id; drives rotations, tape variants, tear variants
    var entry: RoutePoint?        // nil on first stop
    var exit: RoutePoint?         // nil on last stop
    var inLeg: StoryLeg?
    var outLeg: StoryLeg?
    var hasSeal: Bool             // at most one wax seal per page
}

nonisolated struct CoverModel: Hashable, Sendable, Identifiable {
    var id: String { "cover" }
    var title: String
    var dateText: String          // "19 OCT 2026"
    var city: String?
    var postmark: String          // "ARRIVED · 19 OCT 2026 · MUMBAI"
    var heroPhotos: [StoryPhoto]  // up to 3
    var intro: String?
    var seed: UInt64
}

nonisolated struct StatsModel: Hashable, Sendable {
    var stops: Int
    var km: Double?               // nil when no leg has km
    var totalMinutes: Int         // time at stops + travel
    var travelMinutes: Int
    var modes: [String]           // distinct transport raw values in use, route order
    var photos: Int
    var moneyText: String?        // "₹1,240" or "₹300 + $5"
}

nonisolated struct OverviewStop: Hashable, Sendable, Identifiable {
    var id: String                // stop page id
    var number: Int               // 1-based pin number
    var name: String
    var latitude: Double?
    var longitude: Double?        // nil = stop left off the map
}

nonisolated struct OverviewModel: Hashable, Sendable, Identifiable {
    var id: String { "overview" }
    var stops: [OverviewStop]
    var legs: [StoryLeg]          // legs[i] connects stops[i] -> stops[i+1]
    var stats: StatsModel
}

nonisolated struct ClosingModel: Hashable, Sendable, Identifiable {
    var id: String { "closing" }
    var stats: StatsModel
    var closingNote: String?
    var seed: UInt64
}

nonisolated enum StoryPage: Hashable, Sendable, Identifiable {
    case cover(CoverModel)
    case overview(OverviewModel)
    case stop(StopPageModel)
    case closing(ClosingModel)
    var id: String {
        switch self {
        case .cover(let m): m.id
        case .overview(let m): m.id
        case .stop(let m): m.id
        case .closing(let m): m.id
        }
    }
}

nonisolated enum RenderMode: Sendable { case interactive, print }

/// Rendering metrics shared by phone and PDF. Phone pages REFLOW (decision #1): views lay out from `size`, not a fixed canvas.
nonisolated struct PageMetrics: Hashable, Sendable {
    var size: CGSize
    var margin: CGFloat           // 24 phone, 36 PDF
    var mode: RenderMode
    static let a4 = PageMetrics(size: CGSize(width: 595, height: 842), margin: 36, mode: .print)
    static func phone(_ size: CGSize) -> PageMetrics { .init(size: size, margin: 24, mode: .interactive) }
}

/// Builds pages from a Journey. Implemented by Story/Engine (agent B1).
protocol StoryPageBuilding {
    @MainActor func pages(for journey: Journey) -> [StoryPage]
}
