import CareKit
import CareStore
import CareStoreTestSupport
import Foundation
import GRDB
import Testing

// Issue #4: repository behavior over the shared protocols, exercised on BOTH
// the GRDB implementation and the in-memory fakes so the fake's semantics
// stay pinned to the real one (and #5/#6 tests can trust the fakes).

enum RepoKind: String, CaseIterable, Sendable {
    case grdb
    case inMemory

    func pair() throws -> (any GarmentRepository, any WashLogRepository) {
        switch self {
        case .grdb:
            let store = try CareStore.inMemory(downsampler: FakeDownsampler())
            return (store.garments, store.washLog)
        case .inMemory:
            let garments = InMemoryGarmentRepository()
            return (garments, InMemoryWashLogRepository(garments: garments))
        }
    }
}

/// GRDB persists `Date` as ISO8601 TEXT with millisecond precision, so
/// timestamp equality after a round trip must be tolerance-based.
private func sameTimestamp(_ lhs: Date?, _ rhs: Date?) -> Bool {
    guard let lhs, let rhs else { return lhs == rhs }
    return abs(lhs.timeIntervalSince(rhs)) < 1.0
}

private func sampleProfile() -> CareProfile {
    CareProfile()
        .applying([
            .machineWash(temperature: .celsius40, action: .normal),
            .noBleach,
            .naturalDry(.flat),
            .ironCap(.celsius150),
            .professionalRequires(.hydrocarbon),
            .noTumbleDry,
        ])
}

@Suite("Garment repository CRUD", .serialized)
struct GarmentRepositoryTests {
    @Test("save assigns id and timestamps, round-trips every field", arguments: RepoKind.allCases)
    func saveAndFetch(_ kind: RepoKind) throws {
        let (garments, _) = try kind.pair()
        let saved = try garments.save(
            Garment(
                name: "Merino Crew",
                category: .knitwear,
                fabricNote: "100% merino",
                photo: PhotoReference(fileName: "IMG_1.jpg"),
                careProfile: sampleProfile()
            )
        )
        #expect(saved.id != nil, Comment("\(rawValue(kind))"))
        #expect(saved.createdAt != nil)
        #expect(saved.updatedAt != nil)

        let fetched = try #require(try garments.garment(id: saved.id!))
        #expect(fetched.name == "Merino Crew")
        #expect(fetched.category == .knitwear)
        #expect(fetched.fabricNote == "100% merino")
        #expect(fetched.photo == PhotoReference(fileName: "IMG_1.jpg"))
        #expect(fetched.careProfile == sampleProfile())
        #expect(sameTimestamp(fetched.createdAt, saved.createdAt))
        #expect(sameTimestamp(fetched.updatedAt, saved.updatedAt))
    }

    @Test("update refreshes fields and updatedAt, keeps createdAt", arguments: RepoKind.allCases)
    func update(_ kind: RepoKind) throws {
        let (garments, _) = try kind.pair()
        let saved = try garments.save(Garment(name: "Old Name", category: .top))
        Thread.sleep(forTimeInterval: 0.01)
        var modified = saved
        modified.name = "New Name"
        modified.category = .outerwear
        modified.careProfile = sampleProfile()
        let updated = try garments.update(modified)

        #expect(updated.name == "New Name")
        #expect(updated.category == .outerwear)
        #expect(updated.careProfile == sampleProfile())
        #expect(sameTimestamp(updated.createdAt, saved.createdAt))
        #expect((updated.updatedAt ?? .distantPast) >= (saved.updatedAt ?? .distantPast))

        let fetched = try #require(try garments.garment(id: saved.id!))
        #expect(fetched.name == "New Name")
    }

    @Test("update of a missing garment throws garmentNotFound", arguments: RepoKind.allCases)
    func updateMissing(_ kind: RepoKind) throws {
        let (garments, _) = try kind.pair()
        let ghost = Garment(id: 9999, name: "Ghost", category: .other)
        #expect(throws: CareStoreError.garmentNotFound(9999)) {
            try garments.update(ghost)
        }
    }

    @Test("list is ordered most-recently-updated first", arguments: RepoKind.allCases)
    func ordering(_ kind: RepoKind) throws {
        let (garments, _) = try kind.pair()
        let first = try garments.save(Garment(name: "First", category: .top))
        Thread.sleep(forTimeInterval: 0.01)
        _ = try garments.save(Garment(name: "Second", category: .bottom))
        Thread.sleep(forTimeInterval: 0.01)
        _ = try garments.update(Garment(
            id: first.id,
            name: "First touched",
            category: .top,
            createdAt: first.createdAt,
            updatedAt: first.updatedAt
        ))
        let all = try garments.allGarments()
        #expect(all.map(\.name) == ["First touched", "Second"])
    }

    @Test("delete removes the garment", arguments: RepoKind.allCases)
    func delete(_ kind: RepoKind) throws {
        let (garments, _) = try kind.pair()
        let saved = try garments.save(Garment(name: "Doomed", category: .accessory))
        try garments.delete(id: saved.id!)
        #expect(try garments.garment(id: saved.id!) == nil)
    }
}

