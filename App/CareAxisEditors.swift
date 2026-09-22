import CareKit
import SwiftUI

// Issue #5: the five care-axis editors.
//
// Each editor is one Form `Section` bound to a `CareProfile` axis:
// defaults to `.unknown`, summarizes the current rule in its header, and
// links to the symbol reference sheet for its family so users can look up
// what a glyph means while recording it. Sections (not disclosure groups)
// keep every control in the accessibility tree for VoiceOver and UI tests.
//
// The mode pickers already express every explicit prohibition
// ("do not wash / bleach / iron / dry clean" as axis states; "do not tumble
// dry" and "do not wring" as drying states), so there are no separate
// prohibition toggles — one source of truth per state.

// MARK: - Wash

struct WashAxisEditor: View {
    @Binding var profile: CareProfile

    private enum Mode: Hashable {
        case unknown, doNotWash, handWash, machine
    }

    private var mode: Binding<Mode> {
        Binding(
            get: {
                switch profile.wash {
                case .unknown: .unknown
                case .doNotWash: .doNotWash
                case .handWash: .handWash
                case .machine: .machine
                }
            },
            set: { newMode in
                switch newMode {
                case .unknown: profile.wash = .unknown
                case .doNotWash: profile.wash = .doNotWash
                case .handWash: profile.wash = .handWash
                case .machine:
                    if case .machine = profile.wash { break }
                    profile.wash = .machine(temperature: .celsius40, action: .normal)
                }
            }
        )
    }

    var body: some View {
        Section {
            Picker("Wash", selection: mode) {
                Text("Not recorded").tag(Mode.unknown)
                Text("Do not wash at home").tag(Mode.doNotWash)
                Text("Hand wash only").tag(Mode.handWash)
                Text("Machine wash").tag(Mode.machine)
            }
            // navigationLink style: options open as a pushed list whose rows
            // are reliably queryable (menu popups are not, in CI XCUITest).
            .pickerStyle(.navigationLink)
            .accessibilityIdentifier("axis.wash.mode")

            if case .machine = profile.wash {
                Picker("Maximum temperature", selection: tempBinding) {
                    ForEach(WashTemperature.allCases, id: \.self) { temp in
                        Text(temp.celsiusDescription).tag(temp)
                    }
                }
                .accessibilityIdentifier("axis.wash.temp")
                Picker("Cycle", selection: actionBinding) {
                    Text("Normal").tag(WashAction.normal)
                    Text("Permanent press").tag(WashAction.permanentPress)
                    Text("Gentle").tag(WashAction.gentle)
                }
                .accessibilityIdentifier("axis.wash.action")
            }
            SymbolSheetLink(family: .wash)
        } header: {
            AxisHeader(axis: .wash, value: CarePlainLanguageRenderer.washRule(profile.wash))
        }
    }

    private var tempBinding: Binding<WashTemperature> {
        Binding(
            get: { if case let .machine(t, _) = profile.wash { t } else { .celsius40 } },
            set: { t in
                let action: WashAction =
                    if case let .machine(_, a) = profile.wash { a } else { .normal }
                profile.wash = .machine(temperature: t, action: action)
            }
        )
    }

    private var actionBinding: Binding<WashAction> {
        Binding(
            get: { if case let .machine(_, a) = profile.wash { a } else { .normal } },
            set: { a in
                let temp: WashTemperature =
                    if case let .machine(t, _) = profile.wash { t } else { .celsius40 }
                profile.wash = .machine(temperature: temp, action: a)
            }
        )
    }
}

// MARK: - Bleach

struct BleachAxisEditor: View {
    @Binding var profile: CareProfile

    private enum Mode: Hashable {
        case unknown, anyBleach, oxygenOnly, doNotBleach
    }

    private var mode: Binding<Mode> {
        Binding(
            get: {
                switch profile.bleach {
                case .unknown: .unknown
                case .allowed(.anyBleach): .anyBleach
                case .allowed(.oxygenOnly): .oxygenOnly
                case .doNotBleach: .doNotBleach
                }
            },
            set: { newMode in
                switch newMode {
                case .unknown: profile.bleach = .unknown
                case .anyBleach: profile.bleach = .allowed(.anyBleach)
                case .oxygenOnly: profile.bleach = .allowed(.oxygenOnly)
                case .doNotBleach: profile.bleach = .doNotBleach
                }
            }
        )
    }

    var body: some View {
        Section {
            Picker("Bleach", selection: mode) {
                Text("Not recorded").tag(Mode.unknown)
                Text("Any bleach").tag(Mode.anyBleach)
                Text("Oxygen (color-safe) only").tag(Mode.oxygenOnly)
                Text("Do not bleach").tag(Mode.doNotBleach)
            }
            // navigationLink style: options open as a pushed list whose rows
            // are reliably queryable (menu popups are not, in CI XCUITest).
            .pickerStyle(.navigationLink)
            .accessibilityIdentifier("axis.bleach.mode")
            SymbolSheetLink(family: .bleach)
        } header: {
            AxisHeader(axis: .bleach, value: CarePlainLanguageRenderer.bleachRule(profile.bleach))
        }
    }
}

