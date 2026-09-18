import Foundation

// Issue #2: the pure care domain.
//
// Value semantics only: no Foundation networking, no persistence, no UI.
// Every axis models `unknown` explicitly (PLAN.md risk table: "unknown never
// passes silently"), and explicit manufacturer "do not" prohibitions attach to
// the published `CareAxis` set (see CareContract.swift) — they are not a
// sixth axis.

// MARK: - Wash axis

/// Maximum machine-wash temperature recorded on a care label, in degrees
/// Celsius. Raw ISO 3758 wash-tub numbers (30/40/50/60/70/95).
public enum WashTemperature: Int, Codable, Equatable, Sendable, CaseIterable, Comparable {
    case celsius30 = 30
    case celsius40 = 40
    case celsius50 = 50
    case celsius60 = 60
    case celsius70 = 70
    case celsius95 = 95

    public static func < (lhs: WashTemperature, rhs: WashTemperature) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Plain-language temperature, e.g. "40 °C".
    public var celsiusDescription: String { "\(rawValue) °C" }
}

/// Mechanical action recorded by the bar(s) under a wash tub.
/// Ordered from least to most gentle for later engine use (issue #3).
public enum WashAction: Int, Codable, Equatable, Sendable, CaseIterable, Comparable {
    case normal = 0
    case permanentPress = 1
    case gentle = 2

