"""Contract/adversarial tests for the gate; fixtures are not native-play evidence."""

from copy import deepcopy
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile
import zlib

TOOLS = Path(__file__).parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
SPEC = importlib.util.spec_from_file_location("native_gameplay_probe", TOOLS / "probe_native_gameplay.py")
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)
HEAD = "a" * 40
DIGEST = "b" * 64


def fixtures(data_dir=Path("/tmp/native-fire-unit-fixture")):
    backend = {"display": "macOS", "renderer": "gl_compatibility", "driver": "opengl3",
               "adapter": "Apple Software Renderer (unit fixture)", "api": "4.1",
               "vendor": "Apple Inc.", "adapter_type": 0, "user_data_dir": str(data_dir)}
    build = {"source_head": HEAD, "sha256": DIGEST}
    graphics = {"source_head": HEAD, "archive_sha256": DIGEST, "platform": "macos",
                "runner_architecture": "x86_64", "gate_passed": True,
                "required_compatibility_passed": True, "validated_quality_tier": "gl_compatibility",
                "results": [{"requested_renderer": "forward_plus", "requested_driver": "vulkan",
                             "status": "failed_before_backend_report", "returncode": -6},
                            {"requested_renderer": "gl_compatibility", "requested_driver": "opengl3",
                             "status": "passed", "returncode": 0, "actual_backend": backend,
                             "invocation": {"environment_overrides": {}}}]}
    selected = {"renderer": "gl_compatibility", "driver": "opengl3",
                "actual_backend": backend, "environment": {}}
    return build, graphics, selected


def log_for(selected):
    return ("SCENE112_GRAPHICS_BACKEND=" + json.dumps(selected["actual_backend"])
            + "\nSCENE112_FIRE_OK actual lesson3 and campaignCase2; unit-test fixture only\n"
            + "SCENE112_AUDIO_STOP driver=Dummy mixes=2 synchronized=true\n")


def png_bytes(width=1280, height=720):
    def chunk(name, payload):
        return (struct.pack(">I", len(payload)) + name + payload
                + struct.pack(">I", zlib.crc32(name + payload)))
    row = b"\0" + (bytes(range(256)) * ((width * 3 + 255) // 256))[:width * 3]
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(row * height)) + chunk(b"IEND", b""))


