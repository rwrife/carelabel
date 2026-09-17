# Care Label — PLAN

## Scope

Care Label is an iPhone-only, local-first SwiftUI app that stores per-garment care instructions (modeled on ISO 3758 care-symbol semantics), decodes care symbols into plain language, and evaluates a user-selected laundry basket for wash/dry/bleach/iron compatibility, flagging conflicts with named garments and specific care caps. It also keeps a per-garment wash log.

Out of scope: wardrobe/fashion management, outfit planning, OCR, stain advice, detergent recommendations, fabric-science claims, dry-cleaning service integration, accounts/cloud, Android, native iPad.

## Architecture

```
CareLabel (SwiftUI app target, iPhone-only)
├── Domain (pure Swift package `CareKit`)
│   ├── Garment, Category, FabricNote
│   ├── CareProfile  // wash{temp,action}, bleach, dry{method,heat}, iron{cap}, professional, prohibitions[]
│   ├── CareSymbol   // ISO 3758 symbol table: glyph id -> plain-language meaning
│   ├── BasketEvaluationEngine // deterministic compatibility grouping + conflict reasons
│   └── WashLog      // per-garment method+date entries
├── Data (GRDB/SQLite store + app-container photo store; versioned schema)
├── Features
│   ├── Registry (list, add/edit garment, photo capture/pick)
│   ├── CareEditor (structured care-cap editing, symbol reference sheets)
│   ├── SymbolReference (browse/search decoded symbol table)
│   ├── Basket (picker + compatibility report + conflict reasons)
│   ├── WashLog (history + last-washed surfacing)
│   └── Settings (backup/restore, CSV export, about)
└── CareWorkspaceLayout (single layout-adaptation seam; compact today,
    dual-screen/regular-width migration target — see README)
```

The compatibility engine is pure, table-driven, and unit-testable without UI:

- Garments group into a compatible basket iff, per axis (max wash temp, wash action, bleach, dry method/heat, iron cap, dry-clean-only), the strictest member's cap can be honored without violating any other member's explicit prohibitions.
- Hard conflicts (e.g., garment A "do not tumble dry" vs basket plan using tumble dry; dry-clean-only garment in a wet-wash basket) are named with garment + rule + axis.
- Ambiguity is representable: an unrecorded axis is `unknown`, not "safe" — the report says "care not recorded" rather than silently passing.

## Technology choices

| Choice | Rationale |
|---|---|
| SwiftUI, Swift 6, iOS 26 SDK floor | Current Apple-native baseline; strict concurrency; per user policy all mobile ideas pin iOS 26+. |
| iPhone-only (`TARGETED_DEVICE_FAMILY = 1`) | User directive 2026-09-15; simplifies build + App Store submission; iPad is explicit opt-in. |
| GRDB/SQLite | Transactional local store with migrations; mature; testable in pure Swift. |
| Photos: app-container copies only | No Photo Library library-wide permission; add-only/pick then copy. |
| Zero network | MVP has no backend; a CI gate fails the build if networking APIs are introduced outside an allowlist. |
| Xcode + macOS GitHub Actions for CI | Required for iOS builds; TestFlight upload via App Store Connect API secrets already configured. |

## Milestones & dependency order

1. **M1 Skeleton + CI** — Xcode project, `CareKit` package, iOS 26 build on macOS runner, iPhone-only enforcement check, zero-network gate. *(no deps)*
2. **M2 Domain layer** — CareProfile/CareSymbol tables, BasketEvaluationEngine + WashLog models, exhaustive unit tests incl. unknown-axis semantics. *(M1)*
3. **M3 Registry + care editor** — garment CRUD, photo capture/pick, accessible forms, care-cap editing. *(M2)*
4. **M4 Basket builder + conflict UI** — picker, compatibility report with named reasons, empty/unknown states. *(M2, M3)*
5. **M5 Wash log + symbol reference** — history UI, last-washed surfacing, browsable decoded symbol table. *(M2, M3)*
6. **M6 Backup/export + accessibility pass** — JSON archive backup/restore (previewed merge), CSV export, VoiceOver/Dynamic Type audit incl. symbol glyph labels. *(M3–M5)*
7. **M7 Release** — signed archive, TestFlight upload via ASC API secrets, release evidence. *(M1–M6)*

## Testing strategy

- **Pure-domain unit tests** (every CI run, Linux-compatible where possible): symbol table completeness, compatibility matrix every axis pair, conflict reason correctness, unknown-axis behavior, wash-log cadence math.
- **Data-layer tests**: schema migration fixtures, backup round-trip (export→wipe→restore equality), CSV output golden files.
- **UI tests** (macOS runner, iPhone simulator): add garment → build basket → observe conflict → log wash happy path; accessibility audit scan as a separate gated step.
- **Release evidence**: actual `xcodebuild` logs + App Store Connect processing status; never claimed from source inspection. On Linux only structural checks run and are labeled as such.

## Packaging / distribution

- Ad hoc builds during development; TestFlight via App Store Connect API (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID` repository secrets, referenced by name only).
- Bundle ID `com.infinityball.carelabel` (registered, `CREATED`).
- App Store submission is a late milestone with its own evidence gate; iPhone-only SKU.

## Risks

| Risk | Mitigation |
|---|---|
| Care-symbol semantics oversimplified → wrong advice | Model the ISO 3758 table faithfully, keep it a *decoding of the manufacturer's label*, show "unknown" states, no fabric-advice claims. |
| Compatibility engine false "safe" | Strictest-wins per axis + explicit prohibition check + `unknown` never passes silently; table-driven tests over the full axis matrix. |
| Photo storage bloat | Downscale to fixed max dimension on import; per-app storage budget with user-visible usage. |
| Layout seam rot (dual-screen future) | `CareWorkspaceLayout` is the single adaptation point with a protocol + test doubles. |
| iOS toolchain drift | `toolchain.json` pins Xcode/iOS SDK/Swift mode; CI asserts the pin. |

## Non-goals (explicit)

No OCR, no AI advice, no network features, no iPad/Watch/Android in MVP, no purchase/shopping links, no dry-cleaner integration, no laundry-reminder subscriptions; wash-cadence data is descriptive history, not a hygiene recommendation.
