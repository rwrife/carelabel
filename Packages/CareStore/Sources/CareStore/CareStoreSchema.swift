import Foundation
import GRDB

// Issue #4: schema + migrations.

public enum CareStoreError: Error, Equatable, Sendable {
    /// A `care_profile_json` row could not be decoded. Reported with the row
    /// id so corruption is diagnosable instead of silently defaulting.
    case corruptCareProfile(garmentID: Int64?, underlying: String)
    /// A photo file name stored or requested was rejected.
    case unsafePhotoFileName(String)
    /// A photo referenced by the database is missing from the photo store.
    case missingPhoto(String)
    /// A repository update named a garment id that no longer exists.
    case garmentNotFound(Int64)
}

/// Schema identity. `v1` is frozen forever — never edit it in place; append
/// a `v2` migration and register it below when the schema evolves.
///
/// Schema v1:
///
///   garment(
///     id INTEGER PRIMARY KEY AUTOINCREMENT,
///     name TEXT NOT NULL,
///     category TEXT NOT NULL,
///     fabric_note TEXT,
///     photo_file_name TEXT,
///     care_profile_json TEXT NOT NULL,   -- JSON-encoded CareKit CareProfile
///     created_at DATETIME NOT NULL,
///     updated_at DATETIME NOT NULL
///   )
///
///   wash_log(
///     id INTEGER PRIMARY KEY AUTOINCREMENT,
///     garment_id INTEGER NOT NULL REFERENCES garment(id) ON DELETE CASCADE,
///     method TEXT NOT NULL,
///     logged_at DATETIME NOT NULL
///   )
///   INDEX wash_log_garment_date ON wash_log(garment_id, logged_at)
///
/// `care_profile_json` stores CareKit's `CareProfile` with JSONEncoder, so
/// domain evolution stays with CareKit's Codable conformance while the SQL
/// schema stays stable. Foreign keys are enforced (GRDB enables them per
/// connection by default), which is what makes garment deletion cascade to
/// wash-log rows.
public enum CareStoreSchema {
    /// Stable, ordered migration identifiers. The count is the schema version.
    public static let migrationIdentifiers: [String] = ["v1"]

    /// Current schema version == number of registered migrations.
    public static var currentVersion: Int { migrationIdentifiers.count }

    public static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "garment") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("name", .text).notNull()
                table.column("category", .text).notNull()
                table.column("fabric_note", .text)
                table.column("photo_file_name", .text)
                table.column("care_profile_json", .text).notNull()
                table.column("created_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull()
            }
            try db.create(table: "wash_log") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("garment_id", .integer).notNull()
                    .references("garment", onDelete: .cascade)
                table.column("method", .text).notNull()
                table.column("logged_at", .datetime).notNull()
            }
            try db.create(
                index: "wash_log_garment_date",
                on: "wash_log",
                columns: ["garment_id", "logged_at"]
            )
        }
        return migrator
    }()
}
