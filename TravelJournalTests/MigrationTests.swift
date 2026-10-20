import XCTest
import SwiftData
@testable import TravelJournal

final class MigrationTests: XCTestCase {
    func testV1StoreMigratesToV2() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mig-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("store.sqlite")
        let id: UUID

        do {
            let schema = Schema(versionedSchema: TJSchemaV1.self)
            let c = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let ctx = ModelContext(c)
            let j = TJSchemaV1.Journey(title: "Old Trip", city: "Mumbai")
            id = j.id
            ctx.insert(j)
            try ctx.save()
        }

        let schema = Schema(versionedSchema: TJSchemaV2.self)
        let c = try ModelContainer(for: schema, migrationPlan: TJMigrationPlan.self,
                                   configurations: [ModelConfiguration(schema: schema, url: url)])
        let all = try ModelContext(c).fetch(FetchDescriptor<Journey>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, id)
        XCTAssertEqual(all.first?.title, "Old Trip")
        XCTAssertEqual(all.first?.city, "Mumbai")
        XCTAssertNil(all.first?.country)
    }
}
