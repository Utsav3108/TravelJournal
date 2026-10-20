import Foundation
import SwiftData

// TJSchemaV1 (frozen snapshot) lives in SchemaV1Snapshot.swift.

enum TJSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [Journey.self, Stop.self, StopPhoto.self, Leg.self] }
}

enum TJMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [TJSchemaV1.self, TJSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: TJSchemaV1.self, toVersion: TJSchemaV2.self)]
    }
}

enum AppContainer {
    static func make(inMemory: Bool) -> ModelContainer {
        let schema = Schema(versionedSchema: TJSchemaV2.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, migrationPlan: TJMigrationPlan.self, configurations: [cfg])
        } catch {
            // Never wipe the on-disk store; fall back to memory so the app can show an error state.
            let mem = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [mem])
        }
    }
}
