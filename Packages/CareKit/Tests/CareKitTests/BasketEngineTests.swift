import Foundation
import Testing
@testable import CareKit

// Issue #3 acceptance tests for the basket compatibility engine:
// - strictest-wins per axis + explicit prohibition checking
// - every conflict names garment, axis, violated rule, and plan value
// - unknown axes surface as needsAttention, never silently safe
// - deterministic ordering (stable garment ordering)
// - table-driven matrix coverage incl. multi-conflict garments and
//   all-unknown baskets.

// MARK: - Fixtures

private func item(
    _ id: String,
    _ name: String,
    _ profile: CareProfile = .unknownProfile
) -> BasketItem {
    BasketItem(id: id, name: name, profile: profile)
}

/// A fully-recorded, maximally permissive profile. Axis-specific matrix tests
/// override exactly one axis so the only attention/conflict possible comes
/// from the axis under test (wash defaults match the default `BasketPlan`).
private func neutralProfile(
    wash: CareWash = .machine(temperature: .celsius40, action: .normal),
    bleach: CareBleach = .allowed(.anyBleach),
    dry: CareDry = .tumble(heat: .high),
    iron: CareIron = .cap(.celsius200),
    professional: CareProfessional = .doNotDryClean,
    prohibitions: Set<CareProhibition> = []
) -> CareProfile {
    CareProfile(
        wash: wash, bleach: bleach, dry: dry, iron: iron,
        professional: professional, prohibitions: prohibitions
    )
}

/// A garment safe for the gentle 30 °C reference plan below.
private let safeTowel = item(
    "towel", "towel",
    neutralProfile(
        wash: .machine(temperature: .celsius60, action: .normal),
        dry: .tumble(heat: .high)
    )
)

/// Delicate garment: 30 °C gentle cap, no bleach, flat dry, low iron.
/// Professional left `.unknown` — a wet plan must not demand it (tested
/// separately).
private let coolSilk = item(
    "silk", "silk",
    CareProfile(
        wash: .machine(temperature: .celsius30, action: .gentle),
        bleach: .doNotBleach,
        dry: .natural(.flat),
        iron: .cap(.celsius110)
    )
)

/// Reference wet plan: 30 °C gentle wash, no bleach, no machine dry, no iron —
/// compatible with both fixture garments above under strictest-wins.
private let referencePlan = BasketPlan(
    washTemperature: .celsius30, washAction: .gentle
)

// MARK: - Grouping + ordering

@Suite("Basket engine grouping")
struct BasketGroupingTests {
    @Test("All-compatible basket forms one strictest-wins group")
    func allCompatible() {
        let eval = BasketEvaluationEngine.evaluate(
            basket: [safeTowel, coolSilk], plan: referencePlan)
        #expect(eval.conflicts.isEmpty)
        #expect(eval.needsAttention.isEmpty)
        #expect(eval.group.members.map(\.id) == ["towel", "silk"])
        #expect(eval.isFullySafe)
    }

    @Test("Conflicted and unknown garments never join the group")
    func unsafeNeverGrouped() {
        let noWash = item("rug", "rug", CareProfile(wash: .doNotWash))
        let mystery = item("mystery", "mystery") // fully unknown
        let eval = BasketEvaluationEngine.evaluate(
            basket: [safeTowel, noWash, mystery, coolSilk], plan: referencePlan)
        #expect(eval.group.members.map(\.id) == ["towel", "silk"])
        #expect(eval.conflicts.map(\.garment.id) == ["rug"])
        #expect(eval.needsAttention.map(\.garment.id) == ["mystery"])
        #expect(!eval.isFullySafe)
    }

