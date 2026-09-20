import CareKit
import Foundation

// Issue #4: domain-facing persistence models.
//
// These structs are what features (issues #5/#6) and tests talk to. They map
// one-to-one onto GRDB records (see CareStoreRecords.swift); the care profile
// itself is CareKit's `CareProfile`, serialized losslessly as JSON.

/// High-level wardrobe category for a registry garment.
/// Raw values are stored in the database — never rename one in place; add a
/// new case and map the old value in a migration if the taxonomy changes.
public enum GarmentCategory: String, Codable, Equatable, Sendable, CaseIterable {
    case top
    case bottom
    case dress
    case outerwear
    case knitwear
    case activewear
    case undergarment
    case accessory
    case other
}

/// The care event recorded by a wash-log entry.
/// Raw-value rules match `GarmentCategory`: additive changes only.
public enum WashMethod: String, Codable, Equatable, Sendable, CaseIterable {
    case machineWash
    case handWash
    case dryClean
    case professionalWetClean
}

/// A photo kept in the photo store, referenced by file name only so the
/// database never stores absolute container paths (the app container path
/// can change between installs; file names are container-relative).
public struct PhotoReference: Codable, Equatable, Sendable, Hashable {
    public var fileName: String

    public init(fileName: String) {
        self.fileName = fileName
    }

    /// Rejects anything that is not a single plain file name so a reference
    /// can never escape the photo directory via path components.
    public var isSafeFileName: Bool {
        !fileName.isEmpty
            && fileName != "."
            && fileName != ".."
            && !fileName.contains("/")
            && !fileName.contains("\\")
            && fileName.count <= 128
    }
}

/// One garment in the registry (issue #4 acceptance: name, category, fabric
/// note, photo reference, care profile, created/updated timestamps).
public struct Garment: Codable, Equatable, Sendable, Identifiable {
    /// `nil` until the garment has been saved once.
    public var id: Int64?
    public var name: String
    public var category: GarmentCategory
    public var fabricNote: String?
    public var photo: PhotoReference?
    public var careProfile: CareProfile
    /// `nil` until the repository stamps it (insert/update time).
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: Int64? = nil,
        name: String,
        category: GarmentCategory,
        fabricNote: String? = nil,
        photo: PhotoReference? = nil,
        careProfile: CareProfile = .unknownProfile,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.fabricNote = fabricNote
        self.photo = photo
        self.careProfile = careProfile
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// One wash/clean event for one garment (issue #4 acceptance: garment id,
/// method, date).
public struct WashLogEntry: Codable, Equatable, Sendable, Identifiable {
    /// `nil` until the repository stamps it.
    public var id: Int64?
    public var garmentID: Int64
    public var method: WashMethod
    public var loggedAt: Date

    public init(id: Int64? = nil, garmentID: Int64, method: WashMethod, loggedAt: Date) {
        self.id = id
        self.garmentID = garmentID
        self.method = method
        self.loggedAt = loggedAt
    }
}
