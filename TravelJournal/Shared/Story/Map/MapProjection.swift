import SwiftUI
import CoreGraphics

/// Output of the map pipeline. `pins` are in snapshot POINT space (`size`), one per stop that has
/// coordinates, in route order (`stopIndices` says which stop each pin belongs to).
nonisolated struct MapSnap: @unchecked Sendable {
    var image: CGImage
    /// Pixels per point of `image` (pass to `Image(..., scale:)`).
    var scale: CGFloat = 1
    var pins: [CGPoint]
    var size: CGSize
    var stopIndices: [Int] = []
    var isFallback: Bool = false
}

nonisolated struct GeoPoint: Hashable, Sendable {
    var lat: Double
    var lon: Double
}

/// Pure geometry helpers: region fitting, fallback layout, cache keys, hit paths.
nonisolated enum MapProjection {
    struct Region: Equatable, Sendable {
        var centerLat: Double
        var centerLon: Double
        var latSpan: Double
        var lonSpan: Double
    }

    static let minSpan = 0.01
    static let paddingFactor = 1.5
    /// `MapMode.zoomedOut` multiplies both spans by this, so a stop's exact street is not readable.
    static let zoomOutFactor = 3.0

    /// Bounding box * padding, expanded to the card aspect ratio (width/height, measured on the
    /// ground using cos(lat) so nothing is distorted), with a minimum span. Nil when empty.
    static func fitRegion(_ pts: [GeoPoint], aspect: CGFloat, padding: Double = paddingFactor, minSpan: Double = minSpan) -> Region? {
        guard !pts.isEmpty else { return nil }
        let lats = pts.map(\.lat), lons = pts.map(\.lon)
        let minLat = lats.min()!, maxLat = lats.max()!, minLon = lons.min()!, maxLon = lons.max()!
        let cLat = (minLat + maxLat) / 2, cLon = (minLon + maxLon) / 2
        let k = max(cos(cLat * .pi / 180), 0.2)
        var latSpan = max((maxLat - minLat) * padding, minSpan)
        var lonSpan = max((maxLon - minLon) * padding, minSpan)
        let a = Double(max(aspect, 0.1))
        let groundW = lonSpan * k, groundH = latSpan
        if groundW / groundH < a { lonSpan = groundH * a / k } else { latSpan = groundW / a }
        return Region(centerLat: cLat, centerLon: cLon, latSpan: min(latSpan, 170), lonSpan: min(lonSpan, 350))
    }

    /// Same centre, both spans times `factor` (aspect kept), clamped like `fitRegion`.
    static func widened(_ r: Region, by factor: Double = zoomOutFactor) -> Region {
        Region(centerLat: r.centerLat, centerLon: r.centerLon,
               latSpan: min(r.latSpan * factor, 170), lonSpan: min(r.lonSpan * factor, 350))
    }

    /// Points pulled toward the centre of `size` by `factor`: the illustrated fallback's wider region.
    static func shrinkTowardCentre(_ pts: [CGPoint], size: CGSize, by factor: Double = zoomOutFactor) -> [CGPoint] {
        let cx = size.width / 2, cy = size.height / 2, k = CGFloat(1 / max(factor, 1))
        return pts.map { CGPoint(x: cx + ($0.x - cx) * k, y: cy + ($0.y - cy) * k) }
    }

    /// Linear lat/lon -> point mapping inside `size` for the illustrated fallback. Preserves the
    /// geographic aspect (cos lat), centres the route, keeps `inset` clear on every side.
    /// A single point maps to the centre. Output order = input order.
    static func fallbackPoints(_ pts: [GeoPoint], size: CGSize, inset: CGFloat = 36) -> [CGPoint] {
        guard !pts.isEmpty else { return [] }
        let availW = max(size.width - 2 * inset, 1), availH = max(size.height - 2 * inset, 1)
        let lats = pts.map(\.lat), lons = pts.map(\.lon)
        let minLat = lats.min()!, maxLat = lats.max()!, minLon = lons.min()!, maxLon = lons.max()!
        let k = max(cos(((minLat + maxLat) / 2) * .pi / 180), 0.2)
        let w = (maxLon - minLon) * k, h = maxLat - minLat
        if w < 1e-9 && h < 1e-9 { return pts.map { _ in CGPoint(x: size.width / 2, y: size.height / 2) } }
        let scale = min(w > 1e-9 ? availW / w : .infinity, h > 1e-9 ? availH / h : .infinity)
        let usedW = w * scale, usedH = h * scale
        let ox = (size.width - usedW) / 2, oy = (size.height - usedH) / 2
        return pts.map { p in
            CGPoint(x: ox + (p.lon - minLon) * k * scale, y: oy + (maxLat - p.lat) * scale)
        }
    }

    /// Stable disk-cache key (FNV-1a over rounded coordinates, size, scale and zoom). Zoomed-out keys
    /// differ from normal ones; normal keys match earlier builds, so existing caches stay valid.
    static func cacheKey(_ pts: [GeoPoint], size: CGSize, scale: CGFloat, zoomedOut: Bool = false) -> String {
        var s = "v2|\(Int(size.width.rounded()))x\(Int(size.height.rounded()))@\(Int(scale))"
        if zoomedOut { s += "|zoom3" }
        for p in pts { s += String(format: "|%.5f,%.5f", p.lat, p.lon) }
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    /// Invisible hit area for one leg: a straight segment stroked 28pt wide, NOT dashed.
    static func hitPath(from a: CGPoint, to b: CGPoint, width: CGFloat = 28) -> Path {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        return p.strokedPath(StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    /// Consecutive pairs of LOCATED stops. `from`/`to` index into the pin array; `leg` is the index
    /// of the leg that starts at the earlier stop (nil when out of range).
    static func segments(located stopIndices: [Int], legCount: Int) -> [(from: Int, to: Int, leg: Int?)] {
        guard stopIndices.count > 1 else { return [] }
        return (0..<(stopIndices.count - 1)).map { k in
            let i = stopIndices[k]
            return (k, k + 1, i < legCount ? i : nil)
        }
    }
}

/// Stats-strip text, pure. Two fixed rows; the strip uppercases them.
nonisolated enum OverviewStatsFormat {
    /// Row 1: "4 stops", "8.4 km", "5½ hours". km omitted when nil/zero.
    static func primaryRow(_ s: StatsModel) -> [String] {
        var out = ["\(s.stops) \(s.stops == 1 ? "stop" : "stops")"]
        if let km = s.km, km > 0 { out.append(kmText(km)) }
        out.append(TravelFormat.hours(minutes: s.totalMinutes))
        return out
    }

    /// Row 2: "travel 1 hour", "taxi, auto, walk +1". Empty when there was no travel and no known mode.
    static func secondaryRow(_ s: StatsModel) -> [String] {
        var out: [String] = []
        if let t = travelText(s) { out.append(t) }
        if let modes = TravelFormat.modeList(raws: s.modes) { out.append(modes.lowercased()) }
        return out
    }

    static func travelText(_ s: StatsModel) -> String? {
        s.travelMinutes > 0 ? "travel \(TravelFormat.hours(minutes: s.travelMinutes))" : nil
    }

    static func kmText(_ km: Double) -> String { TravelFormat.km(km) }

    /// One leg's time ("1 h 5 min").
    static func duration(_ minutes: Int) -> String { TravelFormat.legDuration(minutes: minutes) }
}

/// Pin badge de-overlap. Anchors (true positions) stay on the route line; the numbered badge may be
/// pushed outward. Deterministic and order-stable: pairs are visited in index order, coincident
/// points separate along a fixed per-index angle, no randomness.
nonisolated enum PinLayout {
    static let diameter: CGFloat = 26

    static func badges(anchors: [CGPoint], bounds: CGSize, diameter: CGFloat = PinLayout.diameter, gap: CGFloat = 12, inset: CGFloat = 3) -> [CGPoint] {
        var p = anchors
        let n = p.count
        guard n > 0 else { return [] }
        let minD = diameter + gap
        let r = diameter / 2 + inset
        func clamp(_ q: CGPoint) -> CGPoint {
            CGPoint(x: min(max(q.x, r), max(bounds.width - r, r)), y: min(max(q.y, r), max(bounds.height - r, r)))
        }
        p = p.map(clamp)
        for _ in 0..<400 {
            var moved = false
            for i in 0..<n {
                for j in (i + 1)..<max(n, i + 1) {
                    var dx = p[j].x - p[i].x, dy = p[j].y - p[i].y
                    var d = (dx * dx + dy * dy).squareRoot()
                    if d >= minD { continue }
                    if d < 0.01 {
                        let a = Double(j) * 2.399963      // golden angle: fixed per index
                        dx = CGFloat(cos(a)); dy = CGFloat(sin(a)); d = 1
                    }
                    let push = (minD - d) / 2 + 0.05
                    let ux = dx / d, uy = dy / d
                    p[i] = clamp(CGPoint(x: p[i].x - ux * push, y: p[i].y - uy * push))
                    p[j] = clamp(CGPoint(x: p[j].x + ux * push, y: p[j].y + uy * push))
                    moved = true
                }
            }
            if !moved { break }
        }
        return p
    }
}

/// Leg summary rows ("taxi · 18 min · 5.2 km"), pure.
nonisolated enum OverviewLegsFormat {
    static func rows(_ model: OverviewModel) -> [(route: String, detail: String)] {
        model.legs.enumerated().compactMap { i, leg in
            guard model.stops.indices.contains(i + 1) else { return nil }
            var parts: [String] = []
            if let m = TravelFormat.modeName(raw: leg.modeRaw) { parts.append(m.lowercased()) }
            if let min = leg.minutes { parts.append(OverviewStatsFormat.duration(min)) }
            if let km = leg.km, km > 0 { parts.append(OverviewStatsFormat.kmText(km)) }
            guard !parts.isEmpty else { return nil }
            return ("\(model.stops[i].number)→\(model.stops[i + 1].number)", parts.joined(separator: " · "))
        }
    }
}
