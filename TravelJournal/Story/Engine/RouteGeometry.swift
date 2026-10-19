import Foundation

/// Route continuity between stop pages (component-specs section 4, v1 rule).
///
/// The route leaves page N through its RIGHT edge and enters page N+1 through its LEFT edge,
/// at the same `t` (height as a fraction of the page). `t` is a pure function of the leg key
/// (leg id, or the from-stop id when a leg row is missing) via Seed, in `tRange`, so it
/// stays clear of the page corners and never changes when other stops are edited.
/// Side alternation is deliberately NOT used in v1: the book always flows left to right
/// (spec: "exit side is always .right in v1").
///
/// Seed lives in the MainActor-default design system, so these functions are MainActor.
@MainActor
enum RouteGeometry {
    static let tRange: ClosedRange<Double> = 0.35...0.7
    static let exitEdge: PageEdge = .right

    /// Deterministic `t` for a leg key.
    static func t(forLegKey key: String) -> Double {
        var s = SeededStream(key, "exit")
        return s.range(tRange.lowerBound, tRange.upperBound)
    }

    /// Exit point on the departing page and entry point on the next page for one leg.
    static func crossing(forLegKey key: String) -> (exit: RoutePoint, entry: RoutePoint) {
        let t = t(forLegKey: key)
        let exit = RoutePoint(edge: exitEdge, t: t)
        return (exit, RoutePoint(edge: exit.edge.opposite, t: t))
    }

    /// For stops 0..<n joined by `legKeys` (n-1 keys): per-stop (entry, exit).
    /// First stop has no entry, last stop has no exit. An empty key list means one stop.
    static func stopCrossings(legKeys: [String]) -> [(entry: RoutePoint?, exit: RoutePoint?)] {
        let n = legKeys.count + 1
        return (0..<n).map { i in
            let entry = i > 0 ? crossing(forLegKey: legKeys[i - 1]).entry : nil
            let exit = i < n - 1 ? crossing(forLegKey: legKeys[i]).exit : nil
            return (entry, exit)
        }
    }
}
