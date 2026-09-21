import CareKit
import SwiftUI

// Issue #5: the symbol reference sheet.
//
// One sheet per `CareSymbolFamily`, reached from the matching axis editor.
// Every symbol row draws its glyph (CareGlyphView below), the plain-language
// meaning, and — required by the issue — a VoiceOver label of the form
// "glyph description, meaning" so a blind user hears both. `needsReview`
// symbols honestly display their uncertainty note.

struct SymbolReferenceSheet: View {
    let family: CareSymbolFamily

    private var symbols: [CareSymbol] {
        CareSymbolTable.symbols(in: family)
    }

    var body: some View {
        List {
            Section {
                ForEach(symbols) { symbol in
                    SymbolRow(symbol: symbol)
                }
            } header: {
                Text("\(family.title) symbols")
            } footer: {
                Text(
                    "Glyphs are simplified drawings of ISO 3758 marks. The app records what your physical label states."
                )
            }
        }
        .navigationTitle("\(family.title) symbols")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("sheet.\(family.rawValue)")
    }
}

struct SymbolRow: View {
    let symbol: CareSymbol

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CareGlyphView(symbolID: symbol.id)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(symbol.meaning)
                    .font(.body)
                Text(symbol.notation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if symbol.needsReview {
                    Label("Meaning needs review", systemImage: "questionmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 60)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Symbol: \(symbol.notation). \(symbol.meaning)")
        .accessibilityIdentifier("symbol.row.\(symbol.id)")
    }
}

// MARK: - Glyph rendering
//
// A single dispatch over the shipped symbol ids drawing each ISO 3758 mark
// as simple geometry (tub, triangle, square+circle, iron, circle, with X
// overlays, temperature numbers, dots, bars, and lines). These are honest
// simplified renderings, not the font-exact glyphs; the VoiceOver text is
// the authoritative description either way.

struct CareGlyphView: View {
    let symbolID: String

