import Foundation
import SwiftData

enum TJSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Journey.self, Stop.self, StopPhoto.self, Leg.self] }
}

enum TJMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [TJSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum AppContainer {
    static func make(inMemory: Bool) -> ModelContainer {
        let schema = Schema(versionedSchema: TJSchemaV1.self)
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
