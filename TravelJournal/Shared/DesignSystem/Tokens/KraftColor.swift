import SwiftUI

extension Color {
    /// sRGB colour from a 0xRRGGBB literal.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// The ten Vintage Kraft spec tokens plus a few derived values.
enum KraftColor {
    static let paper      = Color(hex: 0xF3EBDD)
    static let paperDeep  = Color(hex: 0xE6D9C3)
    static let kraft      = Color(hex: 0xC9A97E)
    static let kraftDark  = Color(hex: 0x8B6B4A)
    static let ink        = Color(hex: 0x2B2420)
    static let inkSoft    = Color(hex: 0x5E5249)
    static let route      = Color(hex: 0x9E3B2F)
    static let sealRose   = Color(hex: 0xB5838D)
    static let stampTeal  = Color(hex: 0x3E6B6A)
    static let highlight  = Color(hex: 0xF2D06B, opacity: 0.70)

    // Derived (not in spec).
    static let polaroidWhite = Color(hex: 0xFBF7EE)
    static let shadow        = Color(hex: 0x2B2420, opacity: 0.18)
    static let paperEdge     = Color(hex: 0x8B6B4A, opacity: 0.35)
}
