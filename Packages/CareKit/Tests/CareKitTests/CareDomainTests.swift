import Foundation
import Testing
@testable import CareKit

// Issue #2 acceptance tests for the care domain:
// - symbol table completeness (every symbol decodes into a real effect)
// - profile round-trip codability
// - renderer golden tests
// - unknown-axis semantics

@Suite("Care symbol table")
struct CareSymbolTableTests {
    @Test("Table covers all five symbol families")
    func familiesAreCovered() {
        for family in CareSymbolFamily.allCases {
            #expect(!CareSymbolTable.symbols(in: family).isEmpty, "family \(family.rawValue) empty")
        }
        let covered = Set(CareSymbolTable.all.map(\.family))
        #expect(covered == Set(CareSymbolFamily.allCases))
    }

    @Test("Symbol ids are unique and lookup is total")
    func idsAreUnique() {
        #expect(CareSymbolTable.lookup.count == CareSymbolTable.all.count)
        for symbol in CareSymbolTable.all {
            #expect(CareSymbolTable.lookup[symbol.id] == symbol)
        }
    }

    @Test("Every symbol decodes: applying it removes unknown-ness on its target")
    func everySymbolDecodes() {
        for symbol in CareSymbolTable.all {
            let applied = CareProfile.unknownProfile.decoding([symbol])
            switch symbol.effect {
            case .machineWash, .handWash, .noWash:
                #expect(applied.wash != .unknown, "symbol \(symbol.id)")
            case .bleachAllowed, .noBleach:
                #expect(applied.bleach != .unknown, "symbol \(symbol.id)")
            case .tumbleDry, .naturalDry:
                #expect(applied.dry != .unknown, "symbol \(symbol.id)")
            case .ironCap, .noIron:
                #expect(applied.iron != .unknown, "symbol \(symbol.id)")
            case .professionalRequires, .noDryClean:
                #expect(applied.professional != .unknown, "symbol \(symbol.id)")
            case .noWring, .noTumbleDry:
                // Prohibition-only glyphs: they land in the prohibition set.
                let prohibition: CareProhibition = symbol.effect == .noWring ? .doNotWring : .doNotTumbleDry
                #expect(applied.prohibitions.contains(prohibition), "symbol \(symbol.id)")
            }
            // Each symbol must decode to exactly one of the five axes.
            #expect(CareAxis.allCases.contains(symbol.axis))
        }
    }

    @Test("Prohibition glyphs keep the prohibition set consistent with axes")
    func prohibitionGlyphsAttachToPublishedAxes() {
        let prohibitionSymbols = CareSymbolTable.all.filter {
            if case .noWring = $0.effect { return true }
            if case .noTumbleDry = $0.effect { return true }
            if case .noWash = $0.effect { return true }
            if case .noBleach = $0.effect { return true }
            if case .noIron = $0.effect { return true }
            if case .noDryClean = $0.effect { return true }
            return false
        }
        // Seven prohibition-effect glyphs (incl. both bleach variants).
        #expect(prohibitionSymbols.count == 7)
        for symbol in prohibitionSymbols {
            let applied = CareProfile.unknownProfile.decoding([symbol])
            for prohibition in applied.prohibitions {
                #expect(prohibition.axis == symbol.axis, "symbol \(symbol.id)")
            }
        }
    }

    @Test("Wash family enumerates the full 6x3 temperature/action tub grid")
    func washGridIsComplete() {
        let tubs = CareSymbolTable.symbols(in: .wash).filter {
            if case .machineWash = $0.effect { return true }
            return false
        }
        // 6 temperatures x 3 actions, plus the needsReview unnumbered legacy tub.
        #expect(tubs.count == 19)
        // The legacy unnumbered tub duplicates the 40/normal cell; exclude it
        // from the strict grid so every real cell must have exactly one glyph.
        let strictTubs = tubs.filter { $0.id != "wash-any-temperature" }
        #expect(strictTubs.count == 18)
        var seen: [String] = []
        for temperature in WashTemperature.allCases {
            for action in WashAction.allCases {
                let matches = strictTubs.filter {
                    if case let .machineWash(t, a) = $0.effect { return t == temperature && a == action }
                    return false
                }
                #expect(matches.count == 1, "grid cell \(temperature)-\(action)")
                seen.append(contentsOf: matches.map(\.id))
            }
        }
        #expect(Set(seen).count == 18)
    }

