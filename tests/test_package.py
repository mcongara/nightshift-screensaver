"""Verify release allowlists and language-specific installation metadata."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location("packager", Path(__file__).resolve().parents[1] / "scripts/package.py")
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)


class PackageTests(unittest.TestCase):
    def test_both_languages_are_self_contained_and_exclude_private_data(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            files = {
                "VERSION": "0.2.0\n", "LICENSE": "MIT",
                "bridge/nightshift.py": "# bridge", "scripts/install.py": "# installer",
                "scripts/run-installer.sh": "#!/bin/bash\n",
                "docs/INSTALL.en.md": "English guide", "docs/INSTALL.tr.md": "Türkçe kılavuz",
                "build/private-session.json": "PRIVATE", ".claude/settings.json": "SECRET"
            }
            for language in ("tr", "en"):
                files.update({f"build/{language}/NightShift.saver/Contents/MacOS/NightShift": language,
                              f"build/{language}/NightShiftMonitor": "monitor",
                              f"build/{language}/language.txt": language})
            for name, value in files.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(value)
            with patch.object(packager, "REPO", root):
                for language in ("tr", "en"):
                    archive = packager.package(language)
                    with zipfile.ZipFile(archive) as z:
                        self.assertIsNone(z.testzip())
                        self.assertEqual(z.read("NightShift/build/language.txt").decode(), language)
                        self.assertEqual(z.read("NightShift/build/NightShift.saver/Contents/MacOS/NightShift").decode(), language)
                        launcher = "Install.command" if language == "en" else "Kur.command"
                        mode = z.getinfo("NightShift/" + launcher).external_attr >> 16
                        self.assertTrue(mode & 0o111)
                        guide = "INSTALL.md" if language == "en" else "KURULUM.md"
                        self.assertIn("NightShift/" + guide, z.namelist())
                        self.assertIn("NightShift/LICENSE", z.namelist())
                        expected = {
                            "build/NightShift.saver/Contents/MacOS/NightShift", "build/NightShiftMonitor",
                            "build/language.txt", "bridge/nightshift.py", "scripts/install.py",
                            "scripts/run-installer.sh", "LICENSE", "VERSION", guide, launcher,
                            "Uninstall.command" if language == "en" else "Kaldir.command"
                        }
                        self.assertEqual(set(z.namelist()), {"NightShift/" + n for n in expected})
                        self.assertFalse(any("private" in n or ".claude" in n for n in z.namelist()))

    def test_mismatched_build_language_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name in ("build/en/NightShift.saver/Contents/MacOS/NightShift", "build/en/NightShiftMonitor", "build/en/language.txt", "VERSION"):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("tr")
            with patch.object(packager, "REPO", root), self.assertRaises(SystemExit):
                packager.package("en")
