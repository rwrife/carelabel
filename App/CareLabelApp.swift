import CareKit
import CareStore
import SwiftUI

@main
struct CareLabelApp: App {
    /// Issue #4: the app-private store. Opened lazily on first use; features
    /// in issues #5/#6 reach the registry and wash log through this seam.
    static let store: CareStore = {
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

    var body: some Scene {
        WindowGroup {
            BootstrapHomeView()
        }
    }
}