    @Test("Output ordering is deterministic for the same basket")
    func orderingIsStable() {
        let rug = item("rug", "rug", CareProfile(wash: .doNotWash))
        let mystery = item("mystery", "mystery")
        let basket = [coolSilk, rug, safeTowel, mystery]
        let first = BasketEvaluationEngine.evaluate(basket: basket, plan: referencePlan)
        let second = BasketEvaluationEngine.evaluate(basket: basket, plan: referencePlan)
        #expect(first == second)
        #expect(first.conflicts.map(\.garment.id) == ["rug"])
        #expect(first.group.members.map(\.id) == ["silk", "towel"])
        // A permuted basket tracks the new input order.
        let permuted = BasketEvaluationEngine.evaluate(
            basket: [rug, mystery, coolSilk, safeTowel], plan: referencePlan)
        #expect(permuted.conflicts.map(\.garment.id) == ["rug"])
        #expect(permuted.needsAttention.map(\.garment.id) == ["mystery"])
        #expect(permuted.group.members.map(\.id) == ["silk", "towel"])
    }

    @Test("Empty basket evaluates to an empty safe group")
    func emptyBasket() {
        let eval = BasketEvaluationEngine.evaluate(basket: [], plan: referencePlan)
        #expect(eval.group.members.isEmpty)
        #expect(eval.conflicts.isEmpty)
        #expect(eval.needsAttention.isEmpty)
        #expect(eval.isFullySafe)
    }

    @Test("The evaluation echoes the exact plan into the group")
    func groupCarriesPlan() {
        let eval = BasketEvaluationEngine.evaluate(basket: [safeTowel], plan: referencePlan)
        #expect(eval.group.plan == referencePlan)
    }
}

// MARK: - Wash axis matrix

@Suite("Basket engine wash axis")
struct BasketWashAxisTests {
    struct WashCase: Sendable {
        let label: String
        let wash: CareWash
        let planTemp: WashTemperature
        let planAction: WashAction
        let expected: [BasketConflict.ConflictRule]
    }

    static let matrix: [WashCase] = {
        var cases: [WashCase] = []
        let recorded: [CareWash] = [
            .doNotWash, .handWash,
            .machine(temperature: .celsius30, action: .gentle),
            .machine(temperature: .celsius40, action: .permanentPress),
            .machine(temperature: .celsius60, action: .normal),
        ]
        let plans: [(WashTemperature, WashAction)] = [
            (.celsius30, .gentle), (.celsius40, .normal), (.celsius60, .normal),
        ]
        for plan in plans {
            cases.append(WashCase(
                label: "unknown @ \(plan.0)-\(plan.1)",
                wash: .unknown, planTemp: plan.0, planAction: plan.1,
                expected: [] // unknown -> needsAttention, not a conflict
            ))
            for wash in recorded {
                var expected: [BasketConflict.ConflictRule] = []
                switch wash {
                case .unknown: continue
                case .doNotWash:
                    expected.append(.doNotWashViolated)
                case .handWash:
                    expected.append(.handWashViolatedByMachinePlan(
                        plannedTemperature: plan.0, plannedAction: plan.1))
                case let .machine(cap, required):
                    if plan.0 > cap {
                        expected.append(.washTemperatureExceeded(cap: cap, planned: plan.0))
                    }
                    if plan.1 < required {
                        expected.append(.washActionExceeded(required: required, planned: plan.1))
                    }
                }
                cases.append(WashCase(
                    label: "machine cap vs plan",
                    wash: wash, planTemp: plan.0, planAction: plan.1,
                    expected: expected
                ))
            }
        }
        return cases
    }()

    @Test("Wash matrix: expected conflicts match exactly", arguments: matrix)
    func washMatrix(_ testCase: WashCase) {
        let garment = item("g", "g", neutralProfile(wash: testCase.wash))
        let plan = BasketPlan(
            washTemperature: testCase.planTemp, washAction: testCase.planAction)
        let eval = BasketEvaluationEngine.evaluate(basket: [garment], plan: plan)
        #expect(eval.conflicts.map(\.rule) == testCase.expected, Comment("\(testCase.label)"))
        // Unknown wash on a wet plan must always surface as needsAttention
        // on exactly the wash axis.
        if testCase.wash == .unknown {
            #expect(eval.needsAttention.map(\.garment.id) == ["g"])
            #expect(eval.needsAttention[0].axes == [.wash])
        } else {
            #expect(eval.needsAttention.isEmpty)
        }
    }

