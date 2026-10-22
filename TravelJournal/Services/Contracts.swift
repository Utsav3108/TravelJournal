import Foundation

// Phase 2 shared contracts. FROZEN: agents must not edit this file.

/// One imported photo with whatever metadata could be read.
struct PhotoMeta: Identifiable, Hashable, Sendable {
    /// PHAsset.localIdentifier when available, otherwise a generated UUID string.
    let id: String
    var date: Date?
    var latitude: Double?
    var longitude: Double?
    /// Downscaled JPEG bytes (<= 2048 px long edge, orientation baked in).
    var jpegData: Data
    var hasLocation: Bool { latitude != nil && longitude != nil }
}

struct PlaceCandidate: Identifiable, Hashable, Sendable {
    var id: String { "\(name)|\(latitude)|\(longitude)" }
    var name: String
    var address: String?
    var city: String?
    var latitude: Double
    var longitude: Double
}

/// Resolves places. Implemented by Services (B2); consumed by Capture UI (B3) and Stop editor (B1).
protocol PlaceLookup: Sendable {
    /// Best name for a coordinate: nearby POI first, then reverse geocode. nil if nothing found / offline.
    func place(near latitude: Double, longitude: Double) async -> PlaceCandidate?
    /// Text search biased to a city/region (coordinate optional).
    func search(_ query: String, nearLatitude: Double?, nearLongitude: Double?) async -> [PlaceCandidate]
}

/// Turns picker selections into PhotoMeta. Implemented by Services (B2); consumed by Capture UI (B3).
protocol PhotoImporting {
    /// Loads picked items; requests photo-library access only when needed (in context).
    func importItems(_ items: [AnyHashable]) async -> [PhotoMeta]
}
