#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

expected_sha="${1:-}"
if [[ -z "$expected_sha" ]]; then
  echo "usage: Scripts/ci.sh <expected-commit-sha>" >&2
  exit 2
fi

artifact_root="${CARELABEL_ARTIFACT_DIR:-$repo_root/build/ci-artifacts}"
mkdir -p "$artifact_root" "$repo_root/build"
artifact_dir="$(mktemp -d "$artifact_root/run.XXXXXX")"
derived_data="$(mktemp -d "$repo_root/build/DerivedData.XXXXXX")"
phase="initialization"

write_provenance() {
  local result=$?
  {
    echo "expected_sha=$expected_sha"
    echo "actual_sha=$(git rev-parse HEAD 2>/dev/null || echo unavailable)"
    echo "runner_os=${RUNNER_OS:-unknown}"
    echo "runner_arch=${RUNNER_ARCH:-unknown}"
    echo "developer_dir=${DEVELOPER_DIR:-unselected}"
    echo "simulator_udid=${simulator_udid:-unselected}"
    echo "phase=$phase"
    echo "exit_status=$result"
  } > "$artifact_dir/provenance.txt"
  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    python3 Scripts/boot_simulator.py capture \
      --timeout 15 --output "$artifact_dir/xcode-version.txt" \
      -- xcodebuild -version || true
    python3 Scripts/boot_simulator.py capture \
      --timeout 15 --output "$artifact_dir/iphoneos-sdk-version.txt" \
      -- xcrun --sdk iphoneos --show-sdk-version || true
    python3 Scripts/boot_simulator.py capture \
      --timeout 20 --output "$artifact_dir/simulator-devices-exit.log" \
      -- xcrun simctl list devices available --json || true
  fi
}
trap write_provenance EXIT

actual_sha="$(git rev-parse HEAD)"
if [[ "$actual_sha" != "$expected_sha" ]]; then
  echo "Checked out SHA $actual_sha does not equal requested SHA $expected_sha" >&2
  exit 1
fi

phase="helper_tests"
python3 -m unittest discover -s Scripts/tests -v 2>&1 | tee "$artifact_dir/helper-tests.log"

phase="iphone_only_project_gate"
# Static grep gate: every TARGETED_DEVICE_FAMILY setting in project files must
# be exactly 1 (never 1,2). The post-build device_family_guard below re-checks
# the built Info.plist; this gate fails fast even before any build happens.
project_files=(CareLabel.xcodeproj/project.pbxproj)
bad_family="$(grep -rhoE 'TARGETED_DEVICE_FAMILY = [^;]+;' "${project_files[@]}" \
  | grep -vE 'TARGETED_DEVICE_FAMILY = 1;' || true)"
family_hits="$(grep -rhoE 'TARGETED_DEVICE_FAMILY = [^;]+;' "${project_files[@]}" | wc -l | tr -d ' ' || echo 0)"
if [[ -n "$bad_family" ]]; then
  echo "iPhone-only gate failed: non-iPhone TARGETED_DEVICE_FAMILY setting(s) found:" >&2
  echo "$bad_family" >&2
  exit 1
fi
if [[ "$family_hits" -lt 4 ]]; then
  echo "iPhone-only gate failed: expected >=4 TARGETED_DEVICE_FAMILY settings, found $family_hits" >&2
  exit 1
fi
echo "iPhone-only project gate passed: $family_hits TARGETED_DEVICE_FAMILY setting(s), all = 1"

phase="zero_network_gate"
python3 Scripts/zero_network_guard.py 2>&1 | tee "$artifact_dir/zero-network-gate.log"

phase="toolchain_selection"
python3 Scripts/select_xcode.py \
  --toolchain toolchain.json \
  > "$artifact_dir/developer-dir.txt" \
  2> >(tee "$artifact_dir/toolchain-selection.log" >&2)
export DEVELOPER_DIR
DEVELOPER_DIR="$(<"$artifact_dir/developer-dir.txt")"

phase="simulator_selection"
sdk_version="$(python3 -c 'import json; print(json.load(open("toolchain.json", encoding="utf-8"))["iphoneos_sdk"])')"
simulator_udid="$(python3 Scripts/select_simulator.py \
  --sdk "$sdk_version" \
  --devices-json-out "$artifact_dir/simulator-devices.json")"
echo "platform=iOS Simulator,id=$simulator_udid" > "$artifact_dir/destination.txt"

phase="simulator_boot"
python3 Scripts/boot_simulator.py boot \
  --udid "$simulator_udid" \
  --devices-json "$artifact_dir/simulator-devices.json" \
  --log "$artifact_dir/simulator-boot.log" \
  --boot-timeout 120 \
  --bootstatus-timeout 180 \
  2> >(tee -a "$artifact_dir/simulator-boot.log" >&2)

phase="domain_tests"
# Issue #2 acceptance criterion: domain package coverage must be reported.
# We run the pure-Swift CareKit tests with instrumentation, merge the raw
# profiles, and print a per-file coverage report into the CI artifact log.
carekit_scratch="$repo_root/build/CareKitScratch"
xcrun swift test \
  --package-path Packages/CareKit \
  --scratch-path "$carekit_scratch" \
  --enable-code-coverage \
  2>&1 | tee "$artifact_dir/domain-tests.log"

