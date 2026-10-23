import SwiftUI
import XCTest
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers
@testable import TravelJournal

/// Platform-neutral image helpers for tests (no UIKit): render a view to a `CGImage`, write PNGs, count ink pixels,
/// and build JPEG fixtures with a chosen EXIF orientation and colour space.
enum TestImages {
    @MainActor
    static func render<V: View>(_ view: V, proposed: ProposedViewSize? = nil, scale: CGFloat = 1) -> CGImage? {
        let r = ImageRenderer(content: view)
        if let proposed { r.proposedSize = proposed }
        r.scale = scale
        return r.cgImage
    }

    static func writePNG(_ image: CGImage?, to url: URL) {
        guard let image, let data = ImageDrawing.pngData(image) else { return }
        try? data.write(to: url)
    }

    /// Pixels whose alpha is above `threshold` (0...255), read through an RGBA bitmap.
    static func opaquePixelCount(_ cg: CGImage, threshold: UInt8 = 40) -> Int {
        let w = cg.width, h = cg.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: ImageDrawing.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var n = 0
        for i in stride(from: 0, to: buf.count, by: 4) where buf[i + 3] > threshold { n += 1 }
        return n
    }

    /// RGBA of one pixel (top-left origin), read through an sRGB bitmap.
    static func pixel(_ cg: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var px = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: ImageDrawing.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return (0, 0, 0, 0) }
        ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
        return (px[0], px[1], px[2], px[3])
    }

    /// Flat-colour JPEG of `size` pixels with the given EXIF orientation (1 = upright, 6 = rotated 90° clockwise) and colour space.
    /// The top half is red and the bottom half blue, so a rotation is visible in the pixels.
    static func jpeg(size: CGSize, orientation: Int = 1, colorSpace: CGColorSpace = ImageDrawing.sRGB) -> Data {
        let w = Int(size.width), h = Int(size.height)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [1, 0, 0, 1])!)     // CG origin is bottom-left: this is the BOTTOM half...
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h / 2))
        ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [0, 0, 1, 1])!)     // ...and this the TOP half.
        ctx.fill(CGRect(x: 0, y: h / 2, width: w, height: h - h / 2))
        let image = ctx.makeImage()!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.95,
                                                 kCGImagePropertyOrientation: orientation] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    /// Renders one PDF page (media box) into a bitmap.
    static func image(of page: PDFPage, size: CGSize) -> CGImage? {
        guard let ref = page.pageRef else { return nil }
        return ImageDrawing.render(size: size, opaque: true) { ctx in
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: size))
            // PDF pages are bottom-left origin; the helper context is top-left, so flip back.
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
            let box = ref.getBoxRect(.mediaBox)
            ctx.scaleBy(x: size.width / box.width, y: size.height / box.height)
            ctx.translateBy(x: -box.minX, y: -box.minY)
            ctx.drawPDFPage(ref)
        }
    }
}

// MARK: Snapshot references

/// Compares `image` with `TravelJournalTests/__Snapshots__/<name>-<platform>.png` (platform = ios / macos, since text
/// renders differently). Passes when at most `tolerance` (0...1) of the pixels differ by more than `pixelThreshold`
/// on any RGBA channel. Records the reference instead (and fails, so a fresh recording is never a silent pass) when
/// it is missing or when `RECORD_SNAPSHOTS=1` is set; from xcodebuild use `TEST_RUNNER_RECORD_SNAPSHOTS=1`.
/// On a mismatch the actual image is written to the temporary directory and its path is in the failure message.
func assertSnapshot(_ image: CGImage, named name: String, tolerance: Double = 0.001, pixelThreshold: UInt8 = 16,
                    file: StaticString = #filePath, line: UInt = #line) {
    let url = Snapshots.referenceURL(named: name)
    let record = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
    guard !record, let reference = Snapshots.load(url) else {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let data = ImageDrawing.pngData(image) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url)
            XCTFail("Snapshot \"\(name)\" recorded at \(url.path). Check it by eye, then re-run.", file: file, line: line)
        } catch {
            XCTFail("Snapshot \"\(name)\" could not be recorded at \(url.path): \(error)", file: file, line: line)
        }
        return
    }
    guard reference.width == image.width, reference.height == image.height else {
        let actual = Snapshots.writeFailure(image, named: name)
        XCTFail("Snapshot \"\(name)\" size \(image.width)x\(image.height) != reference \(reference.width)x\(reference.height). "
                + "Actual: \(actual.path)", file: file, line: line)
        return
    }
    let a = Snapshots.rgba(image), b = Snapshots.rgba(reference)
    var differing = 0
    for i in stride(from: 0, to: a.count, by: 4) {
        for k in 0..<4 where (a[i + k] > b[i + k] ? a[i + k] - b[i + k] : b[i + k] - a[i + k]) > pixelThreshold {
            differing += 1
            break
        }
    }
    let fraction = Double(differing) / Double(max(image.width * image.height, 1))
    if fraction > tolerance {
        let actual = Snapshots.writeFailure(image, named: name)
        XCTFail(String(format: "Snapshot \"%@\": %.3f%% of pixels differ (allowed %.3f%%). Actual: %@",
                       name, fraction * 100, tolerance * 100, actual.path), file: file, line: line)
    }
}

enum Snapshots {
    /// `TravelJournalTests/__Snapshots__`, found from this source file's path.
    static let directory = URL(fileURLWithPath: "\(#filePath)").deletingLastPathComponent()
        .appendingPathComponent("__Snapshots__", isDirectory: true)

    static var platform: String {
        #if os(macOS)
        "macos"
        #else
        "ios"
        #endif
    }

    static func referenceURL(named name: String) -> URL {
        directory.appendingPathComponent("\(name)-\(platform).png")
    }

    static func load(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    static func writeFailure(_ image: CGImage, named name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-\(name)-\(platform)-actual.png")
        TestImages.writePNG(image, to: url)
        return url
    }

    /// Premultiplied RGBA bytes in sRGB, row 0 at the top.
    static func rgba(_ cg: CGImage) -> [UInt8] {
        let w = cg.width, h = cg.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        if let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                               space: ImageDrawing.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return buf
    }
}
