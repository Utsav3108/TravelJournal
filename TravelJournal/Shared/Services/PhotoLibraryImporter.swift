import Foundation
import Photos
import PhotosUI
import CoreLocation
import SwiftUI

/// Imports `PhotosPickerItem`s (passed as AnyHashable). The picker must be created with `photoLibrary: .shared()`
/// so `itemIdentifier` is available. Asset metadata (location/date, including user edits in Photos) is preferred;
/// EXIF is the fallback (no identifier, no permission, limited access, or asset not in the limited set).
struct PhotoLibraryImporter: PhotoImporting {
    init() {}

    func importItems(_ items: [AnyHashable]) async -> [PhotoMeta] {
        let picks = items.compactMap { $0 as? PhotosPickerItem }
        guard !picks.isEmpty else { return [] }

        let canReadAssets = picks.contains { $0.itemIdentifier != nil } ? await Self.ensureReadAccess() : false

        var result: [PhotoMeta] = []
        for item in picks {   // sequential: keeps memory flat on large selections
            if Task.isCancelled { break }
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            var date: Date?, lat: Double?, lon: Double?
            if canReadAssets, let id = item.itemIdentifier,
               let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject {
                date = asset.creationDate
                if let c = asset.location?.coordinate, CLLocationCoordinate2DIsValid(c) {
                    lat = c.latitude; lon = c.longitude
                }
            }
            if let meta = PhotoMetaFactory.make(id: item.itemIdentifier, data: data,
                                                assetDate: date, assetLatitude: lat, assetLongitude: lon) {
                result.append(meta)
            }
        }
        return result
    }

    /// True when authorized or limited. Prompts only if not yet determined; denied/restricted falls back to EXIF.
    static func ensureReadAccess() async -> Bool {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        return status == .authorized || status == .limited
    }
}