@Suite("Wash log repository", .serialized)
struct WashLogRepositoryTests {
    @Test("log requires an existing garment", arguments: RepoKind.allCases)
    func foreignKey(_ kind: RepoKind) throws {
        let (_, washLog) = try kind.pair()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(throws: CareStoreError.garmentNotFound(4242)) {
            try washLog.log(WashLogEntry(garmentID: 4242, method: .machineWash, loggedAt: date))
        }
    }

    @Test("entries per garment are newest-first; allEntries spans garments", arguments: RepoKind.allCases)
    func queries(_ kind: RepoKind) throws {
        let (garments, washLog) = try kind.pair()
        let a = try garments.save(Garment(name: "A", category: .top))
        let b = try garments.save(Garment(name: "B", category: .bottom))
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        try washLog.log(WashLogEntry(garmentID: a.id!, method: .machineWash, loggedAt: base.addingTimeInterval(2)))
        try washLog.log(WashLogEntry(garmentID: a.id!, method: .dryClean, loggedAt: base.addingTimeInterval(5)))
        try washLog.log(WashLogEntry(garmentID: b.id!, method: .handWash, loggedAt: base.addingTimeInterval(1)))

        let forA = try washLog.entries(for: a.id!)
        #expect(forA.count == 2)
        #expect(forA.first?.method == .dryClean)
        #expect(forA.allSatisfy { $0.garmentID == a.id })
        #expect(forA.allSatisfy { $0.id != nil })

        let all = try washLog.allEntries()
        #expect(all.count == 3)
        #expect(Set(all.map(\.garmentID)) == Set([a.id!, b.id!]))
        #expect(all.map(\.loggedAt) == all.map(\.loggedAt).sorted(by: >))
    }
}

@Suite("Database-level guarantees", .serialized)
struct DatabaseGuaranteeTests {
    @Test("foreign keys are enforced directly at the SQL level")
    func sqliteForeignKey() throws {
        let store = try CareStore.inMemory(downsampler: FakeDownsampler())
        #expect(throws: (any Error).self) {
            try store.db.write { writer in
                try writer.execute(
                    sql: "INSERT INTO wash_log (garment_id, method, logged_at) VALUES (99, 'machineWash', ?)",
                    arguments: [Date()]
                )
            }
        }
    }

    @Test("deleting a garment cascades to wash_log rows", arguments: [true])
    func cascadeAtSQLLevel(_ _: Bool) throws {
        let store = try CareStore.inMemory(downsampler: FakeDownsampler())
        let saved = try store.garments.save(Garment(name: "Cascade", category: .top))
        try store.washLog.log(WashLogEntry(
            garmentID: saved.id!,
            method: .machineWash,
            loggedAt: Date(timeIntervalSince1970: 1_750_000_000)
        ))
        let before = try store.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM wash_log") ?? -1 }
        #expect(before == 1)
        try store.garments.delete(id: saved.id!)
        let after = try store.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM wash_log") ?? -1 }
        #expect(after == 0)
    }

    @Test("a corrupt care_profile_json surfaces as corruptCareProfile, not a default")
    func corruptProfile() throws {
        let store = try CareStore.inMemory(downsampler: FakeDownsampler())
        let stamp = Date(timeIntervalSince1970: 1_760_000_000)
        try store.db.write { writer in
            try writer.execute(
                sql: """
                INSERT INTO garment (id, name, category, care_profile_json, created_at, updated_at)
                VALUES (1, 'Broken', 'top', ?, ?, ?)
                """,
                arguments: ["{ not json", stamp, stamp]
            )
        }
        var caught: CareStoreError?
        do {
            _ = try store.garments.garment(id: 1)
        } catch let error as CareStoreError {
            caught = error
        }
        if case .some(.corruptCareProfile(let id, _)) = caught {
            #expect(id == 1)
        } else {
            Issue.record("expected corruptCareProfile, got \(String(describing: caught))")
        }
    }

    @Test("unknown stored category reads back as .other instead of crashing")
    func unknownCategory() throws {
        let store = try CareStore.inMemory(downsampler: FakeDownsampler())
        let stamp = Date(timeIntervalSince1970: 1_760_000_000)
        // A valid encoded CareProfile (unknown) paired with a category raw
        // value a future app version might add.
        let profileJSON = String(
            decoding: try JSONEncoder().encode(CareProfile.unknownProfile),
            as: UTF8.self
        )
        try store.db.write { writer in
            try writer.execute(
                sql: """
                INSERT INTO garment (id, name, category, care_profile_json, created_at, updated_at)
                VALUES (1, 'Time Traveler', 'hologarment', ?, ?, ?)
                """,
                arguments: [profileJSON, stamp, stamp]
            )
        }
        let garment = try #require(try store.garments.garment(id: 1))
        #expect(garment.category == .other)
        #expect(garment.careProfile == .unknownProfile)
    }
}

private func rawValue(_ kind: RepoKind) -> String { kind.rawValue }
