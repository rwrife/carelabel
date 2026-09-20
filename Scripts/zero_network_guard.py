#!/usr/bin/env python3
"""Zero-network gate for the Care Label MVP.

The MVP makes no network requests at all (README "Privacy, permissions, and
data storage"). This gate fails CI if any networking API token appears in
shipped Swift sources outside the explicit allowlist file. The allowlist is
intentionally empty; adding an entry is a deliberate product decision.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

BANNED_TOKENS = (
    "URLSession",
    "import Network",
    "import FoundationNetworking",
    "NWConnection",
    "NWListener",
    "NWParameters",
    "CFNetwork",
    "MultipeerConnectivity",
)

DEFAULT_SCAN_ROOTS = ("App", "UITests", "Packages")


def load_allowlist(path: Path) -> set[str]:
    """Repo-relative allowlisted paths; blank lines and #-comments ignored."""
    if not path.exists():
        raise ValueError(f"Allowlist file {path} does not exist")
    entries = set()
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line and not line.startswith("#"):
            entries.add(line)
    return entries


def collect_swift_sources(repo_root: Path, scan_roots=tuple(DEFAULT_SCAN_ROOTS)) -> list[Path]:
    sources: list[Path] = []
    for root in scan_roots:
        base = repo_root / root
        if base.is_dir():
            for source in sorted(base.rglob("*.swift")):
                # Skip SwiftPM build directories: `.build` contains fetched
                # third-party checkouts, which are not shipped first-party
                # sources (dependencies are vetted by review, not the guard).
                if ".build" in source.relative_to(base).parts:
                    continue
                sources.append(source)
    return sources


def find_violations(
    repo_root: Path,
    allowlist: set[str],
    scan_roots=tuple(DEFAULT_SCAN_ROOTS),
) -> list[str]:
    violations: list[str] = []
    for source in collect_swift_sources(repo_root, scan_roots):
        try:
            relative = source.relative_to(repo_root).as_posix()
        except ValueError:
            continue
        if relative in allowlist:
            continue
        for line_number, line in enumerate(
            source.read_text(encoding="utf-8").splitlines(), start=1
        ):
            for token in BANNED_TOKENS:
                if token in line:
                    violations.append(
                        f"{relative}:{line_number}: banned networking token {token!r}: {line.strip()}"
                    )
    return violations


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--allowlist", type=Path, default=None)
    args = parser.parse_args()
    repo_root = args.repo_root.resolve()
    allowlist_path = args.allowlist or repo_root / "network_allowlist.txt"
    try:
        allowlist = load_allowlist(allowlist_path)
    except (OSError, ValueError) as error:
        print(f"zero-network gate misconfigured: {error}", file=sys.stderr)
        return 2
    violations = find_violations(repo_root, allowlist)
    if violations:
        print(
            f"Zero-network gate failed: {len(violations)} banned networking usage(s) "
            f"outside {allowlist_path.name}:",
            file=sys.stderr,
        )
        for violation in violations:
            print(f"  {violation}", file=sys.stderr)
        return 1
    scanned = len(collect_swift_sources(repo_root))
    print(f"Zero-network gate passed: {scanned} Swift source(s) scanned, allowlist has {len(allowlist)} entry(ies).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
