import CareKit
import CareStore
import Foundation
import SwiftUI
import UIKit

// Issue #5: read-only detail for one registry garment. Recomputes from the
// shared model so registry edits and deletions stay live; pops itself once
// its garment is gone (delete cascade per the documented rule).

@MainActor
struct GarmentDetailView: View {
    let garmentID: Int64?
    let model: GarmentRegistryModel
    var onEdit: () -> Void
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var garment: Garment? {
        model.garments.first { $0.id == garmentID }
    }

    var body: some View {
        Group {
            if let garment {
                content(for: garment)
            } else {
                ContentUnavailableView("Garment deleted", systemImage: "tray")
            }
        }
        .navigationTitle(garment?.name ?? "Garment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit", action: onEdit)
                    .accessibilityIdentifier("detail.edit")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete garment")
                .accessibilityIdentifier("detail.delete")
            }
        }
        .onChange(of: model.garments) { _, _ in
            if garment == nil { dismiss() }
        }
        .accessibilityIdentifier("detail.root")
    }

    @ViewBuilder
    private func content(for garment: Garment) -> some View {
        List {
            if let fileName = garment.photo?.fileName,
               let data = RegistryThumbnailCache.shared.data(named: fileName),
               let image = UIImage(data: data) {
                Section("Label photo") {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 260)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Label photo of \(garment.name)")
                        .accessibilityIdentifier("detail.photo")
                }
            }

            Section("Care rules") {
                ForEach(
                    Array(CarePlainLanguageRenderer.rules(for: garment.careProfile).enumerated()),
                    id: \.offset
                ) { _, rule in
                    Label {
                        Text(rule)
                    } icon: {
                        Image(systemName: rule == CarePlainLanguageRenderer.unknownAxisRule
                              ? "questionmark.circle" : "checkmark.circle")
                            .foregroundStyle(rule == CarePlainLanguageRenderer.unknownAxisRule
                                             ? .orange : .green)
                    }
                }
            }
            .accessibilityIdentifier("detail.rules")

            Section("Garment") {
                LabeledContent("Category", value: garment.category.displayName)
                if let note = garment.fabricNote, !note.isEmpty {
                    LabeledContent("Fabric note", value: note)
                }
                if let updatedAt = garment.updatedAt {
                    LabeledContent("Updated", value: Self.dateString(from: updatedAt))
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Built per call — DateFormatter is a mutable reference type and a
    /// non-Sendable global would be rejected in Swift 6 language mode.
    private static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
