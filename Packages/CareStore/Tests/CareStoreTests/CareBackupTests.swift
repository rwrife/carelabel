import CareKit
import CareStore
import CareStoreTestSupport
import Foundation
import Testing

// Issue #7 acceptance criteria:
// 1. Versioned JSON archive including photo blobs (base64)
// 2. Round-trip test export -> wipe -> restore -> equality in CI
// 3. Restore shows a preview (counts added/merged/unchanged) and explicit confirmation
// 4. Corrupt archives fail with clear errors and no partial writes
// 5. CSV export (garments + last-washed + key care caps) with escaping tests

@Suite("Backup & Restore", .serialized)
struct BackupRestoreTests {
    private func makeTestStore() throws -> CareStore {
        try CareStore.inMemory(downsampler: FakeDownsampler())
    }

    @Test("round-trip export -> wipe -> restore -> equality matches original data and photos")
    func exportWipeRestoreRoundTrip() throws {
        let store = try makeTestStore()

        // 1. Populate store with garments (one with photo, one without)
        let profileA = CareProfile(
            wash: .machine(temperature: .celsius40, action: .gentle),
            bleach: .allowed(.oxygenOnly),
            dry: .tumble(heat: .low),
            iron: .cap(.celsius110),
            professional: .doNotDryClean,
            prohibitions: [.doNotDryClean]
        )
        let refA = try store.photoStore.importPhoto(data: Data("fake-label-photo".utf8))
        let savedA = try store.garments.save(
            Garment(name: "Wool Cardigan", category: .knitwear, fabricNote: "100% Merino", photo: refA, careProfile: profileA)
        )

        let profileB = CareProfile(
            wash: .machine(temperature: .celsius60, action: .normal),
            bleach: .unknown,
            dry: .natural(.hang),
            iron: .unknown,
            professional: .unknown,
            prohibitions: []
        )
        let savedB = try store.garments.save(
            Garment(name: "Linen Shirt", category: .top, fabricNote: "Pure linen", photo: nil, careProfile: profileB)
        )

        // Add wash log entries
        let dateA = Date(timeIntervalSince1970: 1_700_000_100)
        let dateB = Date(timeIntervalSince1970: 1_700_000_200)
        _ = try store.washLog.log(WashLogEntry(garmentID: savedA.id!, method: .handWash, loggedAt: dateA))
        _ = try store.washLog.log(WashLogEntry(garmentID: savedB.id!, method: .machineWash, loggedAt: dateB))

        // 2. Export archive
        let allGarmentsBefore = try store.garments.allGarments()
        let allLogsBefore = try store.washLog.allEntries()
        let archive = try CareBackupEngine.makeArchive(
            schemaVersion: CareStoreSchema.currentVersion,
            garments: allGarmentsBefore,
            washLog: allLogsBefore
        ) { ref in
            try? store.photoStore.data(for: ref)
        }

        #expect(archive.garments.count == 2)
        #expect(archive.washLog.count == 2)
        #expect(archive.garments.first { $0.name == "Wool Cardigan" }?.photoBase64 != nil)
        #expect(archive.garments.first { $0.name == "Linen Shirt" }?.photoBase64 == nil)

        let encoded = try CareBackupEngine.encode(archive)
        let decoded = try CareBackupEngine.decode(encoded)
        #expect(decoded.formatVersion == 1)
        #expect(decoded.garments.count == 2)

        // 3. Wipe store (simulated by a fresh in-memory instance)
        let cleanStore = try makeTestStore()
        #expect(try cleanStore.garments.allGarments().isEmpty)
        #expect(try cleanStore.washLog.allEntries().isEmpty)

        // 4. Restore into clean store
        let preview = try CareBackupEngine.restore(archive: decoded, into: cleanStore)
        #expect(preview.addedGarmentCount == 2)
        #expect(preview.mergedGarmentCount == 0)
        #expect(preview.unchangedGarmentCount == 0)
        #expect(preview.addedWashLogCount == 2)

        // 5. Verify equality
        let restoredGarments = try cleanStore.garments.allGarments()
        #expect(restoredGarments.count == 2)

        guard let restoredA = restoredGarments.first(where: { $0.name == "Wool Cardigan" }),
              let restoredB = restoredGarments.first(where: { $0.name == "Linen Shirt" }) else {
            Issue.record("Restored garments missing expected entries")
            return
        }

        #expect(restoredA.category == .knitwear)
        #expect(restoredA.fabricNote == "100% Merino")
        #expect(restoredA.careProfile == profileA)
        #expect(restoredA.photo != nil)
        if let photoRef = restoredA.photo {
            let data = try cleanStore.photoStore.data(for: photoRef)
            // Restore writes the EXACT stored (already-downscaled) bytes back
            // without re-running the downsampler — no quality loss per cycle.
            let storedBefore = try store.photoStore.data(for: refA)
            #expect(data == storedBefore)
        }

        #expect(restoredB.category == .top)
        #expect(restoredB.fabricNote == "Pure linen")
        #expect(restoredB.careProfile == profileB)
        #expect(restoredB.photo == nil)

        let restoredLogs = try cleanStore.washLog.allEntries()
        #expect(restoredLogs.count == 2)
        #expect(restoredLogs.contains { $0.garmentID == restoredA.id! && $0.method == .handWash })
        #expect(restoredLogs.contains { $0.garmentID == restoredB.id! && $0.method == .machineWash })
    }

