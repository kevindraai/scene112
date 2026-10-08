"""Bounded native diagnostics parser/lifecycle fixtures; not native launch evidence."""

import importlib.util
import json
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "diagnostic_probe", Path(__file__).parents[1] / "tools/probe_native_graphics.py"
)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class NativeDiagnostics(unittest.TestCase):
    def test_windows_host_inventory_uses_readonly_cim_and_bounded_timeout(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(
                probe, "invoke", return_value=(0, '{"video":[{"Name":"fixture"}]}')
            ) as invoke:
                result = probe.capture_host(Path(directory), "windows")
            command = invoke.call_args.args[0]
            self.assertIn("Get-CimInstance", command[-1])
            self.assertNotIn("Set-", command[-1])
            self.assertEqual(invoke.call_args.kwargs["timeout"], 45)
            self.assertEqual(result["returncode"], 0)
            self.assertEqual(
                probe.json_read((Path(directory) / "host/system.json").read_text())[
                    "inventory"
                ]["video"][0]["Name"],
                "fixture",
            )

    def test_mac_host_inventory_requests_only_planned_display_hardware_types(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(
                probe,
                "invoke",
                return_value=(0, '{"SPDisplaysDataType":[],"SPHardwareDataType":[]}'),
            ) as invoke:
                probe.capture_host(Path(directory), "macos")
            self.assertEqual(
                invoke.call_args.args[0],
                [
                    "system_profiler",
                    "SPDisplaysDataType",
                    "SPHardwareDataType",
                    "-json",
                ],
            )

    def test_host_failure_is_preserved_as_diagnostic_not_fake_inventory(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(probe, "invoke", return_value=(124, "PROBE_TIMEOUT")):
                result = probe.capture_host(Path(directory), "macos")
            stored = probe.json_read((Path(directory) / "host/system.json").read_text())
            self.assertEqual(result["returncode"], 124)
            self.assertIn("parse_error", stored)
            self.assertNotIn("inventory", stored)

    def test_only_recent_reports_of_exact_own_process_are_copied(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            reports = base / "Library/Logs/DiagnosticReports"
            reports.mkdir(parents=True)
            own = reports / "Scene112-new.ips"
            own.write_text(json.dumps({"app_name": "Scene112"}) + "\n{}")
            old = reports / "Scene112-old.ips"
            old.write_text(json.dumps({"app_name": "Scene112"}))
            os.utime(old, (1, 1))
            (reports / "OtherApp-new.ips").write_text(
                json.dumps({"app_name": "OtherApp"})
            )
            (reports / "Scene112-impostor.ips").write_text(
                json.dumps({"app_name": "OtherApp"})
            )
            output = base / "out"
            output.mkdir()
            with (
                patch.object(probe.platform, "system", return_value="Darwin"),
                patch.object(probe.Path, "home", return_value=base),
            ):
                copied = probe.capture_crashes(output, time.time() - 1)
            self.assertEqual([item["file"] for item in copied], ["Scene112-new.ips"])
            self.assertTrue(copied[0]["copied"])
            self.assertEqual(
                (output / "own-crashes/Scene112-new.ips").read_bytes(), own.read_bytes()
            )

    def test_crash_report_count_is_bounded(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            reports = base / "Library/Logs/DiagnosticReports"
            reports.mkdir(parents=True)
            for index in range(8):
                (reports / f"Scene112-{index}.crash").write_text(
                    "Process: Scene112 [1234]\nfixture"
                )
            output = base / "out"
            output.mkdir()
            with (
                patch.object(probe.platform, "system", return_value="Darwin"),
                patch.object(probe.Path, "home", return_value=base),
            ):
                self.assertEqual(len(probe.capture_crashes(output, time.time() - 1)), 5)

    def test_large_own_reports_record_reason_without_unbounded_upload(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            reports = base / "Library/Logs/DiagnosticReports"
            reports.mkdir(parents=True)
            path = reports / "Scene112-large.crash"
            with path.open("wb") as stream:
                stream.write(b"Process: Scene112 [1234]\n")
                stream.truncate(4 * 1024 * 1024 + 1)
            output = base / "out"
            output.mkdir()
            with (
                patch.object(probe.platform, "system", return_value="Darwin"),
                patch.object(probe.Path, "home", return_value=base),
            ):
                copied = probe.capture_crashes(output, time.time() - 1)
            self.assertFalse(copied[0]["copied"])
            self.assertFalse((output / "own-crashes").exists())

    def test_other_platforms_never_scan_mac_reports(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(probe.platform, "system", return_value="Windows"):
                self.assertEqual(probe.capture_crashes(Path(directory), 0), [])


if __name__ == "__main__":
    unittest.main()
