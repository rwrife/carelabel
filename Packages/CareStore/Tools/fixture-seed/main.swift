import CareKit
import CareStore
import Foundation
import GRDB

// Deterministic seeder for the committed schema-v1 fixture
// (Tests/CareStoreTests/Fixtures/v1.sqlite).
//
// It applies the real CareStoreSchema v1 migration and inserts one garment
// and two wash-log entries with FIXED dates and fixed photo file names, so
// the fixture is stable and the migration tests can assert exact contents.
// Run via Scripts/make_fixture_db.py — never hand-edit the result.

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: fixture-seed <output.sqlite>\n".utf8))
    exit(2)
}
let outputURL = URL(fileURLWithPath: arguments[1])
try? FileManager.default.removeItem(at: outputURL)

var config = Configuration()
config.foreignKeysEnabled = true
let db = try DatabaseQueue(path: outputURL.path, configuration: config)
try CareStoreSchema.migrator.migrate(db)

func fixedDate(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = formatter.date(from: iso) else {
        fatalError("bad fixed date \(iso)")
    }
    return date
}

let seedProfile = CareProfile()
    .applying([
        .machineWash(temperature: .celsius40, action: .normal),
        .noBleach,
        .naturalDry(.flat),
        .ironCap(.celsius150),
        .professionalRequires(.dryCleanAnySolvent),
        .noTumbleDry,
    ])

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let profileJSON = String(decoding: try encoder.encode(seedProfile), as: UTF8.self)

let created = fixedDate("2026-01-01T00:00:00.000Z")

try db.write { writer in
    try writer.execute(
        sql: """
        INSERT INTO garment (id, name, category, fabric_note, photo_file_name, care_profile_json, created_at, updated_at)
        VALUES (1, 'Fixture Cardigan', 'knitwear', '70% wool / 30% acrylic', 'FIXTURE-PHOTO-1.jpg', ?, ?, ?)
        """,
        arguments: [profileJSON, created, created]
    )
    try writer.execute(
        sql: """
        INSERT INTO wash_log (id, garment_id, method, logged_at) VALUES
        (1, 1, 'machineWash', ?),
        (2, 1, 'dryClean', ?)
        """,
        arguments: [fixedDate("2026-01-08T09:00:00.000Z"), fixedDate("2026-02-01T18:30:00.000Z")]
    )
}

let garmentCount = try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM garment") ?? -1 }
let entryCount = try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM wash_log") ?? -1 }
guard garmentCount == 1, entryCount == 2 else {
    fatalError("seed verification failed: garments=\(garmentCount) wash_log=\(entryCount)")
}
print("Seeded \(outputURL.path): 1 garment, 2 wash-log entries")
