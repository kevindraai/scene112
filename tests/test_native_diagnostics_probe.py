"""Bounded native diagnostics parser/lifecycle fixtures; not native launch evidence."""

import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import MagicMock, patch

spec = importlib.util.spec_from_file_location(
    "diagnostic_probe", Path(__file__).parents[1] / "tools/probe_native_graphics.py"
)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class NativeDiagnostics(unittest.TestCase):
    def test_known_intel_cluster_abort_can_request_separate_mobile_proof(self):
        result = {"status": "failed_before_backend_report", "returncode": -6,
                  "actual_backend": None, "phase_log": []}
        output = "MoltenVK version 1.4.1\nApple - Apple Paravirtual device\nRender Pipeline Descriptor Validation\nNo valid pixelFormats set."
        self.assertTrue(probe.intel_mobile_candidate("macos", "x86_64", result, output))
        self.assertFalse(probe.intel_mobile_candidate("windows", "AMD64", result, output))
        self.assertFalse(probe.intel_mobile_candidate("macos", "arm64", result, output))
        for replacement in ("Apple M4", "Intel Iris Pro", "Unknown"):
            self.assertFalse(probe.intel_mobile_candidate("macos", "x86_64", result, output.replace("Apple - Apple Paravirtual device", replacement)))
        self.assertEqual(result["status"], "failed_before_backend_report")

    def test_other_primary_errors_and_late_failures_never_select_mobile(self):
        result = {"status": "failed_before_backend_report", "returncode": -6,
                  "actual_backend": None, "phase_log": []}
        output = "MoltenVK version 1.4.1\nApple - Apple Paravirtual device\nRender Pipeline Descriptor Validation\nNo valid pixelFormats set."
        for key, value in (("returncode", 124), ("status", "invalid_evidence"),
                           ("actual_backend", {"renderer": "forward_plus"}),
                           ("phase_log", ["SCENE112_GRAPHICS_STAGE=world_begin"])):
            self.assertFalse(probe.intel_mobile_candidate("macos", "x86_64", {**result, key: value}, output))
        for bad in (output + "\nERROR: shader failure", output.replace("No valid pixelFormats set.", "Unknown crash"),
                    output + "\nSCENE112_GRAPHICS_BACKEND=malformed", output + "\nSCENE112_GRAPHICS_STAGE=world_begin"):
            self.assertFalse(probe.intel_mobile_candidate("macos", "x86_64", result, bad))

    def test_mobile_quality_requires_separate_passed_actual_mobile_vulkan(self):
        failed = {"status": "failed_before_backend_report", "mobile_fallback_candidate_verified": True}
        compatibility = {"status": "passed"}
        mobile = {"requested_renderer": "mobile", "requested_driver": "vulkan",
                  "status": "passed", "actual_backend": {"renderer": "mobile", "driver": "vulkan"}}
        self.assertEqual(probe.quality_tier([failed, compatibility, mobile]), "mobile")
        self.assertEqual(failed["status"], "failed_before_backend_report")
        self.assertIsNone(probe.quality_tier([{"status": "failed_before_backend_report"}, compatibility, mobile]))
        for key, value in (("status", "invalid_evidence"), ("status", "timed_out"),
                           ("actual_backend", None), ("actual_backend", {"renderer": "gl_compatibility", "driver": "opengl3"})):
            self.assertIsNone(probe.quality_tier([failed, compatibility, {**mobile, key: value}]))
        self.assertEqual(probe.quality_tier([{"status": "passed"}, compatibility]), "forward_plus")

    def test_host_stderr_preamble_does_not_contaminate_json_stdout(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            code, output = probe.invoke(
                [
                    sys.executable,
                    "-c",
                    "import sys,json;print('Device PreExisted fixture',file=sys.stderr);print(json.dumps(dict(display=True)))",
                ],
                base,
                base / "system.txt",
                separate_stderr=True,
            )
            self.assertEqual(code, 0)
            self.assertEqual(probe.json_read(output), {"display": True})
            self.assertIn("Device PreExisted", (base / "system-stderr.txt").read_text())

    def test_host_capture_requests_separate_stderr_and_preserves_reference(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(probe, "invoke", return_value=(0, "{}")) as invoke:
                probe.capture_host(Path(directory), "macos")
            self.assertTrue(invoke.call_args.kwargs["separate_stderr"])
            self.assertEqual(
                probe.json_read((Path(directory) / "host/system.json").read_text())[
                    "stderr_file"
                ],
                "host/system-stderr.txt",
            )

    def test_actual_bounded_child_timeout_keeps_partial_output(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            code, output = probe.invoke(
                [
                    sys.executable,
                    "-c",
                    "import time;print('partial fixture',flush=True);time.sleep(5)",
                ],
                base,
                base / "process.txt",
                timeout=0.1,
            )
            self.assertEqual(code, 124)
            self.assertIn("partial fixture", output)
            self.assertIn("PROBE_TIMEOUT", output)
            stored = probe.json_read((base / "process.invoke.json").read_text())
            self.assertTrue(stored["timed_out"])
            self.assertGreater(stored["pid"], 0)

    def test_environment_override_is_child_local_and_recorded(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            with patch.dict(os.environ, {"SCENE112_FIXTURE_ENV": "parent"}):
                code, output = probe.invoke(
                    [
                        sys.executable,
                        "-c",
                        "import os;print(os.environ['SCENE112_FIXTURE_ENV'])",
                    ],
                    base,
                    base / "process.txt",
                    environment={"SCENE112_FIXTURE_ENV": "child"},
                )
                self.assertEqual(os.environ["SCENE112_FIXTURE_ENV"], "parent")
            self.assertEqual((code, output.strip()), (0, "child"))
            stored = probe.json_read((base / "process.invoke.json").read_text())
            self.assertEqual(
                stored["environment_overrides"], {"SCENE112_FIXTURE_ENV": "child"}
            )

    def test_live_sample_is_own_pid_before_kill_inside_existing_budget(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            process = MagicMock()
            process.pid = 91
            process.communicate.side_effect = [
                subprocess.TimeoutExpired("fixture", 5),
                subprocess.TimeoutExpired("fixture", 5),
                ("partial", None),
            ]
            lifecycle = MagicMock()
            lifecycle.attach_mock(process, "child")
            with (
                patch.object(probe.subprocess, "Popen") as popen,
                patch.object(probe.platform, "system", return_value="Darwin"),
                patch.object(probe, "sample_child", return_value={"pid": 91}) as sample,
            ):
                lifecycle.attach_mock(sample, "sample")
                popen.return_value.__enter__.return_value = process
                code, _ = probe.invoke(
                    ["/fixture/Scene112"],
                    base,
                    base / "process.txt",
                    timeout=10,
                    sample_own_process=True,
                )
            self.assertEqual(code, 124)
            sample.assert_called_once_with(91, base)
            names = [call[0] for call in lifecycle.mock_calls]
            self.assertLess(names.index("sample"), names.index("child.kill"))
            self.assertEqual(process.communicate.call_args_list[0].kwargs["timeout"], 5)
            self.assertLessEqual(
                process.communicate.call_args_list[1].kwargs["timeout"], 10
            )

    def test_sampling_never_targets_other_executables(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            with (
                patch.object(probe.platform, "system", return_value="Darwin"),
                patch.object(probe, "sample_child") as sample,
            ):
                code, _ = probe.invoke(
                    [sys.executable, "-c", "print('fixture')"],
                    base,
                    base / "process.txt",
                    timeout=10,
                    sample_own_process=True,
                )
            self.assertEqual(code, 0)
            sample.assert_not_called()

    def test_delayed_ips_is_linked_by_pid_not_publication_folder(self):
        text = (
            json.dumps({"app_name": "Scene112"})
            + "\n"
            + json.dumps(
                {
                    "pid": 2047,
                    "procLaunch": "2026-10-08 17:07:12.7800 +0000",
                    "captureTime": "2026-10-08 17:07:14.0917 +0000",
                }
            )
        )
        origin = probe.crash_origin(text, 3000)
        self.assertEqual(origin["origin"], "other_own_process")
        self.assertEqual(origin["reported_pid"], 2047)
        self.assertLess(origin["procLaunch_epoch"], origin["captureTime_epoch"])
        self.assertEqual(probe.crash_origin(text, 2047)["origin"], "current_process")

    def test_delayed_crash_capture_retains_original_process_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            reports = base / "Library/Logs/DiagnosticReports"
            reports.mkdir(parents=True)
            report = reports / "Scene112-delayed.ips"
            report.write_text(
                json.dumps({"app_name": "Scene112"})
                + "\n"
                + json.dumps(
                    {"pid": 2047, "procLaunch": "2026-10-08 17:07:12.7800 +0000"}
                )
            )
            output = base / "out"
            output.mkdir()
            with (
                patch.object(probe.platform, "system", return_value="Darwin"),
                patch.object(probe.Path, "home", return_value=base),
            ):
                copied = probe.capture_crashes(
                    output, time.time() - 1, expected_pid=3000
                )
            self.assertTrue(copied[0]["copied"])
            self.assertEqual(copied[0]["origin"], "other_own_process")
            self.assertEqual(copied[0]["reported_pid"], 2047)
            self.assertEqual(copied[0]["expected_pid"], 3000)

    def test_crash_origin_without_pid_never_claims_current_process(self):
        self.assertEqual(
            probe.crash_origin('{"app_name":"Scene112"}\n{}', 91)["origin"], "unknown"
        )
        self.assertEqual(
            probe.crash_origin('{"app_name":"Scene112"}\n{"pid":NaN}', 91)["origin"],
            "unknown",
        )
        self.assertEqual(
            probe.crash_origin("Process: Scene112 [91]\nfixture", 91)["origin"],
            "current_process",
        )

    def test_argument_buffer_probe_is_explicit_and_intel_only(self):
        self.assertEqual(probe.intel_probe_environment("macos", "x86_64", False), {})
        self.assertEqual(
            probe.intel_probe_environment("macos", "x86_64", True),
            {
                "MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS": "0",
                "MVK_CONFIG_USE_MTLHEAP": "0",
            },
        )
        for target, arch in (("macos", "arm64"), ("windows", "AMD64")):
            with self.assertRaises(ValueError):
                probe.intel_probe_environment(target, arch, True)

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
