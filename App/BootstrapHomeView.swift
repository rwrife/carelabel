import CareKit
import SwiftUI

struct BootstrapHomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "checklist.sequential")
                    .font(.system(size: 54))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Care Label")
                        .font(.largeTitle.bold())
                    Text("A local-first wardrobe-care app for wash-safe laundry.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Native app foundation is ready", systemImage: "checkmark.circle")
                        Text("Garment registry, care decoding, and basket tools arrive in the next milestones.")
                            .foregroundStyle(.secondary)
                        Text("Care is tracked across \(CareAxis.allCases.count) axes: wash, bleach, dry, iron, professional.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
            .navigationTitle("Home")
        }
        .accessibilityIdentifier("bootstrap.home")
    }
}
