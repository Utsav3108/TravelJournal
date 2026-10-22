import Foundation
import SwiftData

/// One row per photo. The display image (JPEG, long edge <= `PhotoLimits.displayMaxPixel`) lives in `imageData` and
/// syncs through CloudKit. Thumbnails are decoded from it on each device (see `StoredPhotos`) and never synced.
/// A photo with no `imageData` (sample data, or a file the V2→V3 migration couldn't read) draws a placeholder.
@Model
final class StopPhoto {
    var id: UUID = UUID()
    var stop: Stop?
    var orderIndex: Int = 0
    var isHero: Bool = false
    @Attribute(.externalStorage) var imageData: Data?
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    var captureDate: Date?
    var latitude: Double?
    var longitude: Double?
    var caption: String?

    init(id: UUID = UUID(), orderIndex: Int = 0, isHero: Bool = false) {
        self.id = id
        self.orderIndex = orderIndex
        self.isHero = isHero
    }
}
