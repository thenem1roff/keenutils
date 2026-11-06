#!/usr/bin/env python3
"""Offline regression tests for the Flowseal strategy manager (never use router)."""
import importlib.util
import io
import json
import shutil
import sys
import tempfile
import unittest
import zipfile
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
MODULES = ROOT / "modules" / "flowseal"
sys.path.insert(0, str(MODULES))
spec = importlib.util.spec_from_file_location("flowseal_manager", MODULES / "manager.py")
manager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manager)


class FlowsealManagerTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.addCleanup(patch.stopall)
        for name, value in [
            ("HOME", self.root / "home"),
            ("STRATEGIES", self.root / "home/strategies"),
            ("TEMP", self.root / "home/tmp"),
            ("HISTORY", self.root / "home/history"),
            ("NFQWS2_CONF", self.root / "router/nfqws2.conf"),
        ]:
            patch.object(manager, name, value).start()
        manager.STRATEGIES.mkdir(parents=True)
        manager.NFQWS2_CONF.parent.mkdir()
        manager.NFQWS2_CONF.write_text("original router config\n", encoding="utf-8")
        self.archive = self.root / "archive.zip"
        with zipfile.ZipFile(self.archive, "w") as archive:
            base = "zapret-discord-youtube-1.10.4/"
            archive.writestr(
                base + "general (ALT12).bat",
                'winws.exe --filter-tcp=443 --hostlist="%LISTS%list-general.txt" '
                '--dpi-desync=fake --dpi-desync-fake-tls=0x160301\n',
            )
            archive.writestr(base + "lists/list-general.txt", "example.org\n")
            archive.writestr(base + "bin/winws.exe", "must not extract")
            archive.writestr(base + "bin/tls.bin", b"\x16\x03\x01")

    def test_safe_extraction_only_expected_files(self):
        source = self.root / "source"
        source.mkdir()
        profiles = manager.extract_release(self.archive, source)
        self.assertEqual(profiles, ["general (ALT12).bat"])
        self.assertTrue((source / "lists/list-general.txt").is_file())
        self.assertTrue((source / "bin/tls.bin").is_file())
        self.assertFalse((source / "bin/winws.exe").exists())

    def test_reject_zip_path_traversal(self):
        evil = self.root / "evil.zip"
        with zipfile.ZipFile(evil, "w") as archive:
            archive.writestr("zapret-discord-youtube-1.10.4/../general (ALT1).bat", "test")
        with self.assertRaises(manager.ManagerError):
            manager.extract_release(evil, self.root / "untrusted")

    def test_identification_distinguishes_versions_and_profiles(self):
        self.assertEqual(manager.strategy_id("1.10.4", "general (ALT12).bat"), "flowseal-1.10.4-alt12")
        self.assertEqual(
            manager.strategy_id("1.10.4", "general (SIMPLE FAKE ALT2).bat"),
            "flowseal-1.10.4-simple-fake-alt2",
        )
        self.assertNotEqual(
            manager.strategy_id("1.10.4", "general (ALT12).bat"),
            manager.strategy_id("1.10.3", "general (ALT12).bat"),
        )

    def test_add_strategy_saves_automatically_without_touching_router(self):
        def fake_download(url, target):
            shutil.copyfile(self.archive, target)
            return "a" * 64

        original = manager.NFQWS2_CONF.read_bytes()
        with patch.object(manager, "release_info", return_value=("1.10.4", "https://github.com/Flowseal/zapret-discord-youtube/releases/download/1.10.4/zapret-discord-youtube-1.10.4.zip")), \
             patch.object(manager, "download_release", side_effect=fake_download), \
             patch.object(manager, "prompt", side_effect=["1", "", ""]), \
             redirect_stdout(io.StringIO()):
            manager.add_strategy()
        saved = manager.STRATEGIES / "flowseal-1.10.4-alt12"
        info = json.loads((saved / "info.json").read_text(encoding="utf-8"))
        self.assertEqual(info["source"], "Flowseal")
        self.assertEqual(info["version"], "1.10.4")
        self.assertEqual(info["name"], "ALT12")
        self.assertTrue(info["game_ports"])
        self.assertTrue((saved / "nfqws2.conf").exists())
        self.assertTrue((saved / "REPORT.md").exists())
        self.assertEqual(manager.NFQWS2_CONF.read_bytes(), original)
        self.assertEqual(list(manager.TEMP.iterdir()), [])

    def test_delete_strategy_also_removes_its_old_revisions(self):
        identity = "flowseal-1.10.4-alt12"
        saved = manager.STRATEGIES / identity
        saved.mkdir()
        info = {"source": "Flowseal", "name": "ALT12", "version": "1.10.4"}
        (saved / "info.json").write_text(json.dumps(info), encoding="utf-8")
        manager.HISTORY.mkdir()
        old = manager.HISTORY / (identity + "-20261106-010000")
        old.mkdir()
        (old / "nfqws2.conf").write_text("older config", encoding="utf-8")
        unrelated = manager.HISTORY / "flowseal-1.10.4-alt13-20261106-010000"
        unrelated.mkdir()
        with patch.object(manager, "prompt", side_effect=["3", ""]), redirect_stdout(io.StringIO()):
            manager.show_strategy(saved, info)
        self.assertFalse(saved.exists())
        self.assertFalse(old.exists())
        self.assertTrue(unrelated.is_dir())


if __name__ == "__main__":
    unittest.main()