    @Test("Strictest-wins across a group: hotter plan conflicts the cooler cap")
    func strictestWinsTemp() {
        let plan = BasketPlan(washTemperature: .celsius60, washAction: .normal)
        let eval = BasketEvaluationEngine.evaluate(
            basket: [safeTowel, coolSilk], plan: plan)
        let silkConflicts = eval.conflicts.filter { $0.garment.id == "silk" }
        #expect(silkConflicts.map(\.rule) == [
            .washTemperatureExceeded(cap: .celsius30, planned: .celsius60),
            .washActionExceeded(required: .gentle, planned: .normal),
        ])
        #expect(eval.group.members.map(\.id) == ["towel"])
    }

    @Test("Gentleness: gentle-required garment conflicts any harsher plan action")
    func strictestWinsAction() {
        // 30 °C gentle plan: silk's 30/gentle caps are honored exactly.
        let gentlePlan = BasketPlan(washTemperature: .celsius30, washAction: .gentle)
        let eval = BasketEvaluationEngine.evaluate(basket: [coolSilk], plan: gentlePlan)
        #expect(eval.conflicts.isEmpty)
        #expect(eval.isFullySafe)
        // Same temperature but normal action is too aggressive.
        let harshPlan = BasketPlan(washTemperature: .celsius30, washAction: .normal)
        let harshEval = BasketEvaluationEngine.evaluate(basket: [coolSilk], plan: harshPlan)
        #expect(harshEval.conflicts.map(\.rule) == [
            .washActionExceeded(required: .gentle, planned: .normal)
        ])
    }

    @Test("Hand-wash and do-not-wash conflict wording names plan values")
    func washSpecialStates() {
        let plan = BasketPlan(washTemperature: .celsius40, washAction: .gentle)
        let hand = item("hand", "hand sweater", neutralProfile(wash: .handWash))
        let noWash = item("rug", "rug", neutralProfile(wash: .doNotWash))
        let eval = BasketEvaluationEngine.evaluate(basket: [hand, noWash], plan: plan)
        #expect(eval.conflicts[0].reason == "hand sweater — wash: label says hand wash only; plan machine washes at 40 °C, gentle cycle")
        #expect(eval.conflicts[1].reason == "rug — wash: label says do not wash; plan is a machine-wash plan")
    }
}

// MARK: - Bleach axis

@Suite("Basket engine bleach axis")
struct BasketBleachAxisTests {
    struct BleachCase: Sendable {
        let label: String
        let bleach: CareBleach
        let planBleach: BleachKind?
        let expected: [BasketConflict.ConflictRule]
        let expectAttention: Bool
    }

    static let matrix: [BleachCase] = {
        var cases: [BleachCase] = []
        let recorded: [CareBleach] = [.allowed(.anyBleach), .allowed(.oxygenOnly), .doNotBleach]
        for planBleach in [BleachKind?.some(.anyBleach), .some(.oxygenOnly), nil] {
            cases.append(BleachCase(
                label: "unknown vs \(String(describing: planBleach))",
                bleach: .unknown, planBleach: planBleach,
                expected: [], expectAttention: planBleach != nil
            ))
            for state in recorded {
                var expected: [BasketConflict.ConflictRule] = []
                if let planned = planBleach {
                    switch state {
                    case .unknown: continue
                    case .doNotBleach:
                        expected.append(.doNotBleachViolated(planned: planned))
                    case .allowed(.anyBleach):
                        break
                    case .allowed(.oxygenOnly):
                        if planned == .anyBleach {
                            expected.append(.oxygenBleachOnlyViolated(planned: planned))
                        }
                    }
                }
                cases.append(BleachCase(
                    label: "\(state) vs \(String(describing: planBleach))",
                    bleach: state, planBleach: planBleach,
                    expected: expected, expectAttention: false
                ))
            }
        }
        return cases
    }()