class Selection(unittest.TestCase):
    def setUp(self):
        self.build, self.graphics, self.selected = fixtures()

    def select(self):
        return probe.select_backend(self.build, self.graphics, HEAD, DIGEST, "macos", "x86_64")

    def test_explicit_passed_quality_preserves_failed_research(self):
        before = deepcopy(self.graphics)
        self.assertEqual(self.select(), self.selected)
        self.assertEqual(self.graphics, before)

    def test_all_supported_proven_tiers_and_driver_are_replayed(self):
        for tier, driver, target, arch in (("forward_plus", "metal", "macos", "arm64"),
                                         ("forward_plus", "d3d12", "windows", "AMD64"),
                                         ("mobile", "vulkan", "macos", "x86_64"),
                                         ("gl_compatibility", "opengl3_angle", "windows", "x86_64")):
            with self.subTest((tier, driver)):
                build, graphics, selected = fixtures()
                passed = graphics["results"][1]
                graphics.update(platform=target, runner_architecture=arch, validated_quality_tier=tier,
                                results=[passed])
                passed.update(requested_renderer=tier, requested_driver=driver)
                passed["actual_backend"].update(renderer=tier, driver=driver,
                                                 display="macOS" if target == "macos" else "Windows")
                if tier == "mobile":
                    passed["invocation"]["environment_overrides"] = probe.ALLOWED_ENVIRONMENT.copy()
                actual = probe.select_backend(build, graphics, HEAD, DIGEST, target, arch)
                self.assertEqual((actual["renderer"], actual["driver"]), (tier, driver))
                self.assertEqual(actual["environment"], passed["invocation"]["environment_overrides"])

    def test_stale_source_or_archive_on_either_proof_is_rejected(self):
        for part, field in (("build", "source_head"), ("build", "sha256"),
                            ("graphics", "source_head"), ("graphics", "archive_sha256")):
            self.setUp()
            getattr(self, part)[field] = "stale"
            with self.subTest((part, field)), self.assertRaises(ValueError):
                self.select()

    def test_actual_target_and_architecture_must_match(self):
        for field, value in (("platform", "windows"), ("runner_architecture", "arm64"),
                             ("runner_architecture", None), ("runner_architecture", "unknown")):
            self.setUp()
            self.graphics[field] = value
            with self.subTest((field, value)), self.assertRaises(ValueError):
                self.select()
        self.graphics["runner_architecture"] = "AMD64"
        self.assertEqual(self.select()["driver"], "opengl3")

    def test_failed_gate_and_unknown_quality_cannot_borrow_a_green_result(self):
        for field, value in (("gate_passed", False), ("gate_passed", 1),
                             ("required_compatibility_passed", False),
                             ("validated_quality_tier", None), ("validated_quality_tier", "invented")):
            self.setUp()
            self.graphics[field] = value
            with self.subTest((field, value)), self.assertRaises(ValueError):
                self.select()

    def test_failed_or_ambiguous_selected_tier_is_fatal(self):
        for status in ("clean_angle_fallback_detected", "environment_unavailable", "timed_out", "failed"):
            self.setUp()
            self.graphics["results"][1]["status"] = status
            with self.subTest(status), self.assertRaises(ValueError):
                self.select()
        self.setUp()
        self.graphics["results"].append(deepcopy(self.graphics["results"][1]))
        with self.assertRaises(ValueError):
            self.select()

    def test_zero_code_is_strict_and_backend_cannot_silently_fallback(self):
        for code in (1, -6, 124, False):
            self.setUp()
            self.graphics["results"][1]["returncode"] = code
            with self.subTest(code), self.assertRaises(ValueError):
                self.select()
        for field, value in (("display", "headless"), ("driver", "opengl3_angle"),
                             ("renderer", "mobile"), ("adapter", "")):
            self.setUp()
            self.graphics["results"][1]["actual_backend"][field] = value
            with self.subTest((field, value)), self.assertRaises(ValueError):
                self.select()

    def test_untrusted_environment_is_not_applied(self):
        for environment in ({"DYLD_INSERT_LIBRARIES": "/foreign"},
                            {"MVK_CONFIG_USE_MTLHEAP": "1"}, [],
                            probe.ALLOWED_ENVIRONMENT.copy()):
            self.setUp()
            self.graphics["results"][1]["invocation"]["environment_overrides"] = environment
            with self.subTest(environment), self.assertRaises(ValueError):
                self.select()

    def test_malformed_result_containers_and_nonobject_backend_are_rejected(self):
        for results in ({}, [None], [], "passed"):
            self.setUp()
            self.graphics["results"] = results
            with self.subTest(results), self.assertRaises(ValueError):
                self.select()
        self.setUp()
        self.graphics["results"][1]["actual_backend"] = []
        with self.assertRaises(ValueError):
            self.select()


