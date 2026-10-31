import Foundation
import ImageIO
import OSLog
import SwiftData

// TJSchemaV1...V4 (frozen snapshots) live in SchemaV1Snapshot.swift ... SchemaV4Snapshot.swift.

/// V5 adds `Journey.mapStopID`, the stop a story is pinned at on the Mac bookshelf map (optional).
enum TJSchemaV5: VersionedSchema {
    static var versionIdentifier = Schema.Version(5, 0, 0)
    static var models: [any PersistentModel.Type] { [Journey.self, Stop.self, StopPhoto.self, Leg.self] }
}

enum TJMigrationPlan: SchemaMigrationPlan {
    /// Directory holding `Photos/` for the V2→V3 file import. `nil` = the default Application Support location.
    nonisolated(unsafe) static var photoBaseURL: URL?

    static var schemas: [any VersionedSchema.Type] { [TJSchemaV1.self, TJSchemaV2.self, TJSchemaV3.self, TJSchemaV4.self, TJSchemaV5.self] }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: TJSchemaV1.self, toVersion: TJSchemaV2.self),
            .custom(fromVersion: TJSchemaV2.self, toVersion: TJSchemaV3.self,
                    willMigrate: { context in try PhotoFileMigration.stage(in: context, baseURL: photoBaseURL) },
                    didMigrate: { context in try PhotoFileMigration.finish(in: context, baseURL: photoBaseURL) }),
            .lightweight(fromVersion: TJSchemaV3.self, toVersion: TJSchemaV4.self),
            .lightweight(fromVersion: TJSchemaV4.self, toVersion: TJSchemaV5.self),
        ]
    }
}

/// V2→V3: move each photo file into `StopPhoto.imageData` (re-encoded JPEG, long edge <= 2048 px, colour profile kept).
/// V3 no longer has the file-path columns, so this runs in two steps around the schema change:
/// - `stage` (V2 store, paths still known): re-encode each readable file into `MigrationStaging/<photo id>.jpg` and note
///   which files it came from.
/// - `finish` (V3 store): copy the staged bytes into the rows, save, and only then delete the staging copies and the
///   original files. A file that couldn't be read is left alone and its row keeps `imageData == nil`.
nonisolated enum PhotoFileMigration {
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TravelJournal", category: "migration")

    /// What `stage` records next to each staged image.
    private struct Staged: Codable {
        var originals: [String]     // paths relative to the base directory
        var width: Int
        var height: Int
    }

    /// Application Support/TravelJournal, where V2 kept `Photos/`.
    static var defaultBaseURL: URL {
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("TravelJournal", isDirectory: true)
    }

    private static func stagingDirectory(_ base: URL) -> URL { base.appendingPathComponent("MigrationStaging", isDirectory: true) }

    static func stage(in context: ModelContext, baseURL: URL?) throws {
        let base = baseURL ?? defaultBaseURL
        let dir = stagingDirectory(base)
        let photos = try context.fetch(FetchDescriptor<TJSchemaV2.StopPhoto>())
        for photo in photos {
            let rel = photo.relativePath
            guard !rel.isEmpty, !rel.hasPrefix("sample:") else { continue }
            guard let raw = try? Data(contentsOf: base.appendingPathComponent(rel)),
                  let enc = PhotoEncoding.reencoded(raw, maxPixel: PhotoLimits.displayMaxPixel) else {
                logger.error("Photo file unreadable during migration: \(rel, privacy: .public)")
                continue
            }
            let originals = [rel] + (photo.thumbRelativePath.isEmpty ? [] : [photo.thumbRelativePath])
            let note = try JSONEncoder().encode(Staged(originals: originals, width: enc.width, height: enc.height))
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try enc.data.write(to: dir.appendingPathComponent("\(photo.id.uuidString).jpg"), options: .atomic)
            try note.write(to: dir.appendingPathComponent("\(photo.id.uuidString).json"), options: .atomic)
        }
    }

    static func finish(in context: ModelContext, baseURL: URL?) throws {
        let base = baseURL ?? defaultBaseURL
        let dir = stagingDirectory(base)
        var done: [URL] = []
        for photo in try context.fetch(FetchDescriptor<TJSchemaV3.StopPhoto>()) where photo.imageData == nil {
            let image = dir.appendingPathComponent("\(photo.id.uuidString).jpg")
            let noteURL = dir.appendingPathComponent("\(photo.id.uuidString).json")
            guard let data = try? Data(contentsOf: image),
                  let note = (try? Data(contentsOf: noteURL)).flatMap({ try? JSONDecoder().decode(Staged.self, from: $0) }) else { continue }
            photo.imageData = data
            photo.pixelWidth = note.width
            photo.pixelHeight = note.height
            done += [image, noteURL] + note.originals.map { base.appendingPathComponent($0) }
        }
        try context.save()
        // The bytes are saved; now the staging copies and the original files are redundant.
        for url in done { try? FileManager.default.removeItem(at: url) }
        if let left = try? FileManager.default.contentsOfDirectory(atPath: dir.path), left.isEmpty {
            try? FileManager.default.removeItem(at: dir)
        }
    }
}

