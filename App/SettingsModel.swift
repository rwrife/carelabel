import CareStore
import Foundation
import Observation

/// Local-only data ownership operations for Settings. The model prepares
/// user-initiated files for the system share sheet and keeps restore as a
/// two-step preview/confirm operation.
@MainActor
@Observable
final class SettingsModel {
    private let store: CareStore

    var backupURL: URL?
    var csvURL: URL?
    var restorePreview: CareRestorePreview?
    var lastError: String?
    var statusMessage: String?
    var storageUsage = PhotoStore.Usage(fileCount: 0, totalBytes: 0)

    private var pendingArchive: CareBackupArchive?

    init(store: CareStore) {
        self.store = store
        refreshStorageUsage()
    }

    func prepareBackup() {
        do {
            let garments = try store.garments.allGarments()
            let entries = try store.washLog.allEntries()
            let archive = try CareBackupEngine.makeArchive(
                schemaVersion: CareStoreSchema.currentVersion,
                garments: garments,
                washLog: entries
            ) { reference in
                try? store.photoStore.data(for: reference)
            }
            let url = try exportURL(named: "CareLabel-backup.json")
            try CareBackupEngine.encode(archive).write(to: url, options: .atomic)
            backupURL = url
            statusMessage = "Backup ready to share."
            lastError = nil
        } catch {
            fail("Could not create the backup", error: error)
        }
    }

    func prepareCSV() {
        do {
            let garments = try store.garments.allGarments()
            let entries = try store.washLog.allEntries()
            let lastWashedByGarment: [Int64: Date] = Dictionary(grouping: entries, by: \.garmentID)
                .compactMapValues { rows in rows.map(\.loggedAt).max() }
            let csv = CareBackupEngine.csvSummary(garments: garments) { id in
                lastWashedByGarment[id]
            }
            let url = try exportURL(named: "CareLabel-garments.csv")
            try Data(csv.utf8).write(to: url, options: .atomic)
            csvURL = url
            statusMessage = "CSV ready to share."
            lastError = nil
        } catch {
            fail("Could not create the CSV export", error: error)
        }
    }

    /// Reads and validates an archive, then computes a preview only. No store
    /// writes happen until the user calls `confirmRestore()` from the explicit
    /// confirmation dialog.
    func previewRestore(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let archive = try CareBackupEngine.decode(Data(contentsOf: url))
            let existing = try store.garments.allGarments()
            pendingArchive = archive
            restorePreview = CareBackupEngine.previewRestore(
                archive: archive,
                existingGarments: existing
            )
            statusMessage = nil
            lastError = nil
        } catch {
            pendingArchive = nil
            restorePreview = nil
            fail("Could not read this backup", error: error)
        }
    }

    func cancelRestore() {
        pendingArchive = nil
        restorePreview = nil
    }

    func confirmRestore() {
        guard let archive = pendingArchive else { return }
        do {
            let result = try CareBackupEngine.restore(archive: archive, into: store)
            pendingArchive = nil
            restorePreview = nil
            refreshStorageUsage()
            statusMessage = "Restore complete: \(result.addedGarmentCount) added, \(result.mergedGarmentCount) merged, \(result.unchangedGarmentCount) unchanged."
            lastError = nil
        } catch {
            // CareBackupEngine restores inside one SQLite transaction and
            // removes staged photo files on rollback.
            pendingArchive = nil
            restorePreview = nil
            fail("Nothing was restored", error: error)
        }
    }

    func refreshStorageUsage() {
        do {
            storageUsage = try store.photoStore.usage()
        } catch {
            fail("Could not read photo storage usage", error: error)
        }
    }

    private func exportURL(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CareLabel-Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name, isDirectory: false)
    }

    private func fail(_ context: String, error: Error) {
        let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        lastError = "\(context). \(detail)"
        statusMessage = nil
    }
}
