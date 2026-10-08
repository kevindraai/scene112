"""Tool classification tests, not fabricated native gameplay evidence."""
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

script = Path(__file__).parents[1] / "tools/probe_native_graphics.py"
spec = importlib.util.spec_from_file_location("graphics_probe", script)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

BACKEND = {"display": "macos", "renderer": "forward_plus", "driver": "metal",
           "adapter": "Apple virtual example (fixture)", "api": "Metal 3", "user_data_dir": "/tmp/probe-user"}
OK = probe.BACKEND_PREFIX + json.dumps(BACKEND) + "\nSCENE112_VISUAL_OK checks=90"
REPORT = {"display": "macos", "renderer": "forward_plus", "driver": "metal", "checks": 90,
          "walk_metres": 10.2, "drive_metres": 22.0, "engine": {"major": 4, "minor": 7, "patch": 2},
          "conditions": [{"conditions": name} for name in ("day", "dusk", "rain")]}


class Classification(unittest.TestCase):
    def test_success_requires_actual_matching_backend(self):
        self.assertEqual(probe.classify(OK, 0, probe.backend_from_log(OK), "forward_plus", "metal"), "passed")
        self.assertEqual(probe.classify(OK, 0, BACKEND, "forward_plus", "d3d12"), "requested_backend_not_used")

    def test_automatic_compatibility_fallback_is_not_forward_plus_success(self):
        fallback = dict(BACKEND, renderer="gl_compatibility", driver="opengl3")
        self.assertEqual(probe.classify(OK, 0, fallback, "forward_plus", "metal"), "requested_backend_not_used")

    def test_only_explicit_pre_backend_init_errors_are_unavailable(self):
        output = "ERROR: No Metal devices found.\nERROR: Could not initialize Metal context."
        self.assertEqual(probe.classify(output, 1, None, "forward_plus", "metal"), "environment_unavailable")
        self.assertEqual(probe.classify(output, 1, BACKEND, "forward_plus", "metal"), "failed_after_backend_initialization")

    def test_startup_shader_and_dependency_errors_are_fatal(self):
        for detail in ("SCRIPT ERROR: Parse failed", "ERROR: Failed to load libEGL.dll", "ERROR: Shader compilation failed", "ERROR: Unknown graphics failure"):
            self.assertEqual(probe.classify(detail, 1, None, "forward_plus", "metal"), "failed_before_backend_report")

    def test_late_gc_and_gameplay_errors_cannot_be_waived(self):
        for detail in ("ERROR: 6 resources still in use at exit", "ERROR: VISUAL missing imported model"):
            self.assertEqual(probe.classify(OK + "\n" + detail, 0, BACKEND, "forward_plus", "metal"), "failed_after_backend_initialization")

    def test_timeout_and_no_window_are_not_graphical_evidence(self):
        self.assertEqual(probe.classify("ERROR: No Metal devices found.", 124, None, "forward_plus", "metal"), "timed_out")
        self.assertEqual(probe.classify(OK, 0, dict(BACKEND, display="headless"), "forward_plus", "metal"), "invalid_headless_evidence")

    def test_missing_gameplay_marker_cannot_pass_on_init_alone(self):
        self.assertEqual(probe.classify("", 0, BACKEND, "forward_plus", "metal"), "failed_after_backend_initialization")

    def test_duplicate_logs_must_report_consistent_actual_backends(self):
        self.assertEqual(probe.backend_from_log(OK + "\n" + OK), BACKEND)
        with self.assertRaises(ValueError):
            probe.backend_from_log(OK + "\n" + probe.BACKEND_PREFIX + json.dumps(dict(BACKEND, driver="vulkan")))

    def test_nan_marker_cannot_enter_provenance(self):
        with self.assertRaises(ValueError):
            probe.backend_from_log(probe.BACKEND_PREFIX + '{"adapter_type":NaN}')

    def test_real_distance_conditions_and_engine_are_required(self):
        probe.require_gameplay_report(REPORT, BACKEND)
        for mutation in ({"walk_metres": 0.0}, {"drive_metres": 20.0}, {"walk_metres": float("nan")},
                         {"checks": True}, {"conditions": []}, {"display": "headless"}, {"driver": "vulkan"}):
            report = deepcopy(REPORT)
            report.update(mutation)
            with self.assertRaises(ValueError):
                probe.require_gameplay_report(report, BACKEND)

    def test_missing_or_placeholder_png_cannot_count_as_rendered_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "capture.png"
            path.write_bytes(b"not rendered" * 100)
            with self.assertRaises(ValueError):
                probe.check_png(path)


if __name__ == "__main__":
    unittest.main()
