import MapKit
import CoreGraphics
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The one place the MapKit snapshot's platform image type is touched. `MKMapSnapshotter` hands back `UIImage` on iOS and
/// `NSImage` on macOS; everything downstream works with `CGImage` only.
enum MapKitImageEdge {
    /// Light appearance for the paper-toned map (the app is light-only).
    static func forceLight(_ options: MKMapSnapshotter.Options) {
        #if os(iOS)
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        #elseif os(macOS)
        options.appearance = NSAppearance(named: .aqua)
        #endif
    }

    /// `MKMapSnapshotter.Options.scale` exists on iOS only; on macOS the snapshot comes back at the display's backing scale,
    /// so callers derive the real scale from the pixel width (`pixelScale`).
    static func request(scale: CGFloat, on options: MKMapSnapshotter.Options) {
        #if os(iOS)
        options.scale = scale
        #endif
    }

    static func pixelScale(of image: CGImage, forPointWidth width: CGFloat) -> CGFloat {
        width > 0 ? CGFloat(image.width) / width : 1
    }

    static func cgImage(from snapshot: MKMapSnapshotter.Snapshot) -> CGImage? {
        #if os(iOS)
        return snapshot.image.cgImage
        #elseif os(macOS)
        var rect = CGRect(origin: .zero, size: snapshot.image.size)
        return snapshot.image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #endif
    }

    /// Where `snapshot.point(for:)` puts a coordinate, in top-left-origin points like the `CGImage` we draw. `UIImage` is
    /// already top-left; `NSImage` counts y up from the bottom, so on macOS the y is mirrored.
    static func point(for coordinate: CLLocationCoordinate2D, in snapshot: MKMapSnapshotter.Snapshot) -> CGPoint {
        let p = snapshot.point(for: coordinate)
        #if os(macOS)
        return topLeftOrigin(p, imageHeight: snapshot.image.size.height)
        #else
        return p
        #endif
    }

    /// Mirror a bottom-left-origin point into top-left-origin space (and back: it is its own inverse).
    static func topLeftOrigin(_ p: CGPoint, imageHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: imageHeight - p.y)
    }

    /// Cache-key suffix. Mac pins were once cached unflipped, so those entries must not be reused; iOS keys are unchanged.
    static let pinOriginTag: String = {
        #if os(macOS)
        "-y2"
        #else
        ""
        #endif
    }()
}
