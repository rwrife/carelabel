import CareKit
import CareStore
import SwiftUI

// Issue #6: the wash basket — multi-select picker from the registry, plan
// controls (clean mode/temp/action/bleach/dry/iron), and the compatibility
// report from the pure `BasketEvaluationEngine` (issue #3).
//
// LAYOUT SEAM (acceptance criterion): this view never decides stacked vs
// split itself. It asks `CareWorkspaceLayout.presentation()` — the single
// adaptation point — and renders accordingly:
//
//   .stacked      (today's compact iPhone)  — picker screen first; the
//       evaluation pushes a sequential report screen.
//   .splitPanels  (regular width, and the documented iPhone Duo span) —
//       garment picker on the leading panel, live report on the trailing
//       panel: exactly the "basket at the machine" dual-screen mode from
//       the README, realized structurally today so the future fold-API
//       work only changes how the two panels are spanned, not this view.
//
// No fold APIs are referenced anywhere; no iPad target changes (the app
// stays TARGETED_DEVICE_FAMILY = 1).

@MainActor
struct BasketView: View {
    @State private var model: WardrobeWorkspaceModel
    @State private var showReport = false

    init(store: CareStore) {
        _model = State(initialValue: WardrobeWorkspaceModel(store: store))
    }

    /// Convenience for the workspace root which owns the shared model.
    init(model: WardrobeWorkspaceModel) {
        _model = State(initialValue: model)
    }

    private var presentation: CareWorkspacePresentation {
        CareWorkspaceLayout.presentation()
    }

    var body: some View {
        Group {
            switch presentation {
            case .stacked:
                stackedLayout
            case .splitPanels:
                // Dual-screen design target: picker panel beside live report
                // panel. Unreachable on the compact iPhone today; documented
                // in README "iPhone Duo dual-screen design target".
                HStack(spacing: 0) {
                    pickerList
                    Divider()
                    BasketReportPanel(model: model)
                }
            }
        }
        .navigationTitle("Basket")
    }

    // MARK: - Stacked (today's iPhone)

