import CareKit
import CareStore
import CareStoreTestSupport
import Foundation
import Testing

// Issue #4: photo store — fixed downscale promise, no originals, safe file
// names, and queryable usage.

@Suite("Photo store", .serialized)
struct PhotoStoreTests {
    private func tempStore(downsampler: any PhotoDownsampler = FakeDownsampler()) throws -> (PhotoStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CareStore-photos-\(UUID().uuidString)", isDirectory: true)
        return (PhotoStore(directory: directory, downsampler: downsampler), directory)
    }

    @Test("fixed maximum dimension matches the documented CareKit promise")
    func maximumDimension() {
        #expect(PhotoStore.maximumPhotoDimensionPoints == 1_600)
        #expect(PhotoStore.maximumPhotoDimensionPoints == CarePhotoLimits.maximumPhotoDimensionPoints)
    }

    @Test("the downsampler is invoked with the fixed maximum dimension")
    func downsamplerSeesTheCap() throws {
        // Capturing fake with a lock-protected box (suite-safe).
        struct Capturing: PhotoDownsampler {
            let box = CapturedBox()
            func downscale(imageData: Data, maximumDimension: Int) throws -> Data {
                box.values.append(maximumDimension)
                return Data("out".utf8)
            }
        }
        final class CapturedBox: @unchecked Sendable {
            let lock = NSLock()
            var values: [Int] = []
            var recorded: [Int] {
                lock.lock(); defer { lock.unlock() }
                return values
            }
        }
        let capture = Capturing()
        let (store, directory) = try tempStore(downsampler: capture)
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try store.importPhoto(data: Data("huge-original".utf8))
        #expect(capture.box.recorded == [PhotoStore.maximumPhotoDimensionPoints])
    }

    @Test("import writes downscaled bytes only; originals are never stored")
    func originalsNotRetained() throws {
        let (store, directory) = try tempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = Data(repeating: 0xAB, count: 1_000_000)  // pretend raw capture
        let reference = try store.importPhoto(data: original)
        #expect(reference.isSafeFileName)
        #expect(reference.fileName.hasSuffix(".jpg"))

        let stored = try store.data(for: reference)
        // Stored bytes are the FAKE downscaled output, not the original.
        #expect(stored == Data("jpeg-fake".utf8))
        #expect(stored != original)

        // Nothing else was written into the store directory.
        let usage = try store.usage()
        #expect(usage.fileCount == 1)
        #expect(usage.totalBytes == stored.count)
    }

    @Test("usage is queryable and grows/shrinks with imports and deletes")
    func usageAccounting() throws {
        let small = FakeDownsampler(outputBytes: Array("ab".utf8))
        let big = FakeDownsampler(outputBytes: Array(repeating: UInt8(ascii: "x"), count: 4_096))

        let (smallStore, smallDir) = try tempStore(downsampler: small)
        let (bigStore, bigDir) = try tempStore(downsampler: big)
        defer {
            try? FileManager.default.removeItem(at: smallDir)
            try? FileManager.default.removeItem(at: bigDir)
        }

        #expect(try smallStore.usage() == PhotoStore.Usage(fileCount: 0, totalBytes: 0))
        let first = try smallStore.importPhoto(data: Data("a".utf8))
        #expect(try smallStore.usage() == PhotoStore.Usage(fileCount: 1, totalBytes: 2))
        _ = try bigStore.importPhoto(data: Data("b".utf8))
        #expect(try bigStore.usage() == PhotoStore.Usage(fileCount: 1, totalBytes: 4_096))

        try smallStore.deletePhoto(named: first.fileName)
        #expect(try smallStore.usage() == PhotoStore.Usage(fileCount: 0, totalBytes: 0))
    }

    @Test("path-escape file names are rejected everywhere")
    func unsafeNamesRejected() throws {
        let (store, directory) = try tempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        for name in ["../etc/passwd", "a/b.jpg", "..", "", ".hidden/../../x"] {
            let reference = PhotoReference(fileName: name)
            #expect(!reference.isSafeFileName, Comment("should reject \(name)"))
            #expect(throws: PhotoStore.PhotoStoreError.unsafeFileName(name)) {
                try store.fileURL(named: name)
            }
        }
        #expect(throws: (any Error).self) {
            try store.data(for: PhotoReference(fileName: "missing.jpg"))
        }
    }

    @Test("deleting a garment removes its photo file end-to-end")
    func garmentDeleteRemovesPhoto() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CareStore-e2e-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CareStore.open(containerDirectory: directory, downsampler: FakeDownsampler())

        let photo = try store.photoStore.importPhoto(data: Data("raw".utf8))
        let saved = try store.garments.save(Garment(name: "Photo Tee", category: .top, photo: photo))
        #expect(try store.photoStore.photoExists(named: photo.fileName))

        try store.garments.delete(id: saved.id!)
        #expect(try store.photoStore.photoExists(named: photo.fileName) == false)
        #expect(try store.photoStore.usage() == PhotoStore.Usage(fileCount: 0, totalBytes: 0))
    }
}
