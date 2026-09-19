import Foundation

// Issue #3: the basket compatibility engine.
//
// Pure evaluation only: no UI, no storage, no Foundation networking. Given a
// set of garments and a proposed basket plan, the engine produces one
// compatible group plus per-garment hard conflicts and needs-attention
// entries, all in deterministic order (issue #3 acceptance criteria).
//
// Evaluation posture (PLAN.md risk table "compatibility engine false safe"):
// - Strictest-wins per axis: the plan must honor every member's cap, so a
//   plan that violates even one garment is a conflict for that garment.
// - Explicit prohibitions are checked against plan values (e.g. "do not
//   tumble dry" vs a tumble plan, dry-clean-required garment in a wet plan).
// - An `unknown` axis on an axis the plan exercises surfaces as
//   needsAttention — it is never silently grouped as safe. A fully-unknown
//   garment always needs attention, whatever the plan.
// - `doNotWring` is never exercised: the MVP plan vocabulary has no wring
//   value, so the engine honestly cannot conflict or clear it.

// MARK: - Basket inputs

/// One garment entering the basket. Kept engine-local so the pure domain
/// does not depend on persistence types (the stored `Garment` record is
/// issue #4 and will map onto this).
public struct BasketItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let profile: CareProfile

    public init(id: String, name: String, profile: CareProfile = .unknownProfile) {
        self.id = id
        self.name = name
        self.profile = profile
    }
}

/// The proposed way of washing the basket: how the load is cleaned and what
/// subsequent steps (bleach, drying, ironing) the user intends.
public struct BasketPlan: Codable, Equatable, Sendable {
    /// How the load is cleaned. `.machineWash` is the "wet plan";
    /// `.dryClean` routes the load through professional cleaning instead.
    public enum CleanMode: String, Codable, Equatable, Sendable, CaseIterable {
        case machineWash
        case dryClean
    }

    /// The drying step of a plan, mirroring the dry axis states.
    public enum PlanDry: Codable, Equatable, Sendable {
        case tumble(heat: DryHeat)
        case natural(method: NaturalDryMethod)
    }

    public var cleanMode: CleanMode
    /// Machine-wash temperature the plan runs at (wet mode only).
    public var washTemperature: WashTemperature
    /// Machine-wash action the plan runs at (wet mode only).
    public var washAction: WashAction
    /// Bleach the plan adds, or `nil` for a no-bleach plan.
    public var bleach: BleachKind?
    /// Drying the plan applies, or `nil` if the load is not machine dried.
    public var drying: PlanDry?
    /// Ironing the plan applies, or `nil` if nothing is ironed.
    public var iron: IronTemperature?

    public init(
        cleanMode: CleanMode = .machineWash,
        washTemperature: WashTemperature = .celsius40,
        washAction: WashAction = .normal,
        bleach: BleachKind? = nil,
        drying: PlanDry? = nil,
        iron: IronTemperature? = nil
    ) {
        self.cleanMode = cleanMode
        self.washTemperature = washTemperature
        self.washAction = washAction
        self.bleach = bleach
        self.drying = drying
        self.iron = iron
    }
}

// MARK: - Evaluation outputs

/// A hard rule violation: names the garment, the axis, the rule broken, and
/// the plan value that triggered it (issue #3 acceptance criterion).
public struct BasketConflict: Equatable, Sendable {
    public let garment: BasketItem
    public let axis: CareAxis
    public let rule: ConflictRule
    /// Pre-rendered human-readable reason naming garment, axis, rule, and the
    /// triggering plan value.
    public let reason: String

    /// The specific rule that was violated. Each case carries both the
    /// garment's recorded cap and the plan value that exceeded it, so the
    /// reason is fully explainable from the conflict alone.
    public enum ConflictRule: Equatable, Sendable {
        case doNotWashViolated
        case handWashViolatedByMachinePlan(
            plannedTemperature: WashTemperature, plannedAction: WashAction)
        case washTemperatureExceeded(cap: WashTemperature, planned: WashTemperature)
        case washActionExceeded(required: WashAction, planned: WashAction)
        case doNotBleachViolated(planned: BleachKind)
        case oxygenBleachOnlyViolated(planned: BleachKind)
        case doNotTumbleDryViolated(plannedHeat: DryHeat)
        case naturalDryRequiredButTumblePlanned(
            required: NaturalDryMethod, plannedHeat: DryHeat)
        case naturalDryMethodMismatch(required: NaturalDryMethod, planned: NaturalDryMethod)
        case tumbleHeatExceeded(cap: DryHeat, planned: DryHeat)
        case doNotIronViolated(planned: IronTemperature)
        case ironCapExceeded(cap: IronTemperature, planned: IronTemperature)
        case dryCleanRequiredInWetPlan(kind: ProfessionalKind)
        case doNotDryCleanViolated