    @Test("Bleach matrix", arguments: matrix)
    func bleachMatrix(_ testCase: BleachCase) {
        let garment = item("g", "g", neutralProfile(bleach: testCase.bleach))
        let plan = BasketPlan(bleach: testCase.planBleach)
        let eval = BasketEvaluationEngine.evaluate(basket: [garment], plan: plan)
        #expect(eval.conflicts.map(\.rule) == testCase.expected, Comment("\(testCase.label)"))
        if testCase.expectAttention {
            #expect(eval.needsAttention.map(\.axes) == [[.bleach]])
        } else {
            #expect(eval.needsAttention.isEmpty, Comment("\(testCase.label)"))
        }
    }

    @Test("Oxygen-only garment survives an oxygen-only plan")
    func oxygenPlanHonorsOxygenCap() {
        let garment = item("tee", "tee", neutralProfile(bleach: .allowed(.oxygenOnly)))
        let eval = BasketEvaluationEngine.evaluate(
            basket: [garment], plan: BasketPlan(bleach: .oxygenOnly))
        #expect(eval.conflicts.isEmpty)
        #expect(eval.isFullySafe)
    }
}

// MARK: - Dry axis + prohibitions

@Suite("Basket engine dry axis")
struct BasketDryAxisTests {
    struct DryCase: Sendable {
        let label: String
        let dry: CareDry
        let prohibitions: Set<CareProhibition>
        let planDry: BasketPlan.PlanDry?
        let expected: [BasketConflict.ConflictRule]
    }

    static let matrix: [DryCase] = {
        var cases: [DryCase] = []
        let planDrys: [BasketPlan.PlanDry?] = [
            .tumble(heat: .low), .tumble(heat: .normal), .tumble(heat: .high),
            .natural(method: .flat), .natural(method: .hang), .natural(method: .drip),
            nil,
        ]
        let recorded: [(CareDry, Set<CareProhibition>)] = [
            (.tumble(heat: .low), []),
            (.tumble(heat: .normal), []),
            (.tumble(heat: .high), []),
            (.natural(.flat), []),
            (.natural(.hang), []),
            (.natural(.drip), []),
            (.unknown, [.doNotTumbleDry]), // prohibition recorded, axis unknown
        ]
        for planDry in planDrys {
            cases.append(DryCase(
                label: "unknown vs \(String(describing: planDry))",
                dry: .unknown, prohibitions: [], planDry: planDry,
                expected: []
            ))
            for (dry, prohibitions) in recorded {
                var expected: [BasketConflict.ConflictRule] = []
                if let planDry {
                    switch planDry {
                    case let .tumble(plannedHeat):
                        if prohibitions.contains(.doNotTumbleDry) {
                            expected.append(.doNotTumbleDryViolated(plannedHeat: plannedHeat))
                        }
                        switch dry {
                        case .unknown: break
                        case .tumble(let cap):
                            if plannedHeat > cap {
                                expected.append(.tumbleHeatExceeded(cap: cap, planned: plannedHeat))
                            }
                        case .natural(let required):
                            expected.append(.naturalDryRequiredButTumblePlanned(
                                required: required, plannedHeat: plannedHeat))
                        }
                    case .natural(let plannedMethod):
                        if case .natural(let required) = dry, required != plannedMethod {
                            expected.append(.naturalDryMethodMismatch(
                                required: required, planned: plannedMethod))
                        }
                    }
                }
                cases.append(DryCase(
                    label: "recorded vs plan",
                    dry: dry, prohibitions: prohibitions, planDry: planDry,
                    expected: expected
                ))
            }
        }
        return cases
    }()