class Runtime(unittest.TestCase):
    def setUp(self):
        _, _, self.selected = fixtures()
        self.data = Path(self.selected["actual_backend"]["user_data_dir"])
        self.output = log_for(self.selected)

    def test_complete_and_duplicate_consistent_logs_pass(self):
        for output in (self.output, self.output + self.output):
            self.assertEqual(probe.validate_runtime(output, 0, self.selected, self.data),
                             self.selected["actual_backend"])

    def test_late_engine_script_shader_and_cleanup_errors_are_fatal(self):
        for error in ("ERROR: leak", "SCRIPT ERROR: bug", "ERROR: shader compilation failed"):
            with self.subTest(error), self.assertRaises(ValueError):
                probe.validate_runtime(self.output + error, 0, self.selected, self.data)

    def test_nonzero_exit_even_after_success_is_fatal(self):
        for code in (1, 124, 126, -6):
            with self.subTest(code), self.assertRaises(ValueError):
                probe.validate_runtime(self.output, code, self.selected, self.data)

    def test_missing_gameplay_or_audio_marker_is_fatal(self):
        for prefix in ("SCENE112_FIRE_OK", "SCENE112_AUDIO_STOP", "SCENE112_GRAPHICS_BACKEND="):
            output = "\n".join(line for line in self.output.splitlines() if not line.startswith(prefix))
            with self.subTest(prefix), self.assertRaises(ValueError):
                probe.validate_runtime(output, 0, self.selected, self.data)

    def test_one_mix_unsynchronized_or_other_driver_cannot_pass(self):
        for replacement in ("mixes=1 synchronized=true", "mixes=2 synchronized=false", "mixes=0 synchronized=false"):
            output = self.output.replace("mixes=2 synchronized=true", replacement)
            with self.subTest(replacement), self.assertRaises(ValueError):
                probe.validate_runtime(output, 0, self.selected, self.data)
        with self.assertRaises(ValueError):
            probe.validate_runtime(self.output.replace("driver=Dummy", "driver=WASAPI"), 0, self.selected, self.data)
        with self.assertRaises(ValueError):
            probe.validate_runtime(self.output + "SCENE112_AUDIO_STOP driver=Dummy mixes=1 synchronized=false\n",
                                   0, self.selected, self.data)

    def test_changed_actual_backend_and_conflicting_markers_are_rejected(self):
        for field, value in (("display", "headless"), ("renderer", "mobile"),
                             ("driver", "vulkan"), ("adapter", "different GPU"), ("api", "3.0")):
            other = deepcopy(self.selected)
            other["actual_backend"][field] = value
            with self.subTest(field), self.assertRaises(ValueError):
                probe.validate_runtime(log_for(other), 0, self.selected, self.data)
            with self.subTest("conflict " + field), self.assertRaises(ValueError):
                probe.validate_runtime(self.output + log_for(other), 0, self.selected, self.data)

    def test_foreign_actual_and_proven_user_directories_are_rejected(self):
        with self.assertRaises(ValueError):
            probe.validate_runtime(self.output, 0, self.selected, self.data / "wrong")
        other = deepcopy(self.selected)
        other["actual_backend"]["user_data_dir"] = str(self.data / "foreign")
        with self.assertRaises(ValueError):
            probe.validate_runtime(log_for(other), 0, self.selected, self.data)