        /// Axis the rule belongs to (matches `CareAxis.allCases` ordering use).
        public var axis: CareAxis {
            switch self {
            case .doNotWashViolated, .handWashViolatedByMachinePlan,
                 .washTemperatureExceeded, .washActionExceeded:
                .wash
            case .doNotBleachViolated, .oxygenBleachOnlyViolated:
                .bleach
            case .doNotTumbleDryViolated, .naturalDryRequiredButTumblePlanned,
                 .naturalDryMethodMismatch, .tumbleHeatExceeded:
                .dry
            case .doNotIronViolated, .ironCapExceeded:
                .iron
            case .dryCleanRequiredInWetPlan, .doNotDryCleanViolated:
                .professionalCleaning
            }
        }

        /// Full human-readable reason: garment, axis, rule, plan value.
        public func reason(garmentName: String) -> String {
            let head = "\(garmentName) — \(axis.rawValue): "
            switch self {
            case .doNotWashViolated:
                return head + "label says do not wash; plan is a machine-wash plan"
            case let .handWashViolatedByMachinePlan(temperature, action):
                return head + "label says hand wash only; plan machine washes at "
                    + "\(temperature.celsiusDescription), \(action.plainName) cycle"
            case let .washTemperatureExceeded(cap, planned):
                return head + "label caps machine wash at \(cap.celsiusDescription); "
                    + "plan washes at \(planned.celsiusDescription)"
            case let .washActionExceeded(required, planned):
                return head + "label requires \(required.plainName) cycle; "
                    + "plan runs \(planned.plainName) cycle"
            case let .doNotBleachViolated(planned):
                return head + "label says do not bleach; plan uses \(planned.plainName)"
            case let .oxygenBleachOnlyViolated(planned):
                return head + "label allows oxygen-based bleach only; "
                    + "plan uses \(planned.plainName)"
            case let .doNotTumbleDryViolated(plannedHeat):
                return head + "label says do not tumble dry; "
                    + "plan tumble dries on \(plannedHeat.plainName) heat"
            case let .naturalDryRequiredButTumblePlanned(required, plannedHeat):
                return head + "label requires natural drying (\(required.plainName)); "
                    + "plan tumble dries on \(plannedHeat.plainName) heat"
            case let .naturalDryMethodMismatch(required, planned):
                return head + "label requires \(required.plainName) drying; "
                    + "plan dries by \(planned.plainName)"
            case let .tumbleHeatExceeded(cap, planned):
                return head + "label caps tumble heat at \(cap.plainName); "
                    + "plan tumble dries on \(planned.plainName) heat"
            case let .doNotIronViolated(planned):
                return head + "label says do not iron; plan irons at \(planned.celsiusDescription)"
            case let .ironCapExceeded(cap, planned):
                return head + "label caps iron at \(cap.celsiusDescription) soleplate; "
                    + "plan irons at \(planned.celsiusDescription)"
            case let .dryCleanRequiredInWetPlan(kind):
                return head + "label requires professional cleaning (\(kind.plainName)); "
                    + "plan is a machine-wash plan"
            case .doNotDryCleanViolated:
                return head + "label says do not dry clean; plan is a dry-clean plan"
            }
        }
    }
}

/// A garment the engine refuses to call safe because an axis the plan relies
/// on was never recorded. `axes` lists every exercised-but-unrecorded axis,
/// in `CareAxis.allCases` order.
public struct NeedsAttention: Equatable, Sendable {
    public let garment: BasketItem
    public let axes: [CareAxis]
    /// Pre-rendered human-readable reason naming the garment and the
    /// unrecorded axes.
    public let reason: String
}

/// The complete deterministic verdict for one basket + plan.
public struct BasketEvaluation: Equatable, Sendable {
    /// The single compatible group: every member's caps and prohibitions are
    /// honored by the plan (strictest-wins held across all members).
    public struct CompatibleGroup: Equatable, Sendable {
        public let plan: BasketPlan
        /// Members in basket input order.
        public let members: [BasketItem]
    }

    public let group: CompatibleGroup
    /// Garments with unrecorded axes the plan relies on (never marked safe),
    /// in basket input order.
    public let needsAttention: [NeedsAttention]
    /// Hard conflicts, basket input order, and within a garment in
    /// `CareAxis.allCases` order. A garment may carry several conflicts.
    public let conflicts: [BasketConflict]

    /// True only when nothing conflicts and nothing needs attention —
    /// unknown never contributes to this verdict.
    public var isFullySafe: Bool {
        conflicts.isEmpty && needsAttention.isEmpty
    }
}

// MARK: - Plain names for conflict reasons

