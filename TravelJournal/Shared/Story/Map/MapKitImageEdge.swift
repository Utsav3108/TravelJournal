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
}
