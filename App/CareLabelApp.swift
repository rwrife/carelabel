import CareKit
import CareStore
import SwiftUI

@main
struct CareLabelApp: App {
    /// True under the UI-test launch argument. UI tests need a deterministic
    /// world, so the app wipes its own container at launch in that mode
    /// (test-only; never true for end users).
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")

    /// Issue #4: the app-private store. Opened lazily on first use; features
    /// in issues #5/#6 reach the registry and wash log through this seam.
    static let store: CareStore = {
        if isUITesting {
            wipeContainerForUITesting()
        }
        do {
            return try CareStore.open(
                containerDirectory: CareStoreContainer.defaultContainerDirectory(),
                downsampler: UIKitPhotoDownsampler()
            )
        } catch {
            // A broken store must never crash launch during the bootstrap
            // milestone; surface in diagnostics and let the store rebuild
            // on next launch (SQLite is WAL-safe for crash recovery).
            NSLog("CareStore open failed: \(error)")
            return try! CareStore.inMemory(downsampler: UIKitPhotoDownsampler())
        }
    }()

    /// Test-only: removes the SQLite file and photo directory so every UI
    /// test run starts from an empty registry. Guarded by `isUITesting`.
    private static func wipeContainerForUITesting() {
        let directory = CareStoreContainer.defaultContainerDirectory()
        try? FileManager.default.removeItem(at: directory)
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

/// Root view: hosts the registry (issue #5) and injects the photo-store
/// reader the list/detail thumbnails read through.
struct AppRootView: View {
    var body: some View {
        NavigationStack {
            GarmentRegistryView(store: CareLabelApp.store)
        }
        .onAppear {
            RegistryThumbnailCache.shared.reader = { fileName in
                try? CareLabelApp.store.photoStore.data(for: PhotoReference(fileName: fileName))
            }
        }
    }
}
