"""Scenario-isolation tests. Mock process/PNG fixtures are not native evidence."""

from copy import deepcopy
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from contextlib import redirect_stdout

from test_native_gameplay_probe import HEAD, fixtures, log_for, png_bytes, probe


def scenario_log(selected, scenario):
    return ("SCENE112_GRAPHICS_BACKEND=" + json.dumps(selected["actual_backend"])
            + "\n" + probe.SCENARIOS[scenario]["marker"] + "\n"
            + "SCENE112_AUDIO_STOP driver=Dummy mixes=2 synchronized=true\n")


class ScenarioRuntime(unittest.TestCase):
    def setUp(self):
        _, _, self.selected = fixtures()
        self.data = Path(self.selected["actual_backend"]["user_data_dir"])

    def test_research_uses_its_exact_semantic_marker_and_allows_duplicate_logs(self):
        output = scenario_log(self.selected, "research")
        for text in (output, output + output):
            self.assertEqual(probe.validate_runtime(text, 0, self.selected, self.data, "research"),
                             self.selected["actual_backend"])

    def test_scenarios_cannot_substitute_for_each_other(self):
        for wanted, emitted in (("fire", "research"), ("research", "fire")):
            with self.subTest(wanted), self.assertRaises(ValueError):
                probe.validate_runtime(scenario_log(self.selected, emitted), 0,
                                       self.selected, self.data, wanted)

    def test_combined_success_markers_are_rejected_in_both_scenarios(self):
        mixed = scenario_log(self.selected, "fire") + scenario_log(self.selected, "research")
        for scenario in probe.SCENARIOS:
            with self.subTest(scenario), self.assertRaisesRegex(ValueError, "Conflicting"):
                probe.validate_runtime(mixed, 0, self.selected, self.data, scenario)

    def test_truncated_or_unanchored_research_success_is_rejected(self):
        output = scenario_log(self.selected, "research")
        for marker in ("SCENE112_RESEARCH_OK", "SCENE112_RESEARCH_OK actual fire",
                       "copied text: " + probe.SCENARIOS["research"]["marker"]):
            with self.subTest(marker), self.assertRaises(ValueError):
                probe.validate_runtime(output.replace(probe.SCENARIOS["research"]["marker"], marker),
                                       0, self.selected, self.data, "research")

    def test_research_retains_exit_audio_and_late_error_gates(self):
        output = scenario_log(self.selected, "research")
        for code, text in ((1, output), (124, output), (-6, output),
                           (0, output + "ERROR: shutdown failed"),
                           (0, output.replace("mixes=2", "mixes=1")),
                           (0, output.replace("synchronized=true", "synchronized=false")),
                           (0, output.replace("driver=Dummy", "driver=WASAPI"))):
            with self.subTest(code=code, text=text), self.assertRaises(ValueError):
                probe.validate_runtime(text, code, self.selected, self.data, "research")

    def test_research_retains_actual_backend_and_user_directory_gates(self):
        for field, value in (("display", "headless"), ("renderer", "forward_plus"),
                             ("driver", "vulkan"), ("adapter", "Other GPU"),
                             ("api", "changed"), ("user_data_dir", "/foreign")):
            changed = deepcopy(self.selected)
            changed["actual_backend"][field] = value
            with self.subTest(field), self.assertRaises(ValueError):
                probe.validate_runtime(scenario_log(changed, "research"), 0,
                                       self.selected, self.data, "research")

    def test_unknown_scenario_cannot_fall_back_to_fire(self):
        for scenario in ("", "Fire", "other", None, []):
            with self.subTest(scenario=scenario), self.assertRaises(ValueError):
                probe.validate_runtime(log_for(self.selected), 0, self.selected, self.data, scenario)