// MARK: - Dry

struct DryAxisEditor: View {
    @Binding var profile: CareProfile

    private enum Mode: Hashable {
        case unknown, tumble, natural, noTumble, noWring
    }

    private var mode: Binding<Mode> {
        Binding(
            get: {
                if profile.prohibitions.contains(.doNotTumbleDry)
                    && profile.dry == .unknown && !profile.prohibitions.contains(.doNotWring) {
                    return .noTumble
                }
                if profile.prohibitions.contains(.doNotWring)
                    && profile.dry == .unknown && !profile.prohibitions.contains(.doNotTumbleDry) {
                    return .noWring
                }
                switch profile.dry {
                case .unknown: return .unknown
                case .tumble: return .tumble
                case .natural: return .natural
                }
            },
            set: { newMode in
                switch newMode {
                case .unknown:
                    profile.dry = .unknown
                    profile.prohibitions.remove(.doNotTumbleDry)
                    profile.prohibitions.remove(.doNotWring)
                case .tumble:
                    if case .tumble = profile.dry { break }
                    profile.dry = .tumble(heat: .normal)
                    profile.prohibitions.remove(.doNotTumbleDry)
                    profile.prohibitions.remove(.doNotWring)
                case .natural:
                    if case .natural = profile.dry { break }
                    profile.dry = .natural(.hang)
                    profile.prohibitions.remove(.doNotTumbleDry)
                    profile.prohibitions.remove(.doNotWring)
                case .noTumble:
                    profile.dry = .unknown
                    profile.prohibitions.remove(.doNotWring)
                    profile.prohibitions.insert(.doNotTumbleDry)
                case .noWring:
                    profile.dry = .unknown
                    profile.prohibitions.remove(.doNotTumbleDry)
                    profile.prohibitions.insert(.doNotWring)
                }
            }
        )
    }

    var body: some View {
        Section {
            Picker("Drying", selection: mode) {
                Text("Not recorded").tag(Mode.unknown)
                Text("Tumble dry").tag(Mode.tumble)
                Text("Natural dry").tag(Mode.natural)
                Text("Do not tumble dry").tag(Mode.noTumble)
                Text("Do not wring").tag(Mode.noWring)
            }
            // navigationLink style: options open as a pushed list whose rows
            // are reliably queryable (menu popups are not, in CI XCUITest).
            .pickerStyle(.navigationLink)
            .accessibilityIdentifier("axis.dry.mode")

            if case .tumble = profile.dry {
                Picker("Heat", selection: heatBinding) {
                    Text("Low").tag(DryHeat.low)
                    Text("Normal").tag(DryHeat.normal)
                    Text("High").tag(DryHeat.high)
                }
                .accessibilityIdentifier("axis.dry.heat")
            }
            if case .natural = profile.dry {
                Picker("Method", selection: methodBinding) {
                    Text("Dry flat").tag(NaturalDryMethod.flat)
                    Text("Line dry").tag(NaturalDryMethod.hang)
                    Text("Drip dry").tag(NaturalDryMethod.drip)
                }
                .accessibilityIdentifier("axis.dry.method")
            }
            SymbolSheetLink(family: .drying)
        } header: {
            AxisHeader(axis: .dry, value: drySummary)
        }
    }

    private var drySummary: String {
        var parts = [CarePlainLanguageRenderer.dryRule(profile.dry)]
        if profile.prohibitions.contains(.doNotTumbleDry) {
            parts.append(CarePlainLanguageRenderer.prohibitionRule(.doNotTumbleDry))
        }
        if profile.prohibitions.contains(.doNotWring) {
            parts.append(CarePlainLanguageRenderer.prohibitionRule(.doNotWring))
        }
        return parts.joined(separator: "; ")
    }

    private var heatBinding: Binding<DryHeat> {
        Binding(
            get: { if case let .tumble(h) = profile.dry { h } else { .normal } },
            set: { profile.dry = .tumble(heat: $0) }
        )
    }

    private var methodBinding: Binding<NaturalDryMethod> {
        Binding(
            get: { if case let .natural(m) = profile.dry { m } else { .hang } },
            set: { profile.dry = .natural($0) }
        )
    }
}

// MARK: - Iron

struct IronAxisEditor: View {
    @Binding var profile: CareProfile

    private enum Mode: Hashable {
        case unknown, doNotIron, capped
    }

    private var mode: Binding<Mode> {
        Binding(
            get: {
                switch profile.iron {
                case .unknown: .unknown
                case .doNotIron: .doNotIron
                case .cap: .capped
                }
            },
            set: { newMode in
                switch newMode {
                case .unknown: profile.iron = .unknown
                case .doNotIron: profile.iron = .doNotIron
                case .capped:
                    if case .cap = profile.iron { break }
                    profile.iron = .cap(.celsius150)
                }
            }
        )
    }

