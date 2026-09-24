import CareKit
import CareStore
import SwiftUI

// Issue #6: the standalone Symbol Reference screen — the whole decoded
// ISO 3758 table browsable by family and searchable by glyph name or
// meaning. Reuses `SymbolRow` / `CareGlyphView` from the issue #5 sheet so
// glyph rendering and the VoiceOver "glyph, meaning" labeling stay in one
// place.
//
// Family filtering is a toolbar menu (a leaf button whose identifier
// surfaces reliably in XCUITest — CI evidence from issue #5 says menu-
// style Pickers inside Lists do not).

@MainActor
struct SymbolReferenceScreen: View {
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
            if model.symbolSections.isEmpty {
                ContentUnavailableView(
                    "No symbols match",
                    systemImage: "magnifyingglass",
                    description: Text(
                        "Nothing matches “\(model.symbolSearchText)”. Try a glyph shape (tub, iron, triangle) or a rule word (tumble, bleach)."
                    )
                )
                .accessibilityIdentifier("symbols.empty")
            } else {
                symbolList
            }
        }
        .searchable(
            text: Binding(
                get: { model.symbolSearchText },
                set: { model.symbolSearchText = $0 }
            ),
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search glyph name or meaning"
        )
        .navigationTitle("Care Symbols")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("All families") { model.symbolFamilyFilter = nil }
                    ForEach(CareSymbolFamily.allCases, id: \.self) { family in
                        Button(family.title) { model.symbolFamilyFilter = family }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter by family")
                // NOTE: toolbar `Menu` does not bridge accessibilityIdentifier
                // into the XCUITest tree (CI run 35965330787: same container
                // caveat as sheet/section containers). Tests locate it by its
                // accessibility label; the identifier stays for future tooling.
                .accessibilityIdentifier("symbols.family.filter")
            }
        }
    }

    private var symbolList: some View {
        List {
            ForEach(model.symbolSections, id: \.family) { section in
                // NOTE: no Section-level accessibilityIdentifier — it would
                // cascade over child identifiers in the XCUITest hierarchy
                // (see issue #5 CI evidence). Section headers carry the
                // family title instead.
                Section(section.family.title) {
                    ForEach(section.symbols) { symbol in
                        SymbolRow(symbol: symbol)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("symbols.list")
    }
}
