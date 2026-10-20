import Foundation
import CoreGraphics

// Route geometry: pure functions (page-relative points, dash trimming, bezier sampling).

nonisolated struct CubicBezier: Hashable {
    var p0: CGPoint, c1: CGPoint, c2: CGPoint, p3: CGPoint

    func point(_ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u*u*u*p0.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*p3.x,
                       y: u*u*u*p0.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*p3.y)
    }

    var reversed: CubicBezier { CubicBezier(p0: p3, c1: c2, c2: c1, p3: p0) }

    /// Points t = 0, 1/n, ... 1.
    func flattened(_ n: Int = 64) -> [CGPoint] { (0...n).map { point(CGFloat($0) / CGFloat(n)) } }
}

nonisolated enum PageRouteGeometry {
    /// Dash pattern of the route: `dash` on, `gap` off. Strokes begin at the page edge with `phase` already consumed,
    /// so each page starts with a half dash and two facing pages join into one whole dash.
    static let dash: CGFloat = 9
    static let gap: CGFloat = 7
    static var period: CGFloat { dash + gap }
    static var phase: CGFloat { dash / 2 }
    static let lineWidth: CGFloat = 3
    static let arrowOffsetFromEdge: CGFloat = 14

    /// Route point on a page edge -> page-relative point. `t` is clamped to 0...1.
    static func pagePoint(_ rp: RoutePoint, in size: CGSize) -> CGPoint {
        let t = CGFloat(min(max(rp.t, 0), 1))
        switch rp.edge {
        case .left: return CGPoint(x: 0, y: t * size.height)
        case .right: return CGPoint(x: size.width, y: t * size.height)
        case .top: return CGPoint(x: t * size.width, y: 0)
        case .bottom: return CGPoint(x: t * size.width, y: size.height)
        }
    }

    /// Unit vector pointing from the edge into the page.
    static func inward(_ edge: PageEdge) -> CGVector {
        switch edge {
        case .left: CGVector(dx: 1, dy: 0)
        case .right: CGVector(dx: -1, dy: 0)
        case .top: CGVector(dx: 0, dy: 1)
        case .bottom: CGVector(dx: 0, dy: -1)
        }
    }

    /// Largest length <= `length` at which a dash (starting with `phase` consumed) ends exactly: (dash - phase) + k * period.
    /// Lengths shorter than the first partial dash are returned unchanged.
    static func trimmedLength(_ length: CGFloat) -> CGFloat {
        let firstEnd = dash - phase
        guard length > firstEnd else { return max(length, 0) }
        let k = ((length - firstEnd) / period).rounded(.down)
        return firstEnd + k * period
    }

    /// Fraction (0...1) of a path of `length` to keep so it ends on a whole dash.
    static func trimFraction(length: CGFloat) -> CGFloat {
        guard length > 0 else { return 1 }
        return min(1, trimmedLength(length) / length)
    }

    static func polylineLength(_ pts: [CGPoint]) -> CGFloat {
        guard pts.count > 1 else { return 0 }
        var l: CGFloat = 0
        for i in 1..<pts.count { l += hypot(pts[i].x - pts[i-1].x, pts[i].y - pts[i-1].y) }
        return l
    }

    /// Point and unit direction at arc length `d` along a polyline.
    static func sample(_ pts: [CGPoint], atDistance d: CGFloat) -> (point: CGPoint, dir: CGVector)? {
        guard pts.count > 1 else { return nil }
        var remaining = max(d, 0)
        for i in 1..<pts.count {
            let a = pts[i-1], b = pts[i]
            let seg = hypot(b.x - a.x, b.y - a.y)
            if seg <= 0 { continue }
            if remaining <= seg || i == pts.count - 1 {
                let t = min(remaining / seg, 1)
                return (CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t),
                        CGVector(dx: (b.x - a.x) / seg, dy: (b.y - a.y) / seg))
            }
            remaining -= seg
        }
        return nil
    }

    static func rotate(_ p: CGPoint, around c: CGPoint, degrees: Double) -> CGPoint {
        let r = degrees * .pi / 180
        let dx = p.x - c.x, dy = p.y - c.y
        return CGPoint(x: c.x + dx * CGFloat(cos(r)) - dy * CGFloat(sin(r)),
                       y: c.y + dx * CGFloat(sin(r)) + dy * CGFloat(cos(r)))
    }
}

