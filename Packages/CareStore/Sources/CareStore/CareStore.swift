import Foundation
import GRDB

// Issue #4: database factory.
//
// The app container is the ONLY location: a file URL from the app-group
// container when the app declares one (see `defaultContainerDirectory`),
// otherwise the app-support directory. All data is app-private (no iCloud,
// no network, excluded from none — the MVP ships everything inside the
// container).

public enum CareStoreContainer {
    /// Default durable location for the SQLite file.
    /// The MVP has no app group entitlement (single app target), so the app
    /// support directory IS the app container; when a group is introduced,
    /// return the group URL here so every caller follows in one change.
    public static func defaultContainerDirectory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("CareLabel", isDirectory: true)
    }
}

public struct CareStore {
    public let db: DatabaseQueue
    public let photoStore: PhotoStore

    public init(db: DatabaseQueue, photoStore: PhotoStore) {
        self.db = db
        self.photoStore = photoStore
    }

    /// Opens (creating if needed) the canonical app database and migrates it
    /// to `CareStoreSchema.currentVersion`.
    public static func open(
        containerDirectory: URL,
        downsampler: any PhotoDownsampler,
        fileManager: FileManager = .default
    ) throws -> CareStore {
        try fileManager.createDirectory(at: containerDirectory, withIntermediateDirectories: true)
        let databaseURL = containerDirectory.appendingPathComponent("carelabel.sqlite")
        var config = Configuration()
        config.foreignKeysEnabled = true
        let db = try DatabaseQueue(path: databaseURL.path, configuration: config)
        try CareStoreSchema.migrator.migrate(db)
        let photoDirectory = containerDirectory.appendingPathComponent("photos", isDirectory: true)
        return CareStore(db: db, photoStore: PhotoStore(directory: photoDirectory, downsampler: downsampler))
    }

    /// Convenience in-memory database for previews and quick tests.
    public static func inMemory(downsampler: any PhotoDownsampler) throws -> CareStore {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let db = try DatabaseQueue(configuration: config)
        try CareStoreSchema.migrator.migrate(db)
        let photoDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CareStore-photo-\(UUID().uuidString)", isDirectory: true)
        return CareStore(db: db, photoStore: PhotoStore(directory: photoDirectory, downsampler: downsampler))
    }

    public var garments: GarmentRepository { GRDBGarmentRepository(db: db, photoStore: photoStore) }
    public var washLog: WashLogRepository { GRDBWashLogRepository(db: db) }
}

/// Schema version actually applied to a database (used by migration
/// tests and future diagnostics).
public func careStoreAppliedSchemaVersion(_ reader: any DatabaseReader) throws -> Int {
    try reader.read { db in try CareStoreSchema.migrator.appliedMigrations(db).count }
}
