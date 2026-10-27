import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers

enum PhotoStoreError: Error, Equatable {
    case limitReached
    case undecodable
}

/// Photos live in the model (`StopPhoto.imageData`), so removing a photo, stop or journey removes its bytes with the
/// row (the stop/journey delete rules cascade). There are no files to clean up.
protocol PhotoStoring {
    /// Re-encode `data` (orientation baked in, long edge <= `PhotoLimits.displayMaxPixel`, colour profile kept) and
    /// append it to `stop`.
    @discardableResult
    func importPhoto(data: Data, into stop: Stop) throws -> StopPhoto
    /// Remove one photo, promoting a new hero if needed.
    func removePhoto(_ photo: StopPhoto, from stop: Stop)
}

enum PhotoLimits {
    static let maxPerStop = 4
    static let displayMaxPixel = 2048
}

/// Does nothing; for sample data and previews.
struct NoopPhotoStore: PhotoStoring {
    func importPhoto(data: Data, into stop: Stop) throws -> StopPhoto { throw PhotoStoreError.undecodable }
    func removePhoto(_ photo: StopPhoto, from stop: Stop) { PhotoRules.detach(photo, from: stop) }
}

enum PhotoRules {
    /// Detach from stop, delete the row, renumber, promote first remaining photo if hero was removed.
    static func detach(_ photo: StopPhoto, from stop: Stop) {
        let wasHero = photo.isHero
        stop.photos.removeAll { $0 === photo }
        photo.modelContext?.delete(photo)
        let rest = stop.orderedPhotos
        for (i, p) in rest.enumerated() { p.orderIndex = i }
        if (wasHero || !rest.contains(where: \.isHero)), let first = rest.first { stop.setHero(first) }
    }
}

/// Stores photos in the model. Needs no files, so it has no state.
struct ModelPhotoStore: PhotoStoring {
    init() {}

    @discardableResult
    func importPhoto(data: Data, into stop: Stop) throws -> StopPhoto {
        guard stop.photos.count < PhotoLimits.maxPerStop else { throw PhotoStoreError.limitReached }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { throw PhotoStoreError.undecodable }

        let meta = Self.metadata(of: src)
        guard let full = PhotoEncoding.downscaled(src, maxPixel: PhotoLimits.displayMaxPixel),
              let fullData = PhotoEncoding.jpegData(full) else { throw PhotoStoreError.undecodable }

        let photo = StopPhoto(orderIndex: (stop.photos.map(\.orderIndex).max() ?? -1) + 1,
                              isHero: stop.photos.isEmpty)
        photo.imageData = fullData
        photo.pixelWidth = full.width
        photo.pixelHeight = full.height
        photo.captureDate = meta.date
        photo.latitude = meta.lat
        photo.longitude = meta.lon
        stop.photos.append(photo)
        return photo
    }

    func removePhoto(_ photo: StopPhoto, from stop: Stop) {
        PhotoRules.detach(photo, from: stop)
    }

    private static func metadata(of src: CGImageSource) -> (date: Date?, lat: Double?, lon: Double?) {
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return (nil, nil, nil) }
        var date: Date?
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let s = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            date = f.date(from: s)
        }
        var lat: Double?, lon: Double?
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           var la = gps[kCGImagePropertyGPSLatitude] as? Double, var lo = gps[kCGImagePropertyGPSLongitude] as? Double {
            if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { la = -la }
            if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { lo = -lo }
            lat = la; lon = lo
        }
        return (date, lat, lon)
    }
}
