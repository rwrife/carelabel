import CareKit
import Foundation
import GRDB

// Issue #4: GRDB record types. Column names map through explicit CodingKeys
// raw values (snake_case columns, camelCase Swift properties).

/// Row of `garment`. CareProfile round-trips through `care_profile_json`.
struct GarmentRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "garment"

    var id: Int64?
    var name: String
    var category: String
    var fabricNote: String?
    var photoFileName: String?
    var careProfileJSON: String
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case fabricNote = "fabric_note"
        case photoFileName = "photo_file_name"
        case careProfileJSON = "care_profile_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(_ garment: Garment, createdAt: Date, updatedAt: Date) throws {
        self.id = garment.id
        self.name = garment.name
        self.category = garment.category.rawValue
        self.fabricNote = garment.fabricNote
        self.photoFileName = garment.photo?.fileName
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.careProfileJSON = String(decoding: try encoder.encode(garment.careProfile), as: UTF8.self)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func toGarment() throws -> Garment {
        let profile: CareProfile
        do {
            profile = try JSONDecoder().decode(CareProfile.self, from: Data(careProfileJSON.utf8))
        } catch {
            throw CareStoreError.corruptCareProfile(
                garmentID: id,
                underlying: String(describing: error)
            )
        }
        var photo: PhotoReference?
        if let photoFileName {
            let reference = PhotoReference(fileName: photoFileName)
            // A stored name that is not path-safe must never reach the photo
            // store; the reference is dropped rather than trusting the row.
            photo = reference.isSafeFileName ? reference : nil
        }
        return Garment(
            id: id,
            name: name,
            category: GarmentCategory(rawValue: category) ?? .other,
            fabricNote: fabricNote,
            photo: photo,
            careProfile: profile,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Row of `wash_log`.
struct WashLogRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "wash_log"

    var id: Int64?
    var garmentID: Int64
    var method: String
    var loggedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case garmentID = "garment_id"
        case method
        case loggedAt = "logged_at"
    }

    init(_ entry: WashLogEntry) {
        self.id = entry.id
        self.garmentID = entry.garmentID
        self.method = entry.method.rawValue
        self.loggedAt = entry.loggedAt
    }

    func toEntry() -> WashLogEntry {
        WashLogEntry(
            id: id,
            garmentID: garmentID,
            method: WashMethod(rawValue: method) ?? .machineWash,
            loggedAt: loggedAt
        )
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
