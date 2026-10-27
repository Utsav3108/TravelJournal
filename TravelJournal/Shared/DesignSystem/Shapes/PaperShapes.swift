import SwiftUI

/// Rectangle whose chosen edges are jagged like torn paper. Seeded, so identical on screen and PDF.
/// variant 0 = bottom torn, 1 = top and bottom torn, 2 = all four edges.
struct TornEdgeShape: Shape {
    var variant: Int = 0
    var seed: String = "torn"

    func path(in rect: CGRect) -> Path {
        var s = SeededStream(seed, "torn\(variant)")
        let v = max(0, min(2, variant))
        let topTorn = v >= 1, bottomTorn = true, sideTorn = v == 2
        let amp: CGFloat = 2.6
        let sideAmp: CGFloat = 1.5

        func edge(from a: CGPoint, to b: CGPoint, inward: CGPoint, torn: Bool, amplitude: CGFloat, stream: inout SeededStream) -> [CGPoint] {
            guard torn else { return [b] }
            let length = hypot(b.x - a.x, b.y - a.y)
            var pts: [CGPoint] = []
            var d: CGFloat = 0
            while true {
                d += CGFloat(stream.range(5, 9))
                if d >= length - 4 { break }
                let t = d / length
                let jitter = CGFloat(stream.unit()) * amplitude
                pts.append(CGPoint(x: a.x + (b.x - a.x) * t + inward.x * jitter,
                                   y: a.y + (b.y - a.y) * t + inward.y * jitter))
            }
            pts.append(b)
            return pts
        }

        let inset = amp
        let l = rect.minX + (sideTorn ? sideAmp : 0), r = rect.maxX - (sideTorn ? sideAmp : 0)
        let t = rect.minY + (topTorn ? inset : 0), b = rect.maxY - (bottomTorn ? inset : 0)
        var p = Path()
        let tl = CGPoint(x: l, y: t), tr = CGPoint(x: r, y: t), br = CGPoint(x: r, y: b), bl = CGPoint(x: l, y: b)
        p.move(to: tl)
        var all: [CGPoint] = []
        all += edge(from: tl, to: tr, inward: CGPoint(x: 0, y: 1), torn: topTorn, amplitude: amp, stream: &s).map { $0 }
        // right edge: jitter inward (negative x) -> pass inward as (-1,0) but side jitter is small
        all += edge(from: tr, to: br, inward: CGPoint(x: -1, y: 0), torn: sideTorn, amplitude: sideAmp, stream: &s)
        all += edge(from: br, to: bl, inward: CGPoint(x: 0, y: -1), torn: bottomTorn, amplitude: amp, stream: &s)
        all += edge(from: bl, to: tl, inward: CGPoint(x: 1, y: 0), torn: sideTorn, amplitude: sideAmp, stream: &s)
        // bottom jitter should extend outward into the inset band: shift torn bottom/top points outward by amp
        for pt in all { p.addLine(to: pt) }
        p.closeSubpath()
        return p
    }
}

/// Washi tape strip with serrated short ends.
struct WashiShape: Shape {
    var teeth: Int = 3
    var depth: CGFloat = 2

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let step = rect.height / CGFloat(teeth * 2)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        for i in 0..<(teeth * 2) {
            let y = rect.minY + step * CGFloat(i + 1)
            p.addLine(to: CGPoint(x: rect.maxX - (i % 2 == 0 ? depth : 0), y: y))
        }
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        for i in 0..<(teeth * 2) {
            let y = rect.maxY - step * CGFloat(i + 1)
            p.addLine(to: CGPoint(x: rect.minX + (i % 2 == 0 ? depth : 0), y: y))
        }
        p.closeSubpath()
        return p
    }
}

/// Highlighter band with slightly ragged left and right ends.
struct MarkerBandShape: Shape {
    var seed: String = "band"