    @Test("Dry matrix", arguments: matrix)
    func dryMatrix(_ testCase: DryCase) {
        let garment = item("g", "g", neutralProfile(dry: testCase.dry, prohibitions: testCase.prohibitions))
        let plan = BasketPlan(drying: testCase.planDry)
        let eval = BasketEvaluationEngine.evaluate(basket: [garment], plan: plan)
        #expect(eval.conflicts.map(\.rule) == testCase.expected, Comment("\(testCase.label)"))
        // Unknown dry axis always needs attention when the plan dries.
        if testCase.dry == .unknown, testCase.planDry != nil {
            #expect(eval.needsAttention.map(\.axes) == [[.dry]])
        } else {
            #expect(eval.needsAttention.isEmpty, Comment("\(testCase.label)"))
        }
    }

    @Test("Do-not-tumble-dry prohibition conflicts every tumble plan heat")
    func doNotTumbleProhibition() {
        let garment = item("knit", "knit", neutralProfile(
            wash: .machine(temperature: .celsius30, action: .gentle),
            dry: .unknown, prohibitions: [.doNotTumbleDry]))
        for heat in DryHeat.allCases {
            let eval = BasketEvaluationEngine.evaluate(
                basket: [garment],
                plan: BasketPlan(
                    washTemperature: .celsius30, washAction: .gentle,
                    drying: .tumble(heat: heat)))
            #expect(eval.conflicts.map(\.rule) == [
                .doNotTumbleDryViolated(plannedHeat: heat)
            ], "heat \(heat)")
            #expect(eval.conflicts[0].reason.hasPrefix("knit — dry: label says do not tumble dry"))
            // Axis still unknown too — attention accompanies the conflict.
            #expect(eval.needsAttention.count == 1)
        }
        // A natural-dry plan honors the prohibition.
        let safeEval = BasketEvaluationEngine.evaluate(
            basket: [garment],
            plan: BasketPlan(washTemperature: .celsius30, washAction: .gentle,
                             drying: .natural(method: .flat)))
        #expect(safeEval.conflicts.isEmpty)
    }

    @Test("Tumble heat strictest-wins: normal cap conflicts high plan only")
    func tumbleHeatCap() {
        let garment = item("tee", "tee", neutralProfile(dry: .tumble(heat: .normal)))
        #expect(BasketEvaluationEngine.evaluate(
            basket: [garment], plan: BasketPlan(drying: .tumble(heat: .low))
        ).conflicts.isEmpty)
        #expect(BasketEvaluationEngine.evaluate(
            basket: [garment], plan: BasketPlan(drying: .tumble(heat: .normal))
        ).conflicts.isEmpty)
        let hot = BasketEvaluationEngine.evaluate(
            basket: [garment], plan: BasketPlan(drying: .tumble(heat: .high)))
        #expect(hot.conflicts.map(\.rule) == [
            .tumbleHeatExceeded(cap: .normal, planned: .high)
        ])
        #expect(hot.conflicts[0].reason == "tee — dry: label caps tumble heat at normal; plan tumble dries on high heat")
    }

    @Test("Do-not-wring prohibition is never falsely violated")
    func wringNotInPlanVocabulary() {
        // The plan vocabulary has no wring value: a wring prohibition must not
        // produce conflicts on any plan. All other axes are recorded and
        // honored here, so the garment can be safely grouped.
        let garment = item("g", "g", neutralProfile(
            dry: .natural(.hang), prohibitions: [.doNotWring]))
        let eval = BasketEvaluationEngine.evaluate(
            basket: [garment],
            plan: BasketPlan(drying: .natural(method: .hang)))
        #expect(eval.conflicts.isEmpty)
        #expect(eval.needsAttention.isEmpty)
    }
}

// MARK: - Iron axis

@Suite("Basket engine iron axis")
struct BasketIronAxisTests {
    struct IronCase: Sendable {
        let label: String
        let iron: CareIron
        let planIron: IronTemperature?
        let expected: [BasketConflict.ConflictRule]
        let expectAttention: Bool
    }

