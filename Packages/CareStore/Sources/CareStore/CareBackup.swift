import CareKit
import Foundation

// Issue #7: user-owned data lifecycle.
//
// A versioned JSON backup archive (profiles, garments, photos, wash log),
// previewed restore/merge, and CSV export. Everything here is pure
// Foundation/CareKit logic so it is fully unit-testable on Linux — the app
// target only wires this to the share sheet / file importer.

/// One garment plus its embedded photo bytes (base64) inside a backup
/// archive. Photo bytes travel WITH the record so a restore never depends
/// on a photo file surviving separately from the JSON.
public struct CareBackupGarment: Codable, Equatable, Sendable {
    public var id: Int64?
    public var name: String
    public var category: GarmentCategory
    public var fabricNote: String?
    public var careProfile: CareProfile
    public var createdAt: Date?
    public var updatedAt: Date?
    /// Base64-encoded JPEG bytes of the label photo, if any. `nil` means the
    /// garment had no photo — never a signal of failure.
    public var photoBase64: String?

    public init(
        id: Int64?,
        name: String,
        category: GarmentCategory,
        fabricNote: String?,
        careProfile: CareProfile,
        createdAt: Date?,
        updatedAt: Date?,
        photoBase64: String?
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.fabricNote = fabricNote
        self.careProfile = careProfile
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.photoBase64 = photoBase64
    }
}

/// One wash-log entry inside a backup archive. Carries `garmentID` so
/// restore can re-associate entries with their (possibly renumbered)
/// garment via the same identity key used for merge matching.
public struct CareBackupWashLogEntry: Codable, Equatable, Sendable {
    public var id: Int64?
    public var garmentID: Int64
    public var method: WashMethod
    public var loggedAt: Date

    public init(id: Int64?, garmentID: Int64, method: WashMethod, loggedAt: Date) {
        self.id = id
        self.garmentID = garmentID
        self.method = method
        self.loggedAt = loggedAt
    }
}

/// The full backup archive. `schemaVersion` is the `CareStoreSchema` version
/// the data was exported from — a restore that is asked to read a NEWER
/// schema version than this build understands must refuse, never guess.
public struct CareBackupArchive: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var schemaVersion: Int
    public var exportedAt: Date
    public var garments: [CareBackupGarment]
    public var washLog: [CareBackupWashLogEntry]

    public init(
        formatVersion: Int = CareBackupArchive.currentFormatVersion,
        schemaVersion: Int,
        exportedAt: Date,
        garments: [CareBackupGarment],
        washLog: [CareBackupWashLogEntry]
    ) {
        self.formatVersion = formatVersion
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.garments = garments
        self.washLog = washLog
    }
}

public enum CareBackupError: Error, Equatable, Sendable {
    /// The archive bytes are not valid JSON, or are missing required keys.
    case corruptArchive(String)
    /// The archive was produced by a NEWER backup format than this build
    /// understands — never guess at an unknown shape.
    case unsupportedFormatVersion(found: Int, maximumSupported: Int)
    case unsupportedSchemaVersion(found: Int, maximumSupported: Int)
    /// A garment declared a photo reference, but reading its photo data failed.
    /// Export must fail loud rather than produce an incomplete backup archive.
    case missingPhotoData(garmentName: String, fileName: String)
    /// A garment in the archive is missing a stable identity (name + created
    /// timestamp) needed for merge matching.
    case garmentMissingIdentity
    case duplicateGarmentID(Int64)
    case washLogReferencesMissingGarment(Int64)
}

extension CareBackupError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .corruptArchive:
            "This file is not a valid Care Label backup."
        case let .unsupportedFormatVersion(found, maximum):
            "This backup uses format version \(found), but this app supports through version \(maximum)."
        case let .unsupportedSchemaVersion(found, maximum):
            "This backup needs database version \(found), but this app supports through version \(maximum)."
        case let .missingPhotoData(name, file):
            "Could not read photo '\(file)' for '\(name)'. Backup was canceled to prevent data loss."
        case .garmentMissingIdentity:
            "A garment in this backup has no name. Nothing was restored."
        case let .duplicateGarmentID(id):
            "This backup contains duplicate garment ID \(id). Nothing was restored."
        case let .washLogReferencesMissingGarment(id):
            "A wash entry refers to missing garment ID \(id). Nothing was restored."
        }
    }
}