extension WashAction {
    var plainName: String {
        switch self {
        case .normal: "normal"
        case .permanentPress: "permanent-press"
        case .gentle: "gentle"
        }
    }
}

extension BleachKind {
    var plainName: String {
        switch self {
        case .anyBleach: "any bleach"
        case .oxygenOnly: "oxygen-based (color-safe) bleach"
        }
    }
}

extension DryHeat {
    var plainName: String {
        switch self {
        case .low: "low"
        case .normal: "normal"
        case .high: "high"
        }
    }
}

extension NaturalDryMethod {
    var plainName: String {
        switch self {
        case .flat: "dry flat"
        case .hang: "line dry (hang to dry)"
        case .drip: "drip dry"
        }
    }
}

extension ProfessionalKind {
    var plainName: String {
        switch self {
        case .dryCleanAnySolvent: "dry clean, any solvent"
        case .hydrocarbon: "dry clean, hydrocarbon solvents only"
        case .perchloroethylene: "dry clean, perchloroethylene-family solvents"
        case .wetClean: "professional wet cleaning"
        }
    }
}

// MARK: - Engine

/// Deterministic basket compatibility evaluation (issue #3). Pure function
/// over `BasketItem` + `BasketPlan` — no state, no storage, no UI.
public enum BasketEvaluationEngine {
    /// Evaluates every garment against the plan.
    ///
    /// Ordering contract (for testability, issue #3): the compatible group
    /// lists members in input order; `needsAttention` and `conflicts` list
    /// garments in input order; within one garment, conflicts follow
    /// `CareAxis.allCases` order and at most one needs-attention entry per
    /// garment is produced.
    public static func evaluate(basket: [BasketItem], plan: BasketPlan) -> BasketEvaluation {
        var compatible: [BasketItem] = []
        var allConflicts: [BasketConflict] = []
        var attention: [NeedsAttention] = []

        for item in basket {
            let garmentConflicts = conflicts(for: item, plan: plan)
            let unknownAxes = unrecordedExercisedAxes(for: item, plan: plan)

            if !garmentConflicts.isEmpty {
                for conflict in garmentConflicts {
                    allConflicts.append(conflict)
                }
            }
            if !unknownAxes.isEmpty {
                attention.append(NeedsAttention(
                    garment: item,
                    axes: unknownAxes,
                    reason: needsAttentionReason(item, axes: unknownAxes)
                ))
            }
            if garmentConflicts.isEmpty && unknownAxes.isEmpty {
                compatible.append(item)
            }
        }

        return BasketEvaluation(
            group: BasketEvaluation.CompatibleGroup(plan: plan, members: compatible),
            needsAttention: attention,
            conflicts: allConflicts
        )
    }

    // MARK: Axis exercise map

    /// Axes whose recorded state the plan relies on. Unknown states on these
    /// axes surface as needs-attention; other unknown axes make no plan
    /// claim and (except for fully-unknown garments) stay silent.
    static func exercisedAxes(for plan: BasketPlan) -> [CareAxis] {
        var axes: [CareAxis] = []
        switch plan.cleanMode {
        case .machineWash:
            axes.append(.wash)
        case .dryClean:
            axes.append(.professionalCleaning)
        }
        if plan.bleach != nil { axes.append(.bleach) }
        if plan.drying != nil { axes.append(.dry) }
        if plan.iron != nil { axes.append(.iron) }
        return axes.filterUniqueInPublishedOrder()
    }

    /// Unrecorded axes the plan exercises. A fully-unknown garment always
    /// returns all five published axes — it can never pass as safe.
    static func unrecordedExercisedAxes(for item: BasketItem, plan: BasketPlan) -> [CareAxis] {
        if item.profile.isFullyUnknown {
            return CareAxis.allCases
        }
        let profile = item.profile
        return exercisedAxes(for: plan).filter { axis in
            switch axis {
            case .wash: profile.wash == .unknown
            case .bleach: profile.bleach == .unknown
            case .dry: profile.dry == .unknown
            case .iron: profile.iron == .unknown
            case .professionalCleaning: profile.professional == .unknown
            }
        }
    }

    private static func needsAttentionReason(_ item: BasketItem, axes: [CareAxis]) -> String {
        let names = axes.map { $0.rawValue }.joined(separator: ", ")
        return "\(item.name) — care not recorded on: \(names); "
            + "the plan relies on these axes, so the garment is not marked safe"
    }

    // MARK: Conflicts, in published axis order

    static func conflicts(for item: BasketItem, plan: BasketPlan) -> [BasketConflict] {
        var rules: [ConflictRuleSource] = []
        rules.append(contentsOf: washConflicts(item.profile, plan: plan))
        rules.append(contentsOf: bleachConflicts(item.profile, plan: plan))
        rules.append(contentsOf: dryConflicts(item.profile, plan: plan))
        rules.append(contentsOf: ironConflicts(item.profile, plan: plan))
        rules.append(contentsOf: professionalConflicts(item.profile, plan: plan))
        return rules.map { rule in
            BasketConflict(
                garment: item,
                axis: rule.axis,
                rule: rule,
                reason: rule.reason(garmentName: item.name)
            )
        }
    }