class ScenarioReplay(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="scene112-scenario-unit-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.data, self.evidence = self.root / "user", self.root / "evidence"
        self.data.mkdir()
        self.evidence.mkdir()
        _, _, self.selected = fixtures(self.data)
        self.executable = self.root / "Scene112"

    def replay(self, wanted="research", pictures="research", marker="research", symlink=False):
        def simulated_process(command, cwd, output, **kwargs):
            self.assertEqual(command[-2:], ["--", f"--{wanted}-playthrough"])
            self.assertEqual(kwargs["timeout"], 480)
            self.assertEqual(command[command.index("--rendering-driver") + 1], "opengl3")
            self.assertEqual(command[command.index("--audio-driver") + 1], "Dummy")
            self.assertEqual(command[command.index("--resolution") + 1], "1280x720")
            for name in probe.SCENARIOS[wanted]["png_names"]:
                self.assertFalse((self.data / name).exists())
                self.assertFalse((self.evidence / name).exists())
            if pictures:
                for name in probe.SCENARIOS[pictures]["png_names"]:
                    if symlink:
                        target = self.root / ("original-" + name)
                        target.write_bytes(png_bytes())
                        (self.data / name).symlink_to(target)
                    else:
                        (self.data / name).write_bytes(png_bytes())
            return 0, scenario_log(self.selected, marker)
        with patch.object(probe, "invoke", side_effect=simulated_process):
            return probe.run_playthrough(self.executable, self.evidence, self.data,
                                         self.selected, wanted)

    def test_research_cleans_own_stale_images_and_preserves_unrelated_fire_evidence(self):
        for name in probe.SCENARIOS["research"]["png_names"]:
            (self.data / name).write_bytes(b"stale research")
            (self.evidence / name).write_bytes(b"stale research")
        for name in probe.PNG_NAMES:
            (self.data / name).write_bytes(b"prior fire evidence")
            (self.evidence / name).write_bytes(b"prior fire evidence")
        (self.data / "dienst.json").write_text("player save stays")
        result = self.replay()
        self.assertEqual((result["scenario"], result["status"]), ("research", "passed"))
        self.assertEqual([p["file"] for p in result["screenshots"]],
                         list(probe.SCENARIOS["research"]["png_names"]))
        for frame in result["screenshots"]:
            self.assertEqual(frame["sha256"], hashlib.sha256((self.evidence / frame["file"]).read_bytes()).hexdigest())
        for name in probe.PNG_NAMES:
            self.assertEqual((self.data / name).read_bytes(), b"prior fire evidence")
            self.assertEqual((self.evidence / name).read_bytes(), b"prior fire evidence")
        self.assertEqual((self.data / "dienst.json").read_text(), "player save stays")

    def test_success_with_only_previous_research_frames_cannot_pass(self):
        for name in probe.SCENARIOS["research"]["png_names"]:
            (self.data / name).write_bytes(png_bytes())
        result = self.replay(pictures=None)
        self.assertEqual(result["status"], "failed")
        self.assertNotIn("screenshots", result)

    def test_fresh_frames_of_wrong_scenario_cannot_pass(self):
        for wanted, pictures in (("research", "fire"), ("fire", "research")):
            with self.subTest(wanted):
                result = self.replay(wanted=wanted, pictures=pictures, marker=wanted)
                self.assertEqual(result["status"], "failed")
                self.assertNotIn("screenshots", result)

    def test_matching_images_cannot_mask_wrong_runtime_scenario(self):
        result = self.replay(marker="fire")
        self.assertEqual(result["status"], "failed")
        self.assertNotIn("screenshots", result)

    def test_research_symlink_frames_are_not_fresh_regular_files(self):
        result = self.replay(symlink=True)
        self.assertEqual(result["status"], "failed")
        self.assertIn("regular file", result["reason"])

    def test_main_reports_are_scenario_specific_with_fire_default_preserved(self):
        archive = self.root / "native.zip"
        archive.write_bytes(b"unit archive not executable")
        build, graphics, _ = fixtures(self.data)
        build["sha256"] = graphics["archive_sha256"] = hashlib.sha256(archive.read_bytes()).hexdigest()
        build_path, graphics_path = self.root / "build.json", self.root / "graphics.json"
        build_path.write_text(json.dumps(build))
        graphics_path.write_text(json.dumps(graphics))
        for scenario, option in (("fire", []), ("fire", ["--scenario", "fire"]),
                                 ("research", ["--scenario", "research"])):
            with self.subTest(scenario=scenario, option=option):
                calls = []
                def simulate_run(executable, evidence, data, selected, requested):
                    calls.append(requested)
                    return {"scenario": requested, "status": "passed"}
                args = ["--archive", str(archive), "--provenance", str(build_path),
                        "--graphics-provenance", str(graphics_path), "--source-head", HEAD,
                        "--platform", "macos", "--output-dir", str(self.evidence), *option]
                with patch.object(probe.platform, "system", return_value="Darwin"), \
                        patch.object(probe.platform, "machine", return_value="x86_64"), \
                        patch.object(probe, "unpack_archive", return_value=self.executable), \
                        patch.object(probe, "user_directory", return_value=self.data), \
                        patch.object(probe, "run_playthrough", side_effect=simulate_run), \
                        redirect_stdout(io.StringIO()) as output:
                    code = probe.main(args)
                self.assertEqual(code, 0)
                self.assertEqual(calls, [scenario])
                report = json.loads((self.evidence / f"{scenario}-graphics-provenance.json").read_text())
                self.assertEqual(report["scenario"], scenario)
                self.assertEqual(report["result"]["scenario"], scenario)
                self.assertEqual(report["archive_sha256"], build["sha256"])
                self.assertTrue(report["gate_passed"])
                self.assertIn(f"SCENE112_NATIVE_{scenario.upper()}_OK", output.getvalue())
                self.assertIn("Case3" if scenario == "research" else "Lesson3", report["scope"])

    def test_failed_research_preflight_removes_own_success_without_touching_fire(self):
        for name in (*probe.SCENARIOS["research"]["png_names"],
                     "research-graphics-provenance.json", "result.json"):
            (self.evidence / name).write_text("old success")
        (self.evidence / probe.REPORT_NAME).write_text("preserve fire report")
        with patch.object(probe.platform, "system", return_value="Darwin"), \
                patch.object(probe, "unpack_archive") as unpack, \
                patch.object(probe, "invoke") as invoke, redirect_stdout(io.StringIO()) as output:
            code = probe.main(["--archive", str(self.root / "missing.zip"),
                               "--provenance", str(self.root / "build.json"),
                               "--graphics-provenance", str(self.root / "graphics.json"),
                               "--source-head", HEAD, "--platform", "macos",
                               "--output-dir", str(self.evidence), "--scenario", "research"])
        self.assertEqual(code, 1)
        unpack.assert_not_called()
        invoke.assert_not_called()
        report = json.loads((self.evidence / "research-graphics-provenance.json").read_text())
        self.assertEqual(report["scenario"], "research")
        self.assertFalse(report["gate_passed"])
        self.assertFalse((self.evidence / "result.json").exists())
        self.assertEqual((self.evidence / probe.REPORT_NAME).read_text(), "preserve fire report")
        self.assertTrue(all(not (self.evidence / name).exists()
                            for name in probe.SCENARIOS["research"]["png_names"]))
        self.assertIn("SCENE112_NATIVE_RESEARCH_FAILED", output.getvalue())


if __name__ == "__main__":
    unittest.main()
