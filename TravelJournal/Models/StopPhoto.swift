import Foundation
import SwiftData

/// One row per photo file. Pixels live on disk; only relative paths are stored.
@Model
final class StopPhoto {
    var id: UUID = UUID()
    var stop: Stop?
    var orderIndex: Int = 0
    var isHero: Bool = false
    var relativePath: String = ""
    var thumbRelativePath: String = ""
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    var captureDate: Date?
    var latitude: Double?
    var longitude: Double?
    var caption: String?

    init(id: UUID = UUID(), relativePath: String = "", thumbRelativePath: String = "",
         orderIndex: Int = 0, isHero: Bool = false) {
        self.id = id
        self.relativePath = relativePath
        self.thumbRelativePath = thumbRelativePath
        self.orderIndex = orderIndex
        self.isHero = isHero
    }
}
