import SwiftUI

/// Pure formatting helpers (unit-testable). Wording comes from `TravelFormat`.
enum KraftFormat {
    /// "auto · 20 min · 6 km", "taxi · 1 h 5 min · 5.2 km"; missing parts are omitted. Lower case:
    /// print callers uppercase it.
    static func legLabel(mode: KraftTransport?, minutes: Int?, km: Double?) -> String {
        var parts: [String] = []
        if let mode, let name = TravelFormat.modeName(raw: mode.rawValue) { parts.append(name.lowercased()) }
        if let minutes { parts.append(TravelFormat.legDuration(minutes: minutes)) }
        if let km { parts.append(TravelFormat.km(km)) }
        return parts.joined(separator: " · ")
    }

    /// One leg's time: 65 -> "1 h 5 min", 45 -> "45 min".
    static func duration(minutes: Int) -> String { TravelFormat.legDuration(minutes: minutes) }

    /// "4 stops", "8.4 km", "5½ hours", "taxi, auto".
    static func statsLine(stops: Int, km: Double, minutes: Int, modes: [KraftTransport]) -> [String] {
        var items = ["\(stops) \(stops == 1 ? "stop" : "stops")",
                     TravelFormat.km(km),
                     TravelFormat.hours(minutes: minutes)]
        if let list = TravelFormat.modeList(raws: modes.map(\.rawValue)) { items.append(list.lowercased()) }
        return items
    }
}

// MARK: LegConnector

/// Dashed wobbly route running left-to-right across the frame, with arrowhead and a mode badge.
struct LegConnector: View {
    var mode: KraftTransport? = .taxi
    var minutes: Int? = 18
    var km: Double? = 5.2
    var size: CGSize = CGSize(width: 280, height: 100)
    var seed: String = "leg"

    private struct Geo {
        var p0: CGPoint, c1: CGPoint, c2: CGPoint, p3: CGPoint
        func point(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            return CGPoint(x: u*u*u*p0.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*p3.x,
                           y: u*u*u*p0.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*p3.y)
        }
    }

    private var geo: Geo {
        var s = SeededStream(seed, "wobble")
        let midY = size.height / 2
        let w = size.width
        return Geo(p0: CGPoint(x: 0, y: midY),
                   c1: CGPoint(x: w * 0.3, y: midY + CGFloat(s.range(-18, 18))),
                   c2: CGPoint(x: w * 0.65, y: midY + CGFloat(s.range(-18, 18))),
                   p3: CGPoint(x: w - 14, y: midY + CGFloat(s.range(-8, 8))))
    }

    var body: some View {
        let g = geo
        let badge = g.point(0.55)
        let label = KraftFormat.legLabel(mode: mode, minutes: minutes, km: km)
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: g.p0)
                p.addCurve(to: g.p3, control1: g.c1, control2: g.c2)
            }
            .stroke(KraftColor.route, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [9, 7]))

            arrowhead(g).fill(KraftColor.route)

            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(KraftColor.polaroidWhite)
                    Circle().stroke(KraftColor.route, lineWidth: 1.5)
                    if let mode { TransportIcon(mode: mode, size: 22) }
                }
                .frame(width: 36, height: 36)
                if !label.isEmpty {
                    Text(label).stampLabel().foregroundStyle(KraftColor.ink).fixedSize()
                }
            }
            .position(x: badge.x + (label.isEmpty ? 0 : 40), y: badge.y - 24)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.isEmpty ? "Leg" : "Leg: \(label)")
    }

    private func arrowhead(_ g: Geo) -> Path {
        let dx = g.p3.x - g.c2.x, dy = g.p3.y - g.c2.y
        let len = max(hypot(dx, dy), 0.001)
        let ux = dx / len, uy = dy / len
        let tip = CGPoint(x: g.p3.x + ux * 12, y: g.p3.y + uy * 12)
        let nx = -uy, ny = ux
        var p = Path()
        p.move(to: tip)
        p.addLine(to: CGPoint(x: g.p3.x + nx * 7, y: g.p3.y + ny * 7))
        p.addLine(to: CGPoint(x: g.p3.x - nx * 7, y: g.p3.y - ny * 7))
        p.closeSubpath()
        return p
    }
}

// MARK: StatsStrip

/// Typewriter stats row: "4 stops · 8.4 km · 5 h 20 min · walk, taxi".
struct StatsStrip: View {
    var stops: Int
    var km: Double
    var minutes: Int
    var modes: [KraftTransport] = []

    var body: some View {
        let items = KraftFormat.statsLine(stops: stops, km: km, minutes: minutes, modes: modes)
        ViewThatFits(in: .horizontal) {
            Text(items.joined(separator: " · ")).lineLimit(1).fixedSize()
                .frame(maxWidth: .infinity, minHeight: 36)
            Text(items.joined(separator: " · ")).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .stampLabel()
        .foregroundStyle(KraftColor.ink)
        .padding(.horizontal, 12)
        .background(KraftColor.paperDeep)
        .overlay(alignment: .top) { dashedLine }
        .overlay(alignment: .bottom) { dashedLine }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(items.joined(separator: ", "))
    }

    private var dashedLine: some View {
        Rectangle().stroke(KraftColor.kraftDark, style: StrokeStyle(lineWidth: 1, dash: [4, 3])).frame(height: 1)
    }
}

#Preview("Route components") {
    ZStack {
        PaperBackground()
        VStack(spacing: 24) {
            LegConnector()
            LegConnector(mode: .autoRickshaw, minutes: nil, km: 1.2, seed: "b")
            StatsStrip(stops: 4, km: 8.4, minutes: 320, modes: [.walk, .taxi])
        }
        .padding(24)
    }
}