    static let matrix: [IronCase] = {
        var cases: [IronCase] = []
        let recorded: [CareIron] = [.doNotIron, .cap(.celsius110), .cap(.celsius150), .cap(.celsius200)]
        for planIron in [IronTemperature?.some(.celsius110), .some(.celsius150), .some(.celsius200), nil] {
            cases.append(IronCase(
                label: "unknown vs \(String(describing: planIron))",
                iron: .unknown, planIron: planIron,
                expected: [], expectAttention: planIron != nil
            ))
            for state in recorded {
                var expected: [BasketConflict.ConflictRule] = []
                if let planned = planIron {
                    switch state {
                    case .unknown: continue
                    case .doNotIron:
                        expected.append(.doNotIronViolated(planned: planned))
                    case .cap(let cap):
                        if planned > cap {
                            expected.append(.ironCapExceeded(cap: cap, planned: planned))
                        }
                    }
                }
                cases.append(IronCase(
                    label: "\(state) vs \(String(describing: planIron))",
                    iron: state, planIron: planIron,
                    expected: expected, expectAttention: false
                ))
            }
        }
        return cases
    }()

    @Test("Iron matrix", arguments: matrix)
    func ironMatrix(_ testCase: IronCase) {
        let garment = item("g", "g", neutralProfile(iron: testCase.iron))
        let eval = BasketEvaluationEngine.evaluate(
            basket: [garment], plan: BasketPlan(iron: testCase.planIron))
        #expect(eval.conflicts.map(\.rule) == testCase.expected, Comment("\(testCase.label)"))
        if testCase.expectAttention {
            #expect(eval.needsAttention.map(\.axes) == [[.iron]])
        } else {
            #expect(eval.needsAttention.isEmpty, Comment("\(testCase.label)"))
        }
    }

    @Test("Do-not-iron prohibition conflicts any iron plan")
    func doNotIronProhibition() {
        let garment = item("nylon", "nylon jacket", neutralProfile(iron: .doNotIron))
        let eval = BasketEvaluationEngine.evaluate(
            basket: [garment], plan: BasketPlan(iron: .celsius150))
        #expect(eval.conflicts.map(\.rule) == [.doNotIronViolated(planned: .celsius150)])
        #expect(eval.conflicts[0].reason == "nylon jacket — iron: label says do not iron; plan irons at 150 °C")
    }
}

// MARK: - Professional axis

@Suite("Basket engine professional axis")
struct BasketProfessionalAxisTests {
    @Test("Dry-clean-required garment conflicts every machine-wash plan")
    func dryCleanOnlyInWetPlan() {
        let suit = item("suit", "wool suit",
                        neutralProfile(professional: .requires(.perchloroethylene)))
        let eval = BasketEvaluationEngine.evaluate(basket: [suit], plan: referencePlan)
        #expect(eval.conflicts.map(\.rule) == [
            .dryCleanRequiredInWetPlan(kind: .perchloroethylene)
        ])
        #expect(eval.conflicts[0].reason == "wool suit — professionalCleaning: label requires professional cleaning (dry clean, perchloroethylene-family solvents); plan is a machine-wash plan")
    }

    @Test("Dry-clean plan honors requires and blocks do-not-dry-clean")
    func dryCleanPlan() {
        let suit = item("suit", "wool suit",
                        neutralProfile(professional: .requires(.dryCleanAnySolvent)))
        let record = item("record", "vinyl sleeve",
                          neutralProfile(professional: .doNotDryClean))
        let eval = BasketEvaluationEngine.evaluate(
            basket: [suit, record], plan: BasketPlan(cleanMode: .dryClean))
        #expect(eval.group.members.map(\.id) == ["suit"])
        #expect(eval.conflicts.map(\.rule) == [.doNotDryCleanViolated])
        #expect(eval.conflicts[0].garment.id == "record")
        #expect(eval.conflicts[0].reason == "vinyl sleeve — professionalCleaning: label says do not dry clean; plan is a dry-clean plan")
    }

    @Test("Dry-clean plan requires the professional axis to be recorded")
    func dryCleanPlanUnknownAttention() {
        // Professional unknown but plan is dry-clean: attention, not silent
        // safe.
        let garment = item("g", "g", neutralProfile(professional: .unknown))
        let eval = BasketEvaluationEngine.evaluate(
            basket: [garment], plan: BasketPlan(cleanMode: .dryClean))
        #expect(eval.conflicts.isEmpty)
        #expect(eval.needsAttention.map(\.axes) == [[.professionalCleaning]])
        #expect(!eval.isFullySafe)
    }

    @Test("Wet plan does not demand a recorded professional axis")
    func wetPlanIgnoresUnknownProfessional() {
        // Professional unknown, wet plan: the plan makes no claim on that
        // axis, so the garment can still be safe on the recorded axes.
        let garment = item("g", "g", neutralProfile(professional: .unknown))
        let eval = BasketEvaluationEngine.evaluate(basket: [garment], plan: referencePlan)
        #expect(eval.needsAttention.isEmpty)
        #expect(eval.isFullySafe)
    }
}