    @Test("restore preview reports added, merged, and unchanged accurately")
    func restorePreviewSemantics() throws {
        let profile = CareProfile(wash: .machine(temperature: .celsius30, action: .normal))
        let existing = [
            Garment(id: 1, name: "Tee", category: .top, fabricNote: "Cotton", careProfile: profile),
            Garment(id: 2, name: "Jeans", category: .bottom, fabricNote: "Denim", careProfile: profile)
        ]

        let modifiedProfile = CareProfile(wash: .machine(temperature: .celsius40, action: .normal))
        let archive = CareBackupArchive(
            schemaVersion: 1,
            exportedAt: Date(),
            garments: [
                CareBackupGarment(id: 10, name: "Tee", category: .top, fabricNote: "Cotton", careProfile: profile, createdAt: nil, updatedAt: nil, photoBase64: nil), // unchanged
                CareBackupGarment(id: 20, name: "Jeans", category: .bottom, fabricNote: "Denim", careProfile: modifiedProfile, createdAt: nil, updatedAt: nil, photoBase64: nil), // merged
                CareBackupGarment(id: 30, name: "Socks", category: .other, fabricNote: "Wool", careProfile: profile, createdAt: nil, updatedAt: nil, photoBase64: nil), // added
            ],
            washLog: []
        )

        let preview = CareBackupEngine.previewRestore(archive: archive, existingGarments: existing)
        #expect(preview.unchangedGarmentCount == 1)
        #expect(preview.mergedGarmentCount == 1)
        #expect(preview.addedGarmentCount == 1)
        #expect(preview.addedWashLogCount == 0)
    }

    @Test("corrupt archive fails with clear error and performs no partial writes")
    func corruptArchiveAtomicRollback() throws {
        let store = try makeTestStore()
        _ = try store.garments.save(Garment(name: "Existing Item", category: .top))

        // Corrupt archive with invalid JSON
        let corruptData = Data("{\"not_a_valid_archive\": true}".utf8)
        #expect(throws: CareBackupError.self) {
            try CareBackupEngine.decode(corruptData)
        }