    @Test("needsReview flags are only on documented legacy/uncertain glyphs")
    func needsReviewGlyphsAreDocumented() {
        let flagged = Set(CareSymbolTable.all.filter(\.needsReview).map(\.id))
        #expect(flagged == [
            "wash-any-temperature",
            "do-not-chlorine-bleach",
            "tumble-dry-high",
            "line-dry-legacy-square",
            "dry-in-shade",
            "do-not-wring",
            "iron-any-legacy",
        ])
    }
}

@Suite("Care profile codability")
struct CareProfileCodabilityTests {
    @Test("A fully populated profile round-trips through JSON")
    func populatedProfileRoundTrips() throws {
        let profile = CareProfile(
            wash: .machine(temperature: .celsius40, action: .gentle),
            bleach: .allowed(.oxygenOnly),
            dry: .tumble(heat: .low),
            iron: .cap(.celsius110),
            professional: .requires(.hydrocarbon),
            prohibitions: [.doNotWring, .doNotBleach]
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(CareProfile.self, from: data)
        #expect(decoded == profile)
    }

    @Test("Every enum axis state round-trips through JSON")
    func allAxisStatesRoundTrip() throws {
        let washStates: [CareWash] = [
            .unknown, .doNotWash, .handWash,
            .machine(temperature: .celsius95, action: .normal),
        ]
        let bleachStates: [CareBleach] = [.unknown, .allowed(.anyBleach), .allowed(.oxygenOnly), .doNotBleach]
        let dryStates: [CareDry] = [
            .unknown, .tumble(heat: .high), .natural(.flat), .natural(.hang), .natural(.drip),
        ]
        let ironStates: [CareIron] = [.unknown, .doNotIron, .cap(.celsius200)]
        let professionalStates: [CareProfessional] = [
            .unknown, .doNotDryClean, .requires(.dryCleanAnySolvent),
            .requires(.hydrocarbon), .requires(.perchloroethylene), .requires(.wetClean),
        ]

        for state in washStates { try #require(roundTrips(state) == state) }
        for state in bleachStates { try #require(roundTrips(state) == state) }
        for state in dryStates { try #require(roundTrips(state) == state) }
        for state in ironStates { try #require(roundTrips(state) == state) }
        for state in professionalStates { try #require(roundTrips(state) == state) }
        for prohibition in CareProhibition.allCases { try #require(roundTrips(prohibition) == prohibition) }
        for symbol in CareSymbolTable.all { try #require(roundTrips(symbol) == symbol) }
    }

    private func roundTrips<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

@Suite("Care effect application")
struct CareEffectApplicationTests {
    @Test("Decoding multiple label symbols folds into one profile")
    func multiSymbolDecodeFolds() throws {
        let wash = try #require(CareSymbolTable.lookup["wash-40-one-bar"])
        let bleach = try #require(CareSymbolTable.lookup["oxygen-bleach-only"])
        let dry = try #require(CareSymbolTable.lookup["tumble-dry-low"])
        let iron = try #require(CareSymbolTable.lookup["iron-medium"])
        let professional = try #require(CareSymbolTable.lookup["dry-clean-p"])
        let profile = CareProfile.unknownProfile.decoding([wash, bleach, dry, iron, professional])
        #expect(profile.wash == .machine(temperature: .celsius40, action: .permanentPress))
        #expect(profile.bleach == .allowed(.oxygenOnly))
        #expect(profile.dry == .tumble(heat: .low))
        #expect(profile.iron == .cap(.celsius150))
        #expect(profile.professional == .requires(.perchloroethylene))
        #expect(profile.prohibitions.isEmpty)
    }

    @Test("Prohibition-only glyphs never mark their axis as recorded")
    func prohibitionOnlyKeepsAxisUnknown() throws {
        let noTumble = try #require(CareSymbolTable.lookup["do-not-tumble-dry"])
        let profile = CareProfile.unknownProfile.decoding([noTumble])
        #expect(profile.dry == .unknown)
        #expect(profile.prohibitions == [.doNotTumbleDry])
        #expect(!profile.isFullyUnknown)
    }

    @Test("Fully-unknown profile is the neutral fold start")
    func unknownProfileIsNeutral() {
        #expect(CareProfile.unknownProfile.isFullyUnknown)
        #expect(CareProfile.unknownProfile.decoding([CareSymbol]()) == .unknownProfile)
    }
}

@Suite("Plain-language renderer")
struct CareRendererTests {
    @Test("Golden: fully unknown profile renders five not-recorded lines")
    func fullyUnknownGolden() {
        #expect(CarePlainLanguageRenderer.rules(for: .unknownProfile) == [
            "Care not recorded — check the label and add it",
            "Care not recorded — check the label and add it",
            "Care not recorded — check the label and add it",
            "Care not recorded — check the label and add it",
            "Care not recorded — check the label and add it",
        ])
    }

    @Test("Golden: a full decoded label renders ordered plain-language rules")
    func fullLabelGolden() throws {
        let profile = CareProfile.unknownProfile.decoding([
            try #require(CareSymbolTable.lookup["wash-30-two-bars"]),
            try #require(CareSymbolTable.lookup["do-not-bleach"]),
            try #require(CareSymbolTable.lookup["dry-flat"]),
            try #require(CareSymbolTable.lookup["iron-low"]),
            try #require(CareSymbolTable.lookup["do-not-dry-clean"]),
            try #require(CareSymbolTable.lookup["do-not-wring"]),
        ])
        #expect(CarePlainLanguageRenderer.rules(for: profile) == [
            "Machine wash up to 30 °C, gentle cycle",
            "Do not use bleach",
            "Dry flat",
            "Iron up to 110 °C soleplate",
            "Do not dry clean",
            "Prohibited: do not bleach",
            "Prohibited: do not wring",
            "Prohibited: do not dry clean",
        ])
    }

    @Test("Golden: hand-wash and do-not-wash states")
    func washSpecialStatesGolden() {
        #expect(Array(CarePlainLanguageRenderer.rules(for: .init(wash: .handWash)).prefix(1)) == ["Hand wash only"])
        #expect(Array(CarePlainLanguageRenderer.rules(for: .init(wash: .doNotWash)).prefix(1)) == ["Do not wash at home"])
    }

    @Test("Unknown axes always render exactly the not-recorded sentence")
    func unknownAxisRendering() {
        // One unknown axis mixed into an otherwise fully recorded profile:
        // the count of not-recorded lines must equal the count of unknown
        // axes, and recorded axes never collapse into it.
        let partial = CareProfile(
            wash: .machine(temperature: .celsius60, action: .normal),
            bleach: .unknown,
            dry: .natural(.drip),
            iron: .unknown,
            professional: .requires(.wetClean)
        )
        let rendered = CarePlainLanguageRenderer.rules(for: partial)
        #expect(rendered.count == 5)
        #expect(rendered.filter { $0 == CarePlainLanguageRenderer.unknownAxisRule }.count == 2)
        #expect(rendered[0] == "Machine wash up to 60 °C, normal cycle")
        #expect(rendered[2] == "Drip dry")
        #expect(rendered[4] == "Professional wet cleaning")
    }

    @Test("Renderer is deterministic for the same profile")
    func rendererIsDeterministic() throws {
        let profile = CareProfile.unknownProfile.decoding([
            try #require(CareSymbolTable.lookup["do-not-wring"]),
            try #require(CareSymbolTable.lookup["do-not-bleach"]),
        ])
        #expect(CarePlainLanguageRenderer.rules(for: profile) == CarePlainLanguageRenderer.rules(for: profile))
    }
}
