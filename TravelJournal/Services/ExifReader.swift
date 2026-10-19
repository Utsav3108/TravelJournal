import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Metadata pulled out of an image file's EXIF/GPS dictionaries.
nonisolated struct ExifMetadata: Equatable, Sendable {
    var date: Date?
    var latitude: Double?
    var longitude: Double?
}

/// Pure, testable EXIF parsing. No Photos / UIKit dependency.
nonisolated enum ExifReader {
    static func read(_ data: Data) -> ExifMetadata {
        let opts: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let src = CGImageSourceCreateWithData(data as CFData, opts as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, opts as CFDictionary) as? [CFString: Any]
        else { return ExifMetadata() }
        return read(properties: props)
    }

    static func read(properties props: [CFString: Any]) -> ExifMetadata {
        var out = ExifMetadata()
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            let s = (exif[kCGImagePropertyExifDateTimeOriginal] as? String)
                ?? (exif[kCGImagePropertyExifDateTimeDigitized] as? String)
            if let s {
                // "OffsetTimeOriginal" (EXIF 2.31), e.g. "+05:30". Use the raw key name for SDK portability.
                let offset = (exif["OffsetTimeOriginal" as CFString] as? String)
                    ?? (exif["OffsetTimeDigitized" as CFString] as? String)
                out.date = parseDate(s, offset: offset)
            }
        }
        if out.date == nil, let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let s = tiff[kCGImagePropertyTIFFDateTime] as? String {
            out.date = parseDate(s, offset: nil)
        }
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           var lat = number(gps[kCGImagePropertyGPSLatitude]),
           var lon = number(gps[kCGImagePropertyGPSLongitude]) {
            // Values are unsigned magnitudes; the Ref keys carry the hemisphere.
            if (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased() == "S" { lat = -abs(lat) }
            if (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased() == "W" { lon = -abs(lon) }
            if abs(lat) <= 90, abs(lon) <= 180 {
                out.latitude = lat
                out.longitude = lon
            }
        }
        return out
    }

    /// "yyyy:MM:dd HH:mm:ss" with optional "+HH:mm" offset; falls back to the given (device) time zone.
    static func parseDate(_ s: String, offset: String?, fallback: TimeZone = .current) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.timeZone = timeZone(fromOffset: offset) ?? fallback
        return f.date(from: s.trimmingCharacters(in: .whitespaces))
    }

    static func timeZone(fromOffset offset: String?) -> TimeZone? {
        guard let offset = offset?.trimmingCharacters(in: .whitespaces), offset.count >= 5 else { return nil }
        let sign: Int
        switch offset.first {
        case "+": sign = 1
        case "-": sign = -1
        default: return nil
        }
        let parts = offset.dropFirst().split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return TimeZone(secondsFromGMT: sign * (h * 3600 + m * 60))
    }

    private static func number(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }
}

/// Builds `PhotoMeta` from raw image data plus optional PHAsset-derived values (which win over EXIF).
nonisolated enum PhotoMetaFactory {
    /// Same cap as the photo store's display size.
    static let maxPixel = PhotoLimits.displayMaxPixel

    static func make(id: String? = nil,
                     data: Data,
                     assetDate: Date? = nil,
                     assetLatitude: Double? = nil,
                     assetLongitude: Double? = nil,
                     maxPixel: Int = PhotoMetaFactory.maxPixel) -> PhotoMeta? {
        guard let jpeg = downscaledJPEG(from: data, maxPixel: maxPixel) else { return nil }
        let exif = ExifReader.read(data)
        var lat = exif.latitude, lon = exif.longitude
        if let a = assetLatitude, let b = assetLongitude { lat = a; lon = b }
        return PhotoMeta(id: id ?? UUID().uuidString,
                         date: assetDate ?? exif.date,
                         latitude: lat, longitude: lon,
                         jpegData: jpeg)
    }

    /// JPEG with orientation baked in and long edge <= maxPixel.
    static func downscaledJPEG(from data: Data, maxPixel: Int = PhotoMetaFactory.maxPixel, quality: Double = 0.85) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
