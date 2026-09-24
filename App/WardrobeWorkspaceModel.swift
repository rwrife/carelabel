import CareKit
import CareStore
import Foundation
import Observation

// Issue #6: observable state for the three workspace screens — Basket,
// Wash Log, and Symbol Reference.
//
// Like `GarmentRegistryModel` (issue #5), the views never touch GRDB
// directly: everything routes through this model over the `CareStore` seam.
// Basket evaluation itself stays pure — this model only assembles
// `BasketItem`s from the registry and hands them to
// `BasketEvaluationEngine` (issue #3), so the verdict semantics cannot
// drift between the engine's tests and the UI.

@MainActor
@Observable
final class WardrobeWorkspaceModel {
    private let store: CareStore

    /// Registry in repository order (most-recently-updated first). The
    /// basket picker preserves this order for selection and evaluation.
    var garments: [Garment] = []

    /// Last user-visible failure message; nil when healthy.
    var lastError: String?

    // MARK: Basket state

    /// Selected garment ids. Ordered: the basket (and therefore the
    /// engine's deterministic output order) follows selection order.
    var selectedIDs: [Int64] = []

    /// Active basket picker search text (name or category, like the registry).
    var basketSearchText: String = ""

    /// The proposed wash plan (issue #3 inputs: temp/action/bleach/dry/iron).
    var plan = BasketPlan()

    /// True once the user has run an evaluation; while true, the report
    /// shows `evaluation` and plan/picker edits mark the report `stale`.
    var evaluated = false
    private var evaluation: BasketEvaluation?
    /// Snapshot of the exact garments + plan the last verdict was computed
    /// from; any drift (selection, plan, or a profile edit behind the same
    /// id) marks the verdict stale.
    private var evaluatedGarments: [Garment] = []
    private var evaluatedPlan: BasketPlan?

    /// True when the registry/selection/plan changed after the last
    /// evaluation — the report UI says the verdict is out of date.
    var isEvaluationStale: Bool {
        guard evaluated, evaluation != nil else { return false }
        return selectedGarments != evaluatedGarments || plan != evaluatedPlan
    }

    /// The live evaluation, or nil before the first run / after the user
    /// clears it.
    var currentEvaluation: BasketEvaluation? {
        evaluated ? evaluation : nil
    }

    /// Selected garments in selection order (garments deleted meanwhile are
    /// dropped from the selection).
    var selectedGarments: [Garment] {
        selectedIDs.compactMap { id in garments.first { $0.id == id } }
    }

    /// Picker list: registry filtered by `basketSearchText` (name or
    /// category display name, case-insensitive).
    var filteredGarments: [Garment] {
        let query = basketSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return garments }
        return garments.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.category.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    /// Registry grouped by category, in `GarmentCategory.allCases` order,
    /// for the picker's category grouping (acceptance criterion).
    var pickerSections: [(category: GarmentCategory, garments: [Garment])] {
        GarmentCategory.allCases.compactMap { category in
            let items = filteredGarments.filter { $0.category == category }
            return items.isEmpty ? nil : (category, items)
        }
    }

    // MARK: Wash log state

    /// Every wash entry, newest first (repository ordering).
    var entries: [WashLogEntry] = []

    /// Wash-log entries grouped per garment, newest-first within each group
    /// (the repository already orders them).
    var logSections: [(garment: Garment, entries: [WashLogEntry])] {
        garments.compactMap { garment in
            guard let id = garment.id else { return nil }
            let rows = entries.filter { $0.garmentID == id }
            return rows.isEmpty ? nil : (garment, rows)
        }
    }

    /// Most recent wash date for one garment, nil if never washed.
    /// Registry rows surface this as "last washed".
    func lastWashedDate(for garment: Garment) -> Date? {
        guard let id = garment.id else { return nil }
        return entries.first { $0.garmentID == id }?.loggedAt
    }

    // MARK: Symbol reference state

    /// Active symbol search text (matches glyph notation or meaning).
    var symbolSearchText: String = ""

    /// Family filter; nil means browse every family.
    var symbolFamilyFilter: CareSymbolFamily?

