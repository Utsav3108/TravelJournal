import Foundation
import CoreGraphics

/// What a composer lays out for: the continuous canvas, which way content flows, and the size of each cut slice.
/// Units are points; pixel specs (story, carousel) render at scale 1, so 1 pt = 1 px.
///
/// The composer places everything in ONE canvas coordinate space (origin top-left), then cuts it into `sliceSize`
/// pieces along `flow`. The flow-axis length of `canvasSize` is `.infinity` when content may run across many slices.
nonisolated struct OutputSpec: Hashable, Sendable {
    /// Direction the canvas grows and is cut: vertical = pages top to bottom, horizontal = cards left to right.
    nonisolated enum Flow: Hashable, Sendable { case vertical, horizontal }

    /// Inset from each slice edge; content blocks stay inside, the route may cross it.
    nonisolated struct Margins: Hashable, Sendable {
        var top: CGFloat
        var left: CGFloat
        var bottom: CGFloat
        var right: CGFloat
        static func uniform(_ v: CGFloat) -> Margins { Margins(top: v, left: v, bottom: v, right: v) }
    }

    var canvasSize: CGSize
    var flow: Flow
    var margins: Margins
    var sliceSize: CGSize
    /// `.print` = static output (PDF, images); `.interactive` = on-screen viewer. Same enum the page views use.
    var mode: RenderMode

    /// Usable rect of one slice, in slice coordinates.
    var contentRect: CGRect {
        CGRect(x: margins.left, y: margins.top,
               width: sliceSize.width - margins.left - margins.right,
               height: sliceSize.height - margins.top - margins.bottom)
    }

    /// A4 portrait PDF (595 x 842 pt, 36 pt margins, matching `PageMetrics.a4`), pages stacked vertically.
    static let a4PDF = OutputSpec(canvasSize: CGSize(width: 595, height: CGFloat.infinity), flow: .vertical,
                                  margins: .uniform(36), sliceSize: CGSize(width: 595, height: 842), mode: .print)

    /// Stub for Phase 3: 9:16 story frames (1080 x 1920 px), stacked vertically.
    static let story = OutputSpec(canvasSize: CGSize(width: 1080, height: CGFloat.infinity), flow: .vertical,
                                  margins: .uniform(64), sliceSize: CGSize(width: 1080, height: 1920), mode: .print)

    /// Stub for Phase 4: 4:5 carousel cards (1080 x 1350 px) cut from one horizontal strip.
    static let carousel = OutputSpec(canvasSize: CGSize(width: CGFloat.infinity, height: 1350), flow: .horizontal,
                                     margins: .uniform(64), sliceSize: CGSize(width: 1080, height: 1350), mode: .print)
}
