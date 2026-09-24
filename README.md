# Care Label

**Pitch:** Local-first iPhone wardrobe-care app: track each garment's care label, decode laundry symbols, and build a wash-safe basket so clothes never get ruined — no accounts, no cloud.

Care Label keeps your wardrobe's care instructions in one private place. Photograph or manually record each garment's care label, get a plain-language decoding of the ISO laundry symbols, and before every wash build a basket: the app flags garments that conflict (hot-wash-only colors with cold-only knits, "do not tumble dry" next to dryer-dependent items) and tells you exactly why each flag exists.

## Motivation

Most people ruin clothes the slow way: a wool sweater shrinks, a printed tee cracks, a "dry clean only" jacket gets washed. Care information lives on a small sewn-in label that is cut off, illegible, or buried at the bottom of a closet, and the ISO 3758 care symbols on it are famously cryptic. Existing laundry apps are either consumable inventories (socks, capsules) or generic reminders; none centers on the *care contract* of each garment and the *per-load safety decision* made at the machine.

## Target users

- Adults who own a mix of care-sensitive clothing (wool, technical fabrics, delicates, prints, denim) and share or do household laundry.
- Anyone who has ever asked "can this go in the wash with the rest?" and guessed.
- People building a capsule wardrobe who want to keep garments alive longer.

## Concrete use cases

1. **Intake:** add a sweater, photograph its label, mark "wool, hand wash, dry flat." 60 seconds per garment.
2. **Decode:** tap any recorded symbol set and read the plain-language rules ("max 30 °C, no wringing, no tumble dry").
3. **Pre-wash basket:** before a load, pick candidate garments; Care Label groups them by compatible wash/dry/bleach/iron settings and flags conflicts with the offending symbol and garment named.
4. **Care lookup at the machine:** search one garment, glance at its wash temperature, dryer rule, and iron cap before committing.
5. **History:** see when a garment was last washed and by which method, to avoid over-washing denim and wool.

## How to use (intended end-to-end workflow)

1. Create garments (name, category, photo optional) and record care instructions either by selecting decoded rules directly or by noting the symbols found.
2. Care Label stores per-garment care caps: wash temperature/action, bleach, drying method, iron cap, dry-cleaning flag, and explicit "do not" prohibitions.
3. Before a load, open **Basket**, add garments, and review the compatibility report (safe groups + flagged conflicts with reasons).
4. Log the wash when done (method + date) — this feeds per-garment wash cadence.
5. Export or back up everything at any time (JSON archive; CSV garment summary).

## MVP feature list

- Garment registry: local records with name, category, fabric note, photo (optional, app-private).
- Care profile editor: structured care caps modeled on ISO 3758 symbol semantics (wash, bleach, dry, iron, professional), with plain-language rendering.
- Symbol decoder reference: built-in table of standard care symbols → meaning, browsable and searchable.
- Wash basket builder: pick garments → deterministic compatibility grouping + conflict list with per-garment reasons.
- Wash log: per-garment method+date history, simple "last washed" surfacing.
- Backup/restore (private JSON) and CSV export.
- Accessibility: Dynamic Type, VoiceOver labels on all symbol glyphs, high-contrast symbol rendering.

## Non-goals

- No wardrobe/fashion cataloging beyond what care requires (no outfit planning, shopping, or social features).
- No OCR of care labels in MVP (manual selection; photo kept as evidence only).
- No laundry detergent advice, stain-remedy claims, or fabric-expert AI.
- No textile/microplastics science claims; care guidance is a decoding of the manufacturer's own label, not medical or safety advice.
- No accounts, cloud sync, telemetry, or third-party analytics.
- No native iPad app (iPhone-only by default; iPad support is an explicit opt-in later).
- No Apple Watch, widgets, or Android in MVP.

## Privacy, permissions, and data storage

- **Local-first:** all garments, photos, and logs live in app-private storage (SQLite via GRDB + app container photos). The MVP makes **no network requests at all**; there is a CI-enforced zero-network gate.
- **Permissions:** Photo Library add-only (or camera capture) for label photos; optional notifications only if a future wash-reminder feature is requested. No location, contacts, or health permissions.
- **Export/backup:** user-initiated JSON archive (full fidelity) and CSV summary, via the system share sheet; restore is explicit and previewed before merge.
- **Data ownership:** nothing leaves the device unless the user exports it. Deleting the app deletes the data.