    /// The decoded symbol table filtered by family and search text —
    /// browsable by family, searchable by glyph name/meaning (acceptance).
    var filteredSymbols: [CareSymbol] {
        var symbols = CareSymbolTable.all
        if let family = symbolFamilyFilter {
            symbols = symbols.filter { $0.family == family }
        }
        let query = symbolSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return symbols }
        return symbols.filter {
            $0.notation.localizedCaseInsensitiveContains(query)
                || $0.meaning.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    /// Symbols grouped by family for the browsable list, honoring the
    /// family filter and search text.
    var symbolSections: [(family: CareSymbolFamily, symbols: [CareSymbol])] {
        CareSymbolFamily.allCases.compactMap { family in
            if let filter = symbolFamilyFilter, filter != family { return nil }
            let items = filteredSymbols.filter { $0.family == family }
            return items.isEmpty ? nil : (family, items)
        }
    }

    // MARK: - Lifecycle

    init(store: CareStore) {
        self.store = store
        reload()
    }

    func reload() {
        do {
            garments = try store.garments.allGarments()
            entries = try store.washLog.allEntries()
            // Drop selections whose garments no longer exist.
            let live = Set(garments.compactMap { $0.id })
            selectedIDs.removeAll { !live.contains($0) }
            lastError = nil
        } catch {
            lastError = "Could not load the wardrobe: \(error)"
        }
    }

    // MARK: - Basket actions

    func toggleSelection(_ garment: Garment) {
        guard let id = garment.id else { return }
        if let index = selectedIDs.firstIndex(of: id) {
            selectedIDs.remove(at: index)
        } else {
            selectedIDs.append(id)
        }
    }

    func isSelected(_ garment: Garment) -> Bool {
        garment.id.map(selectedIDs.contains) ?? false
    }

    /// Runs the pure engine over the current selection + plan and shows the
    /// report. Selection order is preserved so output is deterministic.
    func evaluateBasket() {
        let selected = selectedGarments
        let items: [BasketItem] = selected.compactMap { garment in
            guard let id = garment.id else { return nil }
            return BasketItem(id: String(id), name: garment.name, profile: garment.careProfile)
        }
        evaluation = BasketEvaluationEngine.evaluate(basket: items, plan: plan)
        evaluatedGarments = selected
        evaluatedPlan = plan
        evaluated = true
        washLogged = false
    }

    /// Clears the report (and marks it gone even if it was stale).
    func clearEvaluation() {
        evaluation = nil
        evaluatedGarments = []
        evaluatedPlan = nil
        evaluated = false
        washLogged = false
    }

    /// True once the current report's group has been logged — the one-tap
    /// log button disables until the next evaluation (no double logging).
    private(set) var washLogged = false

    /// The wash method a logged basket actually used, derived from the
    /// evaluated plan (dry-clean plan logs `dryClean`, otherwise machine).
    var loggedMethodForEvaluation: WashMethod {
        evaluatedPlan?.cleanMode == .dryClean ? .dryClean : .machineWash
    }

    /// "One tap logs the wash for grouped garments" (acceptance): inserts
    /// one wash-log entry per member of the compatible group, atomically
    /// from the UI's perspective; failures surface through `lastError`.
    func logWashForEvaluatedGroup() {
        let members = evaluation?.group.members ?? []
        guard evaluated, !members.isEmpty else {
            lastError = "Nothing to log — evaluate the basket first."
            return
        }
        let method = loggedMethodForEvaluation
        let now = Date()
        do {
            for member in members {
                guard let id = Int64(member.id) else { continue }
                _ = try store.washLog.log(
                    WashLogEntry(garmentID: id, method: method, loggedAt: now)
                )
            }
            washLogged = true
            reload()
            // Keep the report visible: logging does not change the plan or
            // selection, but reloading surfaces the new "last washed" dates
            // on registry rows immediately.
        } catch {
            lastError = "Could not log the wash: \(error)"
        }
    }
}

// MARK: - Wash plan display helpers

extension BasketPlan.CleanMode {
    var displayName: String {
        switch self {
        case .machineWash: "Machine wash"
        case .dryClean: "Dry clean"
        }
    }
}

extension WashAction {
    var editorName: String {
        switch self {
        case .normal: "Normal"
        case .permanentPress: "Permanent press"
        case .gentle: "Gentle"
        }
    }
}

extension BleachKind {
    var editorName: String {
        switch self {
        case .anyBleach: "Any bleach"
        case .oxygenOnly: "Oxygen (color-safe) only"
        }
    }
}

extension NaturalDryMethod {
    var editorName: String {
        switch self {
        case .flat: "Dry flat"
        case .hang: "Line dry"
        case .drip: "Drip dry"
        }
    }
}

extension WashMethod {
    var displayName: String {
        switch self {
        case .machineWash: "Machine wash"
        case .handWash: "Hand wash"
        case .dryClean: "Dry clean"
        case .professionalWetClean: "Professional wet clean"
        }
    }
}
