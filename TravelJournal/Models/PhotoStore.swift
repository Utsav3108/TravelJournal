import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers

enum PhotoStoreError: Error, Equatable {
    case limitReached
    case undecodable
    case writeFailed
}

protocol PhotoStoring {
    @discardableResult
    func importPhoto(data: Data, into stop: Stop, journeyID: UUID) throws -> StopPhoto
    /// Remove one photo (files + row), promoting a new hero if needed.
    func removePhoto(_ photo: StopPhoto, from stop: Stop)
    func removeFiles(for photos: [StopPhoto])
    func removeAllFiles(forJourney id: UUID)
    func url(for relativePath: String) -> URL
    /// Delete files under Photos/ not in `knownPaths` (relative paths, display and thumb).
    func sweepOrphans(knownPaths: Set<String>)
}

enum PhotoLimits {
    static let maxPerStop = 4
    static let displayMaxPixel = 2048
    static let thumbMaxPixel = 600
}

/// Does nothing; for sample data and previews.
struct NoopPhotoStore: PhotoStoring {
    func importPhoto(data: Data, into stop: Stop, journeyID: UUID) throws -> StopPhoto { throw PhotoStoreError.writeFailed }
    func removePhoto(_ photo: StopPhoto, from stop: Stop) { PhotoRules.detach(photo, from: stop) }
    func removeFiles(for photos: [StopPhoto]) {}
    func removeAllFiles(forJourney id: UUID) {}
    func url(for relativePath: String) -> URL { URL(fileURLWithPath: "/dev/null").appendingPathComponent(relativePath) }
    func sweepOrphans(knownPaths: Set<String>) {}
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

final class FilePhotoStore: PhotoStoring {
    /// Directory containing `Photos/`. Defaults to Application Support/TravelJournal.
    let baseURL: URL

    nonisolated static var defaultBaseURL: URL {
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("TravelJournal", isDirectory: true)
    }

    init(baseURL: URL? = nil) {
        self.baseURL = baseURL ?? Self.defaultBaseURL
    }

    func url(for relativePath: String) -> URL { baseURL.appendingPathComponent(relativePath) }

    @discardableResult
    func importPhoto(data: Data, into stop: Stop, journeyID: UUID) throws -> StopPhoto {
        guard stop.photos.count < PhotoLimits.maxPerStop else { throw PhotoStoreError.limitReached }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { throw PhotoStoreError.undecodable }

        let meta = Self.metadata(of: src)
        guard let full = PhotoEncoding.downscaled(src, maxPixel: PhotoLimits.displayMaxPixel),
              let fullData = PhotoEncoding.jpegData(full),
              let thumb = PhotoEncoding.downscaled(src, maxPixel: PhotoLimits.thumbMaxPixel),
              let thumbData = PhotoEncoding.jpegData(thumb) else { throw PhotoStoreError.undecodable }

        let id = UUID()
        let rel = "Photos/\(journeyID.uuidString)/\(id.uuidString).jpg"
        let thumbRel = "Photos/\(journeyID.uuidString)/thumbs/\(id.uuidString).jpg"
        do {
            try Self.write(fullData, to: url(for: rel))
            try Self.write(thumbData, to: url(for: thumbRel))
        } catch {
            try? FileManager.default.removeItem(at: url(for: rel))
            try? FileManager.default.removeItem(at: url(for: thumbRel))
            throw PhotoStoreError.writeFailed
        }

        let photo = StopPhoto(id: id, relativePath: rel, thumbRelativePath: thumbRel,
                              orderIndex: (stop.photos.map(\.orderIndex).max() ?? -1) + 1,
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
        removeFiles(for: [photo])
        PhotoRules.detach(photo, from: stop)
    }

    func removeFiles(for photos: [StopPhoto]) {
        for p in photos {
            for rel in [p.relativePath, p.thumbRelativePath] where !rel.isEmpty && !rel.hasPrefix("sample:") {
                try? FileManager.default.removeItem(at: url(for: rel))
            }
        }
    }

    func removeAllFiles(forJourney id: UUID) {
        try? FileManager.default.removeItem(at: url(for: "Photos/\(id.uuidString)"))
    }

    func sweepOrphans(knownPaths: Set<String>) {
        let root = baseURL.appendingPathComponent("Photos", isDirectory: true)
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        let rootPath = baseURL.standardizedFileURL.path + "/"
        var doomed: [URL] = []
        for case let u as URL in e {
            guard (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let path = u.standardizedFileURL.path
            guard path.hasPrefix(rootPath) else { continue }
            if !knownPaths.contains(String(path.dropFirst(rootPath.count))) { doomed.append(u) }
        }
        for u in doomed { try? FileManager.default.removeItem(at: u) }
    }

    // MARK: ImageIO helpers

    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
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

/// Rebuilds this device's local cache files (display image and thumbnail) from synced `StopPhoto.imageData`.
/// Interim bridge: view code still loads photos by relative path; once it decodes `imageData` directly (shared
/// `ImageDecoding`), this and the file paths can go away. Only missing files are written.
enum PhotoCache {
    @discardableResult
    static func warm(context: ModelContext, store: FilePhotoStore) -> Int {
        var d = FetchDescriptor<StopPhoto>()
        d.propertiesToFetch = [\.relativePath, \.thumbRelativePath]
        guard let photos = try? context.fetch(d) else { return 0 }
        let fm = FileManager.default
        var written = 0
        for photo in photos {
            let rel = photo.relativePath, thumbRel = photo.thumbRelativePath
            guard !rel.isEmpty, !rel.hasPrefix("sample:") else { continue }
            let needFull = !fm.fileExists(atPath: store.url(for: rel).path)
            let needThumb = !thumbRel.isEmpty && !fm.fileExists(atPath: store.url(for: thumbRel).path)
            guard needFull || needThumb, let data = photo.imageData else { continue }
            if needFull, (try? FilePhotoStore.write(data, to: store.url(for: rel))) != nil { written += 1 }
            if needThumb, let enc = PhotoEncoding.reencoded(data, maxPixel: PhotoLimits.thumbMaxPixel),
               (try? FilePhotoStore.write(enc.data, to: store.url(for: thumbRel))) != nil { written += 1 }
        }
        return written
    }
}