/// Preview of what a restore WOULD do, computed without writing anything.
/// The UI shows this and requires explicit confirmation before `apply`.
public struct CareRestorePreview: Equatable, Sendable {
    /// Garments present in the archive but not matched to any existing
    /// garment (by name — see `CareBackupEngine.identityKey`) — these will
    /// be inserted.
    public var addedGarmentCount: Int
    /// Garments matched to an existing garment whose recorded fields differ
    /// — these will be updated in place (existing photo/id preserved).
    public var mergedGarmentCount: Int
    /// Garments matched to an existing garment with identical fields — no
    /// write needed.
    public var unchangedGarmentCount: Int
    /// Wash-log entries that will be inserted (entries are never merged or
    /// deduplicated by content — importing the same archive twice would
    /// duplicate them, which is why restore previews this count
    /// explicitly rather than hiding it).
    public var addedWashLogCount: Int

    public init(
        addedGarmentCount: Int,
        mergedGarmentCount: Int,
        unchangedGarmentCount: Int,
        addedWashLogCount: Int
    ) {
        self.addedGarmentCount = addedGarmentCount
        self.mergedGarmentCount = mergedGarmentCount
        self.unchangedGarmentCount = unchangedGarmentCount
        self.addedWashLogCount = addedWashLogCount
    }
}

/// Pure engine: builds/parses backup archives, computes restore previews,
/// and renders the CSV summary. No I/O — `CareStore` (issue #4) supplies the
/// live data and performs the actual writes; this type only transforms
/// values so every rule is unit-testable without a database.
public enum CareBackupEngine {
    /// Portable merge identity: name + category + creation-second (when available). Local
    /// SQLite ids are not portable, and name/category alone is not unique
    /// (two black tees are valid). Creation time is stamped on every saved
    /// garment and survives export; second precision matches ISO8601 JSON.
    public static func identityKey(
        name: String,
        category: GarmentCategory,
        createdAt: Date? = nil
    ) -> String {
        let base = "\(category.rawValue)::\(name.lowercased())"
        guard let createdAt else { return base }
        let createdSecond = Int64(createdAt.timeIntervalSince1970)
        return "\(base)::\(createdSecond)"
    }

    private static func identityKey(_ garment: Garment) -> String {
        identityKey(name: garment.name, category: garment.category, createdAt: garment.createdAt)
    }

    private static func identityKey(_ garment: CareBackupGarment) -> String {
        identityKey(name: garment.name, category: garment.category, createdAt: garment.createdAt)
    }

    // MARK: - Export

    /// Builds an archive from live values. `photoData` is injected so the
    /// engine stays storage-agnostic — the caller (app / CareStore-backed
    /// helper) resolves each garment's photo bytes.
    public static func makeArchive(
        schemaVersion: Int,
        garments: [Garment],
        washLog: [WashLogEntry],
        exportedAt: Date = Date(),
        photoData: (PhotoReference) -> Data?
    ) throws -> CareBackupArchive {
        var backupGarments: [CareBackupGarment] = []
        backupGarments.reserveCapacity(garments.count)

        for garment in garments {
            let photoBase64: String?
            if let reference = garment.photo {
                guard let bytes = photoData(reference) else {
                    throw CareBackupError.missingPhotoData(
                        garmentName: garment.name,
                        fileName: reference.fileName
                    )
                }
                photoBase64 = bytes.base64EncodedString()
            } else {
                photoBase64 = nil
            }

            backupGarments.append(
                CareBackupGarment(
                    id: garment.id,
                    name: garment.name,
                    category: garment.category,
                    fabricNote: garment.fabricNote,
                    careProfile: garment.careProfile,
                    createdAt: garment.createdAt,
                    updatedAt: garment.updatedAt,
                    photoBase64: photoBase64
                )
            )
        }

        let backupEntries = washLog.map {
            CareBackupWashLogEntry(id: $0.id, garmentID: $0.garmentID, method: $0.method, loggedAt: $0.loggedAt)
        }
        return CareBackupArchive(
            schemaVersion: schemaVersion,
            exportedAt: exportedAt,
            garments: backupGarments,
            washLog: backupEntries
        )
    }

