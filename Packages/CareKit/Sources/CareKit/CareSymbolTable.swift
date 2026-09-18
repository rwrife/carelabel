import Foundation

// MARK: - ISO 3758 symbol reference
//
// Source list for this table (the ISO standard itself is paywalled, so the
// glyph set and meanings were compiled from these public reproductions,
// cross-checked against each other):
//
//   1. GINETEX — the owner/maintainer of ISO 3758. Published care-label
//      symbol brochure / care-label.com symbol chart (2012 symbol revision).
//   2. ASTM D5489 standard guide symbol glossary (US household care
//      symbols, published free by ASTM).
//   3. The WGTR/AFM "Guide for Care Symboling" reproduction commonly used
//      by textile educators.
//
// Where these sources disagree, where a glyph is legacy (pre-2012 ISO
// 3758:1996 / R 3758:1989 era), or where the MVP value model cannot express
// the full symbol (e.g. process-strength bars under the professional
// circle, or drying in the shade), the entry is flagged `needsReview: true`
// and the `meaning` states the uncertainty. `needsReview` entries are
// shipped and decoded — they are honest best-effort mappings, not gaps —
// but they must be re-audited before any store listing claims.
//
// Process-strength modifiers (one or two bars under the professional
// circle) and light/heat extensions are NOT modeled by the MVP value types;
// they are intentionally absent from this table rather than silently
// flattened. A garment bearing those variants should record the nearest
// modeled symbol plus a fabric note.

/// Symbol families per the published five-axis care model; each family maps
/// onto one `CareAxis` (the "do not wring" prohibition glyph is filed under
/// drying, matching `CareProhibition.doNotWring.axis`).
public enum CareSymbolFamily: String, Codable, Equatable, Sendable, CaseIterable {
    case wash
    case bleach
    case drying
    case iron
    case professional
}

/// One decoded care-label symbol: its stable glyph id, textual notation of
/// the glyph, plain-language meaning, and the concrete effect applying it
/// has on a `CareProfile`.
public struct CareSymbol: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let family: CareSymbolFamily
    /// Short textual description of the glyph itself, e.g. "wash tub marked
    /// 40 with one bar underneath".
    public let notation: String
    /// Plain-language rule the manufacturer asserts, suitable for display.
    public let meaning: String
    public let effect: CareSymbolEffect
    /// Honest-uncertainty flag — see source list at the top of this file.
    public let needsReview: Bool

    public init(
        id: String,
        family: CareSymbolFamily,
        notation: String,
        meaning: String,
        effect: CareSymbolEffect,
        needsReview: Bool = false
    ) {
        self.id = id
        self.family = family
        self.notation = notation
        self.meaning = meaning
        self.effect = effect
        self.needsReview = needsReview
    }

    /// The care axis this symbol's meaning lands on.
    public var axis: CareAxis {
        switch family {
        case .wash: .wash
        case .bleach: .bleach
        case .drying: .dry
        case .iron: .iron
        case .professional: .professionalCleaning
        }
    }
}

/// The complete shipped symbol reference, in declaration order
/// (deterministic for tests and UI listing).
public enum CareSymbolTable {
    /// Wash temperatures in ISO order used throughout the table.
    private static let washTemperatures: [(WashTemperature, String)] = [
        (.celsius30, "30"), (.celsius40, "40"), (.celsius50, "50"),
        (.celsius60, "60"), (.celsius70, "70"), (.celsius95, "95"),
    ]

    /// Mechanical-action variants of a tub: plain, one bar, two bars.
    private static func washSymbols(
        temperature: WashTemperature,
        number: String
    ) -> [CareSymbol] {
        [
            CareSymbol(
                id: "wash-\(number)",
                family: .wash,
                notation: "wash tub marked \(number), no bars",
                meaning: "Machine wash at up to \(number) °C, normal cycle",
                effect: .machineWash(temperature: temperature, action: .normal)
            ),
            CareSymbol(
                id: "wash-\(number)-one-bar",
                family: .wash,
                notation: "wash tub marked \(number) with one bar underneath",
                meaning: "Machine wash at up to \(number) °C, permanent-press (synthetics) cycle",
                effect: .machineWash(temperature: temperature, action: .permanentPress)
            ),
            CareSymbol(
                id: "wash-\(number)-two-bars",
                family: .wash,
                notation: "wash tub marked \(number) with two bars underneath",
                meaning: "Machine wash at up to \(number) °C, gentle/mild cycle",
                effect: .machineWash(temperature: temperature, action: .gentle)
            ),
        ]
    }

