import SwiftUI
import UIKit

/// Paper "illustrated" map used when the snapshot fails, we are offline, or no stop has coordinates.
/// Hand-drawn style contour lines; the dashed route is drawn by the page overlay, not here.
enum IllustratedMapFallback {
    static func render(size: CGSize, seed: String, scale: CGFloat = 2) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = scale
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: size, format: fmt).image { r in
            let c = r.cgContext
            UIColor(red: 0xE9 / 255, green: 0xDD / 255, blue: 0xC6 / 255, alpha: 1).setFill()
            c.fill(CGRect(origin: .zero, size: size))
            var s = SeededStream(seed, "contours")
            let ink = UIColor(red: 0x8B / 255, green: 0x6B / 255, blue: 0x4A / 255, alpha: 1)
            c.setLineJoin(.round); c.setLineCap(.round)
            // Faint graph-paper grid.
            c.setStrokeColor(ink.withAlphaComponent(0.10).cgColor); c.setLineWidth(0.5)
            var x: CGFloat = 0
            while x < size.width { c.move(to: CGPoint(x: x, y: 0)); c.addLine(to: CGPoint(x: x, y: size.height)); x += 28 }
            var y: CGFloat = 0
            while y < size.height { c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: size.width, y: y)); y += 28 }
            c.strokePath()
            // Concentric wobbly contour rings around a few seeded hill centres.
            for _ in 0..<3 {
                let cx = CGFloat(s.range(0.1, 0.9)) * size.width, cy = CGFloat(s.range(0.1, 0.9)) * size.height
                let base = CGFloat(s.range(24, 46)), rings = 4 + s.int(3)
                let phase = s.range(0, 6.28), p2 = s.range(0, 6.28)
                var rad = base
                for k in 0..<rings {
                    rad += CGFloat(s.range(14, 20))
                    c.setStrokeColor(ink.withAlphaComponent(k % 3 == 0 ? 0.42 : 0.26).cgColor)
                    c.setLineWidth(k % 3 == 0 ? 1.1 : 0.7)
                    let steps = 72
                    for i in 0...steps {
                        let t = Double(i) / Double(steps) * 2 * .pi
                        let w = 1 + 0.16 * sin(3 * t + phase + Double(k) * 0.5) + 0.08 * sin(5 * t + p2)
                        let pt = CGPoint(x: cx + CGFloat(cos(t) * w) * rad * 1.35, y: cy + CGFloat(sin(t) * w) * rad)
                        if i == 0 { c.move(to: pt) } else { c.addLine(to: pt) }
                    }
                    c.strokePath()
                }
            }
            // A wavy river.
            c.setStrokeColor(UIColor(red: 0x3E / 255, green: 0x6B / 255, blue: 0x6A / 255, alpha: 0.28).cgColor)
            c.setLineWidth(5)
            let ry = CGFloat(s.range(0.25, 0.75)) * size.height
            let amp = CGFloat(s.range(10, 22)), ph = s.range(0, 6)
            var xx: CGFloat = -4
            c.move(to: CGPoint(x: xx, y: ry))
            while xx < size.width + 4 {
                xx += 6
                c.addLine(to: CGPoint(x: xx, y: ry + amp * CGFloat(sin(Double(xx) / 46 + ph))))
            }
            c.strokePath()
        }
    }
}

/// View wrapper for the fallback on its own.
struct IllustratedMapFallbackView: View {
    var size: CGSize
    var seed: String = "fallback"
    var body: some View {
        Image(uiImage: IllustratedMapFallback.render(size: size, seed: seed))
            .resizable()
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(true)
    }
}