// MARK: - Unknown-axis semantics

@Suite("Basket engine unknown semantics")
struct BasketUnknownAxisTests {
    @Test("All-unknown basket: every garment is needsAttention, none safe")
    func allUnknownBasket() {
        let basket = (1...5).map { item("m\($0)", "mystery-\($0)") }
        let plans: [BasketPlan] = [
            referencePlan,
            BasketPlan(cleanMode: .dryClean),
            BasketPlan(bleach: .anyBleach, drying: .tumble(heat: .high), iron: .celsius200),
        ]
        for plan in plans {
            let eval = BasketEvaluationEngine.evaluate(basket: basket, plan: plan)
            #expect(eval.conflicts.isEmpty, "\(plan.cleanMode)")
            #expect(eval.group.members.isEmpty)
            #expect(eval.needsAttention.count == 5)
            for attention in eval.needsAttention {
                // A fully-unknown garment always lists all five published axes.
                #expect(attention.axes == CareAxis.allCases)
                #expect(attention.reason.contains("care not recorded on: wash, bleach, dry, iron, professionalCleaning"))
            }
            #expect(!eval.isFullySafe)
        }
    }

    @Test("One unknown axis exercised by the plan blocks the group")
    func singleUnknownExercisedAxis() {
        let garment = item("g", "g", neutralProfile(bleach: .unknown))
        let eval = BasketEvaluationEngine.evaluate(
            basket: [garment], plan: BasketPlan(bleach: .oxygenOnly))
        #expect(eval.needsAttention.map(\.axes) == [[.bleach]])
        #expect(eval.group.members.isEmpty)
        #expect(!eval.isFullySafe)
    }

    @Test("Needs-attention axes are reported in published axis order")
    func attentionAxesOrder() {
        let garment = item("g", "g", neutralProfile(
            wash: .unknown, bleach: .unknown, dry: .unknown))
        let plan = BasketPlan(
            washTemperature: .celsius40, washAction: .normal,
            bleach: .anyBleach, drying: .tumble(heat: .low))
        let eval = BasketEvaluationEngine.evaluate(basket: [garment], plan: plan)
        #expect(eval.needsAttention.map(\.axes) == [[.wash, .bleach, .dry]])
    }

    @Test("A recorded prohibition does not mark its axis as recorded for attention")
    func prohibitionOnlyAxisStillUnknown() {
        // Dry axis unknown + do-not-tumble-dry recorded: a tumble plan gets
        // BOTH the named conflict and the unknown-axis attention entry — the
        // prohibition alone must not make the engine call the axis safe.
        let garment = item("knit", "knit", neutralProfile(
            dry: .unknown, prohibitions: [.doNotTumbleDry]))
        let eval = BasketEvaluationEngine.evaluate(
            basket: [garment], plan: BasketPlan(drying: .tumble(heat: .low)))
        #expect(eval.conflicts.count == 1)
        #expect(eval.needsAttention.count == 1)
        #expect(eval.needsAttention[0].axes == [.dry])
        #expect(!eval.isFullySafe)
    }
}