    private typealias ConflictRuleSource = BasketConflict.ConflictRule

    private static func washConflicts(
        _ profile: CareProfile, plan: BasketPlan
    ) -> [ConflictRuleSource] {
        guard plan.cleanMode == .machineWash else { return [] }
        var rules: [ConflictRuleSource] = []
        switch profile.wash {
        case .unknown:
            break // surfaced via needsAttention, not a conflict
        case .doNotWash:
            rules.append(.doNotWashViolated)
        case .handWash:
            rules.append(.handWashViolatedByMachinePlan(
                plannedTemperature: plan.washTemperature,
                plannedAction: plan.washAction
            ))
        case let .machine(capTemperature, requiredAction):
            if plan.washTemperature > capTemperature {
                rules.append(.washTemperatureExceeded(
                    cap: capTemperature, planned: plan.washTemperature))
            }
            // Lower rawValue == more aggressive action. The plan must be at
            // least as gentle as the label requires.
            if plan.washAction < requiredAction {
                rules.append(.washActionExceeded(
                    required: requiredAction, planned: plan.washAction))
            }
        }
        return rules
    }

    private static func bleachConflicts(
        _ profile: CareProfile, plan: BasketPlan
    ) -> [ConflictRuleSource] {
        guard let planned = plan.bleach else { return [] }
        var rules: [ConflictRuleSource] = []
        switch profile.bleach {
        case .unknown:
            break
        case .doNotBleach:
            rules.append(.doNotBleachViolated(planned: planned))
        case .allowed(.anyBleach):
            break
        case .allowed(.oxygenOnly):
            if planned == .anyBleach {
                rules.append(.oxygenBleachOnlyViolated(planned: planned))
            }
        }
        return rules
    }

    private static func dryConflicts(
        _ profile: CareProfile, plan: BasketPlan
    ) -> [ConflictRuleSource] {
        guard let drying = plan.drying else { return [] }
        var rules: [ConflictRuleSource] = []
        switch drying {
        case let .tumble(plannedHeat):
            if profile.prohibitions.contains(.doNotTumbleDry) {
                rules.append(.doNotTumbleDryViolated(plannedHeat: plannedHeat))
            }
            switch profile.dry {
            case .unknown:
                break
            case .tumble(let cap):
                if plannedHeat > cap {
                    rules.append(.tumbleHeatExceeded(cap: cap, planned: plannedHeat))
                }
            case .natural(let required):
                rules.append(.naturalDryRequiredButTumblePlanned(
                    required: required, plannedHeat: plannedHeat))
            }
        case let .natural(plannedMethod):
            // Natural drying never violates a tumble cap or the
            // do-not-tumble prohibition; a *different* required natural
            // method does conflict with the plan's chosen method.
            if case .natural(let required) = profile.dry, required != plannedMethod {
                rules.append(.naturalDryMethodMismatch(required: required, planned: plannedMethod))
            }
        }
        return rules
    }

    private static func ironConflicts(
        _ profile: CareProfile, plan: BasketPlan
    ) -> [ConflictRuleSource] {
        guard let planned = plan.iron else { return [] }
        var rules: [ConflictRuleSource] = []
        switch profile.iron {
        case .unknown:
            break
        case .doNotIron:
            rules.append(.doNotIronViolated(planned: planned))
        case .cap(let cap):
            if planned > cap {
                rules.append(.ironCapExceeded(cap: cap, planned: planned))
            }
        }
        return rules
    }

    private static func professionalConflicts(
        _ profile: CareProfile, plan: BasketPlan
    ) -> [ConflictRuleSource] {
        var rules: [ConflictRuleSource] = []
        switch plan.cleanMode {
        case .machineWash:
            // Dry-clean-required garments never pass in a wet plan
            // (issue #3 example: "dry-clean-only in a wet plan").
            if case .requires(let kind) = profile.professional {
                rules.append(.dryCleanRequiredInWetPlan(kind: kind))
            }
        case .dryClean:
            if profile.professional == .doNotDryClean
                || profile.prohibitions.contains(.doNotDryClean) {
                rules.append(.doNotDryCleanViolated)
            }
        }
        return rules
    }
}

private extension Sequence where Element == CareAxis {
    /// Keeps first occurrence, then re-sorts to the published axis order.
    func filterUniqueInPublishedOrder() -> [CareAxis] {
        let seen = Set(self)
        return CareAxis.allCases.filter(seen.contains)
    }
}
