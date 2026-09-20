import CareKit
import Foundation
import GRDB

// Issue #4: repository protocols + GRDB and in-memory implementations.
//
// Features (issues #5/#6) and tests program against `GarmentRepository` and
// `WashLogRepository`; `GRDBGarmentRepository` / `GRDBWashLogRepository` are
// the shipping implementations, and `CareStoreTestSupport.InMemory…` fakes
// back unit tests without a database file.

public protocol GarmentRepository: Sendable {
    /// Inserts a new garment, stamps `createdAt`/`updatedAt`, returns it with
    /// its new id.
    func save(_ garment: Garment) throws -> Garment
    /// Updates an existing garment by id (refreshes `updatedAt`). Throws
    /// `CareStoreError.garmentNotFound` when the id is gone.
    func update(_ garment: Garment) throws -> Garment
    func garment(id: Int64) throws -> Garment?
    /// All garments, most-recently-updated first.
    func allGarments() throws -> [Garment]
    /// Deletes the garment; its wash-log rows cascade away.
    func delete(id: Int64) throws
}

public protocol WashLogRepository: Sendable {
    /// Records a wash event; throws `CareStoreError.garmentNotFound` when the
    /// garment id does not exist (checked before insert; foreign keys
    /// enforce it in the database too).
    func log(_ entry: WashLogEntry) throws -> WashLogEntry
    /// Entries for one garment, newest first.
    func entries(for garmentID: Int64) throws -> [WashLogEntry]
    /// Every entry, newest first.
    func allEntries() throws -> [WashLogEntry]
}

// MARK: - GRDB implementations

public struct GRDBGarmentRepository: GarmentRepository {
    let db: any DatabaseWriter
    let photoStore: PhotoStore?

    public init(db: any DatabaseWriter, photoStore: PhotoStore? = nil) {
        self.db = db
        self.photoStore = photoStore
    }

    public func save(_ garment: Garment) throws -> Garment {
        let stamp = Date()
        let stored: GarmentRecord = try db.write { writer in
            var record = try GarmentRecord(garment, createdAt: stamp, updatedAt: stamp)
            record.id = nil
            try record.insert(writer)
            return record
        }
        var result = garment
        result.id = stored.id
        result.createdAt = stored.createdAt
        result.updatedAt = stored.updatedAt
        return result
    }

    public func update(_ garment: Garment) throws -> Garment {
        guard let id = garment.id else {
            throw CareStoreError.garmentNotFound(-1)
        }
        let stored: GarmentRecord = try db.write { writer in
            guard let existing = try GarmentRecord.fetchOne(writer, key: id) else {
                throw CareStoreError.garmentNotFound(id)
            }
            var record = try GarmentRecord(garment, createdAt: existing.createdAt, updatedAt: Date())
            record.id = id
            try record.update(writer)
            return record
        }
        var result = garment
        result.id = stored.id
        result.createdAt = stored.createdAt
        result.updatedAt = stored.updatedAt
        return result
    }

    public func garment(id: Int64) throws -> Garment? {
        try db.read { reader in
            try GarmentRecord.fetchOne(reader, key: id)?.toGarment()
        }
    }

    public func allGarments() throws -> [Garment] {
        try db.read { reader in
            try GarmentRecord
                .order(Column("updated_at").desc, Column("id").desc)
                .fetchAll(reader)
                .map { try $0.toGarment() }
        }
    }

    /// Deletes the garment row AND its photo file (so storage usage shrinks
    /// with the registry — acceptance: usage queryable + originals not kept).
    public func delete(id: Int64) throws {
        let photoFileName: String? = try db.write { writer in
            guard let record = try GarmentRecord.fetchOne(writer, key: id) else { return nil }
            // Orphan the photo reference before the row delete, so a crash
            // between the steps cannot leave the DB pointing at a dead file.
            var cleaned = record
            cleaned.photoFileName = nil
            try cleaned.update(writer, columns: ["photo_file_name"])
            try record.delete(writer)
            return record.photoFileName
        }
        if let photoFileName, let photoStore {
            try? photoStore.deletePhoto(named: photoFileName)
        }
    }
}

public struct GRDBWashLogRepository: WashLogRepository {
    let db: any DatabaseWriter

    public init(db: any DatabaseWriter) {
        self.db = db
    }

    public func log(_ entry: WashLogEntry) throws -> WashLogEntry {
        let stored: WashLogRecord = try db.write { writer in
            guard try GarmentRecord.fetchOne(writer, key: entry.garmentID) != nil else {
                throw CareStoreError.garmentNotFound(entry.garmentID)
            }
            var record = WashLogRecord(entry)
            record.id = nil
            try record.insert(writer)
            return record
        }
        var result = entry
        result.id = stored.id
        return result
    }

    public func entries(for garmentID: Int64) throws -> [WashLogEntry] {
        try db.read { reader in
            try WashLogRecord
                .filter(Column("garment_id") == garmentID)
                .order(Column("logged_at").desc, Column("id").desc)
                .fetchAll(reader)
                .map { $0.toEntry() }
        }
    }

    public func allEntries() throws -> [WashLogEntry] {
        try db.read { reader in
            try WashLogRecord
                .order(Column("logged_at").desc, Column("id").desc)
                .fetchAll(reader)
                .map { $0.toEntry() }
        }
    }
}
