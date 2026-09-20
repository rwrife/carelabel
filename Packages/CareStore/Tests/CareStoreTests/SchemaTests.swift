import CareStore
import Foundation
import GRDB
import Testing

// Issue #4: schema invariants.

@Suite("Schema", .serialized)
struct SchemaTests {
    @Test("current version is the registered migration count")
    func versionMatchesMigrations() {
        #expect(CareStoreSchema.currentVersion == CareStoreSchema.migrationIdentifiers.count)
        #expect(CareStoreSchema.currentVersion == 1)
    }

    @Test("fresh database applies v1 and creates exactly the shipped tables")
    func freshSchema() throws {
        let store = try CareStore.inMemory(downsampler: FakeDownsamplerLite())
        let tables = try store.db.read { reader in
            try String.fetchAll(
                reader,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
            )
        }
        #expect(Set(tables) == Set(["garment", "wash_log", "grdb_migrations"]))

        let columns = try store.db.read { reader in
            try String.fetchAll(
                reader,
                sql: "SELECT name FROM pragma_table_info('garment') ORDER BY cid"
            )
        }
        #expect(columns == [
            "id", "name", "category", "fabric_note", "photo_file_name",
            "care_profile_json", "created_at", "updated_at",
        ])

        let washColumns = try store.db.read { reader in
            try String.fetchAll(
                reader,
                sql: "SELECT name FROM pragma_table_info('wash_log') ORDER BY cid"
            )
        }
        #expect(washColumns == ["id", "garment_id", "method", "logged_at"])
    }
}

private struct FakeDownsamplerLite: PhotoDownsampler {
    func downscale(imageData: Data, maximumDimension: Int) throws -> Data { Data() }
}
