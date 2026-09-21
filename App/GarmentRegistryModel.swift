import CareKit
import CareStore
import Foundation
import Observation

// Issue #5: observable state for the garment registry.
//
// The view layer never talks to GRDB directly — everything routes through
// this model over the `CareStore` seam established by issue #4. Repository
// calls are synchronous, local, app-private SQLite work (zero-network MVP).

@MainActor
@Observable
final class GarmentRegistryModel {
    private let store: CareStore

    /// Registry, most-recently-updated first (repository ordering).
    var garments: [Garment] = []

    /// Active search text (matches name or category display name).
    var searchText: String = ""

    /// Last user-visible failure message; nil when healthy.
    var lastError: String?

    init(store: CareStore) {
        self.store = store
        reload()
    }

    /// Registry filtered by `searchText` on name or category, case-insensitive.
    var filteredGarments: [Garment] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return garments }
        return garments.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.category.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    func reload() {
        do {
            garments = try store.garments.allGarments()
            lastError = nil
        } catch {
            lastError = "Could not load the registry: \(error)"
        }
    }

    /// Inserts (id == nil) or updates (id != nil) a garment; returns the
    /// persisted value, or nil when the store rejected the write.
    @discardableResult
    func save(_ garment: Garment) -> Garment? {
        do {
            let saved = try garment.id == nil
                ? store.garments.save(garment)
                : store.garments.update(garment)
            reload()
            return saved
        } catch {
            lastError = "Could not save the garment: \(error)"
            return nil
        }
    }

    /// Documented delete rule (issue #4 repository contract, PLAN.md):
    /// removing a garment cascades its wash-log entries and deletes its
    /// label photo file, so no orphaned photos or logs survive.
    func delete(_ garment: Garment) {
        guard let id = garment.id else {
            reload()
            return
        }
        do {
            try store.garments.delete(id: id)
            reload()
        } catch {
            lastError = "Could not delete the garment: \(error)"
        }
    }

    /// Imports raw image bytes into the app-private photo store (downscaled,
    /// originals not retained — issue #4 promise). Returns nil on failure.
    func importPhoto(_ data: Data) -> PhotoReference? {
        do {
            return try store.photoStore.importPhoto(data: data)
        } catch {
            lastError = "Could not store the label photo: \(error)"
            return nil
        }
    }

    func photoData(named fileName: String) -> Data? {
        try? store.photoStore.data(for: PhotoReference(fileName: fileName))
    }

    /// Removes a photo file that is no longer referenced by any garment
    /// (used when the user removes a photo and then saves the edit).
    func deleteUnreferencedPhoto(named fileName: String) {
        let stillReferenced = garments.contains { $0.photo?.fileName == fileName }
        guard !stillReferenced else { return }
        try? store.photoStore.deletePhoto(named: fileName)
    }
}

// MARK: - Display helpers (kept out of the packages so stored raw values
// never drift with presentation wording)

extension GarmentCategory {
    var displayName: String {
        switch self {
        case .top: "Top"
        case .bottom: "Bottom"
        case .dress: "Dress"
        case .outerwear: "Outerwear"
        case .knitwear: "Knitwear"
        case .activewear: "Activewear"
        case .undergarment: "Undergarment"
        case .accessory: "Accessory"
        case .other: "Other"
        }
    }
}

extension CareProfile {
    /// How many of the five care axes record information (unknown excluded).
    var recordedAxisCount: Int {
        var count = 0
        if wash != .unknown { count += 1 }
        if bleach != .unknown { count += 1 }
        if dry != .unknown { count += 1 }
        if iron != .unknown { count += 1 }
        if professional != .unknown { count += 1 }
        return count
    }
}
