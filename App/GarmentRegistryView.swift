import CareKit
import CareStore
import Observation
import SwiftUI
import UIKit

// Issue #5: the garment registry — list with search, empty state,
// add/edit via GarmentEditor, delete with confirmation. Deletion follows the
// documented rule: the garment's wash-log entries cascade and its photo file
// is removed (GarmentRepository.delete, issue #4).

@MainActor
struct GarmentRegistryView: View {
    @State private var model: GarmentRegistryModel

    /// Presenting the editor with a new (unsaved) garment or an existing one.
    @State private var editorRequest: EditorRequest?
    /// Set while the editor is shown; carries the photo pending removal so
    /// its file can be deleted once the edit is saved.
    @State private var pendingPhotoRemoval: String?

    @State private var garmentPendingDeletion: Garment?

    /// Wrapper so a brand-new (unsaved, id == nil) garment can still drive
    /// `sheet(item:)` with a stable identity.
    struct EditorRequest: Identifiable {
        let id = UUID()
        var garment: Garment
    }

    init(store: CareStore) {
        _model = State(initialValue: GarmentRegistryModel(store: store))
    }

    /// `searchable` needs a Binding; the model owns the text.
    private var searchTextBinding: Binding<String> {
        Binding(
            get: { model.searchText },
            set: { model.searchText = $0 }
        )
    }

    var body: some View {
        Group {
            if model.filteredGarments.isEmpty {
                emptyState
            } else {
                garmentList
            }
        }
        .navigationTitle("My Garments")
        .searchable(
            text: searchTextBinding,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search by name or category"
        )
        .accessibilityIdentifier("registry.searchable")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorRequest = EditorRequest(garment: Garment(name: "", category: .top))
                    pendingPhotoRemoval = nil
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add garment")
                .accessibilityIdentifier("registry.add.toolbar")
            }
        }
        .sheet(item: $editorRequest) { request in
            GarmentEditorView(
                original: request.garment,
                model: model,
                pendingPhotoRemoval: $pendingPhotoRemoval
            )
        }
        .alert(
            "Delete garment?",
            isPresented: Binding(
                get: { garmentPendingDeletion != nil },
                set: { if !$0 { garmentPendingDeletion = nil } }
            ),
            presenting: garmentPendingDeletion
        ) { garment in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                model.delete(garment)
            }
        } message: { garment in
            Text(
                "Deleting \(garment.name) also removes its wash log and label photo. This cannot be undone."
            )
        }
        .overlay {
            if let error = model.lastError {
                ErrorBanner(text: error) { model.lastError = nil }
            }
        }
    }

    private var garmentList: some View {
        List {
            ForEach(model.filteredGarments) { garment in
                NavigationLink {
                    GarmentDetailView(
                        garmentID: garment.id,
                        model: model,
                        onEdit: {
                            editorRequest = EditorRequest(garment: garment)
                            pendingPhotoRemoval = nil
                        },
                        onDelete: {
                            garmentPendingDeletion = garment
                        }
                    )
                } label: {
                    GarmentRow(garment: garment)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        garmentPendingDeletion = garment
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No garments yet", systemImage: "tshirt")
        } description: {
            Text(
                model.searchText.isEmpty
                    ? "Add your first garment to record its care label."
                    : "No garments match \"\(model.searchText)\"."
            )
        } actions: {
            if model.searchText.isEmpty {
                Button("Add garment") {
                    editorRequest = EditorRequest(garment: Garment(name: "", category: .top))
                    pendingPhotoRemoval = nil
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("registry.empty.add")
            }
        }
        // Make the empty state an explicit accessibility GROUP so it exists
        // as a queryable element (CI XCUITest: an identifier on a bare
        // ContentUnavailableView is not exposed as an "other" element).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("registry.empty")
    }
}

// MARK: - Row

// NOTE: deliberately NOT an `.accessibilityElement(children: .combine)` —
// combining removes the child texts from the a11y tree that XCUITest walks,
// breaking `staticTexts` queries. List cells already group children for
// VoiceOver; each text keeps its natural label.
struct GarmentRow: View {
    let garment: Garment

    var body: some View {
        HStack(spacing: 12) {
            photoThumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(garment.name)
                    .font(.headline)
                Text(garment.category.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(careSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var photoThumbnail: some View {
        if let fileName = garment.photo?.fileName,
           let data = RegistryThumbnailCache.shared.data(named: fileName) {
            Image(uiImage: UIImage(data: data) ?? UIImage())
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Label photo of \(garment.name)")
        } else {
            Image(systemName: "tshirt")
                .frame(width: 48, height: 48)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
        }
    }

    private var careSummary: String {
        if garment.careProfile.isFullyUnknown {
            CarePlainLanguageRenderer.unknownAxisRule
        } else {
            "\(garment.careProfile.recordedAxisCount) of \(CareAxis.allCases.count) care axes recorded"
        }
    }
}

/// Tiny in-memory cache so list rows don't re-read photo files every render.
@MainActor
final class RegistryThumbnailCache {
    static let shared = RegistryThumbnailCache()
    private var cache: [String: Data] = [:]
    /// Injected by the app root; reads through the photo store seam.
    var reader: ((String) -> Data?)?

    private init() {}

    func data(named fileName: String) -> Data? {
        if let cached = cache[fileName] { return cached }
        guard let data = reader?(fileName) else { return nil }
        cache[fileName] = data
        return data
    }

    func invalidate() { cache.removeAll() }
}

// MARK: - Error banner

struct ErrorBanner: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        VStack {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(text)
                    .font(.callout)
                    .accessibilityIdentifier("registry.error")
                Button("Dismiss", action: dismiss)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding()
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