phase="domain_coverage_report"
profraw_files=()
while IFS= read -r f; do profraw_files+=("$f"); done < <(find "$carekit_scratch" -name '*.profraw' -type f)
if [[ ${#profraw_files[@]} -eq 0 ]]; then
  echo "Coverage instrumentation produced no .profraw files under $carekit_scratch" >&2
  exit 1
fi
xcrun llvm-profdata merge -sparse "${profraw_files[@]}" -o "$artifact_dir/carekit.profdata"
cov_binary="$(find "$carekit_scratch" -path '*.xctest/Contents/MacOS/*' ! -path '*.dSYM/*' -type f | head -1)"
if [[ -z "$cov_binary" ]]; then
  echo "Could not locate CareKit test binary for coverage report" >&2
  exit 1
fi
xcrun llvm-cov report "$cov_binary" \
  -instr-profile="$artifact_dir/carekit.profdata" \
  CareKit \
  2>&1 | tee "$artifact_dir/domain-coverage.log"
# Fail if the domain sources show zero covered lines — coverage that
# silently stopped instrumenting must not pass as "reported".
if ! awk '/CareKit\/Sources/ { lines+=$6 } END { exit (lines+0 > 0) ? 0 : 1 }' \
  "$artifact_dir/domain-coverage.log"; then
  echo "Coverage report contains no covered lines for CareKit sources" >&2
  exit 1
fi
echo "Domain coverage report written to domain-coverage.log"

phase="data_layer_tests"
# Issue #4 acceptance criterion: the CareStore data layer (GRDB persistence,
# migrations against the committed v1 fixture, photo store) is unit-tested in
# CI. GRDB's test fetch happens at dependency-resolution time on the runner;
# the shipped app still contains zero networking code (enforced by the
# zero-network gate above, which skips SwiftPM .build directories).
carestore_scratch="$repo_root/build/CareStoreScratch"
xcrun swift test \
  --package-path Packages/CareStore \
  --scratch-path "$carestore_scratch" \
  --enable-code-coverage \
  2>&1 | tee "$artifact_dir/data-layer-tests.log"

phase="data_layer_coverage_report"
carestore_profraw=()
while IFS= read -r f; do carestore_profraw+=("$f"); done < <(find "$carestore_scratch" -name '*.profraw' -type f)
if [[ ${#carestore_profraw[@]} -eq 0 ]]; then
  echo "CareStore coverage instrumentation produced no .profraw files under $carestore_scratch" >&2
  exit 1
fi
xcrun llvm-profdata merge -sparse "${carestore_profraw[@]}" -o "$artifact_dir/carestore.profdata"
carestore_cov_binary="$(find "$carestore_scratch" -path '*.xctest/Contents/MacOS/*' ! -path '*.dSYM/*' -type f | head -1)"
if [[ -z "$carestore_cov_binary" ]]; then
  echo "Could not locate CareStore test binary for coverage report" >&2
  exit 1
fi
xcrun llvm-cov report "$carestore_cov_binary" \
  -instr-profile="$artifact_dir/carestore.profdata" \
  CareStore \
  2>&1 | tee "$artifact_dir/data-layer-coverage.log"
if ! awk '/CareStore\/Sources/ { lines+=$6 } END { exit (lines+0 > 0) ? 0 : 1 }' \
  "$artifact_dir/data-layer-coverage.log"; then
  echo "Coverage report contains no covered lines for CareStore sources" >&2
  exit 1
fi
echo "Data layer coverage report written to data-layer-coverage.log"

phase="app_build"
xcodebuild build \
  -project CareLabel.xcodeproj \
  -scheme CareLabel \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator_udid" \
  -derivedDataPath "$derived_data" \
  -resultBundlePath "$artifact_dir/build.xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  2>&1 | tee "$artifact_dir/xcodebuild-build.log"

phase="device_family_guard"
app_plist="$derived_data/Build/Products/Debug-iphonesimulator/CareLabel.app/Info.plist"
if [[ ! -f "$app_plist" ]]; then
  echo "Built app Info.plist missing at $app_plist" >&2
  exit 1
fi
plutil -convert json -o "$artifact_dir/app-info.json" "$app_plist"
python3 - "$artifact_dir/app-info.json" <<'PYTHON'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    info = json.load(handle)
family = info.get("UIDeviceFamily")
if family != [1]:
    raise SystemExit(f"Built app UIDeviceFamily must be [1], observed {family!r}")
print("Verified built app UIDeviceFamily == [1] (iPhone only)")
PYTHON

phase="ui_tests"
xcodebuild test \
  -project CareLabel.xcodeproj \
  -scheme CareLabel \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator_udid" \
  -derivedDataPath "$derived_data" \
  -resultBundlePath "$artifact_dir/tests.xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  2>&1 | tee "$artifact_dir/xcodebuild-test.log"

phase="complete"
