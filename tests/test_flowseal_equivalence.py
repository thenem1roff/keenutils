"""Python is used ONLY in GitHub CI as a reference implementation, never on Keenetic.

Compare Flowseal strategy semantics (arguments/order) of the Shell/AWK port
against the upstream Sxlenium MIT converter. Stock LIST path substitutions
are intentionally excluded from equality comparisons.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests" / "reference"))
from zapret_keenetic.converter import ConverterSettings, convert


def assignment(text: str, name: str) -> list[str]:
    match = re.search(rf'(?ms)^{re.escape(name)}="(.*?)"$' , text)
    if not match:
        raise AssertionError(f"Missing {name}")
    return [line.strip() for line in match.group(1).splitlines() if line.strip()]


def normalized_arguments(text: str) -> list[str]:
    lines = assignment(text, "NFQWS_ARGS_CUSTOM") + assignment(text, "NFQWS_ARGS")
    cleaned = []
    for line in lines:
        # Stock nfqws2 LIST mappings are deliberately not the same as Flowseal.
        line = re.sub(
            r"(--(?:hostlist|hostlist-exclude|ipset|ipset-exclude)=)/opt/etc/nfqws2/lists/[^ ]+",
            r"\1<LIST>",
            line,
        )
        cleaned.append(line)
    return cleaned


class FlowsealParity(unittest.TestCase):
    def run_case(self, fixture: Path, enable_games: bool):
        with tempfile.TemporaryDirectory(prefix="flowseal-parity-") as scratch:
            root = Path(scratch)
            source = root / "source"
            (source / "lists").mkdir(parents=True)
            (source / "bin").mkdir()
            content = fixture.read_text(encoding="utf-8-sig")
            source_file = source / fixture.name
            source_file.write_text(content, encoding="utf-8")
            # Populate referenced resources so the Python baseline does not
            # deliberately substitute missing files with 0x00.
            for item in set(re.findall(r"%BIN%([A-Za-z0-9_.-]+\.bin)", content, re.I)):
                (source / "bin" / item).write_bytes(b"\x16\x03\x01\x00\x03")
            for item in set(re.findall(r"%LISTS%([A-Za-z0-9_.-]+\.txt)", content, re.I)):
                (source / "lists" / item).write_text("example.org\n", encoding="utf-8")

            py_out = root / "python"
            shell_out = root / "shell"
            shell_out.mkdir()
            original = convert(
                ConverterSettings(
                    source=source,
                    profile=fixture.name,
                    output=py_out,
                    target="keenetic",
                    interface="eth3",
                    game_filter="all" if enable_games else "disabled",
                    strict=False,
                )
            )
            env = dict(os.environ)
            env.update(
                FLOWSEAL_OUTPUT=str(shell_out),
                FLOWSEAL_GAMES="yes" if enable_games else "no",
                FLOWSEAL_INTERFACE="eth3",
                FLOWSEAL_ALT_LUA_HEX=(
                    ROOT / "modules/flowseal/hostfakesplit_alt1.lua"
                ).read_bytes().hex(),
            )
            call = subprocess.run(
                ["awk", "-f", str(ROOT / "modules/flowseal/converter.awk"), str(source_file)],
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(call.returncode, 0, call.stderr)
            shell_config = (shell_out / "nfqws2.conf").read_text(encoding="utf-8")
            ref_config = (py_out / "nfqws2.conf").read_text(encoding="utf-8")
            self.assertEqual(
                normalized_arguments(shell_config),
                normalized_arguments(ref_config),
                f"Mismatch for {fixture.name} (game={enable_games})",
            )
            self.assertEqual(
                int(
                    re.search(
                        r"^PROFILES_WRITTEN=(\d+)$",
                        (shell_out / "stats.txt").read_text(),
                        flags=re.M,
                    ).group(1)
                ),
                original.profiles_written,
            )
            self.assertEqual(
                re.search(r"^TCP_PORTS=(.*)$", shell_config, flags=re.M).group(1),
                re.search(r"^TCP_PORTS=(.*)$", ref_config, flags=re.M).group(1),
            )
            self.assertEqual(
                re.search(r"^UDP_PORTS=(.*)$", shell_config, flags=re.M).group(1),
                re.search(r"^UDP_PORTS=(.*)$", ref_config, flags=re.M).group(1),
            )

    def test_flowseal_profiles_match_upstream(self):
        fixtures = sorted((ROOT / "tests/fixtures/flowseal").glob("general*.bat"))
        self.assertGreaterEqual(len(fixtures), 4)
        for fixture in fixtures:
            for enable_games in (False, True):
                with self.subTest(profile=fixture.name, games=enable_games):
                    self.run_case(fixture, enable_games)


if __name__ == "__main__":
    unittest.main()