    public static func < (lhs: WashAction, rhs: WashAction) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The wash axis: an unrecorded state, an explicit "do not wash" (a crossed
/// wash tub on the label), hand-wash-only, or a machine wash with a
/// temperature cap and mechanical action.
public enum CareWash: Codable, Equatable, Sendable {
    case unknown
    case doNotWash
    case handWash
    case machine(temperature: WashTemperature, action: WashAction)
}

// MARK: - Bleach axis

/// Which bleach chemistry the label permits.
public enum BleachKind: String, Codable, Equatable, Sendable, CaseIterable {
    case anyBleach
    case oxygenOnly
}

/// The bleach axis: unrecorded, permitted bleach, or explicit "do not bleach".
public enum CareBleach: Codable, Equatable, Sendable {
    case unknown
    case allowed(BleachKind)
    case doNotBleach
}

// MARK: - Dry axis

/// Tumble-dry heat setting recorded by dot count on a square-and-circle.
/// `Comparable` follows severity (low < normal < high), NOT alphabetical
/// rawValue order — do not "simplify" this to rawValue comparison.
public enum DryHeat: String, Codable, Equatable, Sendable, CaseIterable, Comparable {
    case low
    case normal
    case high

    /// Explicit heat severity rank; matches CaseIterable declaration order.
    public var heatRank: Int {
        switch self {
        case .low: 0
        case .normal: 1
        case .high: 2
        }
    }

    public static func < (lhs: DryHeat, rhs: DryHeat) -> Bool {
        lhs.heatRank < rhs.heatRank
    }
}

/// Natural (non-tumble) drying methods recorded by lines on a square.
public enum NaturalDryMethod: String, Codable, Equatable, Sendable, CaseIterable {
    case flat
    case hang
    case drip
}

/// The dry axis: unrecorded, tumble drying with a heat cap, or a natural
/// drying method. "Do not tumble dry" and "do not wring" are prohibitions
/// (`CareProhibition`), not states of this axis.
public enum CareDry: Codable, Equatable, Sendable {
    case unknown
    case tumble(heat: DryHeat)
    case natural(NaturalDryMethod)
}

// MARK: - Iron axis

/// Iron soleplate temperature caps recorded by dot count on an iron.
public enum IronTemperature: Int, Codable, Equatable, Sendable, CaseIterable, Comparable {
    case celsius110 = 110
    case celsius150 = 150
    case celsius200 = 200

    public static func < (lhs: IronTemperature, rhs: IronTemperature) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var celsiusDescription: String { "\(rawValue) °C" }
}

/// The iron axis: unrecorded, an explicit "do not iron", or a temperature cap.
public enum CareIron: Codable, Equatable, Sendable {
    case unknown
    case doNotIron
    case cap(IronTemperature)
}

// MARK: - Professional cleaning axis

/// Professional-cleaning solvent/method codes recorded by letters in a circle.
public enum ProfessionalKind: String, Codable, Equatable, Sendable, CaseIterable {
    /// Plain circle: professional dry cleaning in any solvent.
    case dryCleanAnySolvent
    /// Circle with F: hydrocarbon solvents only.
    case hydrocarbon
    /// Circle with P: perchloroethylene-family solvents.
    case perchloroethylene
    /// Circle with W: professional wet cleaning.
    case wetClean
}

/// The professional-cleaning axis: unrecorded, a required professional
/// process, or an explicit "do not dry clean".
public enum CareProfessional: Codable, Equatable, Sendable {
    case unknown
    case requires(ProfessionalKind)
    case doNotDryClean
}

// MARK: - Prohibitions

/// Explicit manufacturer "do not" prohibitions. Each attaches to one of the
/// five published `CareAxis` values — prohibitions are never a sixth axis
/// (see CareContract.swift and PLAN.md).
public enum CareProhibition: String, Codable, Equatable, Sendable, CaseIterable {
    case doNotWash
    case doNotBleach
    case doNotTumbleDry
    case doNotWring
    case doNotIron
    case doNotDryClean

    /// The published care axis this prohibition constrains.
    public var axis: CareAxis {
        switch self {
        case .doNotWash: .wash
        case .doNotBleach: .bleach
        case .doNotTumbleDry: .dry
        case .doNotWring: .dry
        case .doNotIron: .iron
        case .doNotDryClean: .professionalCleaning
        }
    }
}

// MARK: - Care profile

/// Everything Care Label records about one garment's care instructions.
/// All axes default to `unknown` — an unrecorded axis is never treated as
/// safe, and `CarePlainLanguageRenderer` renders it as "care not recorded".
public struct CareProfile: Codable, Equatable, Sendable {
    public var wash: CareWash
    public var bleach: CareBleach
    public var dry: CareDry
    public var iron: CareIron
    public var professional: CareProfessional
    public var prohibitions: Set<CareProhibition>

    public init(
        wash: CareWash = .unknown,
        bleach: CareBleach = .unknown,
        dry: CareDry = .unknown,
        iron: CareIron = .unknown,
        professional: CareProfessional = .unknown,
        prohibitions: Set<CareProhibition> = []
    ) {
        self.wash = wash
        self.bleach = bleach
        self.dry = dry
        self.iron = iron
        self.professional = professional
        self.prohibitions = prohibitions
    }

    /// A profile with every axis unrecorded and no prohibitions.
    public static let unknownProfile = CareProfile()

    /// True when no axis records any information (the all-unknown state the
    /// basket engine surfaces as needs-attention in issue #3).
    public var isFullyUnknown: Bool {
        wash == .unknown && bleach == .unknown && dry == .unknown
            && iron == .unknown && professional == .unknown
            && prohibitions.isEmpty
    }

    /// Deterministic prohibition ordering (the `CaseIterable` order) so
    /// renderers and later engine output are stable for tests.
    public var orderedProhibitions: [CareProhibition] {
        CareProhibition.allCases.filter(prohibitions.contains)
    }
}

// MARK: - Symbol effects

/// The concrete profile effect a decoded ISO 3758 symbol has on a care
/// profile. Every table entry carries exactly one effect; `applying(_:)` is
/// the single fold used to build profiles from symbols.
public enum CareSymbolEffect: Codable, Equatable, Sendable {
    case machineWash(temperature: WashTemperature, action: WashAction)
    case handWash
    case noWash
    case bleachAllowed(BleachKind)
    case noBleach
    case tumbleDry(heat: DryHeat)
    case noTumbleDry
    case naturalDry(NaturalDryMethod)
    case ironCap(IronTemperature)
    case noIron
    case professionalRequires(ProfessionalKind)
    case noDryClean
    case noWring
}

extension CareProfile {
    /// Returns a new profile with one decoded symbol effect merged in.
    /// Prohibition effects are additive; axis effects overwrite that axis.
    public func applying(_ effect: CareSymbolEffect) -> CareProfile {
        var updated = self
        switch effect {
        case let .machineWash(temperature, action):
            updated.wash = .machine(temperature: temperature, action: action)
        case .handWash:
            updated.wash = .handWash
        case .noWash:
            updated.wash = .doNotWash
            updated.prohibitions.insert(.doNotWash)
        case let .bleachAllowed(kind):
            updated.bleach = .allowed(kind)
        case .noBleach:
            updated.bleach = .doNotBleach
            updated.prohibitions.insert(.doNotBleach)
        case let .tumbleDry(heat):
            updated.dry = .tumble(heat: heat)
        case .noTumbleDry:
            updated.prohibitions.insert(.doNotTumbleDry)
        case let .naturalDry(method):
            updated.dry = .natural(method)
        case let .ironCap(temperature):
            updated.iron = .cap(temperature)
        case .noIron:
            updated.iron = .doNotIron
            updated.prohibitions.insert(.doNotIron)
        case let .professionalRequires(kind):
            updated.professional = .requires(kind)
        case .noDryClean:
            updated.professional = .doNotDryClean
            updated.prohibitions.insert(.doNotDryClean)
        case .noWring:
            updated.prohibitions.insert(.doNotWring)
        }
        return updated
    }

    /// Folds a sequence of effects left-to-right.
    public func applying(_ effects: some Sequence<CareSymbolEffect>) -> CareProfile {
        effects.reduce(into: self) { profile, effect in
            profile = profile.applying(effect)
        }
    }

    /// Builds a profile by decoding a set of care symbols recorded on a label.
    public func decoding(_ symbols: some Sequence<CareSymbol>) -> CareProfile {
        applying(symbols.map(\.effect))
    }
}
