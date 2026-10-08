"""Synthetic classification/evidence parser fixtures; never native gameplay proof."""

import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "angle_probe", Path(__file__).parents[1] / "tools/probe_native_graphics.py"
)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
BACKEND = {
    "display": "windows",
    "renderer": "gl_compatibility",
    "driver": "opengl3_angle",
    "adapter": "Microsoft WARP (unit fixture)",
    "adapter_type": 4,
    "api": "GLES 3.0",
    "user_data_dir": "/tmp/unit",
}
OK = "SCENE112_VISUAL_OK checks=90"


class AngleClassification(unittest.TestCase):
    def classify(
        self,
        output=OK,
        code=0,
        backend=None,
        renderer="gl_compatibility",
        driver="opengl3",
        allow=True,
    ):
        return probe.classify(
            output,
            code,
            BACKEND if backend is None else backend,
            renderer,
            driver,
            allow,
        )

    def test_clean_automatic_angle_is_detected_without_native_opengl_pass(self):
        self.assertEqual(self.classify(), "clean_angle_fallback_detected")
        self.assertEqual(self.classify(allow=False), "requested_backend_not_used")

    def test_fallback_late_errors_or_nonzero_exit_cannot_qualify(self):
        for error in (
            "ERROR: resources still in use at exit",
            "SCRIPT ERROR: failed",
            "ERROR: Shader compilation failed",
        ):
            self.assertEqual(
                self.classify(OK + "\n" + error), "failed_after_backend_initialization"
            )
        self.assertEqual(self.classify(code=1), "failed_after_backend_initialization")

    def test_partial_gameplay_headless_timeout_do_not_qualify(self):
        self.assertEqual(
            self.classify(output="initialized"), "failed_after_backend_initialization"
        )
        self.assertEqual(
            self.classify(backend=dict(BACKEND, display="headless")),
            "invalid_headless_evidence",
        )
        self.assertEqual(self.classify(code=124), "timed_out")

    def test_primary_forward_plus_fallback_remains_fatal(self):
        self.assertEqual(
            self.classify(renderer="forward_plus", driver="d3d12"),
            "requested_backend_not_used",
        )

    def test_explicit_angle_must_match_actual_angle(self):
        self.assertEqual(self.classify(driver="opengl3_angle"), "passed")
        self.assertEqual(
            self.classify(
                driver="opengl3_angle", backend=dict(BACKEND, driver="opengl3")
            ),
            "requested_backend_not_used",
        )

    def test_gate_requires_separate_exact_angle_replay(self):
        primary = {"status": "passed"}
        detected = {"status": "clean_angle_fallback_detected"}
        exact = {
            "status": "passed",
            "requested_renderer": "gl_compatibility",
            "requested_driver": "opengl3_angle",
        }
        self.assertFalse(probe.compatibility_passed([primary, detected], "windows"))
        self.assertTrue(
            probe.compatibility_passed([primary, detected, exact], "windows")
        )
        self.assertFalse(
            probe.compatibility_passed([primary, detected, exact], "macos")
        )

    def test_second_replay_cannot_redeem_first_functional_failure(self):
        exact = {
            "status": "passed",
            "requested_renderer": "gl_compatibility",
            "requested_driver": "opengl3_angle",
        }
        self.assertFalse(
            probe.compatibility_passed(
                [{}, {"status": "failed_after_backend_initialization"}, exact],
                "windows",
            )
        )
        self.assertFalse(
            probe.compatibility_passed(
                [
                    {},
                    {"status": "clean_angle_fallback_detected"},
                    dict(exact, status="invalid_evidence"),
                ],
                "windows",
            )
        )

    def test_missing_fourth_png_rejects_clean_fallback(self):
        result = self.run_profile(missing=probe.PNG_NAMES[-1])
        self.assertEqual(result["status"], "invalid_evidence")

    def test_fresh_full_evidence_keeps_fallback_label_and_cpu_scope(self):
        result = self.run_profile()
        self.assertEqual(result["status"], "clean_angle_fallback_detected")
        self.assertEqual(len(result["screenshots"]), 4)
        self.assertTrue(result["software_adapter_detected"])
        self.assertFalse(result["physical_target_gpu_acceptance"])

    def run_profile(self, missing=None):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            data = base / "user"
            data.mkdir()
            backend = dict(BACKEND, user_data_dir=str(data.resolve()))
            report = {
                "display": backend["display"],
                "renderer": backend["renderer"],
                "driver": backend["driver"],
                "walk_metres": 10.3,
                "drive_metres": 22.0,
                "checks": 90,
                "conditions": [
                    {"conditions": item} for item in ("day", "dusk", "rain")
                ],
                "engine": {"major": 4, "minor": 7, "patch": 2},
            }

            def fake_invoke(command, cwd, log, timeout=240):
                (data / "visual-runtime.json").write_text(json.dumps(report))
                for name in probe.PNG_NAMES:
                    if name == missing:
                        continue
                    (data / name).write_bytes(
                        b"\x89PNG\r\n\x1a\n"
                        + struct.pack(">I", 13)
                        + b"IHDR"
                        + struct.pack(">II", 1280, 720)
                        + b"fixture" * 200
                    )
                return 0, probe.BACKEND_PREFIX + json.dumps(backend) + "\n" + OK

            with patch.object(probe, "invoke", side_effect=fake_invoke):
                return probe.profile(
                    base / "Scene112.exe",
                    base / "out",
                    data,
                    "gl_compatibility",
                    "opengl3",
                    True,
                )


if __name__ == "__main__":
    unittest.main()