class Replay(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="scene112-fire-probe-unit-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.data, self.evidence = self.root / "user", self.root / "evidence"
        self.data.mkdir()
        self.evidence.mkdir()
        _, _, self.selected = fixtures(self.data)
        self.executable = self.root / "Scene112"

    def replay(self, pictures=True, dimensions=(1280, 720), late_error=False):
        def simulated_process(command, cwd, log, **kwargs):
            self.assertEqual(kwargs["timeout"], 480)
            self.assertEqual(command[-1], "--fire-playthrough")
            self.assertEqual(command[command.index("--rendering-driver") + 1], "opengl3")
            self.assertEqual(command[command.index("--audio-driver") + 1], "Dummy")
            self.assertEqual(command[command.index("--resolution") + 1], "1280x720")
            self.assertEqual(kwargs["environment"], {})
            for name in probe.PNG_NAMES:
                self.assertFalse((self.data / name).exists())
                self.assertFalse((self.evidence / name).exists())
                if pictures:
                    (self.data / name).write_bytes(png_bytes(*dimensions))
            if late_error:
                (self.evidence / "engine.txt").write_text("ERROR: post-success cleanup failure\n")
            return 0, log_for(self.selected)
        with patch.object(probe, "invoke", side_effect=simulated_process):
            return probe.run_playthrough(self.executable, self.evidence, self.data, self.selected)

    def test_replay_removes_stale_files_and_hashes_three_new_images(self):
        for name in probe.PNG_NAMES:
            (self.data / name).write_bytes(b"stale")
            (self.evidence / name).write_bytes(b"stale")
        unrelated = self.data / "save.json"
        unrelated.write_text("preserve")
        result = self.replay()
        self.assertEqual(result["status"], "passed")
        self.assertFalse(result["physical_target_gpu_acceptance"])
        self.assertEqual([p["file"] for p in result["screenshots"]], list(probe.PNG_NAMES))
        for picture in result["screenshots"]:
            self.assertEqual(picture["sha256"], hashlib.sha256((self.evidence / picture["file"]).read_bytes()).hexdigest())
        self.assertEqual(unrelated.read_text(), "preserve")

    def test_success_marker_cannot_reuse_stale_or_missing_screenshots(self):
        for name in probe.PNG_NAMES:
            (self.data / name).write_bytes(png_bytes())
        result = self.replay(pictures=False)
        self.assertEqual(result["status"], "failed")
        self.assertNotIn("screenshots", result)

    def test_exact_dimensions_are_required(self):
        result = self.replay(dimensions=(1280, 721))
        self.assertEqual(result["status"], "failed")
        self.assertIn("1280x720", result["reason"])

    def test_error_only_in_engine_log_remains_fatal(self):
        result = self.replay(late_error=True)
        self.assertEqual(result["status"], "failed")
        self.assertIn("error", result["reason"])

    def test_main_refuses_red_graphics_before_unpack_or_runtime(self):
        archive = self.root / "native.zip"
        archive.write_bytes(b"fixture archive cannot run")
        build, graphics, _ = fixtures(self.data)
        build["sha256"] = graphics["archive_sha256"] = hashlib.sha256(archive.read_bytes()).hexdigest()
        graphics["gate_passed"] = False
        for filename in (*probe.PNG_NAMES, "result.json", probe.REPORT_NAME):
            (self.evidence / filename).write_text("stale passed evidence")
        build_path, graphics_path = self.root / "build.json", self.root / "graphics.json"
        build_path.write_text(json.dumps(build))
        graphics_path.write_text(json.dumps(graphics))
        with patch.object(probe.platform, "system", return_value="Darwin"), \
                patch.object(probe.platform, "machine", return_value="x86_64"), \
                patch.object(probe, "unpack_archive") as unpack, patch.object(probe, "invoke") as invoke:
            code = probe.main(["--archive", str(archive), "--provenance", str(build_path),
                               "--graphics-provenance", str(graphics_path), "--source-head", HEAD,
                               "--platform", "macos", "--output-dir", str(self.evidence)])
        self.assertEqual(code, 1)
        unpack.assert_not_called()
        invoke.assert_not_called()
        self.assertIs(json.loads((self.evidence / probe.REPORT_NAME).read_text())["gate_passed"], False)
        self.assertFalse((self.evidence / "result.json").exists())
        self.assertTrue(all(not (self.evidence / name).exists() for name in probe.PNG_NAMES))


class Unpacking(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="scene112-unpack-unit-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.staging = self.root / "fresh"
        self.staging.mkdir()
        self.archive = self.root / "fixture.zip"

    def archive_with(self, name):
        with zipfile.ZipFile(self.archive, "w") as zipped:
            zipped.writestr(name, b"unit fixture, not executable")

    def test_windows_unpacks_only_from_actual_archive(self):
        self.archive_with("Scene112.exe")
        result = probe.unpack_archive(self.archive, self.staging, "windows")
        self.assertEqual(result, self.staging / "Scene112.exe")

    def test_zip_traversal_both_platform_spellings_rejected(self):
        for name in ("../escape", "..\\escape", "/absolute", "C:/absolute", "C:relative", "\\\\server\\share\\file"):
            self.archive_with(name)
            with self.subTest(name), self.assertRaises(ValueError):
                probe.unpack_archive(self.archive, self.staging, "windows")

    def test_missing_executable_rejected(self):
        self.archive_with("other.exe")
        with self.assertRaises(ValueError):
            probe.unpack_archive(self.archive, self.staging, "windows")

    def prepare_bundle(self):
        app = self.staging / "Scene112.app"
        (app / "Contents/MacOS").mkdir(parents=True)
        (app / "Contents/MacOS/Scene112").write_bytes(b"unit fixture")
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "Scene112"}))
        return app

    def test_mac_strict_signature_verified_before_executable_selection(self):
        self.archive_with("placeholder")
        self.prepare_bundle()
        with patch.object(probe.subprocess, "run") as run:
            executable = probe.unpack_archive(self.archive, self.staging, "macos")
        self.assertEqual(executable.name, "Scene112")
        self.assertEqual(run.call_count, 2)
        self.assertEqual(run.call_args_list[1].args[0][:4], ["codesign", "--verify", "--deep", "--strict"])
        self.assertEqual(run.call_args_list[1].kwargs, {"check": True, "timeout": 60})

    def test_failed_mac_signature_is_fatal(self):
        self.archive_with("placeholder")
        self.prepare_bundle()
        with patch.object(probe.subprocess, "run", side_effect=[None, subprocess.CalledProcessError(1, "codesign")]):
            with self.assertRaises(subprocess.CalledProcessError):
                probe.unpack_archive(self.archive, self.staging, "macos")


if __name__ == "__main__":
    unittest.main()