    private var stackedLayout: some View {
        VStack(spacing: 0) {
            pickerList
            planControls
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.evaluateBasket()
                    showReport = true
                } label: {
                    Text("Evaluate")
                }
                .disabled(model.selectedIDs.isEmpty)
                .accessibilityLabel("Evaluate basket")
                .accessibilityIdentifier("basket.evaluate")
            }
        }
        .navigationDestination(isPresented: $showReport) {
            BasketReportView(model: model)
        }
        .overlay {
            if let error = model.lastError {
                ErrorBanner(text: error) { model.lastError = nil }
            }
        }
    }

    // MARK: - Picker

    private var pickerList: some View {
        List {
            Section {
                ForEach(model.pickerSections, id: \.category) { section in
                    ForEach(section.garments) { garment in
                        BasketPickRow(
                            garment: garment,
                            isSelected: model.isSelected(garment),
                            toggle: { model.toggleSelection(garment) }
                        )
                    }
                }
            } header: {
                Text("Your garments — \(model.selectedIDs.count) selected")
            } footer: {
                Text(model.garments.isEmpty
                     ? "Add garments in the Garments tab first."
                     : "Pick the clothes for this load, set the plan below, then evaluate.")
            }
        }
        .searchable(
            text: Binding(
                get: { model.basketSearchText },
                set: { model.basketSearchText = $0 }
            ),
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search by name or category"
        )
        .overlay {
            if model.filteredGarments.isEmpty && !model.garments.isEmpty {
                ContentUnavailableView(
                    "No garments match",
                    systemImage: "magnifyingglass",
                    description: Text("Nothing in the registry matches “\(model.basketSearchText)”.")
                )
            }
        }
        .accessibilityIdentifier("basket.picker")
    }

    // MARK: - Plan controls (temp / action / bleach / dry / iron)

    private var planControls: some View {
        // NOTE: leaf-level identifiers only — an identifier on a container
        // aggregates a shadowing element in the XCUITest hierarchy (CI run
        // 35780364211, same rule the editor follows).
        VStack(alignment: .leading, spacing: 8) {
            Text("Wash plan")
                .font(.headline)
            HStack {
                Picker("Clean", selection: cleanModeBinding) {
                    ForEach(BasketPlan.CleanMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .accessibilityIdentifier("basket.plan.clean")
            }
            HStack {
                Picker("Temp", selection: tempBinding) {
                    ForEach(WashTemperature.allCases, id: \.self) { temp in
                        Text(temp.celsiusDescription).tag(temp)
                    }
                }
                .accessibilityIdentifier("basket.plan.temp")
                Picker("Cycle", selection: actionBinding) {
                    ForEach(WashAction.allCases, id: \.self) { action in
                        Text(action.editorName).tag(action)
                    }
                }
                .accessibilityIdentifier("basket.plan.action")
            }
            HStack {
                Picker("Bleach", selection: bleachBinding) {
                    Text("None").tag(BleachKind?.none)
                    ForEach(BleachKind.allCases, id: \.self) { kind in
                        Text(kind.editorName).tag(BleachKind?.some(kind))
                    }
                }
                .accessibilityIdentifier("basket.plan.bleach")
                Picker("Iron", selection: ironBinding) {
                    Text("None").tag(IronTemperature?.none)
                    ForEach(IronTemperature.allCases, id: \.self) { temp in
                        Text(temp.celsiusDescription).tag(IronTemperature?.some(temp))
                    }
                }
                .accessibilityIdentifier("basket.plan.iron")
            }
            Picker("Drying", selection: dryModeBinding) {
                Text("None").tag(BasketPlanMode.none)
                Text("Tumble low").tag(BasketPlanMode.tumbleLow)
                Text("Tumble normal").tag(BasketPlanMode.tumbleNormal)
                Text("Tumble high").tag(BasketPlanMode.tumbleHigh)
                Text("Dry flat").tag(BasketPlanMode.dryFlat)
                Text("Line dry").tag(BasketPlanMode.lineDry)
                Text("Drip dry").tag(BasketPlanMode.dripDry)
            }
            .accessibilityIdentifier("basket.plan.dry")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    /// Plan picker modes (BasketPlan.PlanDry carries associated values, so
    /// picker selection goes through these flat tags).
    private enum BasketPlanMode: Hashable {
        case none, tumbleLow, tumbleNormal, tumbleHigh, dryFlat, lineDry, dripDry
    }

    private var cleanModeBinding: Binding<BasketPlan.CleanMode> {
        Binding(get: { model.plan.cleanMode }, set: { model.plan.cleanMode = $0 })
    }
    private var tempBinding: Binding<WashTemperature> {
        Binding(get: { model.plan.washTemperature }, set: { model.plan.washTemperature = $0 })
    }
    private var actionBinding: Binding<WashAction> {
        Binding(get: { model.plan.washAction }, set: { model.plan.washAction = $0 })
    }
    private var bleachBinding: Binding<BleachKind?> {
        Binding(get: { model.plan.bleach }, set: { model.plan.bleach = $0 })
    }
    private var ironBinding: Binding<IronTemperature?> {
        Binding(get: { model.plan.iron }, set: { model.plan.iron = $0 })
    }
    private var dryModeBinding: Binding<BasketPlanMode> {
        Binding(
            get: {
                switch model.plan.drying {
                case nil: .none
                case .tumble(.low): .tumbleLow
                case .tumble(.normal): .tumbleNormal
                case .tumble(.high): .tumbleHigh
                case .natural(.flat): .dryFlat
                case .natural(.hang): .lineDry
                case .natural(.drip): .dripDry
                }
            },
            set: { mode in
                switch mode {
                case .none: model.plan.drying = nil
                case .tumbleLow: model.plan.drying = .tumble(heat: .low)
                case .tumbleNormal: model.plan.drying = .tumble(heat: .normal)
                case .tumbleHigh: model.plan.drying = .tumble(heat: .high)
                case .dryFlat: model.plan.drying = .natural(method: .flat)
                case .lineDry: model.plan.drying = .natural(method: .hang)
                case .dripDry: model.plan.drying = .natural(method: .drip)
                }
            }
        )
    }
}

// MARK: - Pick row

struct BasketPickRow: View {
    let garment: Garment
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(garment.name)
                        .font(.body)
                    Text(garment.category.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(garment.name), \(garment.category.displayName)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : .init())
        .accessibilityIdentifier("basket.row.\(garment.id ?? -1)")
    }
}

// MARK: - Report

/// The compatibility report: safe group, needs-attention, and named-reason
/// conflicts, plus the one-tap wash log (issue #6 acceptance).
@MainActor
struct BasketReportView: View {
    let model: WardrobeWorkspaceModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let evaluation = model.currentEvaluation {
                if model.isEvaluationStale {
                    Label(
                        "Plan or selection changed after this report — evaluate again.",
                        systemImage: "exclamationmark.arrow.triangle.2.circlepath"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("basket.report.stale")
                }

                Section("Safe for this plan (\(evaluation.group.members.count))") {
                    if evaluation.group.members.isEmpty {
                        Text("Nothing in this basket is safe under the current plan.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("basket.report.safe-empty")
                    } else {
                        ForEach(evaluation.group.members) { member in
                            Label(member.name, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.primary)
                                .accessibilityIdentifier("basket.report.safe.\(member.id)")
                        }
                    }
                }
                // NOTE: deliberately NO Section-level accessibilityIdentifier —
                // it cascades over child identifiers in the XCUITest tree
                // (issue #5 CI evidence). Tests match the header text.

                if !evaluation.needsAttention.isEmpty {
                    Section("Needs attention (\(evaluation.needsAttention.count))") {
                        ForEach(
                            Array(evaluation.needsAttention.enumerated()), id: \.offset
                        ) { _, attention in
                            Label {
                                Text(attention.reason)
                            } icon: {
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(.orange)
                            }
                            .accessibilityIdentifier("basket.report.attention.\(attention.garment.id)")
                        }
                    }
                }

                if !evaluation.conflicts.isEmpty {
                    Section("Conflicts (\(evaluation.conflicts.count))") {
                        ForEach(
                            Array(evaluation.conflicts.enumerated()), id: \.offset
                        ) { index, conflict in
                            Label {
                                Text(conflict.reason)
                            } icon: {
                                Image(systemName: "xmark.octagon.fill")
                                    .foregroundStyle(.red)
                            }
                            .accessibilityIdentifier("basket.report.conflict.\(index)")
                        }
                    }
                }

                Section {
                    Button {
                        model.logWashForEvaluatedGroup()
                    } label: {
                        Label(
                            "Log wash (\(evaluation.group.members.count) garment\(evaluation.group.members.count == 1 ? "" : "s"))",
                            systemImage: "drop.circle"
                        )
                        .frame(minHeight: 44)
                    }
                    .disabled(evaluation.group.members.isEmpty || model.washLogged)
                    .accessibilityIdentifier("basket.report.log")

                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("basket.report.done")
                }
            } else {
                ContentUnavailableView(
                    "No report yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Evaluate the basket to see the compatibility report.")
                )
            }
        }
        .navigationTitle("Compatibility report")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if let error = model.lastError {
                ErrorBanner(text: error) { model.lastError = nil }
            }
        }
        .accessibilityIdentifier("basket.report")
    }
}