    /// Deterministic JSON encoding (sorted keys, ISO8601 dates) so a
    /// round-trip export→import→export is byte-stable for tests.
    public static func encode(_ archive: CareBackupArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    /// Parses archive bytes, rejecting corrupt JSON and future-format
    /// archives up front (fail loud, never guess at an unknown shape).
    public static func decode(_ data: Data) throws -> CareBackupArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive: CareBackupArchive
        do {
            archive = try decoder.decode(CareBackupArchive.self, from: data)
        } catch {
            throw CareBackupError.corruptArchive(String(describing: error))
        }
        guard archive.formatVersion > 0,
              archive.formatVersion <= CareBackupArchive.currentFormatVersion else {
            throw CareBackupError.unsupportedFormatVersion(
                found: archive.formatVersion,
                maximumSupported: CareBackupArchive.currentFormatVersion
            )
        }
        guard archive.schemaVersion > 0,
              archive.schemaVersion <= CareStoreSchema.currentVersion else {
            throw CareBackupError.unsupportedSchemaVersion(
                found: archive.schemaVersion,
                maximumSupported: CareStoreSchema.currentVersion
            )
        }
        var garmentIDs = Set<Int64>()
        for garment in archive.garments {
            if garment.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw CareBackupError.garmentMissingIdentity
            }
            if let id = garment.id, !garmentIDs.insert(id).inserted {
                throw CareBackupError.duplicateGarmentID(id)
            }
            if let photoBase64 = garment.photoBase64,
               Data(base64Encoded: photoBase64) == nil {
                throw CareBackupError.corruptArchive("Invalid base64 photo payload for garment '\(garment.name)'")
            }
        }
        for entry in archive.washLog where !garmentIDs.contains(entry.garmentID) {
            throw CareBackupError.washLogReferencesMissingGarment(entry.garmentID)
        }
        return archive
    }

    // MARK: - Restore preview

    /// Computes what a restore of `archive` would do against the current
    /// `existingGarments`, without writing anything.
    public static func previewRestore(
        archive: CareBackupArchive,
        existingGarments: [Garment]
    ) -> CareRestorePreview {
        var existingByKey = Dictionary(
            grouping: existingGarments.map { (identityKey($0), $0) },
            by: \.0
        ).mapValues { $0.map(\.1) }

        var added = 0
        var merged = 0
        var unchanged = 0
        for incoming in archive.garments {
            let key = identityKey(incoming)
            guard var candidates = existingByKey[key], !candidates.isEmpty else {
                added += 1
                continue
            }
            let existing = candidates.removeFirst()
            existingByKey[key] = candidates
            let photoBytes = incoming.photoBase64.flatMap { Data(base64Encoded: $0) }
            if existing.fabricNote == incoming.fabricNote
                && existing.careProfile == incoming.careProfile
                && photoBytes == nil {
                unchanged += 1
            } else {
                merged += 1
            }
        }
        return CareRestorePreview(
            addedGarmentCount: added,
            mergedGarmentCount: merged,
            unchangedGarmentCount: unchanged,
            addedWashLogCount: archive.washLog.count
        )
    }

    // MARK: - Restore plan (what CareStore should actually write)

    /// One garment-level action a restore should perform. `CareStore`
    /// (or the app model) executes these through the repository protocols;
    /// this engine only decides WHAT to do, never touches a database.
    public enum GarmentRestoreAction: Equatable, Sendable {
        /// Insert a brand-new garment (no id — the repository assigns one),
        /// with decoded photo bytes staged separately by the executor.
        case insert(incomingArchiveID: Int64?, garment: Garment, photoData: Data?)
        /// Update an existing garment in place, preserving its id/photo
        /// unless the archive also supplies photo bytes for it.
        case update(incomingArchiveID: Int64?, id: Int64, garment: Garment, photoData: Data?)
        /// Matched and identical — nothing to write.
        case unchanged(incomingArchiveID: Int64?, id: Int64)
    }
    /// Builds the exact per-garment plan a confirmed restore executes,
    /// alongside the wash-log entries to insert (garment ids remapped to
    /// existing/new ids by the SAME identity key used for the preview, so a
    /// restore that also inserts new garments still attaches their wash
    /// history correctly).
    public static func restorePlan(
        archive: CareBackupArchive,
        existingGarments: [Garment]
    ) -> [GarmentRestoreAction] {
        var existingByKey = Dictionary(
            grouping: existingGarments.map { (identityKey($0), $0) },
            by: \.0
        ).mapValues { $0.map(\.1) }

        var actions: [GarmentRestoreAction] = []

        for incoming in archive.garments {
            let photoBytes = incoming.photoBase64.flatMap { Data(base64Encoded: $0) }
            let key = identityKey(incoming)
            guard var candidates = existingByKey[key], !candidates.isEmpty else {
                let inserted = Garment(
                    name: incoming.name,
                    category: incoming.category,
                    fabricNote: incoming.fabricNote,
                    photo: nil,
                    careProfile: incoming.careProfile,
                    createdAt: incoming.createdAt,
                    updatedAt: incoming.updatedAt
                )
                actions.append(.insert(incomingArchiveID: incoming.id, garment: inserted, photoData: photoBytes))
                continue
            }

            let existing = candidates.removeFirst()
            existingByKey[key] = candidates

            if existing.fabricNote == incoming.fabricNote
                && existing.careProfile == incoming.careProfile
                && photoBytes == nil {
                actions.append(.unchanged(incomingArchiveID: incoming.id, id: existing.id ?? -1))
            } else {
                var merged = existing
                merged.fabricNote = incoming.fabricNote
                merged.careProfile = incoming.careProfile
                merged.updatedAt = incoming.updatedAt ?? Date()
                actions.append(.update(incomingArchiveID: incoming.id, id: existing.id ?? -1, garment: merged, photoData: photoBytes))
            }
        }
        return actions
    }

    // MARK: - CSV export

    /// CSV header, fixed column order (acceptance: garments + last-washed +
    /// key care caps).
    public static let csvHeader = [
        "Name", "Category", "Fabric Note", "Wash", "Bleach", "Dry", "Iron",
        "Professional", "Last Washed",
    ]

    /// Renders the garment summary CSV (acceptance: garments + last-washed +
    /// key care caps, with correct escaping). `lastWashed` is injected per
    /// garment id so the engine stays independent of wash-log storage.
    public static func csvSummary(
        garments: [Garment],
        lastWashed: (Int64) -> Date? = { _ in nil }
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        var lines = [csvHeader.map(csvField).joined(separator: ",")]
        for garment in garments {
            let last = garment.id.flatMap(lastWashed).map(formatter.string(from:)) ?? ""
            let row = [
                garment.name,
                garment.category.rawValue,
                garment.fabricNote ?? "",
                garment.careProfile.wash.csvDescription,
                garment.careProfile.bleach.csvDescription,
                garment.careProfile.dry.csvDescription,
                garment.careProfile.iron.csvDescription,
                garment.careProfile.professional.csvDescription,
                last,
            ]
            lines.append(row.map(csvField).joined(separator: ","))
        }
        // CSV requires CRLF line endings per RFC 4180; tests assert this.
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    // MARK: - Restore Execution (Atomic / fail-safe)

    /// Applies a validated restore archive to a CareStore instance in ONE
    /// database transaction — a failure partway through rolls back
    /// everything already written this call (acceptance: "corrupt archives
    /// fail with clear errors and no partial writes"). Uses the internal
    /// GRDB record types directly (same module) rather than nesting calls
    /// through the public repository protocols, which each open their own
    /// `db.write` and are not meant to be called reentrantly from inside
    /// one.
    @discardableResult
    public static func restore(
        archive: CareBackupArchive,
        into store: CareStore
    ) throws -> CareRestorePreview {
        let existing = try store.garments.allGarments()
        let preview = previewRestore(archive: archive, existingGarments: existing)
        let actions = restorePlan(archive: archive, existingGarments: existing)

        // Archive-declared garment id -> live database id, so wash-log
        // entries (which reference the archive's ids) attach correctly
        // whether their garment was inserted, merged, or unchanged. Each
        // action already carries its own archive id directly (not derived
        // from a possibly-ambiguous name+category+timestamp key), so
        // duplicate garments with identical identity keys map correctly.
        var archiveIDToLiveID: [Int64: Int64] = [:]
        var newPhotoFileNames: [String] = []
        var photoFileNamesToDeleteOnSuccess: [String] = []

        do {
            try store.db.write { db in
                for action in actions {
                    switch action {
                    case let .insert(incomingArchiveID, garment, photoData):
                        let createdAt = garment.createdAt ?? Date()
                        let updatedAt = garment.updatedAt ?? createdAt
                        var record = try GarmentRecord(garment, createdAt: createdAt, updatedAt: updatedAt)
                        record.id = nil
                        if let photoData {
                            let newReference = try store.photoStore.restorePhoto(data: photoData)
                            newPhotoFileNames.append(newReference.fileName)
                            record.photoFileName = newReference.fileName
                        }
                        try record.insert(db)
                        if let incomingArchiveID, let newID = record.id {
                            archiveIDToLiveID[incomingArchiveID] = newID
                        }
                    case let .update(incomingArchiveID, id, garment, photoData):
                        guard var record = try GarmentRecord.fetchOne(db, key: id) else {
                            throw CareStoreError.garmentNotFound(id)
                        }
                        let stamp = garment.updatedAt ?? Date()
                        let refreshed = try GarmentRecord(garment, createdAt: record.createdAt, updatedAt: stamp)
                        record.name = refreshed.name
                        record.category = refreshed.category
                        record.fabricNote = refreshed.fabricNote
                        record.careProfileJSON = refreshed.careProfileJSON
                        record.updatedAt = stamp
                        if let photoData {
                            let newReference = try store.photoStore.restorePhoto(data: photoData)
                            newPhotoFileNames.append(newReference.fileName)
                            if let oldFileName = record.photoFileName {
                                photoFileNamesToDeleteOnSuccess.append(oldFileName)
                            }
                            record.photoFileName = newReference.fileName
                        }
                        try record.update(db)
                        if let incomingArchiveID {
                            archiveIDToLiveID[incomingArchiveID] = id
                        }
                    case let .unchanged(incomingArchiveID, id):
                        if let incomingArchiveID {
                            archiveIDToLiveID[incomingArchiveID] = id
                        }
                    }
                }

                for entry in archive.washLog {
                    guard let liveGarmentID = archiveIDToLiveID[entry.garmentID] else {
                        throw CareBackupError.washLogReferencesMissingGarment(entry.garmentID)
                    }
                    var logRecord = WashLogRecord(
                        WashLogEntry(garmentID: liveGarmentID, method: entry.method, loggedAt: entry.loggedAt)
                    )
                    logRecord.id = nil
                    try logRecord.insert(db)
                }
            }
        } catch {
            // SQLite rolled back. Remove every file this attempt created so
            // a failed restore leaves neither rows nor orphaned photos.
            for fileName in newPhotoFileNames {
                try? store.photoStore.deletePhoto(named: fileName)
            }
            throw error
        }

        // The transaction committed. Files staged by this restore are now
        // referenced by live rows; only the OLD photo files superseded by a
        // successful merge are cleaned here. (A rolled-back attempt has
        // already deleted its staged files in the catch block above, so no
        // orphaned photos survive a failed restore.)
        for fileName in photoFileNamesToDeleteOnSuccess {
            try? store.photoStore.deletePhoto(named: fileName)
        }
        return preview
    }

    /// RFC 4180 field escaping: quote a field iff it contains a comma,
    /// quote, or newline, doubling any embedded quotes. Additionally
    /// defuses spreadsheet formula injection (a field beginning with `=`,
    /// `+`, `-`, or `@`) by prefixing a single quote, per OWASP guidance.
    static func csvField(_ raw: String) -> String {
        var field = raw
        if let first = field.first, "=+-@".contains(first) {
            field = "'" + field
        }
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

// MARK: - CSV cap descriptions

extension CareWash {
    var csvDescription: String {
        switch self {
        case .unknown: "Not recorded"
        case .doNotWash: "Do not wash"
        case .handWash: "Hand wash"
        case .machine(let temperature, let action):
            switch action {
            case .normal: temperature.celsiusDescription
            case .permanentPress: "\(temperature.celsiusDescription) permanent press"
            case .gentle: "\(temperature.celsiusDescription) gentle"
            }
        }
    }
}

extension CareBleach {
    var csvDescription: String {
        switch self {
        case .unknown: "Not recorded"
        case .allowed(let kind): kind.rawValue
        case .doNotBleach: "Do not bleach"
        }
    }
}

extension CareDry {
    var csvDescription: String {
        switch self {
        case .unknown: "Not recorded"
        case .tumble(let heat): "Tumble \(heat.rawValue)"
        case .natural(let method): "Natural: \(method.rawValue)"
        }
    }
}

extension CareIron {
    var csvDescription: String {
        switch self {
        case .unknown: "Not recorded"
        case .doNotIron: "Do not iron"
        case .cap(let temperature): temperature.celsiusDescription
        }
    }
}

extension CareProfessional {
    var csvDescription: String {
        switch self {
        case .unknown: "Not recorded"
        case .requires(let kind): "Professional: \(kind.rawValue)"
        case .doNotDryClean: "Do not dry-clean"
        }
    }
}
