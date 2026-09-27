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

/// Root view: five tabs — Garments (registry, issue #5), Basket (wash-safe
/// planning), Wash Log, Symbol Reference, and Settings (issue #7 backup/CSV).
/// All share one `WardrobeWorkspaceModel` and the app-wide store seam.
struct AppRootView: View {
    @State private var workspace: WardrobeWorkspaceModel

    init() {
        _workspace = State(initialValue: WardrobeWorkspaceModel(store: CareLabelApp.store))
    }

    var body: some View {
        TabView {
            NavigationStack {
                GarmentRegistryView(store: CareLabelApp.store, workspace: workspace)
            }
            .tabItem { Label("Garments", systemImage: "tshirt") }

            NavigationStack {
                BasketView(model: workspace)
            }
            .tabItem { Label("Basket", systemImage: "basketball") }

            NavigationStack {
                WashLogView(model: workspace)
            }
            .tabItem { Label("Wash Log", systemImage: "drop") }

            NavigationStack {
                SymbolReferenceScreen(model: workspace)
            }
            .tabItem { Label("Symbols", systemImage: "book.closed") }

            // Issue #7: user-owned data lifecycle (backup/restore, CSV).
            NavigationStack {
                SettingsView(store: CareLabelApp.store)
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .onAppear {
            RegistryThumbnailCache.shared.reader = { fileName in
                try? CareLabelApp.store.photoStore.data(for: PhotoReference(fileName: fileName))
            }
        }
    }
}
