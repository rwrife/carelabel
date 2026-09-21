import CareKit
import CareStore
import PhotosUI
import SwiftUI
import UIKit

// Issue #5: the garment add/edit form.
//
// Identity fields (name, category, fabric note), a label photo section
// (camera capture or limited-library pick, copied into app storage —
// add-only photo access), and the five care-axis editors, each defaulting to
// `.unknown`, each linking to its symbol reference sheet. A live
// plain-language preview at the bottom shows the rules the profile produces.

@MainActor
struct GarmentEditorView: View {
    let original: Garment
    let model: GarmentRegistryModel
    @Binding var pendingPhotoRemoval: String?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var category: GarmentCategory
    @State private var fabricNote: String
    @State private var profile: CareProfile

    /// Photo reference created during THIS editing session (not yet saved).
    @State private var sessionPhoto: PhotoReference?
    /// True when the user removed the garment's existing photo in this session.
    @State private var removedExistingPhoto = false

    @State private var photoItem: PhotosPickerItem?

    /// Name field focus — UI tests (and VoiceOver users) need the keyboard
    /// dismissible deterministically before hitting the Save button.
    @FocusState private var nameFocused: Bool

    init(
        original: Garment,
        model: GarmentRegistryModel,
        pendingPhotoRemoval: Binding<String?>
    ) {
        self.original = original
        self.model = model
        self._pendingPhotoRemoval = pendingPhotoRemoval
        _name = State(initialValue: original.name)
        _category = State(initialValue: original.category)
        _fabricNote = State(initialValue: original.fabricNote ?? "")
        _profile = State(initialValue: original.careProfile)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool { !trimmedName.isEmpty }

    /// The photo currently displayed (session capture wins over the stored one).
    private var displayedPhotoFileName: String? {
        if removedExistingPhoto { return sessionPhoto?.fileName }
        return sessionPhoto?.fileName ?? original.photo?.fileName
    }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                photoSection
                careAxesSection
                previewSection
            }
            .navigationTitle(original.id == nil ? "Add Garment" : "Edit Garment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", role: .cancel) {
                        // A stored photo queued for removal stays referenced
                        // by the unchanged row on cancel — drop the queue.
                        pendingPhotoRemoval = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .accessibilityIdentifier("editor.save")
                }
            }
            .accessibilityIdentifier("editor.root")
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        attachPhoto(data)
                    }
                    photoItem = nil
                }
            }
        }
    }

    // MARK: Sections

    private var identitySection: some View {
        Section("Garment") {
            TextField("Name (e.g. Blue wool sweater)", text: $name)
                .focused($nameFocused)
                .accessibilityIdentifier("editor.name")
            Picker("Category", selection: $category) {
                ForEach(GarmentCategory.allCases, id: \.self) { cat in
                    Text(cat.displayName).tag(cat)
                }
            }
            .accessibilityIdentifier("editor.category")
            TextField("Fabric note (optional)", text: $fabricNote, axis: .vertical)
                .lineLimit(2...4)
                .accessibilityIdentifier("editor.fabricNote")
        }
    }

    private var photoSection: some View {
        Section("Label photo") {
            if let fileName = displayedPhotoFileName,
               let data = photoDisplayData(fileName),
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Current label photo")
                    .accessibilityIdentifier("editor.photo.image")
                Button("Remove photo", role: .destructive) { removePhoto() }
                    .accessibilityIdentifier("editor.photo.remove")
            } else {
                HStack {
                    // Issue acceptance: "camera capture OR limited-library
                    // pick". PhotosPicker is the system out-of-process picker:
                    // no library permission prompt at all (no read access),
                    // and on devices with a camera it also offers in-picker
                    // capture. The selected bytes then flow through the same
                    // `PhotoStore.importPhoto` downscale seam either way.
                    PhotosPicker(
                        selection: $photoItem,
                        selectionBehavior: .single,
                        matching: .images
                    ) {
                        Label("Add photo", systemImage: "photo.on.rectangle")
                    }
                    .accessibilityIdentifier("editor.photo.pick")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHint("Copies the photo into app storage; the original stays in your library.")

                // Simulator/CI has no camera or seeded library: under
                // `-ui-testing`, expose a deterministic source through the
                // same importPhoto seam the camera/picker paths use.
                if TestPhotoSource.isUITesting {
                    Button {
                        attachPhoto(TestPhotoSource.makeTestPhotoData())
                    } label: {
                        Label("Attach test photo", systemImage: "photo.stack")
                    }
                    .accessibilityIdentifier("editor.photo.test")
                }
            }
        }
    }

    private var careAxesSection: some View {
        // Each axis editor carries its own Section; a Group keeps them
        // siblings inside the Form.
        Group {
            WashAxisEditor(profile: $profile)
            BleachAxisEditor(profile: $profile)
            DryAxisEditor(profile: $profile)
            IronAxisEditor(profile: $profile)
            ProfessionalAxisEditor(profile: $profile)
        }
        .accessibilityIdentifier("editor.careAxes")
    }

    private var previewSection: some View {
        Section("Plain-language preview") {
            ForEach(
                Array(CarePlainLanguageRenderer.rules(for: profile).enumerated()),
                id: \.offset
            ) { _, rule in
                Text(rule)
                    .font(.callout)
                    .foregroundStyle(
                        rule == CarePlainLanguageRenderer.unknownAxisRule
                            ? .secondary : .primary
                    )
            }
        }
        .accessibilityIdentifier("editor.preview")
    }

    // MARK: Actions

    private func photoDisplayData(_ fileName: String) -> Data? {
        model.photoData(named: fileName)
    }

    private func attachPhoto(_ data: Data) {
        if let ref = model.importPhoto(data) {
            // A replaced session photo was never referenced by a saved row,
            // so its file can go immediately (nothing to cascade-check).
            if let previous = sessionPhoto {
                model.deleteUnreferencedPhoto(named: previous.fileName)
            }
            sessionPhoto = ref
        }
    }

    private func removePhoto() {
        if let session = sessionPhoto {
            // Imported during this edit but never saved into a row: delete now.
            model.deleteUnreferencedPhoto(named: session.fileName)
            sessionPhoto = nil
        }
        if let stored = original.photo?.fileName {
            // The stored file is deleted only if this edit SAVES without the
            // photo; Cancel keeps DB reference and file consistent.
            pendingPhotoRemoval = stored
        }
        removedExistingPhoto = true
    }

    private func save() {
        // Dismiss the keyboard so a focused field can't cover the sheet's
        // save flow mid-transition.
        nameFocused = false
        var garment = original
        garment.name = trimmedName
        garment.category = category
        garment.fabricNote = fabricNote.isEmpty ? nil : fabricNote
        garment.careProfile = profile
        if removedExistingPhoto {
            garment.photo = sessionPhoto
        } else if let sessionPhoto {
            garment.photo = sessionPhoto
        }

        guard let saved = model.save(garment) else { return }

        // Now that the row is persisted, clean up photo files nothing points at.
        RegistryThumbnailCache.shared.invalidate()
        if let orphan = pendingPhotoRemoval {
            model.deleteUnreferencedPhoto(named: orphan)
            pendingPhotoRemoval = nil
        }
        _ = saved
        dismiss()
    }
}
