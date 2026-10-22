import Foundation
import ImageIO
import OSLog
import SwiftData

// TJSchemaV1 and TJSchemaV2 (frozen snapshots) live in SchemaV1Snapshot.swift / SchemaV2Snapshot.swift.

enum TJSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] { [Journey.self, Stop.self, StopPhoto.self, Leg.self] }
}

enum TJMigrationPlan: SchemaMigrationPlan {
    /// Directory holding `Photos/` for the V2→V3 file import. `nil` = the default Application Support location.
    nonisolated(unsafe) static var photoBaseURL: URL?

    static var schemas: [any VersionedSchema.Type] { [TJSchemaV1.self, TJSchemaV2.self, TJSchemaV3.self] }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: TJSchemaV1.self, toVersion: TJSchemaV2.self),
            .custom(fromVersion: TJSchemaV2.self, toVersion: TJSchemaV3.self, willMigrate: nil,
                    didMigrate: { context in try PhotoFileMigration.run(in: context, baseURL: photoBaseURL) }),
        ]
    }
}

/// V2→V3: copy each photo file into `StopPhoto.imageData` (re-encoded JPEG, long edge <= 2048 px, colour profile kept),
/// save, and only then delete the file. A file that can't be read is left alone and its row keeps `imageData == nil`.
nonisolated enum PhotoFileMigration {
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TravelJournal", category: "migration")

    static func run(in context: ModelContext, baseURL: URL?) throws {
        let base = baseURL ?? FilePhotoStore.defaultBaseURL
        let photos = try context.fetch(FetchDescriptor<StopPhoto>())
        var migrated: [URL] = []
        for photo in photos where photo.imageData == nil {
            let rel = photo.relativePath
            guard !rel.isEmpty, !rel.hasPrefix("sample:") else { continue }
            let file = base.appendingPathComponent(rel)
            guard let raw = try? Data(contentsOf: file),
                  let enc = PhotoEncoding.reencoded(raw, maxPixel: PhotoLimits.displayMaxPixel) else {
                logger.error("Photo file unreadable during migration: \(rel, privacy: .public)")
                continue
            }
            photo.imageData = enc.data
            photo.pixelWidth = enc.width
            photo.pixelHeight = enc.height
            migrated.append(file)
            if !photo.thumbRelativePath.isEmpty { migrated.append(base.appendingPathComponent(photo.thumbRelativePath)) }
        }
        try context.save()
        // Data is saved; now the originals are redundant. (`PhotoCache` rebuilds local cache files on demand.)
        for url in migrated { try? FileManager.default.removeItem(at: url) }
    }
}

struct StoreOpenError: LocalizedError {
    var errorDescription: String? { "The data store could not be opened." }
}

enum AppContainer {
    /// Same container the Mac app will use (spec: iCloud.<bundle id>).
    static let cloudKitContainerID = "iCloud.com.utsavpandya.TravelJournal"

    typealias Factory = () throws -> ModelContainer

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TravelJournal", category: "store")

    /// Opens the real on-disk store. Throws on failure (including a failed migration); never falls back to memory
    /// and never deletes or resets the existing store.
    static func open(cloudKit: Bool) throws -> ModelContainer {
        let schema = Schema(versionedSchema: TJSchemaV3.self)
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
        let schema = Schema(versionedSchema: TJSchemaV3.self)
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
        let cloudKit = !underTest && !arguments.contains("-disableCloudKit")
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
