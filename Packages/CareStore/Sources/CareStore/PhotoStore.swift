import CareKit
import Foundation

// Issue #4: the photo store.
//
// Promises enforced here (CareContract.swift `CarePhotoLimits`):
// - Imported images are downscaled so their longest edge is at most
//   `maximumPhotoDimensionPoints` (1600) and stored as JPEG;
// - Originals are NOT retained — the store only ever writes the downscaled
//   copy, callers pass raw data and receive a `PhotoReference`;
// - Everything lives under one container-relative directory; the database
//   only stores file names, so paths never leave the container;
// - Usage is queryable (file count + byte count) for the user-visible
//   storage view.

/// Downscales `data` so its longest edge is at most `maximumDimension` and
/// returns JPEG bytes. Pure image-processing seam; the app target injects a
/// UIImage-backed implementation, tests inject a deterministic fake — the
/// package itself must not depend on UIKit so it stays testable on Linux.
public protocol PhotoDownsampler: Sendable {
    /// - Returns: encoded image data whose longest edge is <= `maximumDimension`.
    func downscale(imageData: Data, maximumDimension: Int) throws -> Data
}

public struct PhotoStore: Sendable {
    /// Fixed maximum dimension applied to every import. The documented
    /// constant lives in CareKit (`CarePhotoLimits.maximumPhotoDimensionPoints`).
    public static let maximumPhotoDimensionPoints: Int = CarePhotoLimits.maximumPhotoDimensionPoints

    public enum PhotoStoreError: Error, Equatable, Sendable {
        case unsafeFileName(String)
        case fileAlreadyExists(String)
        case fileNotFound(String)
    }

    public let directory: URL
    private let downsampler: any PhotoDownsampler

    public init(directory: URL, downsampler: any PhotoDownsampler) {
        self.directory = directory
        self.downsampler = downsampler
    }

    /// Imports raw image bytes: downscales to the fixed maximum dimension,
    /// writes a uniquely named JPEG, and returns the DB-safe file name.
    /// The caller must discard the original bytes — nothing here keeps them.
    @discardableResult
    public func importPhoto(data: Data) throws -> PhotoReference {
        let downscaled = try downsampler.downscale(
            imageData: data,
            maximumDimension: Self.maximumPhotoDimensionPoints
        )
        let fileName = "photo-\(UUID().uuidUpperCaseCompact).jpg"
        let url = try fileURL(named: fileName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try downscaled.write(to: url, options: .withoutOverwriting)
        return PhotoReference(fileName: fileName)
    }

    public func data(for reference: PhotoReference) throws -> Data {
        let url = try fileURL(named: reference.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CareStoreError.missingPhoto(reference.fileName)
        }
        return try Data(contentsOf: url)
    }

    public func deletePhoto(named fileName: String) throws {
        let url = try fileURL(named: fileName)
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            throw PhotoStoreError.fileNotFound(fileName)
        }
    }

    public func photoExists(named fileName: String) throws -> Bool {
        FileManager.default.fileExists(atPath: try fileURL(named: fileName).path)
    }

    /// Queryable storage usage: file count and total bytes.
    public struct Usage: Equatable, Sendable {
        public var fileCount: Int
        public var totalBytes: Int

        public init(fileCount: Int, totalBytes: Int) {
            self.fileCount = fileCount
            self.totalBytes = totalBytes
        }
    }

    public func usage() throws -> Usage {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        )
        var count = 0
        var bytes = 0
        for url in contents ?? [] {
            count += 1
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            bytes += values?.fileSize ?? 0
        }
        return Usage(fileCount: count, totalBytes: bytes)
    }

    /// Maps a requested name to a URL inside the store directory, rejecting
    /// anything that is not a plain safe file name (no path escape).
    public func fileURL(named fileName: String) throws -> URL {
        let reference = PhotoReference(fileName: fileName)
        guard reference.isSafeFileName else {
            throw PhotoStoreError.unsafeFileName(fileName)
        }
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }
}

extension UUID {
    /// UUID without dashes, uppercase — safe as a file name fragment.
    var uuidUpperCaseCompact: String {
        uuidString.replacingOccurrences(of: "-", with: "").uppercased()
    }
}