    private static let wash: [CareSymbol] = washTemperatures
        .flatMap { washSymbols(temperature: $0.0, number: $0.1) }
        + [
            CareSymbol(
                id: "hand-wash",
                family: .wash,
                notation: "wash tub with a hand dipping into it",
                meaning: "Hand wash only (up to 40 °C, do not wring or scrub)",
                effect: .handWash
            ),
            CareSymbol(
                id: "do-not-wash",
                family: .wash,
                notation: "wash tub crossed out with an X",
                meaning: "Do not wash at home — see professional-cleaning symbols",
                effect: .noWash
            ),
            CareSymbol(
                id: "wash-any-temperature",
                family: .wash,
                notation: "wash tub with no temperature number (legacy glyph)",
                meaning: "Machine wash warm — legacy unnumbered tub; modern ISO 3758 labels always state a number, so record the nearest numbered symbol when in doubt",
                effect: .machineWash(temperature: .celsius40, action: .normal),
                needsReview: true
            ),
        ]

    private static let bleach: [CareSymbol] = [
        CareSymbol(
            id: "any-bleach",
            family: .bleach,
            notation: "plain triangle",
            meaning: "Any bleach may be used (chlorine or oxygen)",
            effect: .bleachAllowed(.anyBleach)
        ),
        CareSymbol(
            id: "oxygen-bleach-only",
            family: .bleach,
            notation: "triangle with two diagonal lines inside",
            meaning: "Only oxygen-based (color-safe) bleach may be used",
            effect: .bleachAllowed(.oxygenOnly)
        ),
        CareSymbol(
            id: "do-not-bleach",
            family: .bleach,
            notation: "triangle crossed out with an X",
            meaning: "Do not use any bleach",
            effect: .noBleach
        ),
        CareSymbol(
            id: "do-not-chlorine-bleach",
            family: .bleach,
            notation: "triangle with two diagonal lines, crossed out with an X (rare legacy variant)",
            meaning: "Do not use chlorine bleach; interpretations vary, so treat as no bleach at all unless the label is clear",
            effect: .noBleach,
            needsReview: true
        ),
    ]

    private static let drying: [CareSymbol] = [
        CareSymbol(
            id: "tumble-dry-normal",
            family: .drying,
            notation: "square with a circle inside, no dots",
            meaning: "Tumble dry, normal heat",
            effect: .tumbleDry(heat: .normal)
        ),
        CareSymbol(
            id: "tumble-dry-low",
            family: .drying,
            notation: "square with a circle inside, one dot",
            meaning: "Tumble dry, low heat",
            effect: .tumbleDry(heat: .low)
        ),
        CareSymbol(
            id: "tumble-dry-high",
            family: .drying,
            notation: "square with a circle inside, two dots",
            meaning: "Tumble dry, higher heat — sources disagree on whether two dots is 'normal' or 'high' heat in the 2012 revision; recorded here as high",
            effect: .tumbleDry(heat: .high),
            needsReview: true
        ),
        CareSymbol(
            id: "do-not-tumble-dry",
            family: .drying,
            notation: "square with a circle inside, crossed out with an X",
            meaning: "Do not tumble dry",
            effect: .noTumbleDry
        ),
        CareSymbol(
            id: "dry-flat",
            family: .drying,
            notation: "square with a horizontal line inside",
            meaning: "Dry flat (do not hang, to avoid stretching)",
            effect: .naturalDry(.flat)
        ),
        CareSymbol(
            id: "line-dry",
            family: .drying,
            notation: "square with a vertical line inside",
            meaning: "Line dry (hang to dry)",
            effect: .naturalDry(.hang)
        ),
        CareSymbol(
            id: "drip-dry",
            family: .drying,
            notation: "square with three vertical lines inside",
            meaning: "Drip dry (hang while still soaking wet, do not wring)",
            effect: .naturalDry(.drip)
        ),
        CareSymbol(
            id: "line-dry-legacy-square",
            family: .drying,
            notation: "plain square with no lines (legacy ISO 3758:1996 glyph)",
            meaning: "Line dry — the plain square's meaning changed across ISO revisions; record the lined variant when the label is modern",
            effect: .naturalDry(.hang),
            needsReview: true
        ),
        CareSymbol(
            id: "dry-in-shade",
            family: .drying,
            notation: "square with two diagonal lines in the upper-left corner",
            meaning: "Dry in the shade, away from direct sunlight — light sensitivity is not modeled by the care axes, so this decodes only as hang-dry",
            effect: .naturalDry(.hang),
            needsReview: true
        ),
        CareSymbol(
            id: "do-not-wring",
            family: .drying,
            notation: "twisted cloth glyph (legacy national-standard glyph)",
            meaning: "Do not wring the garment",
            effect: .noWring,
            needsReview: true
        ),
    ]

