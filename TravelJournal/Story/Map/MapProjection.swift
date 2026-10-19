import SwiftUI
import CoreGraphics

/// Output of the map pipeline. `pins` are in snapshot POINT space (`size`), one per stop that has
/// coordinates, in route order (`stopIndices` says which stop each pin belongs to).
nonisolated struct MapSnap: @unchecked Sendable {
    var image: UIImage
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

    /// Stable disk-cache key (FNV-1a over rounded coordinates, size and scale).
    static func cacheKey(_ pts: [GeoPoint], size: CGSize, scale: CGFloat) -> String {
        var s = "v1|\(Int(size.width.rounded()))x\(Int(size.height.rounded()))@\(Int(scale))"
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

/// Stats-strip text, pure.
nonisolated enum OverviewStatsFormat {
    /// "4 stops", "8.4 km", "5 h 20 min", "walk, taxi" (max 3 then +N). km omitted when nil/zero.
    static func items(_ s: StatsModel) -> [String] {
        var out = ["\(s.stops) \(s.stops == 1 ? "stop" : "stops")"]
        if let km = s.km, km > 0 { out.append(kmText(km)) }
        out.append(duration(s.totalMinutes))
        if !s.modes.isEmpty {
            let shown = s.modes.prefix(3).joined(separator: ", ")
            out.append(s.modes.count > 3 ? "\(shown) +\(s.modes.count - 3)" : shown)
        }
        return out
    }

    static func travelText(_ s: StatsModel) -> String? {
        s.travelMinutes > 0 ? "travel \(duration(s.travelMinutes))" : nil
    }

    static func kmText(_ km: Double) -> String { String(format: "%.1f km", (km * 10).rounded() / 10) }

    static func duration(_ minutes: Int) -> String {
        let m = max(0, minutes)
        let h = m / 60, r = m % 60
        if h == 0 { return "\(r) min" }
        if r == 0 { return "\(h) h" }
        return "\(h) h \(r) min"
    }
}
