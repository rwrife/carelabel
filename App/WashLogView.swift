import CareKit
import CareStore
import SwiftUI

// Issue #6: the wash log — newest-first per-garment history with the
// method used. The data is the repository's ordering (`allEntries()`,
// newest first); this view groups it by garment and labels each group.

@MainActor
struct WashLogView: View {
    @State private var model: WardrobeWorkspaceModel

    init(store: CareStore) {
        _model = State(initialValue: WardrobeWorkspaceModel(store: store))
    }

    /// Convenience for the workspace root which owns the shared model.
    init(model: WardrobeWorkspaceModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            if model.logSections.isEmpty {
                ContentUnavailableView {
                    Label("No washes logged yet", systemImage: "drop")
                } description: {
                    Text("Log a wash from the Basket report and its history shows up here.")
                }
                .accessibilityIdentifier("washlog.empty")
            } else {
                logList
            }
        }
        .navigationTitle("Wash Log")
        .refreshable { model.reload() }
        .overlay {
            if let error = model.lastError {
                ErrorBanner(text: error) { model.lastError = nil }
            }
        }
    }

    private var logList: some View {
        List {
            ForEach(model.logSections, id: \.garment.id) { section in
                Section {
                    ForEach(section.entries) { entry in
                        WashLogRow(entry: entry)
                    }
                } header: {
                    Text(section.garment.name)
                } footer: {
                    Text("Washed \(section.entries.count) time\(section.entries.count == 1 ? "" : "s") — newest first.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("washlog.list")
    }
}

struct WashLogRow: View {
    let entry: WashLogEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.method.displayName)
                    .font(.body)
                Text(WashLogDisplay.dateString(from: entry.loggedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("washlog.row.\(entry.id ?? -1)")
    }

    private var symbolName: String {
        switch entry.method {
        case .machineWash: "washer"
        case .handWash: "hand.raised"
        case .dryClean: "building.2"
        case .professionalWetClean: "drop"
        }
    }
}