    func path(in rect: CGRect) -> Path {
        var s = SeededStream(seed, "band")
        var p = Path()
        let n = 5
        let j: () -> CGFloat = { CGFloat(s.range(0, 3.5)) }
        p.move(to: CGPoint(x: rect.minX + j(), y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - j(), y: rect.minY + 1))
        for i in 1..<n {
            p.addLine(to: CGPoint(x: rect.maxX - j(), y: rect.minY + rect.height * CGFloat(i) / CGFloat(n)))
        }
        p.addLine(to: CGPoint(x: rect.maxX - j(), y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + j(), y: rect.maxY - 1))
        for i in (1..<n).reversed() {
            p.addLine(to: CGPoint(x: rect.minX + j(), y: rect.minY + rect.height * CGFloat(i) / CGFloat(n)))
        }
        p.closeSubpath()
        return p
    }
}

/// Ticket outline: rounded corners plus semicircular notches top and bottom at the perforation line.
struct TicketShape: Shape {
    var perforationX: CGFloat = 64
    var notchRadius: CGFloat = 7
    var corner: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = corner, nr = notchRadius, px = rect.minX + perforationX
        p.move(to: CGPoint(x: rect.minX + c, y: rect.minY))
        p.addLine(to: CGPoint(x: px - nr, y: rect.minY))
        for i in 0...12 {
            let th = Double.pi * (1 - Double(i) / 12)
            p.addLine(to: CGPoint(x: px + nr * CGFloat(cos(th)), y: rect.minY + nr * CGFloat(sin(th))))
        }
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + c), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - c, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: px + nr, y: rect.maxY))
        for i in 0...12 {
            let th = Double.pi * Double(i) / 12
            p.addLine(to: CGPoint(x: px + nr * CGFloat(cos(th)), y: rect.maxY - nr * CGFloat(sin(th))))
        }
        p.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - c), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + c))
        p.addQuadCurve(to: CGPoint(x: rect.minX + c, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// Irregular wax blob.
struct SealShape: Shape {
    var seed: String = "seal"
    var lobes: Int = 14

    func path(in rect: CGRect) -> Path {
        var s = SeededStream(seed, "seal")
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let base = min(rect.width, rect.height) / 2 - 2
        var pts: [CGPoint] = []
        let n = lobes * 2
        for i in 0..<n {
            let a = 2 * Double.pi * Double(i) / Double(n)
            let rr = base + (i % 2 == 0 ? 1.5 : -1.5) + CGFloat(s.range(-2, 2))
            pts.append(CGPoint(x: c.x + rr * CGFloat(cos(a)), y: c.y + rr * CGFloat(sin(a))))
        }
        var p = Path()
        guard let first = pts.first, let last = pts.last else { return p }
        p.move(to: CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2))
        for i in 0..<n {
            let cur = pts[i], nxt = pts[(i + 1) % n]
            p.addQuadCurve(to: CGPoint(x: (cur.x + nxt.x) / 2, y: (cur.y + nxt.y) / 2), control: cur)
        }
        p.closeSubpath()
        return p
    }
}

struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let ro = min(rect.width, rect.height) / 2, ri = ro * 0.42
        for i in 0..<10 {
            let a = -Double.pi / 2 + Double.pi * Double(i) / 5
            let r = i % 2 == 0 ? ro : ri
            let pt = CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// Paperclip outline (stroke only), drawn in a 14x30 box.
struct PaperClipShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 14, sy = rect.height / 30
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var p = Path()
        p.move(to: pt(7, 11))
        p.addLine(to: pt(7, 23))
        p.addCurve(to: pt(1, 23), control1: pt(7, 30), control2: pt(1, 30))
        p.addLine(to: pt(1, 7))
        p.addCurve(to: pt(13, 7), control1: pt(1, -2), control2: pt(13, -2))
        p.addLine(to: pt(13, 23))
        p.addCurve(to: pt(9, 26), control1: pt(13, 28), control2: pt(11, 27))
        return p
    }
}

/// Small hand-drawn arrow (curve with arrowhead) pointing right/up.
struct HandArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let a = CGPoint(x: rect.minX, y: rect.maxY)
        let b = CGPoint(x: rect.maxX - 2, y: rect.minY + 3)
        p.move(to: a)
        p.addQuadCurve(to: b, control: CGPoint(x: rect.midX, y: rect.maxY + 2))
        p.move(to: CGPoint(x: b.x - 9, y: b.y - 2))
        p.addLine(to: b)
        p.addLine(to: CGPoint(x: b.x - 4, y: b.y + 8))
        return p
    }
}