struct StoreOpenError: LocalizedError {
    var errorDescription: String? { "The data store could not be opened." }
}

enum AppContainer {
    /// Same container the Mac app will use (spec: iCloud.<bundle id>).
    static let cloudKitContainerID = "iCloud.com.utsavpandya.TravelJournal"

    /// iCloud sync switch. Off while the project is on a free developer account (no iCloud capability available):
    /// the store is local-only. To turn sync on later, set this to `true`, then add the iCloud (CloudKit) capability and
    /// point `CODE_SIGN_ENTITLEMENTS` at `Config/TravelJournal-iOS.entitlements.disabled` (rename it to `.entitlements`).
    /// The schema is already sync-ready, so nothing else changes.
    static let cloudKitEnabled = false

    typealias Factory = () throws -> ModelContainer

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TravelJournal", category: "store")

    /// Opens the real on-disk store. Throws on failure (including a failed migration); never falls back to memory
    /// and never deletes or resets the existing store.
    static func open(cloudKit: Bool) throws -> ModelContainer {
        let schema = Schema(versionedSchema: TJSchemaV5.self)
        let cfg = cloudKit
            ? ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudKitContainerID))
            : ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, migrationPlan: TJMigrationPlan.self, configurations: [cfg])
        } catch {
            logger.error("Store open failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// In-memory container for previews and tests (and `-uitest`). Not used for real data.
    static func openInMemory() throws -> ModelContainer {
        let schema = Schema(versionedSchema: TJSchemaV5.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [cfg])
    }

    /// Previews/tests convenience. The app itself uses `launchFactory`, which never takes this path for real data.
    static func make(inMemory: Bool) -> ModelContainer {
        precondition(inMemory, "AppContainer.make(inMemory:) is for previews and tests; use AppContainer.open.")
        do { return try openInMemory() } catch { preconditionFailure("In-memory container failed: \(error)") }
    }

    /// Launch flags: `-uitest` in-memory store; `-forceStoreFailure` simulates an open failure; `-disableCloudKit`
    /// keeps the store local. CloudKit is also off under XCTest (no iCloud account on CI/simulators).
    static func launchFactory(arguments: [String] = ProcessInfo.processInfo.arguments,
                              environment: [String: String] = ProcessInfo.processInfo.environment) -> Factory {
        if arguments.contains("-forceStoreFailure") { return { throw StoreOpenError() } }
        if arguments.contains("-uitest") { return { try openInMemory() } }
        let underTest = environment["XCTestConfigurationFilePath"] != nil
        let cloudKit = cloudKitEnabled && !underTest && !arguments.contains("-disableCloudKit")
        return { try open(cloudKit: cloudKit) }
    }
}

/// Holds the result of opening the store. The app shows its normal UI only in `.ready`; `.failed` shows
/// `StoreFailureView` with no model container attached.
@MainActor
@Observable
final class StoreLoader {
    enum State {
        case ready(ModelContainer)
        case failed
    }

    private(set) var state: State
    private let factory: AppContainer.Factory
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TravelJournal", category: "store")

    init(factory: @escaping AppContainer.Factory) {
        self.factory = factory
        self.state = .failed
        load()
    }

    func load() {
        do {
            state = .ready(try factory())
        } catch {
            Self.logger.error("Could not open store: \(String(describing: error), privacy: .public)")
            state = .failed
        }
    }
}