/// Shared report panel used by the split-panels (regular-width / dual-span)
/// layout: renders inline next to the picker instead of on a pushed screen.
@MainActor
struct BasketReportPanel: View {
    let model: WardrobeWorkspaceModel

    var body: some View {
        if let evaluation = model.currentEvaluation {
            VStack(alignment: .leading) {
                Text("Report — \(evaluation.group.plan.cleanMode.displayName), \(evaluation.group.plan.washTemperature.celsiusDescription)")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top)
                List {
                    Section("Safe (\(evaluation.group.members.count))") {
                        ForEach(evaluation.group.members) { member in
                            Label(member.name, systemImage: "checkmark.circle.fill")
                        }
                    }
                    ForEach(
                        Array(evaluation.needsAttention.enumerated()), id: \.offset
                    ) { _, attention in
                        Label(attention.reason, systemImage: "questionmark.circle")
                    }
                    ForEach(
                        Array(evaluation.conflicts.enumerated()), id: \.offset
                    ) { _, conflict in
                        Label(conflict.reason, systemImage: "xmark.octagon.fill")
                    }
                }
            }
            .accessibilityIdentifier("basket.report.panel")
        } else {
            ContentUnavailableView(
                "No report yet",
                systemImage: "list.bullet.rectangle",
                description: Text("Evaluate the basket to see the compatibility report here.")
            )
        }
    }
}
