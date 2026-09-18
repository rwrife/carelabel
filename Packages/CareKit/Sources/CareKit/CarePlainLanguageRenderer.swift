import Foundation

// MARK: - Plain-language rendering
//
// Turns a `CareProfile` into human-readable rules (issue #2 acceptance
// criterion). Ordering is deterministic: the five axes in published
// `CareAxis.allCases` order, then prohibitions in `CaseIterable` order.
// Any axis still `unknown` renders exactly as `unknownAxisRule`, the single
// "care not recorded" sentence required by the issue.

public enum CarePlainLanguageRenderer {
    /// The one sentence every unrecorded axis must render as (PLAN.md:
    /// "unknown" never passes silently).
    public static let unknownAxisRule = "Care not recorded — check the label and add it"

    /// Renders every axis of the profile, in published axis order.
    /// Unrecorded axes render as `unknownAxisRule`; recorded axes render
    /// their rule; each explicit prohibition then gets its own line.
    public static func rules(for profile: CareProfile) -> [String] {
        var rules: [String] = []
        rules.append(washRule(profile.wash))
        rules.append(bleachRule(profile.bleach))
        rules.append(dryRule(profile.dry))
        rules.append(ironRule(profile.iron))
        rules.append(professionalRule(profile.professional))
        for prohibition in profile.orderedProhibitions {
            rules.append(prohibitionRule(prohibition))
        }
        return rules
    }

    static func washRule(_ wash: CareWash) -> String {
        switch wash {
        case .unknown: unknownAxisRule
        case .doNotWash: "Do not wash at home"
        case .handWash: "Hand wash only"
        case let .machine(temperature, action):
            switch action {
            case .normal: "Machine wash up to \(temperature.celsiusDescription), normal cycle"
            case .permanentPress: "Machine wash up to \(temperature.celsiusDescription), permanent-press cycle"
            case .gentle: "Machine wash up to \(temperature.celsiusDescription), gentle cycle"
            }
        }
    }

    static func bleachRule(_ bleach: CareBleach) -> String {
        switch bleach {
        case .unknown: unknownAxisRule
        case .allowed(.anyBleach): "Any bleach may be used"
        case .allowed(.oxygenOnly): "Oxygen-based (color-safe) bleach only"
        case .doNotBleach: "Do not use bleach"
        }
    }

    static func dryRule(_ dry: CareDry) -> String {
        switch dry {
        case .unknown: unknownAxisRule
        case let .tumble(heat):
            switch heat {
            case .low: "Tumble dry, low heat"
            case .normal: "Tumble dry, normal heat"
            case .high: "Tumble dry, high heat"
            }
        case let .natural(method):
            switch method {
            case .flat: "Dry flat"
            case .hang: "Line dry (hang to dry)"
            case .drip: "Drip dry"
            }
        }
    }

    static func ironRule(_ iron: CareIron) -> String {
        switch iron {
        case .unknown: unknownAxisRule
        case .doNotIron: "Do not iron"
        case let .cap(temperature): "Iron up to \(temperature.celsiusDescription) soleplate"
        }
    }

    static func professionalRule(_ professional: CareProfessional) -> String {
        switch professional {
        case .unknown: unknownAxisRule
        case .requires(.dryCleanAnySolvent): "Dry clean professionally (any solvent)"
        case .requires(.hydrocarbon): "Dry clean professionally (hydrocarbon solvents only)"
        case .requires(.perchloroethylene): "Dry clean professionally (perchloroethylene-family solvents)"
        case .requires(.wetClean): "Professional wet cleaning"
        case .doNotDryClean: "Do not dry clean"
        }
    }

    static func prohibitionRule(_ prohibition: CareProhibition) -> String {
        switch prohibition {
        case .doNotWash: "Prohibited: do not wash"
        case .doNotBleach: "Prohibited: do not bleach"
        case .doNotTumbleDry: "Prohibited: do not tumble dry"
        case .doNotWring: "Prohibited: do not wring"
        case .doNotIron: "Prohibited: do not iron"
        case .doNotDryClean: "Prohibited: do not dry clean"
        }
    }
}
