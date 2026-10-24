import Foundation
import Observation
import Photos

/// Add-only access to the photo library, as far as saving slides needs it.
nonisolated enum PhotoLibraryAccess: Sendable, Equatable {
    case authorized, limited, denied, restricted, notDetermined

    /// Add-only saving works for full and limited access.
    var canAdd: Bool { self == .authorized || self == .limited }

    init(_ status: PHAuthorizationStatus) {
        switch status {
        case .authorized: self = .authorized
        case .limited: self = .limited
        case .denied: self = .denied
        case .restricted: self = .restricted
        default: self = .notDetermined
        }
    }
}

/// The photo library seen by `PhotosSaver`. `SystemPhotoLibrary` in the app; a fake in tests.
protocol PhotoLibraryWriting: Sendable {
    /// Asks for add-only access (prompts the first time) and returns the result.
    func requestAddAccess() async -> PhotoLibraryAccess
    /// Adds the image files as new photos, in order (the first file is the oldest, so Photos lists them in order).
    func addImages(at urls: [URL]) async throws
}

/// `PHPhotoLibrary` with `.addOnly` access. Uses `NSPhotoLibraryAddUsageDescription`.
nonisolated struct SystemPhotoLibrary: PhotoLibraryWriting {
    func requestAddAccess() async -> PhotoLibraryAccess {
        PhotoLibraryAccess(await PHPhotoLibrary.requestAuthorization(for: .addOnly))
    }

    func addImages(at urls: [URL]) async throws {
        // One change block, creation dates a second apart: the library sorts by date, so slide 1 comes first.
        let start = Date()
        try await PHPhotoLibrary.shared().performChanges {
            for (i, url) in urls.enumerated() {
                let request = PHAssetCreationRequest.forAsset()
                request.creationDate = start.addingTimeInterval(TimeInterval(i))
                request.addResource(with: .photo, fileURL: url, options: nil)
            }
        }
    }
}

/// "Save to Photos" for exported slides: asks for add-only access, saves every slide in order, and reports one of
/// a few clear states for the preview to show.
@MainActor
@Observable
final class PhotosSaver {
    enum State: Equatable {
        case idle
        case saving
        /// Number of slides saved.
        case saved(Int)
        /// Access was refused (or is restricted); the user can change it in Settings.
        case denied
        case failed(String)

        var message: String? {
            switch self {
            case .idle, .saving: nil
            case .saved(let n): "Saved \(n) slide\(n == 1 ? "" : "s") to Photos."
            case .denied: "TravelJournal can't add to your photo library. Allow it in Settings > Privacy & Security > Photos."
            case .failed(let reason): "The slides could not be saved to Photos. \(reason)"
            }
        }
    }

    private(set) var state: State = .idle
    @ObservationIgnored let library: PhotoLibraryWriting

    init(library: PhotoLibraryWriting = SystemPhotoLibrary()) {
        self.library = library
    }

    var isSaving: Bool { state == .saving }

    /// Saves `urls` in order. Ignored while a save is running.
    func save(_ urls: [URL]) async {
        guard state != .saving else { return }
        guard !urls.isEmpty else { state = .failed("There are no slides."); return }
        state = .saving
        let access = await library.requestAddAccess()
        guard access.canAdd else { state = .denied; return }
        do {
            try await library.addImages(at: urls)
            state = .saved(urls.count)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Back to idle (after the message was shown).
    func reset() { if state != .saving { state = .idle } }
}