/// The dashed route on one page: entry stub (edge -> anchor) and exit run (edge -> anchor, drawn from the edge so
/// both neighbours start with the same half dash), plus arrowhead and badge positions.
nonisolated struct RoutePlan {
    var anchor: CGPoint
    var entryPoint: CGPoint?
    var exitPoint: CGPoint?
    var entryPoly: [CGPoint] = []     // edge -> anchor
    var exitPoly: [CGPoint] = []      // edge -> knee -> anchor
    var lastSegment: CubicBezier?     // knee -> edge (the connector run)
    var knee: CGPoint?
    var badgeCenter: CGPoint?         // on the last segment at t = 0.55
    var arrowTip: CGPoint?
    var arrowDir: CGVector?           // direction of travel at the arrow (towards the exit edge)
    var slot: CGRect?                 // connector slot rectangle

    init(anchor: CGPoint) { self.anchor = anchor }

    static func make(stopID: String, size: CGSize, anchor: CGPoint, entry: RoutePoint?, exit: RoutePoint?,
                     entryPointOverride: CGPoint? = nil, exitPointOverride: CGPoint? = nil, slotSize: CGSize) -> RoutePlan {
        var plan = RoutePlan(anchor: anchor)
        var s = PageSeed.Stream(stopID, "wobble")
        func w(_ a: Double = 18) -> CGFloat { CGFloat(s.range(-a, a)) }

        if let entry {
            let e = entryPointOverride ?? PageRouteGeometry.pagePoint(entry, in: size)
            plan.entryPoint = e
            let n = PageRouteGeometry.inward(entry.edge)
            let dist = max(hypot(anchor.x - e.x, anchor.y - e.y), 1)
            let back = CGVector(dx: (e.x - anchor.x) / dist, dy: (e.y - anchor.y) / dist)
            let reach = min(90, 0.4 * dist)
            let c1 = CGPoint(x: e.x + n.dx * reach - n.dy * w(), y: e.y + n.dy * reach + n.dx * w())
            let c2 = CGPoint(x: anchor.x + back.dx * 60 + w(8), y: anchor.y + back.dy * 60 + w(8))
            plan.entryPoly = CubicBezier(p0: e, c1: c1, c2: c2, p3: anchor).flattened()
        }

        if let exit {
            let x = exitPointOverride ?? PageRouteGeometry.pagePoint(exit, in: size)
            plan.exitPoint = x
            let n = PageRouteGeometry.inward(exit.edge)
            let run = min(slotSize.width, max(hypot(x.x - anchor.x, x.y - anchor.y) * 0.9, 40))
            let k = CGPoint(x: x.x + n.dx * run, y: x.y + n.dy * run)
            plan.knee = k
            let d = CGVector(dx: -n.dx, dy: -n.dy)       // direction of travel towards the edge
            let perp = CGVector(dx: -d.dy, dy: d.dx)
            func off(_ origin: CGPoint, _ along: CGFloat, _ across: CGFloat) -> CGPoint {
                CGPoint(x: origin.x + d.dx * along + perp.dx * across, y: origin.y + d.dy * along + perp.dy * across)
            }
            // Connector run (knee -> edge): gentle wobble inside the slot.
            let last = CubicBezier(p0: k, c1: off(k, run * 0.3, w(7)), c2: off(k, run * 0.65, w(7)), p3: x)
            plan.lastSegment = last
            // Body (anchor -> knee): leaves and arrives travelling in direction d, as in the component spec.
            let along = abs((k.x - anchor.x) * d.dx + (k.y - anchor.y) * d.dy)
            let body = CubicBezier(p0: anchor, c1: off(anchor, 70, w()), c2: off(k, -along * 0.3, w()), p3: k)
            let lastPoly = last.reversed.flattened()
            plan.exitPoly = lastPoly + Array(body.reversed.flattened().dropFirst())
            plan.badgeCenter = last.point(0.55)
            if let sm = PageRouteGeometry.sample(lastPoly, atDistance: PageRouteGeometry.arrowOffsetFromEdge) {
                plan.arrowTip = sm.point
                plan.arrowDir = CGVector(dx: -sm.dir.dx, dy: -sm.dir.dy)   // polyline runs edge -> inward; travel is the reverse
            }
            let half = slotSize.height / 2
            if d.dx != 0 {
                plan.slot = CGRect(x: min(x.x, k.x), y: x.y - half, width: abs(x.x - k.x), height: slotSize.height)
            } else {
                plan.slot = CGRect(x: x.x - half, y: min(x.y, k.y), width: slotSize.height, height: abs(x.y - k.y))
            }
        }
        return plan
    }
}
