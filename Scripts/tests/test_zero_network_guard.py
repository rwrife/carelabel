import tempfile
import unittest
from pathlib import Path

from Scripts.zero_network_guard import find_violations, load_allowlist


class AllowlistTests(unittest.TestCase):
    def write_allowlist(self, text):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "network_allowlist.txt"
        path.write_text(text, encoding="utf-8")
        return path

    def test_ignores_comments_and_blank_lines(self):
        path = self.write_allowlist("# comment\n\n  \nApp/Legal.swift\n")
        self.assertEqual(load_allowlist(path), {"App/Legal.swift"})

    def test_missing_allowlist_is_an_error(self):
        with self.assertRaises(ValueError):
            load_allowlist(Path(tempfile.mkdtemp()) / "missing.txt")


class ViolationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "App").mkdir()
        (self.root / "Packages").mkdir()

    def write(self, relative, text):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def test_clean_sources_have_no_violations(self):
        self.write("App/BootstrapHomeView.swift", "import SwiftUI\nstruct V {}\n")
        self.write("Packages/CareKit/Sources/CareKit/CareContract.swift", "import Foundation\n")
        self.assertEqual(find_violations(self.root, set()), [])

    def test_detects_urlsession_usage(self):
        self.write("App/Sneaky.swift", "let s = URLSession.shared\n")
        violations = find_violations(self.root, set())
        self.assertEqual(len(violations), 1)
        self.assertIn("App/Sneaky.swift:1", violations[0])
        self.assertIn("URLSession", violations[0])

    def test_detects_network_framework_import(self):
        self.write("Packages/X/Sources/Y/Z.swift", "import Network\n")
        violations = find_violations(self.root, set())
        self.assertEqual(len(violations), 1)
        self.assertIn("import Network", violations[0])

    def test_allowlisted_path_is_exempt(self):
        self.write("App/Network.swift", "import FoundationNetworking\nURLSession.shared\n")
        self.assertEqual(find_violations(self.root, {"App/Network.swift"}), [])

    def test_files_outside_scan_roots_are_ignored(self):
        (self.root / "scripts-support").mkdir()
        self.write("scripts-support/Tool.swift", "URLSession.shared\n")
        self.assertEqual(find_violations(self.root, set()), [])

    def test_swiftpm_build_directories_are_skipped(self):
        # Fetched dependency checkouts under .build are not first-party
        # sources; the guard must not scan them (issue #4 added GRDB).
        self.write("Packages/CareStore/.build/checkouts/GRDB/GRDB/Dependency.swift", "URLSession.shared\n")
        self.write("Packages/CareStore/Sources/CareStore/Real.swift", "import Foundation\n")
        self.assertEqual(find_violations(self.root, set()), [])
        # First-party sources under the same root are still scanned.
        self.write("Packages/CareStore/Sources/CareStore/Sneaky.swift", "URLSession.shared\n")
        violations = find_violations(self.root, set())
        self.assertEqual(len(violations), 1)
        self.assertIn("Packages/CareStore/Sources/CareStore/Sneaky.swift", violations[0])


if __name__ == "__main__":
    unittest.main()
