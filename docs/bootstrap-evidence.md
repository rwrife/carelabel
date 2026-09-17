# Issue #1 bootstrap evidence

Dated record of what was actually verified, where, and what remains CI-only.

## What this bootstrap adds

- `CareLabel.xcodeproj` with shared `CareLabel` scheme (app + UI-test targets).
- `App/`: SwiftUI launch-only placeholder wired to `Packages/CareKit`.
- `Packages/CareKit`: pure Swift 6 package holding published MVP product
  contracts (five care axes, `CareWorkspaceLayout` seam, export forms, photo
  downscale dimension) with swift-testing unit tests. The full care domain
  (profiles, ISO 3758 table) is issue #2; the engine is issue #3.
- `UITests/CareLabelLaunchTests.swift`: simulator launch smoke test.
- `Scripts/`: pinned toolchain selection, simulator selection/boot helpers with
  bounded subprocess timeouts, the zero-network gate
  (`Scripts/zero_network_guard.py` + `network_allowlist.txt`), and the CI
  entrypoint `Scripts/ci.sh`.
- `.github/workflows/ci.yml`: exact-head checkout, pinned-SDK simulator
  validation, always-upload artifacts on `macos-15`.

## Product-invariant enforcement

`toolchain.json` pins Xcode 26.0.1 (17A400) / iPhoneOS SDK 26.0 / Swift 6 mode /
deployment target 26.0, per the repo's `toolchain.json` baseline and the
measured hosted-runner inventory (the `/Applications/Xcode_26.0.app` directory
alias measures as Xcode 26.0.1 build 17A400 — an exact-`26.0` pin is not
measurable on hosted runners). `Scripts/select_xcode.py` measures
`xcodebuild -version` and `xcrun --sdk iphoneos --show-sdk-version` for every
installation under `/Applications` and only accepts an actual
version/build/SDK match; a missing pin is a hard CI failure (`PinError`), never
a silent fallback. The workflow checks out
`github.event.pull_request.head.sha` explicitly, so CI tests the exact PR head
commit, not a synthetic merge ref.

iPhone-only is enforced three times:

1. The project sets `TARGETED_DEVICE_FAMILY = 1` in every app/UI-test
   configuration (4 configurations).
2. The `iphone_only_project_gate` phase in `Scripts/ci.sh` greps
   `CareLabel.xcodeproj/project.pbxproj` and fails if any
   `TARGETED_DEVICE_FAMILY` setting is not exactly `1` (e.g. `1,2`).
3. The post-build `device_family_guard` phase converts the built
   `CareLabel.app/Info.plist` to JSON and fails unless `UIDeviceFamily == [1]`.
   `app-info.json` is uploaded as an artifact.

Zero-network is enforced by the `zero_network_gate` phase:
`Scripts/zero_network_guard.py` scans all Swift sources under `App/`,
`UITests/`, and `Packages/` for banned networking tokens (`URLSession`,
`import Network`, `import FoundationNetworking`, `NWConnection`, `NWListener`,
`NWParameters`, `CFNetwork`, `MultipeerConnectivity`) and fails CI unless the
usage path is listed in the intentionally-empty `network_allowlist.txt`.

All simulator subprocesses are bounded (30 s enumeration, 120 s boot, 180 s
bootstatus) with logs preserved in `build/ci-artifacts`, and the workflow
uploads artifacts with `if: always()` so failures keep their provenance
(`provenance.txt` records expected/actual SHA, phase, and exit status).

## Verification actually performed

Linux executor host (this host has no Swift/Xcode toolchain):

- `python3 -m unittest discover -s Scripts/tests` — 22 tests OK: helper tests
  for bounded boot/timeout/exit-code behavior, simulator selection, exact Xcode
  pin selection, and the zero-network gate (detection, allowlist, scan-root
  scoping).
- `docker run swift:6.1 swift test` in `Packages/CareKit` — **4 swift-testing
  tests passed** (Testing library 6.1.3, aarch64-unknown-linux-gnu). This is
  real domain-package behavior evidence on Linux; it is NOT iOS build evidence.
- `bash -n Scripts/ci.sh` — syntax check passes. Workflow YAML parses;
  `toolchain.json` parses.
- `python3 Scripts/zero_network_guard.py` — passed: 6 Swift sources scanned,
  0 banned tokens, allowlist empty.
- Static grep: `TARGETED_DEVICE_FAMILY = 1` appears 4×, `1,2` appears 0×.

Hosted macOS CI (macos-15, exact PR head) is the authoritative gate for: Xcode
26.0.1 (17A400)/SDK 26.0 pin measurement, the iPhone-simulator compile of the
app target, the launch UI test, and the built-`Info.plist`
`UIDeviceFamily == [1]` guard. Those results are recorded on the PR's CI run
and retained in the `ios-ci-<sha>` artifact — they are not claimed here.

## CI repairs

- Run 35273117220 attempt 1 (PR #8 head `ba91f20`) and post-merge main push run
  35274304537 both failed identically: `xcrun simctl list devices available
  --json` timed out at the 30 s budget (hosted-runner CoreSimulator enumeration
  stall; GitHub Actions status operational, exact toolchain pin measured fine
  before the stall). The first rerun (attempt 2) passed end-to-end and PR #8
  merged on that evidence. Because this stall class recurs across
  repos/runners in this fleet, the CI helpers now carry a bounded
  one-shot recovery instead of relying on reruns:
  - `select_simulator.py`: one retry of enumeration with the same 30 s timeout
    on timeout (nonzero exit still fails immediately), plus an immediate
    `flush()` after writing the devices JSON (a caught `TimeoutExpired` can
    otherwise keep the write handle buffered and leave a 0-byte file).
    Test override env: `CARELABEL_SIMCTL_TIMEOUT_SECONDS`.
  - `boot_simulator.py`: on a boot/bootstatus **timeout** (not nonzero exit)
    for a not-yet-booted simulator, one best-effort bounded `simctl shutdown`
    followed by exactly one boot+bootstatus retry; second timeout re-raises.
    All timeout budgets unchanged.
  - Regression tests cover retry sequences, no-second-retry, tolerated
    shutdown failure, and the empty-file-after-timeout subprocess case
    (`Scripts/tests/test_select_simulator.py`,
    `Scripts/tests/test_boot_simulator.py`).

## Explicit non-claims

- No physical-device, VoiceOver, or signed-archive evidence exists or is claimed.
- No TestFlight/upload path exists (issue #7 owns that).
- The simulator test proves launch + home-screen rendering only; product
  journeys arrive with issues #4–#6.
- iPhone Duo dual-screen is a documented design target only; today
  `CareWorkspaceLayout.current` resolves to `.compact`.
