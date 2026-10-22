import Testing
import SwiftUI
import SwiftData
import CoreGraphics
import ImageIO
@testable import TravelJournal

/// Phase 0 (UIKit -> SwiftUI) regression tests. One group per pitfall of moving from `UIImage` to `CGImage`:
/// rotation, scale, accessibility, cache size, colour. Plus text-measurement goldens and a UIKit/AppKit audit.
@MainActor
struct ImageDecodingTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("imgdec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Photos"), withIntermediateDirectories: true)
        return dir
    }

    // MARK: 1. Rotation

    /// EXIF orientation 6 (rotate 90° clockwise to display): a 200x100 file must come out 100x200, and the pixels must really
    /// be rotated, not just relabelled. The fixture is blue on top and red at the bottom in file space, so after a clockwise
    /// turn the left edge is red and the right edge is blue.
    @Test func exifOrientationIsBakedIntoPixels() throws {
        let data = TestImages.jpeg(size: CGSize(width: 200, height: 100), orientation: 6)
        let cg = try #require(ImageDecoding.cgImage(from: data, maxPixel: 1000))
        #expect(cg.width == 100 && cg.height == 200, "portrait after rotation")
        let left = TestImages.pixel(cg, x: 10, y: 100), right = TestImages.pixel(cg, x: 90, y: 100)
        #expect(left.r > 200 && left.b < 60, "left edge red")
        #expect(right.b > 200 && right.r < 60, "right edge blue")
    }

    @Test func uprightFileIsUntouched() throws {
        let cg = try #require(ImageDecoding.cgImage(from: TestImages.jpeg(size: CGSize(width: 200, height: 100)), maxPixel: 1000))
        #expect(cg.width == 200 && cg.height == 100)
        #expect(TestImages.pixel(cg, x: 100, y: 10).b > 200, "top is blue")
        #expect(TestImages.pixel(cg, x: 100, y: 90).r > 200, "bottom is red")
    }

    /// A rotated JPEG stored on a `StopPhoto` still comes out upright through the shared loader.
    @Test @MainActor func storedPhotoLoadsUprightFromTheModel() throws {
        let container = AppContainer.make(inMemory: true)   // keep the container alive as long as its context is used
        let photo = StopPhoto()
        photo.imageData = TestImages.jpeg(size: CGSize(width: 300, height: 150), orientation: 6)
        container.mainContext.insert(photo)
        let cg = try #require(StoredPhotos.image(photo: photo, maxPixel: 600))
        #expect(cg.height > cg.width)
        #expect(StoredPhotos.image(photo: StopPhoto(), maxPixel: 600) == nil, "no image data draws a placeholder")
        withExtendedLifetime(container) {}
    }

    // MARK: 2. Scale

    @Test func decodeSizeIsPointsTimesScale() {
        #expect(ImageDecoding.maxPixel(forPoints: 100, scale: 1) == 100)
        #expect(ImageDecoding.maxPixel(forPoints: 100, scale: 2) == 200)
        #expect(ImageDecoding.maxPixel(forPoints: 100, scale: 3) == 300)
        #expect(ImageDecoding.maxPixel(forPoints: 33.4, scale: 3) == 101, "rounds up so the image is never short of pixels")
        #expect(ImageDecoding.maxPixel(forPoints: 0, scale: 0) == 1, "never zero")
    }

    @Test func decodeNeverUpsizes() throws {
        let cg = try #require(ImageDecoding.cgImage(from: TestImages.jpeg(size: CGSize(width: 100, height: 60)), maxPixel: 800))
        #expect(cg.width == 100 && cg.height == 60)
    }

    /// Decoding at points x scale and passing the same scale to `Image` lays out at the requested point size on 1x, 2x and 3x.
    @Test func imageLaysOutAtRequestedPointSize() throws {
        let data = TestImages.jpeg(size: CGSize(width: 1200, height: 1200))
        for scale in [1.0, 2.0, 3.0] as [CGFloat] {
            let cg = try #require(ImageDecoding.cgImage(from: data, maxPixel: ImageDecoding.maxPixel(forPoints: 100, scale: scale)))
            #expect(cg.width == Int(100 * scale), "pixels at \(scale)x")
            // At renderer scale 1 the output has one pixel per point, so its width is the layout width in points.
            let rendered = try #require(TestImages.render(Image(photo: cg, scale: scale, label: "x"), scale: 1))
            #expect(abs(rendered.width - 100) <= 1, "layout width at \(scale)x was \(rendered.width)")
        }
    }

    // MARK: 3. Accessibility (decorative images are an allow-list)

    /// `Image(decorative:)` / `Image(texture:)` hide an image from VoiceOver. Only paper, tape, maps and book covers that sit inside
    /// an already-labelled card may use them; photos use `Image(photo:scale:label:)`.
    @Test func decorativeImagesAreOnTheAllowList() throws {
        let allowedTexture: Set<String> = [
            "Shared/DesignSystem/Components/PaperBackground.swift",   // paper grain
            "Shared/Story/Map/IllustratedMapFallback.swift",          // map illustration (pins and rows carry the information)
            "Shared/Story/Map/RouteOverviewPage.swift",
            "iOS/App/JourneyShelfView.swift",                      // book covers: the card is one labelled element (.ignore + label)
            "iOS/App/Shelf/FloatingShelvesShelf.swift",
            "iOS/App/Shelf/CoverRackShelf.swift",
            "iOS/App/Shelf/DeskStackShelf.swift",
            "iOS/App/Library/CoverRackBook.swift",
            "macOS/Journey/JourneySidebar.swift",                  // sidebar route map: the pins and stop rows carry the information
            "Shared/Services/ImageDecoding.swift",
        ]
        let allowedDecorative: Set<String> = ["Shared/Services/ImageDecoding.swift"]
        var offenders: [String] = []
        for (path, lines) in try Self.sourceLines() {
            for line in lines {
                if line.contains("Image(texture:"), !allowedTexture.contains(path) { offenders.append("\(path): \(line)") }
                if line.contains("Image(decorative:"), !allowedDecorative.contains(path) { offenders.append("\(path): \(line)") }
            }
        }
        #expect(offenders.isEmpty, "unlabelled images outside the allow-list: \(offenders)")
    }

    /// The photo surfaces that are standalone (not inside a labelled card) must stay labelled.
    @Test func standalonePhotoSurfacesAreLabelled() throws {
        let sources = Dictionary(uniqueKeysWithValues: try Self.sourceLines())
        for file in ["iOS/Story/StoryViewerView.swift", "Shared/Story/Pages/StoryPageView.swift",
                     "iOS/Features/Editor/StopEditorView.swift", "iOS/Features/Capture/AddPhotosFlowView.swift"] {
            #expect(sources[file]?.contains { $0.contains("Image(photo:") } == true, "\(file) should use a labelled Image(photo:)")
        }
    }

    // MARK: 4. Cache cost

    @Test func cacheCostIsWidthTimesHeightTimesFour() throws {
        let cg = try #require(ImageDrawing.render(size: CGSize(width: 50, height: 20)))
        #expect(ImageDecoding.cost(of: cg) == 50 * 20 * 4)
    }

    @Test func cacheEvictsPastItsCostLimit() throws {
        let cache = DecodedImageCache(costLimit: 400_000)                                       // room for 2 images of 160 KB
        var images: [CGImage] = []
        for i in 0..<200 {
            let image = try #require(ImageDrawing.render(size: CGSize(width: 200, height: 200)) { c in
                c.setFillColor(ImageDrawing.color(white: Double(i) / 200)); c.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            })
            images.append(image)   // keep them alive so only the cache's own policy can drop them
            cache.insert(image, forKey: "k\(i)")
        }
        let kept = (0..<200).filter { cache.image(forKey: "k\($0)") != nil }.count
        #expect(kept < 200, "nothing was evicted: the cost limit is not doing its job")
        #expect(kept <= 20, "kept \(kept) images of 160 KB under a 400 KB limit")
        #expect(DecodedImageCache.defaultCostLimit >= 48 << 20 && DecodedImageCache.defaultCostLimit <= 128 << 20)
    }

    // MARK: 5. Colour

    private func isDisplayP3(_ cg: CGImage) -> Bool {
        guard let space = cg.colorSpace else { return false }
        if (space.name as String?) == (CGColorSpace.displayP3 as String) { return true }
        // Embedded ICC profiles are not always matched to the named space; fall back to the profile's own description.
        let desc = space.copyICCData().flatMap { CGColorSpace(iccData: $0 as CFData)?.name as String? } ?? ""
        return desc.contains("P3")
    }

    @Test func displayP3SurvivesDecoding() throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let data = TestImages.jpeg(size: CGSize(width: 64, height: 64), colorSpace: p3)
        let cg = try #require(ImageDecoding.cgImage(from: data, maxPixel: 64))
        #expect(isDisplayP3(cg), "decoded colour space was \(String(describing: cg.colorSpace?.name))")
    }

    @Test @MainActor func displayP3SurvivesThePDFReencode() throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let container = AppContainer.make(inMemory: true)   // keep the container alive as long as its context is used
        defer { withExtendedLifetime(container) {} }
        let stored = StopPhoto()
        stored.imageData = TestImages.jpeg(size: CGSize(width: 400, height: 300), colorSpace: p3)
        container.mainContext.insert(stored)
        let provider = PDFImageProvider(source: ModelPhotoSource(context: container.mainContext))
        let photo = StoryPhoto(id: stored.id.uuidString, isHero: true)
        let cg = try #require(provider.image(for: photo, preferThumbnail: false))
        #expect(isDisplayP3(cg), "PDF re-encode converted the colour space to \(String(describing: cg.colorSpace?.name))")
    }

    // MARK: Paper grain follows the display scale

    @Test func paperGrainIsCrispAtEveryScale() {
        for scale in [1, 2, 3] as [CGFloat] {
            let tile = PaperGrain.tile(scale: scale)
            #expect(tile.width == Int(128 * scale) && tile.height == Int(128 * scale), "pixels at \(scale)x")
            #expect(CGFloat(tile.width) / scale == CGFloat(PaperGrain.points), "always 128 points")
            #expect((tile.colorSpace?.name as String?) == (CGColorSpace.sRGB as String), "authored in sRGB on purpose")
        }
        #expect(PaperGrain.tile(scale: 2) === PaperGrain.tile(scale: 2), "cached")
        #expect(PaperGrain.tile(scale: 9).width == 128 * 4, "clamped at 4x")
    }

    // MARK: Text measurement goldens (CoreText replaced UIFont/NSAttributedString; values come from the UIKit implementation)

    @Test func textMeasurementMatchesTheUIKitImplementation() {
        KraftFonts.register()
        let long = "We reached CST at dawn and the whole city smelled of chai and diesel. Then a taxi to Sardar Pav Bhaji, where the butter was unreasonable and the line was worth it. Siddhivinayak at dusk: marigolds everywhere."
        let paragraphs = "First paragraph here.\nSecond one after a break that is a bit longer to wrap around.\n\nThird after blank."
        func h(_ t: String, _ f: String, _ s: CGFloat, _ ls: CGFloat, _ w: CGFloat) -> CGFloat { PageText.height(t, fontName: f, size: s, lineSpacing: ls, width: w) }
        #expect(h(long, KraftFontName.lora, 16, 3.5, 340) == 117)
        #expect(h(long, KraftFontName.lora, 16, 3.5, 250) == 165)
        #expect(h(long, KraftFontName.lora, 16, 3.5, 520) == 93)
        #expect(h(long, KraftFontName.caveat, 18, 0, 250) == 137)
        #expect(h(paragraphs, KraftFontName.lora, 16, 3.5, 250) == 117)
        #expect(h("Ends with newline\n", KraftFontName.lora, 16, 3.5, 250) == 45)
        #expect(h("A short line of text", KraftFontName.lora, 16, 3.5, 100) == 45)
        #if os(macOS)
        let systemFallbackHeight: CGFloat = 40   // the macOS system font has tighter line metrics than iOS
        #else
        let systemFallbackHeight: CGFloat = 41
        #endif
        #expect(h("A short line of text", "NoSuchFont", 16, 2, 100) == systemFallbackHeight, "unknown font falls back to the system font")
        #expect(h("", KraftFontName.lora, 16, 3.5, 250) == 0)
        #expect(PageText.width("ARRIVED", fontName: KraftFontName.elite, size: 11, tracking: 1.5) == 57)
        #expect(PageText.width("A Day in Mumbai", fontName: "Allura-Regular", size: 44) == 311)
        #expect(PageText.width("Sardar Pav Bhaji", fontName: KraftFontName.caveat, size: 18) == 106)
    }

    // MARK: Drawing helpers

    @Test func drawingHelperUsesTopLeftOriginAndScale() throws {
        let cg = try #require(ImageDrawing.render(size: CGSize(width: 10, height: 10), scale: 2, opaque: true) { c in
            c.setFillColor(ImageDrawing.color(red: 1, green: 0, blue: 0))
            c.fill(CGRect(x: 0, y: 0, width: 10, height: 5))   // top half in UIKit-style coordinates
            c.setFillColor(ImageDrawing.color(red: 0, green: 0, blue: 1))
            c.fill(CGRect(x: 0, y: 5, width: 10, height: 5))
        })
        #expect(cg.width == 20 && cg.height == 20)
        #expect(TestImages.pixel(cg, x: 10, y: 3).r > 240, "top is red")
        #expect(TestImages.pixel(cg, x: 10, y: 16).b > 240, "bottom is blue")
    }

    @Test func hsbMatchesKnownColours() {
        let red = ImageDrawing.hsbToRGB(hue: 0, saturation: 1, brightness: 1)
        let green = ImageDrawing.hsbToRGB(hue: 1.0 / 3, saturation: 1, brightness: 1)
        let grey = ImageDrawing.hsbToRGB(hue: 0.5, saturation: 0, brightness: 0.5)
        #expect(red.r == 1 && red.g == 0 && red.b == 0)
        #expect(abs(green.g - 1) < 1e-9 && green.r < 1e-9)
        #expect(grey.r == 0.5 && grey.g == 0.5 && grey.b == 0.5)
    }

    // MARK: UIKit / AppKit stays at the edges

    /// Source audit for the Phase 0 policy: SwiftUI by default; UIKit/AppKit only in the camera wrapper, the MapKit image edge and the macOS Quit button.
    @Test func uiKitAndAppKitAreOnlyUsedAtTheEdges() throws {
        let allowed: Set<String> = ["iOS/Features/Capture/CameraCaptureView.swift", "Shared/Story/Map/MapKitImageEdge.swift",
                                    "Shared/App/StoreFailureView.swift", // macOS Quit button: SwiftUI has no way to terminate the app
                                    "macOS/Journey/WheelScrollBridge.swift",   // mouse wheel to horizontal scroll: no SwiftUI equivalent
                                    "macOS/Journey/TextInputFocus.swift",      // is a text field being edited: no SwiftUI equivalent
                                    "macOS/Export/PrintBridge.swift"]          // the system print dialog: SwiftUI has no print API
        let banned = ["import UIKit", "import AppKit", "UIImage", "UIColor", "UIFont", "UIGraphics", "UIApplication", "UIViewController",
                      "UIActivity", "UIScreen", "UIWindow", "NSImage", "NSColor", "NSFont", "Image(uiImage:", "Image(nsImage:"]
        var offenders: [String] = []
        for (path, lines) in try Self.sourceLines() where !allowed.contains(path) {
            for line in lines {
                for token in banned where line.range(of: "(?<![A-Za-z])" + NSRegularExpression.escapedPattern(for: token), options: .regularExpression) != nil {
                    offenders.append("\(path): \(line)")
                }
            }
        }
        #expect(offenders.isEmpty, "UIKit/AppKit outside the allowed edge files: \(offenders)")
    }

    // MARK: Helpers

    /// (path relative to TravelJournal/, code lines without comments) for every Swift source file in the app.
    private static func sourceLines() throws -> [(String, [String])] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TravelJournal", isDirectory: true)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var out: [(String, [String])] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let code = text.components(separatedBy: "\n").map { line -> String in
                if let r = line.range(of: "//") { return String(line[..<r.lowerBound]) }
                return line
            }
            out.append((String(url.path.dropFirst(root.path.count + 1)), code))
        }
        return out
    }
}
