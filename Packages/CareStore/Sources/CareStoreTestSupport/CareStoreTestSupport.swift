import CareKit
import CareStore
import Foundation

// Issue #4: in-memory fakes so features and tests use repository protocols
// without a database (acceptance criterion: "Repository protocols so
// features and tests use in-memory fakes").
//
// Lock-protected classes rather than actors: the repository protocols are
// synchronous (GRDB's read/write are synchronous), so the fakes must be too.

/// In-memory garment repository with the same semantics as the GRDB one
/// (auto ids, timestamp stamps).
public final class InMemoryGarmentRepository: GarmentRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var garments: [Int64: Garment] = [:]
    private var nextID: Int64 = 1

    public init() {}

    public func save(_ garment: Garment) throws -> Garment {
        lock.lock(); defer { lock.unlock() }
        var garment = garment
        garment.id = nextID
        nextID += 1
        let stamp = Date()
        garment.createdAt = stamp
        garment.updatedAt = stamp
        garments[garment.id!] = garment
        return garment
    }

    public func update(_ garment: Garment) throws -> Garment {
        lock.lock(); defer { lock.unlock() }
        guard let id = garment.id, garments[id] != nil else {
            throw CareStoreError.garmentNotFound(garment.id ?? -1)
        }
        var garment = garment
        garment.createdAt = garments[id]?.createdAt
        garment.updatedAt = Date()
        garments[id] = garment
        return garment
    }

    public func garment(id: Int64) throws -> Garment? {
        lock.lock(); defer { lock.unlock() }
        return garments[id]
    }

    public func allGarments() throws -> [Garment] {
        lock.lock(); defer { lock.unlock() }
        return garments.values.sorted {
            ($0.updatedAt ?? .distantPast, $0.id ?? 0) > ($1.updatedAt ?? .distantPast, $1.id ?? 0)
        }
    }

    public func delete(id: Int64) throws {
        lock.lock(); defer { lock.unlock() }
        garments[id] = nil
    }

    /// Sync existence check used by `InMemoryWashLogRepository` to mirror
    /// foreign-key rejection (separate lock — no deadlock).
    func contains(garmentID: Int64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return garments[garmentID] != nil
    }

    // Test helper (not part of the protocol).
    public func storedGarmentCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return garments.count
    }
}

/// In-memory wash-log repository with cascade semantics matching the GRDB
/// implementation. Call `cascadeDelete(for:)` after deleting a garment, or
/// construct via `wired(to:)` which wraps garment deletion automatically.
public final class InMemoryWashLogRepository: WashLogRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [WashLogEntry] = []
    private var nextID: Int64 = 1
    private let garments: InMemoryGarmentRepository

    public init(garments: InMemoryGarmentRepository) {
        self.garments = garments
    }

    public func log(_ entry: WashLogEntry) throws -> WashLogEntry {
        guard garments.contains(garmentID: entry.garmentID) else {
            throw CareStoreError.garmentNotFound(entry.garmentID)
        }
        lock.lock(); defer { lock.unlock() }
        var entry = entry
        entry.id = nextID
        nextID += 1
        entries.append(entry)
        return entry
    }

    /// Mirrors the GRDB ON DELETE CASCADE behavior.
    public func cascadeDelete(for garmentID: Int64) {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll { $0.garmentID == garmentID }
    }

    public func entries(for garmentID: Int64) throws -> [WashLogEntry] {
        lock.lock(); defer { lock.unlock() }
        return entries
            .filter { $0.garmentID == garmentID }
            .sorted { ($0.loggedAt, $0.id ?? 0) > ($1.loggedAt, $1.id ?? 0) }
    }

    public func allEntries() throws -> [WashLogEntry] {
        lock.lock(); defer { lock.unlock() }
        return entries.sorted { ($0.loggedAt, $0.id ?? 0) > ($1.loggedAt, $1.id ?? 0) }
    }
}

/// Deterministic fake downsampler: returns fixed bytes without touching an
/// image codec, so photo-store tests run everywhere and assert exact usage.
public struct FakeDownsampler: PhotoDownsampler {
    let outputBytes: [UInt8]

    public init(outputBytes: [UInt8] = Array("jpeg-fake".utf8)) {
        self.outputBytes = outputBytes
    }

    public func downscale(imageData: Data, maximumDimension: Int) throws -> Data {
        Data(outputBytes)
    }
}
