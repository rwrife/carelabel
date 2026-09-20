import CareKit
import CareStore
import CareStoreTestSupport
import Foundation
import GRDB
import Testing

// Issue #4: migrations against the committed v1 fixture database.
//
// The fixture (Tests/CareStoreTests/Fixtures/v1.sqlite) is a real v1-schema
// file with seeded rows, produced by fixture-seed + Scripts/make_fixture_db.py.
// These tests copy it to a temp location, run the migrator, and assert that
// v1 data survives unchanged and the schema is recognized as current.

private func fixtureURL() -> URL {
    // Anchor on this source file: swift-test working directories differ
    // between `swift test` and Xcode, but #filePath does not.
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/v1.sqlite")
}

/// Copies the fixture to a throwaway file and opens it with the production
/// migrator, mirroring `CareStore.open`.
private func migratedFixture() throws -> (store: CareStore, fileURL: URL) {
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CareStore-migration-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    let fileURL = tempDirectory.appendingPathComponent("carelabel.sqlite")
    try FileManager.default.copyItem(at: fixtureURL(), to: fileURL)

    var config = Configuration()
    config.foreignKeysEnabled = true
    let db = try DatabaseQueue(path: fileURL.path, configuration: config)
    try CareStoreSchema.migrator.migrate(db)
    let store = CareStore(
        db: db,
        photoStore: PhotoStore(directory: tempDirectory.appendingPathComponent("photos"), downsampler: FakeDownsampler())
    )
    return (store, fileURL)
}

@Suite("Schema migration v1 -> current", .serialized)
struct MigrationTests {
    @Test("v1 fixture upgrades and reports the current schema version")
    func fixtureUpgradesToCurrent() throws {
        let (store, fileURL) = try migratedFixture()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let applied = try careStoreAppliedSchemaVersion(store.db)
        #expect(applied == CareStoreSchema.currentVersion)
        #expect(applied == 1)  // v1 baseline
    }

    @Test("v1 garment data survives the migration byte-for-byte in fields")
    func fixtureGarmentSurvives() throws {
        let (store, fileURL) = try migratedFixture()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let garments = try store.garments.allGarments()
        #expect(garments.count == 1)
        let cardigan = try #require(garments.first)
        #expect(cardigan.id == 1)
        #expect(cardigan.name == "Fixture Cardigan")
        #expect(cardigan.category == .knitwear)
        #expect(cardigan.fabricNote == "70% wool / 30% acrylic")
        #expect(cardigan.photo == PhotoReference(fileName: "FIXTURE-PHOTO-1.jpg"))

        // The seeded profile went through the JSON column on the v1 side and
        // must decode to the exact same value domain-side.
        let expected = CareProfile()
            .applying([
                .machineWash(temperature: .celsius40, action: .normal),
                .noBleach,
                .naturalDry(.flat),
                .ironCap(.celsius150),
                .professionalRequires(.dryCleanAnySolvent),
                .noTumbleDry,
            ])
        #expect(cardigan.careProfile == expected)
        #expect(cardigan.createdAt == cardigan.updatedAt)
    }

    @Test("v1 wash-log rows survive, newest first")
    func fixtureWashLogSurvives() throws {
        let (store, fileURL) = try migratedFixture()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let entries = try store.washLog.entries(for: 1)
        #expect(entries.count == 2)
        #expect(entries.map(\.method) == [.dryClean, .machineWash])
        #expect(entries[1].loggedAt < entries[0].loggedAt)

        // Writing works on the migrated database too.
        let added = try store.washLog.log(WashLogEntry(
            garmentID: 1,
            method: .handWash,
            loggedAt: entries[0].loggedAt.addingTimeInterval(3600)
        ))
        #expect(added.id != nil)
        #expect(try store.washLog.allEntries().count == 3)
    }

    @Test("cascade delete works after migrating the fixture")
    func cascadeAfterMigration() throws {
        let (store, fileURL) = try migratedFixture()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        try store.garments.delete(id: 1)
        #expect(try store.garments.allGarments().isEmpty)
        #expect(try store.washLog.allEntries().isEmpty)
    }

    @Test("a fresh database reaches the same version as a migrated fixture")
    func freshEqualsMigrated() throws {
        let (store, fileURL) = try migratedFixture()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let fresh = try CareStore.inMemory(downsampler: FakeDownsampler())
        let migratedVersion = try careStoreAppliedSchemaVersion(store.db)
        let freshVersion = try careStoreAppliedSchemaVersion(fresh.db)
        #expect(migratedVersion == freshVersion)
    }

    @Test("migrating twice is a no-op (idempotent)")
    func migrateTwiceIsIdempotent() throws {
        let (store, fileURL) = try migratedFixture()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        try CareStoreSchema.migrator.migrate(store.db)
        let applied = try careStoreAppliedSchemaVersion(store.db)
        #expect(applied == CareStoreSchema.currentVersion)
    }
}
