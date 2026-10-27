import XCTest
import CoreGraphics
import ImageIO
@testable import TravelJournal

// MARK: Image metadata

/// EXIF keys ImageIO writes into every JPEG it encodes, whatever properties are passed. They describe the bitmap,
/// not the photo, camera, place or person.
let structuralExifKeys: Set<CFString> = [kCGImagePropertyExifColorSpace, kCGImagePropertyExifPixelXDimension,
                                         kCGImagePropertyExifPixelYDimension]

/// Fails when `data` (an exported JPEG/PNG) carries identifying metadata: any GPS, Exif-aux, IPTC or maker
/// dictionary, any EXIF field beyond the structural ones ImageIO writes into every JPEG (`structuralExifKeys`:
/// colour space and pixel size), or a TIFF Make / Model / Software / DateTime / Artist.
/// Read through `CGImageSourceCopyPropertiesAtIndex` (plus XMP tags).
func assertNoImageMetadata(_ data: Data, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
        XCTFail("Not a readable image. \(message)", file: file, line: line)
        return
    }
    if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
        let extra = Set(exif.keys).subtracting(structuralExifKeys)
        if !extra.isEmpty {
            XCTFail("Image has EXIF fields \(extra.map { $0 as String }.sorted()). \(message)", file: file, line: line)
        }
    }
    let forbidden: [CFString] = [kCGImagePropertyGPSDictionary, kCGImagePropertyExifAuxDictionary, kCGImagePropertyIPTCDictionary,
                                 kCGImagePropertyMakerAppleDictionary]
    for key in forbidden where props[key] != nil {
        XCTFail("Image has \(key) metadata: \(props[key]!). \(message)", file: file, line: line)
    }
    if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
        for key in [kCGImagePropertyTIFFMake, kCGImagePropertyTIFFModel, kCGImagePropertyTIFFSoftware,
                    kCGImagePropertyTIFFDateTime, kCGImagePropertyTIFFArtist] where tiff[key] != nil {
            XCTFail("Image has TIFF \(key): \(tiff[key]!). \(message)", file: file, line: line)
        }
    }
    // XMP can carry the same fields (location, creator, dates).
    if let meta = CGImageSourceCopyMetadataAtIndex(src, 0, nil),
       let tags = CGImageMetadataCopyTags(meta) as? [CGImageMetadataTag] {
        let names = tags.compactMap { CGImageMetadataTagCopyName($0) as String? }
        let identifying = names.filter { n in ["GPS", "Make", "Model", "Creator", "Artist", "DateTime", "Location"]
            .contains { n.localizedCaseInsensitiveContains($0) } }
        if !identifying.isEmpty {
            XCTFail("Image has XMP tags \(identifying). \(message)", file: file, line: line)
        }
    }
}

// MARK: Slice edges

/// Checks on a composed document, for any spec and either flow axis.
enum SliceChecks {
    /// Every block frame, leg label and leg story that crosses its slice's edges along `axis`, described for a
    /// failure message. `allowed` narrows the band content must stay in (e.g. the Story's safe content rect along y);
    /// default is the whole slice. Full-slice blocks (cover, map, closing) pass the default band.
    static func edgeCrossings(_ doc: ComposedDocument, axis: OutputSpec.Flow,
                              allowed: ((ComposedSlice) -> ClosedRange<CGFloat>)? = nil,
                              tolerance: CGFloat = 0.5) -> [String] {
        var out: [String] = []
        for slice in doc.slices {
            let length = axis == .vertical ? slice.size.height : slice.size.width
            let band = allowed?(slice) ?? 0...length
            func check(_ r: CGRect, _ what: String) {
                let lo = axis == .vertical ? r.minY : r.minX, hi = axis == .vertical ? r.maxY : r.maxX
                if lo < band.lowerBound - tolerance || hi > band.upperBound + tolerance {
                    out.append("\(slice.id): \(what) spans \(lo)...\(hi), outside \(band)")
                }
            }
            for b in slice.blocks { check(b.frame, b.id) }
            for c in slice.connectors {
                if let r = c.labelFrame { check(r, "leg \(c.legIndex) label") }
                if let r = c.storyFrame { check(r, "leg \(c.legIndex) story") }
            }
        }
        return out
    }

    /// Splits a document's slices by kind, for checks that only apply to stop slices.
    static func stopSlices(_ doc: ComposedDocument) -> [ComposedSlice] { doc.slices.filter { $0.kind == .stops } }
}

/// Fails with one line per crossing found by `SliceChecks.edgeCrossings`.
func assertNoSliceEdgeCrossings(_ doc: ComposedDocument, axis: OutputSpec.Flow,
                                allowed: ((ComposedSlice) -> ClosedRange<CGFloat>)? = nil,
                                _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    for crossing in SliceChecks.edgeCrossings(doc, axis: axis, allowed: allowed) {
        XCTFail("\(crossing). \(message)", file: file, line: line)
    }
}