    private static let ironing: [CareSymbol] = [
        CareSymbol(
            id: "iron-low",
            family: .iron,
            notation: "iron with one dot",
            meaning: "Iron at a soleplate cap of 110 °C (steam may cause irreversible damage)",
            effect: .ironCap(.celsius110)
        ),
        CareSymbol(
            id: "iron-medium",
            family: .iron,
            notation: "iron with two dots",
            meaning: "Iron at a soleplate cap of 150 °C",
            effect: .ironCap(.celsius150)
        ),
        CareSymbol(
            id: "iron-high",
            family: .iron,
            notation: "iron with three dots",
            meaning: "Iron at a soleplate cap of 200 °C",
            effect: .ironCap(.celsius200)
        ),
        CareSymbol(
            id: "do-not-iron",
            family: .iron,
            notation: "iron crossed out with an X",
            meaning: "Do not iron",
            effect: .noIron
        ),
        CareSymbol(
            id: "iron-any-legacy",
            family: .iron,
            notation: "plain iron with no dots (legacy glyph)",
            meaning: "Iron warm — legacy undotted iron; treat as a 150 °C cap and prefer the dotted symbol when the label is modern",
            effect: .ironCap(.celsius150),
            needsReview: true
        ),
    ]

    private static let professional: [CareSymbol] = [
        CareSymbol(
            id: "dry-clean-any-solvent",
            family: .professional,
            notation: "plain circle",
            meaning: "Professional dry cleaning in any common solvent",
            effect: .professionalRequires(.dryCleanAnySolvent)
        ),
        CareSymbol(
            id: "dry-clean-p",
            family: .professional,
            notation: "circle with the letter P inside",
            meaning: "Professional dry cleaning in perchloroethylene-family solvents (and hydrocarbons)",
            effect: .professionalRequires(.perchloroethylene)
        ),
        CareSymbol(
            id: "dry-clean-f",
            family: .professional,
            notation: "circle with the letter F inside",
            meaning: "Professional dry cleaning in hydrocarbon solvents only",
            effect: .professionalRequires(.hydrocarbon)
        ),
        CareSymbol(
            id: "professional-wet-clean",
            family: .professional,
            notation: "circle with the letter W inside",
            meaning: "Professional wet cleaning",
            effect: .professionalRequires(.wetClean)
        ),
        CareSymbol(
            id: "do-not-dry-clean",
            family: .professional,
            notation: "circle crossed out with an X",
            meaning: "Do not dry clean",
            effect: .noDryClean
        ),
    ]

    /// Every shipped symbol, grouped family by family in declaration order.
    public static let all: [CareSymbol] = wash + bleach + drying + ironing + professional

    /// O(1) lookup by glyph id.
    public static let lookup: [String: CareSymbol] = Dictionary(
        all.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    /// Convenience: all symbols in one family, in table order.
    public static func symbols(in family: CareSymbolFamily) -> [CareSymbol] {
        all.filter { $0.family == family }
    }
}
