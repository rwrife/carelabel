import CareStore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SettingsView: View {
    @State private var model: SettingsModel
    @State private var showingRestoreImporter = false
    @State private var confirmRestore = false

    init(store: CareStore) {
        _model = State(initialValue: SettingsModel(store: store))
    }

    var body: some View {
        Form {
            Section("Data ownership") {
                Text("All data stays on this iPhone unless you export it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Create backup archive") {
                    model.prepareBackup()
                }
                .accessibilityIdentifier("settings.backup.create")

                if let url = model.backupURL {
                    ShareLink(item: url) {
                        Label("Share backup JSON", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("settings.backup.share")
                }

                Button("Restore from backup…") {
                    showingRestoreImporter = true
                }
                .accessibilityIdentifier("settings.backup.restore")
            }

            Section("CSV export") {
                Button("Create garment summary CSV") {
                    model.prepareCSV()
                }
                .accessibilityIdentifier("settings.csv.create")

                if let url = model.csvURL {
                    ShareLink(item: url) {
                        Label("Share CSV", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("settings.csv.share")
                }
            }

            Section("Storage") {
                LabeledContent("Photo files", value: "\(model.storageUsage.fileCount)")
                LabeledContent("Photo bytes", value: ByteCountFormatter.string(fromByteCount: Int64(model.storageUsage.totalBytes), countStyle: .file))
                Button("Refresh storage usage") {
                    model.refreshStorageUsage()
                }
                .accessibilityIdentifier("settings.storage.refresh")
            }

            if let status = model.statusMessage {
                Section("Status") {
                    Text(status)
                        .foregroundStyle(.green)
                }
            }

            if let error = model.lastError {
                Section("Error") {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Settings")
        .fileImporter(
            isPresented: $showingRestoreImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let first = urls.first else { return }
                model.previewRestore(from: first)
                if model.restorePreview != nil {
                    confirmRestore = true
                }
            case let .failure(error):
                model.lastError = "Could not open the selected file. \(error.localizedDescription)"
            }
        }
        .confirmationDialog(
            "Confirm restore",
            isPresented: $confirmRestore,
            titleVisibility: .visible
        ) {
            Button("Restore now", role: .destructive) {
                model.confirmRestore()
            }
            Button("Cancel", role: .cancel) {
                model.cancelRestore()
            }
        } message: {
            if let preview = model.restorePreview {
                Text(
                    "This will add \(preview.addedGarmentCount), merge \(preview.mergedGarmentCount), keep \(preview.unchangedGarmentCount) unchanged, and append \(preview.addedWashLogCount) wash-log entries."
                )
            } else {
                Text("No restore preview is available.")
            }
        }
    }
}