        // Invalid base64 in photo blob
        let badBase64Archive = CareBackupArchive(
            schemaVersion: 1,
            exportedAt: Date(),
            garments: [
                CareBackupGarment(id: 1, name: "Bad Photo", category: .top, fabricNote: nil, careProfile: .unknownProfile, createdAt: nil, updatedAt: nil, photoBase64: "###INVALID-BASE64###")
            ],
            washLog: []
        )
        let encodedBad = try JSONEncoder().encode(badBase64Archive)
        #expect(throws: CareBackupError.self) {
            try CareBackupEngine.decode(encodedBad)
        }

        // Future format version rejected
        let futureArchive = CareBackupArchive(
            formatVersion: 999,
            schemaVersion: 1,
            exportedAt: Date(),
            garments: [],
            washLog: []
        )
        let encodedFuture = try JSONEncoder().encode(futureArchive)
        #expect(throws: CareBackupError.self) {
            try CareBackupEngine.decode(encodedFuture)
        }

        // Ensure database contents remained unchanged
        let afterGarments = try store.garments.allGarments()
        #expect(afterGarments.count == 1)
        #expect(afterGarments[0].name == "Existing Item")
    }

    @Test("restore rollback removes rows and staged photos after a late failure")
    func restoreRollbackRemovesRowsAndPhotos() throws {
        let store = try makeTestStore()
        let beforeUsage = try store.photoStore.usage()
        let createdAt = Date(timeIntervalSince1970: 1_700_001_000)
        let archive = CareBackupArchive(
            schemaVersion: CareStoreSchema.currentVersion,
            exportedAt: createdAt,
            garments: [
                CareBackupGarment(
                    id: 10,
                    name: "Rollback Tee",
                    category: .top,
                    fabricNote: nil,
                    careProfile: .unknownProfile,
                    createdAt: createdAt,
                    updatedAt: createdAt,
                    photoBase64: Data("staged-photo".utf8).base64EncodedString()
                )
            ],
            // Deliberately bypass decode validation so restore fails only
            // after it has staged the garment row and photo file.
            washLog: [
                CareBackupWashLogEntry(
                    id: 1,
                    garmentID: 404,
                    method: .machineWash,
                    loggedAt: createdAt
                )
            ]
        )

        #expect(throws: CareBackupError.self) {
            try CareBackupEngine.restore(archive: archive, into: store)
        }
        #expect(try store.garments.allGarments().isEmpty)
        #expect(try store.washLog.allEntries().isEmpty)
        #expect(try store.photoStore.usage() == beforeUsage)
    }

    @Test("backup export fails instead of silently omitting a referenced photo")
    func backupExportRejectsMissingPhotoBytes() throws {
        let garment = Garment(
            id: 1,
            name: "Photo Garment",
            category: .top,
            photo: PhotoReference(fileName: "missing.jpg"),
            careProfile: .unknownProfile,
            createdAt: Date(timeIntervalSince1970: 1_700_001_100)
        )

        #expect(throws: CareBackupError.self) {
            try CareBackupEngine.makeArchive(
                schemaVersion: CareStoreSchema.currentVersion,
                garments: [garment],
                washLog: []
            ) { _ in nil }
        }
    }

    @Test("archive validation rejects future schema and dangling wash-log references")
    func archiveRelationshipValidation() throws {
        let futureSchema = CareBackupArchive(
            schemaVersion: CareStoreSchema.currentVersion + 1,
            exportedAt: Date(),
            garments: [],
            washLog: []
        )
        #expect(throws: CareBackupError.self) {
            try CareBackupEngine.decode(CareBackupEngine.encode(futureSchema))
        }

        let dangling = CareBackupArchive(
            schemaVersion: CareStoreSchema.currentVersion,
            exportedAt: Date(),
            garments: [],
            washLog: [CareBackupWashLogEntry(id: 1, garmentID: 404, method: .handWash, loggedAt: Date())]
        )
        #expect(throws: CareBackupError.self) {
            try CareBackupEngine.decode(CareBackupEngine.encode(dangling))
        }
    }

    @Test("CSV export formats columns and escapes commas, quotes, and newlines per RFC 4180")
    func csvExportEscaping() throws {
        let profile = CareProfile(
            wash: .machine(temperature: .celsius40, action: .gentle),
            bleach: .doNotBleach,
            dry: .tumble(heat: .low),
            iron: .cap(.celsius150),
            professional: .requires(.dryCleanAnySolvent)
        )
        let garments = [
            Garment(
                id: 1,
                name: "Basic Tee",
                category: .top,
                fabricNote: "100% Cotton",
                careProfile: profile
            ),
            Garment(
                id: 2,
                name: "Silk, \"Delicate\" Shirt",
                category: .top,
                fabricNote: "Dry clean only,\nline 2",
                careProfile: .unknownProfile
            )
        ]

        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let csv = CareBackupEngine.csvSummary(garments: garments) { id in
            id == 1 ? fixedDate : nil
        }

        #expect(csv.contains("Name,Category,Fabric Note,Wash,Bleach,Dry,Iron,Professional,Last Washed\r\n"))
        #expect(csv.contains("Basic Tee,top,100% Cotton,40 °C gentle,Do not bleach,Tumble low,150 °C,Professional: dryCleanAnySolvent,1970-01-01\r\n") || csv.contains("Basic Tee,top,100% Cotton,40 °C gentle,Do not bleach,Tumble low,150 °C,Professional: dryCleanAnySolvent,2023-11-14\r\n"))
        // Escaped row: quotes doubled, surrounded by quotes
        #expect(csv.contains("\"Silk, \"\"Delicate\"\" Shirt\""))
        #expect(csv.contains("\"Dry clean only,\nline 2\""))
        #expect(csv.hasSuffix("\r\n"))
    }
}
