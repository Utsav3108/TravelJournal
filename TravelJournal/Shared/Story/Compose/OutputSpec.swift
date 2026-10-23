import Foundation
import CoreGraphics

/// What a composer lays out for: the continuous canvas, which way content flows, and the size of each cut slice.
/// Units are layout points. Image specs render at `renderScale` (pixels = points x renderScale); the PDF stays vector.
///
/// | Spec        | Layout size | Scale  | Output        |
/// |-------------|-------------|--------|---------------|
/// | `.a4PDF`    | 595x842 pt  | vector | PDF           |
/// | `.carousel` | 540x675 pt  | 2x     | 1080x1350 px  |
/// | `.story`    | 360x640 pt  | 3x     | 1080x1920 px  |
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

    /// Bands at the top and bottom of each slice where the host app draws its own UI (Instagram Story header,
    /// reply bar). Nothing that must be read goes there; backgrounds and the route may.
    nonisolated struct SafeInsets: Hashable, Sendable {
        var top: CGFloat
        var bottom: CGFloat
        static let none = SafeInsets(top: 0, bottom: 0)
    }

    var canvasSize: CGSize
    var flow: Flow
    var margins: Margins
    var sliceSize: CGSize
    /// `.print` = static output (PDF, images); `.interactive` = on-screen viewer. Same enum the page views use.
    var mode: RenderMode
    /// Pixels per layout point for image output. 1 for the PDF (vector, unused).
    var renderScale: CGFloat = 1
    /// Clear bands (slice coordinates). `.none` for the PDF and carousel.
    var safeInsets: SafeInsets = .none
    /// Most slices the destination accepts (Instagram: 20 per carousel post); nil = no limit.
    var maxSlices: Int?
    /// Width of the profile-grid crop, centred on the slice (Instagram shows 4:5 posts as 3:4 in the grid);
    /// nil when there is no grid crop.
    var gridCropWidth: CGFloat?

    /// Usable rect of one slice, in slice coordinates.
    var contentRect: CGRect {
        CGRect(x: margins.left, y: margins.top,
               width: sliceSize.width - margins.left - margins.right,
               height: sliceSize.height - margins.top - margins.bottom)
    }

    /// `contentRect` further kept clear of the safe-inset bands (equal to `contentRect` when they are smaller than the margins).
    var safeContentRect: CGRect {
        let top = max(margins.top, safeInsets.top)
        let bottom = max(margins.bottom, safeInsets.bottom)
        return CGRect(x: margins.left, y: top, width: sliceSize.width - margins.left - margins.right,
                      height: sliceSize.height - top - bottom)
    }

    /// The grid crop in slice coordinates (full height, centred horizontally); nil when `gridCropWidth` is nil.
    var gridCropRect: CGRect? {
        gridCropWidth.map { CGRect(x: (sliceSize.width - $0) / 2, y: 0, width: $0, height: sliceSize.height) }
    }

    /// Output size in pixels of one slice (`sliceSize` x `renderScale`, rounded).
    var pixelSize: CGSize {
        CGSize(width: (sliceSize.width * renderScale).rounded(), height: (sliceSize.height * renderScale).rounded())
    }

    /// A4 portrait PDF (595 x 842 pt, 36 pt margins, matching `PageMetrics.a4`), pages stacked vertically.
    static let a4PDF = OutputSpec(canvasSize: CGSize(width: 595, height: CGFloat.infinity), flow: .vertical,
                                  margins: .uniform(36), sliceSize: CGSize(width: 595, height: 842), mode: .print)

    /// 9:16 Story frames: 360 x 640 pt at 3x (1080 x 1920 px), stacked vertically, one stop per frame.
    /// Clear bands start at 14% top (89.6 pt: progress bar, avatar, close) and 20% bottom (128 pt: reply bar,
    /// stickers); agent G checks these against current Instagram guidance.
    static let story = OutputSpec(canvasSize: CGSize(width: 360, height: CGFloat.infinity), flow: .vertical,
                                  margins: .uniform(20), sliceSize: CGSize(width: 360, height: 640), mode: .print,
                                  renderScale: 3, safeInsets: SafeInsets(top: 640 * 0.14, bottom: 640 * 0.20))

    /// 4:5 carousel cards: 540 x 675 pt at 2x (1080 x 1350 px), cut from one horizontal strip. At most 20 per
    /// post; the profile grid shows the centred 3:4 crop (675 x 3/4 = 506.25 pt wide).
    static let carousel = OutputSpec(canvasSize: CGSize(width: CGFloat.infinity, height: 675), flow: .horizontal,
                                     margins: .uniform(28), sliceSize: CGSize(width: 540, height: 675), mode: .print,
                                     renderScale: 2, maxSlices: 20, gridCropWidth: 675 * 3 / 4)
}