// MARK: - Multi-conflict garments

@Suite("Basket engine multi-conflict garments")
struct BasketMultiConflictTests {
    @Test("One garment can carry several conflicts, in published axis order")
    func multiConflictOrder() {
        let victim = item("victim", "mixed knit", CareProfile(
            wash: .machine(temperature: .celsius30, action: .gentle),
            bleach: .doNotBleach,
            dry: .tumble(heat: .low),
            iron: .doNotIron,
            professional: .requires(.hydrocarbon)))
        let plan = BasketPlan(
            cleanMode: .machineWash,
            washTemperature: .celsius60, washAction: .normal,
            bleach: .anyBleach,
            drying: .tumble(heat: .high),
            iron: .celsius200)
        let eval = BasketEvaluationEngine.evaluate(basket: [victim], plan: plan)
        #expect(eval.conflicts.map(\.rule) == [
            .washTemperatureExceeded(cap: .celsius30, planned: .celsius60),
            .washActionExceeded(required: .gentle, planned: .normal),
            .doNotBleachViolated(planned: .anyBleach),
            .tumbleHeatExceeded(cap: .low, planned: .high),
            .doNotIronViolated(planned: .celsius200),
            .dryCleanRequiredInWetPlan(kind: .hydrocarbon),
        ])
        // All conflicts name the same garment; all axes match rule.axis.
        for conflict in eval.conflicts {
            #expect(conflict.garment.id == "victim")
            #expect(conflict.axis == conflict.rule.axis)
            #expect(conflict.reason.hasPrefix("mixed knit — \(conflict.axis.rawValue): "))
        }
        #expect(eval.needsAttention.isEmpty)
    }

    @Test("Every conflict reason names garment, axis, rule, and plan value")
    func reasonsAreFullyNamed() {
        let sample: [BasketConflict.ConflictRule] = [
            .washTemperatureExceeded(cap: .celsius30, planned: .celsius60),
            .doNotBleachViolated(planned: .oxygenOnly),
            .tumbleHeatExceeded(cap: .normal, planned: .high),
            .ironCapExceeded(cap: .celsius110, planned: .celsius200),
        ]
        for rule in sample {
            let reason = rule.reason(garmentName: "G")
            #expect(reason.hasPrefix("G — \(rule.axis.rawValue): "))
            #expect(reason.count > "G — wash: ".count)
        }
    }
}

// MARK: - Natural-dry plans

@Suite("Basket engine natural drying")
struct BasketNaturalDryTests {
    @Test("Flat-dry-required garment conflicts every other natural method")
    func naturalMethodMatrix() {
        let flat = item("sweater", "sweater", neutralProfile(dry: .natural(.flat)))
        for method in NaturalDryMethod.allCases {
            let eval = BasketEvaluationEngine.evaluate(
                basket: [flat], plan: BasketPlan(drying: .natural(method: method)))
            if method == .flat {
                #expect(eval.conflicts.isEmpty, "flat vs flat")
            } else {
                #expect(eval.conflicts.map(\.rule) == [
                    .naturalDryMethodMismatch(required: .flat, planned: method)
                ], "flat vs \(method)")
            }
        }
    }

    @Test("Natural plan never violates a tumble cap or do-not-tumble")
    func naturalHonorsTumbleCaps() {
        let garment = item("g", "g", neutralProfile(
            dry: .unknown, prohibitions: [.doNotTumbleDry]))
        let eval = BasketEvaluationEngine.evaluate(
            basket: [garment], plan: BasketPlan(drying: .natural(method: .hang)))
        #expect(eval.conflicts.isEmpty)
        // Dry axis still unknown -> attention on exactly the dry axis.
        #expect(eval.needsAttention.map(\.axes) == [[.dry]])
    }
}