    var body: some View {
        Canvas { graphicsContext, size in
            GlyphRenderer.render(symbolID: symbolID, context: graphicsContext, size: size)
        }
        .accessibilityHidden(true) // row-level label carries glyph + meaning
    }
}

enum GlyphRenderer {
    /// Renders one glyph by id. The GraphicsContext is taken by value and
    /// held in a local `var` so the nested helpers below can draw through it
    /// without capturing an `inout` parameter (illegal for closures).
    static func render(symbolID: String, context: GraphicsContext, size: CGSize) {
        var ctx = context
        let inset: CGFloat = 3
        let rect = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
        let shading = GraphicsContext.Shading.color(.primary)

        func strokePath(_ path: Path, width: CGFloat = 1.8) {
            ctx.stroke(path, with: shading, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }

        func crossOut() {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + 2, y: rect.maxY - 2))
            path.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.minY + 2))
            strokePath(path, width: 2.2)
        }

        // Wash tub: trapezoid-ish rounded bucket.
        func tub() -> Path {
            var path = Path()
            let top = rect.minY + rect.height * 0.18
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.06, y: top))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - rect.width * 0.06, y: top),
                control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.12)
            )
            path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.14, y: rect.maxY - 4))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.maxY - 4),
                control: CGPoint(x: rect.midX, y: rect.maxY + 6)
            )
            path.closeSubpath()
            return path
        }

        func numberText(_ number: String) {
            let resolved = ctx.resolve(
                Text(number).font(.system(size: rect.height * 0.34, weight: .semibold))
            )
            ctx.draw(resolved, at: CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.02))
        }

        func bars(_ count: Int) {
            let barY = rect.maxY - 2 - CGFloat(count) * 3
            for i in 0..<count {
                var path = Path()
                let y = barY + CGFloat(i) * 3
                path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: y))
                path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: y))
                strokePath(path, width: 1.6)
            }
        }

        func triangle() -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY + 2))
            path.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.maxY - 2))
            path.addLine(to: CGPoint(x: rect.minX + 2, y: rect.maxY - 2))
            path.closeSubpath()
            return path
        }

        func squareRect() -> CGRect {
            CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.92)
        }

        func dots(_ count: Int, center: CGPoint, spacing: CGFloat) {
            guard count > 0 else { return }
            let startX = center.x - spacing * CGFloat(count - 1) / 2
            for i in 0..<count {
                let x = startX + spacing * CGFloat(i)
                let dot = CGRect(x: x - 2, y: center.y - 2, width: 4, height: 4)
                ctx.fill(Path(ellipseIn: dot), with: shading)
            }
        }

        // MARK: family dispatch

        if symbolID.hasPrefix("wash-") && symbolID != "wash-any-temperature" {
            strokePath(tub())
            let number = symbolID
                .replacingOccurrences(of: "wash-", with: "")
                .replacingOccurrences(of: "-one-bar", with: "")
                .replacingOccurrences(of: "-two-bars", with: "")
            numberText(number)
            if symbolID.contains("-one-bar") { bars(1) }
            if symbolID.contains("-two-bars") { bars(2) }
            return
        }

        switch symbolID {
        case "wash-any-temperature":
            strokePath(tub())
        case "do-not-wash":
            strokePath(tub())
            crossOut()
        case "hand-wash":
            strokePath(tub())
            // Simplified hand: a stub poking into the tub.
            var hand = Path()
            hand.move(to: CGPoint(x: rect.midX, y: rect.minY))
            hand.addLine(to: CGPoint(x: rect.midX, y: rect.midY))
            hand.addArc(
                center: CGPoint(x: rect.midX, y: rect.midY),
                radius: 3, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false
            )
            strokePath(hand, width: 1.6)
        case "any-bleach":
            strokePath(triangle())
        case "oxygen-bleach-only":
            strokePath(triangle())
            var lines = Path()
            lines.move(to: CGPoint(x: rect.midX - 6, y: rect.maxY - 8))
            lines.addLine(to: CGPoint(x: rect.midX - 1, y: rect.minY + 12))
            lines.move(to: CGPoint(x: rect.midX + 1, y: rect.maxY - 8))
            lines.addLine(to: CGPoint(x: rect.midX + 6, y: rect.minY + 12))
            strokePath(lines, width: 1.4)
        case "do-not-bleach":
            strokePath(triangle())
            crossOut()
        case "do-not-chlorine-bleach":
            strokePath(triangle())
            crossOut()
        case "tumble-dry-normal", "tumble-dry-low", "tumble-dry-high", "do-not-tumble-dry":
            strokePath(Path(roundedRect: squareRect(), cornerRadius: 3))
            let innerRadius = rect.width * 0.24
            let innerCenter = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.04)
            strokePath(
                Path(ellipseIn: CGRect(
                    x: innerCenter.x - innerRadius,
                    y: innerCenter.y - innerRadius,
                    width: innerRadius * 2, height: innerRadius * 2
                ))
            )
            let dotSpacing = innerRadius * 0.55
            switch symbolID {
            case "tumble-dry-low": dots(1, center: innerCenter, spacing: dotSpacing)
            case "tumble-dry-high": dots(2, center: innerCenter, spacing: dotSpacing)
            case "do-not-tumble-dry": crossOut()
            default: break
            }
        case "dry-flat":
            strokePath(Path(roundedRect: squareRect(), cornerRadius: 3))
            var line = Path()
            line.move(to: CGPoint(x: rect.minX + 10, y: rect.midY + rect.height * 0.04))
            line.addLine(to: CGPoint(x: rect.maxX - 10, y: rect.midY + rect.height * 0.04))
            strokePath(line, width: 2)
        case "line-dry":
            strokePath(Path(roundedRect: squareRect(), cornerRadius: 3))
            var line = Path()
            line.move(to: CGPoint(x: rect.midX, y: rect.minY + 10))
            line.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 6))
            strokePath(line, width: 2)
        case "drip-dry":
            strokePath(Path(roundedRect: squareRect(), cornerRadius: 3))
            var lines = Path()
            for offset: CGFloat in [-6, 0, 6] {
                lines.move(to: CGPoint(x: rect.midX + offset, y: rect.minY + 10))
                lines.addLine(to: CGPoint(x: rect.midX + offset, y: rect.maxY - 6))
            }
            strokePath(lines, width: 1.6)
        case "line-dry-legacy-square":
            strokePath(Path(roundedRect: squareRect(), cornerRadius: 3))
        case "dry-in-shade":
            strokePath(Path(roundedRect: squareRect(), cornerRadius: 3))
            var lines = Path()
            lines.move(to: CGPoint(x: rect.minX + 4, y: rect.minY + 10))
            lines.addLine(to: CGPoint(x: rect.minX + 12, y: rect.minY + 3))
            lines.move(to: CGPoint(x: rect.minX + 8, y: rect.minY + 14))
            lines.addLine(to: CGPoint(x: rect.minX + 16, y: rect.minY + 7))
            strokePath(lines, width: 1.4)
        case "do-not-wring":
            // Twisted-cloth glyph: two opposed crescents, crossed out.
            var left = Path()
            left.addArc(
                center: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.midY),
                radius: rect.width * 0.20, startAngle: .degrees(60), endAngle: .degrees(300), clockwise: false
            )
            var right = Path()
            right.addArc(
                center: CGPoint(x: rect.maxX - rect.width * 0.30, y: rect.midY),
                radius: rect.width * 0.20, startAngle: .degrees(240), endAngle: .degrees(120), clockwise: false
            )
            strokePath(left, width: 1.8)
            strokePath(right, width: 1.8)
            crossOut()
        case "iron-low", "iron-medium", "iron-high", "do-not-iron", "iron-any-legacy":
            // Iron: flat bottom, domed top.
            var iron = Path()
            iron.move(to: CGPoint(x: rect.minX + 2, y: rect.maxY - 6))
            iron.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.maxY - 6))
            iron.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.maxY - 12))
            iron.addQuadCurve(
                to: CGPoint(x: rect.minX + 2, y: rect.maxY - 12),
                control: CGPoint(x: rect.midX, y: rect.minY + 4)
            )
            iron.closeSubpath()
            strokePath(iron)
            let count: Int
            switch symbolID {
            case "iron-low": count = 1
            case "iron-medium": count = 2
            case "iron-high": count = 3
            default: count = 0
            }
            dots(count, center: CGPoint(x: rect.midX, y: rect.maxY - 10), spacing: 7)
            if symbolID == "do-not-iron" { crossOut() }
        case "dry-clean-any-solvent", "dry-clean-p", "dry-clean-f", "professional-wet-clean", "do-not-dry-clean":
            let radius = min(rect.width, rect.height * 0.92) * 0.34
            let center = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.46)
            strokePath(Path(ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2
            )))
            let letter: String
            switch symbolID {
            case "dry-clean-p": letter = "P"
            case "dry-clean-f": letter = "F"
            case "professional-wet-clean": letter = "W"
            default: letter = ""
            }
            if !letter.isEmpty {
                let resolved = ctx.resolve(
                    Text(letter).font(.system(size: radius * 1.1, weight: .semibold))
                )
                ctx.draw(resolved, at: center)
            }
            if symbolID == "do-not-dry-clean" { crossOut() }
        default:
            // Unknown id: neutral placeholder circle so nothing renders blank.
            strokePath(Path(ellipseIn: rect.insetBy(dx: 6, dy: 6)))
        }
    }
}

extension CareSymbolFamily {
    var title: String {
        switch self {
        case .wash: "Wash"
        case .bleach: "Bleach"
        case .drying: "Drying"
        case .iron: "Ironing"
        case .professional: "Professional cleaning"
        }
    }
}