    var body: some View {
        Section {
            Picker("Ironing", selection: mode) {
                Text("Not recorded").tag(Mode.unknown)
                Text("Do not iron").tag(Mode.doNotIron)
                Text("Iron with a temperature cap").tag(Mode.capped)
            }
            // navigationLink style: options open as a pushed list whose rows
            // are reliably queryable (menu popups are not, in CI XCUITest).
            .pickerStyle(.navigationLink)
            .accessibilityIdentifier("axis.iron.mode")

            if case .cap = profile.iron {
                Picker("Soleplate cap", selection: capBinding) {
                    ForEach(IronTemperature.allCases, id: \.self) { temp in
                        Text(temp.celsiusDescription).tag(temp)
                    }
                }
                .accessibilityIdentifier("axis.iron.cap")
            }
            SymbolSheetLink(family: .iron)
        } header: {
            AxisHeader(axis: .iron, value: CarePlainLanguageRenderer.ironRule(profile.iron))
        }
    }

    private var capBinding: Binding<IronTemperature> {
        Binding(
            get: { if case let .cap(t) = profile.iron { t } else { .celsius150 } },
            set: { profile.iron = .cap($0) }
        )
    }
}

// MARK: - Professional cleaning

struct ProfessionalAxisEditor: View {
    @Binding var profile: CareProfile

    private enum Mode: Hashable {
        case unknown, requires, doNotDryClean
    }

    private var mode: Binding<Mode> {
        Binding(
            get: {
                switch profile.professional {
                case .unknown: .unknown
                case .requires: .requires
                case .doNotDryClean: .doNotDryClean
                }
            },
            set: { newMode in
                switch newMode {
                case .unknown: profile.professional = .unknown
                case .requires:
                    if case .requires = profile.professional { break }
                    profile.professional = .requires(.dryCleanAnySolvent)
                case .doNotDryClean: profile.professional = .doNotDryClean
                }
            }
        )
    }

    var body: some View {
        Section {
            Picker("Professional cleaning", selection: mode) {
                Text("Not recorded").tag(Mode.unknown)
                Text("Requires professional cleaning").tag(Mode.requires)
                Text("Do not dry clean").tag(Mode.doNotDryClean)
            }
            // navigationLink style: options open as a pushed list whose rows
            // are reliably queryable (menu popups are not, in CI XCUITest).
            .pickerStyle(.navigationLink)
            .accessibilityIdentifier("axis.professional.mode")

            if case .requires = profile.professional {
                Picker("Process", selection: kindBinding) {
                    Text("Dry clean, any solvent").tag(ProfessionalKind.dryCleanAnySolvent)
                    Text("Dry clean, hydrocarbon solvents (F)").tag(ProfessionalKind.hydrocarbon)
                    Text("Dry clean, perchloroethylene family (P)").tag(ProfessionalKind.perchloroethylene)
                    Text("Professional wet cleaning (W)").tag(ProfessionalKind.wetClean)
                }
                .accessibilityIdentifier("axis.professional.kind")
            }
            SymbolSheetLink(family: .professional)
        } header: {
            AxisHeader(axis: .professionalCleaning, value: CarePlainLanguageRenderer.professionalRule(profile.professional))
        }
    }

    private var kindBinding: Binding<ProfessionalKind> {
        Binding(
            get: { if case let .requires(k) = profile.professional { k } else { .dryCleanAnySolvent } },
            set: { profile.professional = .requires($0) }
        )
    }
}

// MARK: - Shared header + sheet link

/// Section header for one axis: title plus the current plain-language rule.
struct AxisHeader: View {
    let axis: CareAxis
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(axis.title)
            Text(value)
                .font(.caption)
                .foregroundStyle(value == CarePlainLanguageRenderer.unknownAxisRule ? .orange : .secondary)
                .lineLimit(2)
        }
        .frame(minHeight: 30)
    }
}

/// Navigation link opening the symbol reference sheet for one family.
struct SymbolSheetLink: View {
    let family: CareSymbolFamily

    var body: some View {
        NavigationLink {
            SymbolReferenceSheet(family: family)
        } label: {
            Label("Symbol reference — \(family.title)", systemImage: "book.closed")
                .frame(minHeight: 44)
        }
        .accessibilityIdentifier("axis.sheet.\(family.rawValue)")
    }
}

extension CareAxis {
    var title: String {
        switch self {
        case .wash: "Wash"
        case .bleach: "Bleach"
        case .dry: "Drying"
        case .iron: "Ironing"
        case .professionalCleaning: "Professional cleaning"
        }
    }
}

// `CareSymbolFamily.title` lives in SymbolReferenceSheet.swift (one owner).