## iPhone Duo dual-screen design target

This is a standard SwiftUI **iPhone-only** app today (`TARGETED_DEVICE_FAMILY = 1`; native iPad support disabled by default — iPad requires explicit opt-in). The dual-screen experience is a **documented design target with a migration path**, not a dependency on unavailable fold APIs:

- **Basket-at-the-machine mode:** one screen shows the garment picker/checkbox roster while the other shows the live compatibility report and conflict reasons.
- **Label-vs-decoding mode:** label photo on one surface, decoded plain-language rules + symbol reference on the other.
- **Migration seam:** all layout decisions route through a single `CareWorkspaceLayout` value; when native dual-screen/fold APIs ship, only that adapter needs a real implementation. Today it resolves to the standard compact iPhone layout (and optional two-column regular width on larger iPhone sizes).

### How the Basket split becomes the dual-screen span (issue #6)

The Basket screen already realizes the picker|report split **structurally** through the seam, with zero dependence on unavailable fold APIs:

- `CareWorkspaceLayout.presentation(for:)` is the single decision point. Every style→presentation mapping lives in `CareKit/CareContract.swift`; call sites never branch on size classes or device traits themselves.
- `.compact` → `.stacked` (today's iPhone): the garment picker and plan controls occupy the screen, and "Evaluate" pushes the compatibility report as a sequential screen. This is what ships in every orientation the iPhone-only build runs in (`CareWorkspaceLayout.current == .compact`).
- `.regularWidth` → `.splitPanels`: the picker renders in the leading panel and the live `BasketReportPanel` in the trailing panel — the exact "basket at the machine" roster-and-report pairing described above.

When fold APIs ship, the migration is confined to two changes: (1) extend `CareWorkspaceLayout` to resolve `.regularWidth` from real screen geometry instead of the hard-coded `.compact`, and (2) span the two already-split panels across the outer displays. No view, model, or engine code in `BasketView`/`WardrobeWorkspaceModel`/`BasketEvaluationEngine` changes, and the iPhone-only target (`TARGETED_DEVICE_FAMILY = 1`) is untouched until an explicit iPad/dual-screen opt-in.

## iOS signing & release

- Bundle identifier: `com.infinityball.carelabel` — App Store Connect registration status: **CREATED**.
- CI uses the repository Actions secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID` (names only; values are never stored in this repository). Release path: archive → validate → TestFlight upload via the App Store Connect API.
- SDK floor: iOS 26 or newer (see `toolchain.json`).

## Current status & milestones

**Status: native bootstrap in flight.** The Xcode project, `CareKit` package, and pinned iOS CI exist in-tree; the authoritative build/test evidence is the pinned macOS CI run for the bootstrap PR (see `docs/bootstrap-evidence.md` for what was verified where).

1. M0: scaffold, plan, backlog. ✅
2. M1: project skeleton + CI + zero-network gate. *(this bootstrap — native CI is the merge gate)*
3. M2: domain layer — garments, care profiles, ISO symbol semantics, pure-Swift compatibility engine.
4. M3: primary flows — registry, care editor, symbol reference.
5. M4: basket builder + conflict UI, wash log.
6. M5: backup/export/restore, accessibility pass.
7. M6: signed TestFlight build, release evidence.

## Development quickstart

- macOS with Xcode 26.0.1 (build 17A400, iOS 26 SDK, Swift 6 mode) per `toolchain.json`.
- Open `CareLabel.xcodeproj`; build/run the `CareLabel` scheme on an iPhone simulator.
- Pure-domain tests: `swift test --package-path Packages/CareKit` (runs on Linux too, via e.g. `swift:6.1`).
- Full local CI entrypoint (macOS only): `Scripts/ci.sh <commit-sha>`.
- Product gates: `python3 Scripts/zero_network_guard.py` (zero-network, allowlist `network_allowlist.txt`) and the iPhone-only checks — `TARGETED_DEVICE_FAMILY = 1` in all app-target configurations, re-verified post-build as `UIDeviceFamily == [1]`.
