#!/usr/bin/env python3
"""Replay fire or research from the exact archive on its proven native backend."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import platform
import plistlib
import re
import shutil
import stat
import subprocess
import tempfile
import time
import zipfile

from probe_native_graphics import (
    backend_from_log,
    check_png,
    implementation_details,
    invoke,
    json_read,
    json_write,
    user_directory,
)

SCENARIOS = {
    "fire": {
        "png_names": ("fire-active.png", "fire-rescue.png", "fire-completed.png"),
        "marker": "SCENE112_FIRE_OK actual lesson3 and campaignCase2;",
        "scope": "Exact standalone graphical Lesson3 and Campaign Case2 replay; explicit travel/aim fixtures with actual input, collisions, local fire, rescue, pause and save.",
    },
    "research": {
        "png_names": ("research-scene.png", "research-interview.png", "research-completed.png"),
        "marker": "SCENE112_RESEARCH_OK actual F/E spatial evidence; two witnesses/contradiction; delayed expert; source board; wrong/incomplete/corrected report; draft/save/archive",
        "scope": "Exact standalone graphical Campaign Case3 replay; completed M3 and travel/aim entry fixtures; actual spatial evidence input, two witnesses, contradiction, observed expert delay, board/report correction, draft/save/archive.",
    },
}
# Keep the M3 default contract; explicit research uses its own names throughout.
PNG_NAMES = SCENARIOS["fire"]["png_names"]
REPORT_NAME = "fire-graphics-provenance.json"
TIMEOUT = 480
ALLOWED_ENVIRONMENT = {
    "MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS": "0",
    "MVK_CONFIG_USE_MTLHEAP": "0",
}


def scenario_definition(scenario: str) -> dict:
    if not isinstance(scenario, str) or scenario not in SCENARIOS:
        raise ValueError("Unknown native gameplay scenario")
    return SCENARIOS[scenario]


def normalized_architecture(value: str) -> str:
    if not isinstance(value, str):
        raise ValueError("Missing native runner architecture")
    aliases = {"amd64": "x86_64", "aarch64": "arm64"}
    value = aliases.get(value.lower(), value.lower())
    if value not in ("x86_64", "arm64"):
        raise ValueError("Unsupported native runner architecture")
    return value


def select_backend(build: dict, graphics: dict, head: str, digest: str,
                   target: str, architecture: str) -> dict:
    """Refuse stale/different artifacts, failed research and implicit fallback."""
    if not isinstance(build, dict) or not isinstance(graphics, dict):
        raise ValueError("Provenance must be an object")
    if not re.fullmatch(r"[0-9a-f]{40}", head):
        raise ValueError("Expected exact Git source head")
    if (build.get("source_head") != head or build.get("sha256") != digest
            or graphics.get("source_head") != head
            or graphics.get("archive_sha256") != digest):
        raise ValueError("Exact source-head/archive provenance mismatch")
    if (graphics.get("platform") != target
            or normalized_architecture(graphics.get("runner_architecture"))
            != normalized_architecture(architecture)):
        raise ValueError("Graphics proof belongs to a different native runner")
    if (graphics.get("gate_passed") is not True
            or graphics.get("required_compatibility_passed") is not True):
        raise ValueError("Prior native graphics gate did not pass")
    tier = graphics.get("validated_quality_tier")
    if tier not in ("forward_plus", "mobile", "gl_compatibility"):
        raise ValueError("No proven selected graphics quality tier")
    results = graphics.get("results")
    if not isinstance(results, list) or any(not isinstance(r, dict) for r in results):
        raise ValueError("Malformed native graphics results")
    matches = [r for r in results if r.get("requested_renderer") == tier
               and r.get("status") == "passed"]
    if len(matches) != 1:
        raise ValueError("Expected one passed result for the selected quality tier")
    selected = matches[0]
    if type(selected.get("returncode")) is not int or selected["returncode"] != 0:
        raise ValueError("Selected graphics process did not exit cleanly")
    actual = selected.get("actual_backend")
    fields = ("display", "renderer", "driver", "adapter", "api", "user_data_dir")
    if not isinstance(actual, dict) or any(
            not isinstance(actual.get(k), str) or not actual[k] for k in fields):
        raise ValueError("Incomplete proven native backend")
    if actual["display"].lower() != {"macos": "macos", "windows": "windows"}[target]:
        raise ValueError("Proven backend is not the target native display")
    allowed_drivers = {
        "forward_plus": ("metal", "vulkan", "d3d12"),
        "mobile": ("metal", "vulkan", "d3d12"),
        "gl_compatibility": ("opengl3", "opengl3_es", "opengl3_angle"),
    }
    requested = selected.get("requested_driver")
    if (actual["renderer"] != tier or actual["driver"] not in allowed_drivers[tier]
            or not (actual["driver"] == requested
                    or (requested == "opengl3" and actual["driver"] == "opengl3_es"))):
        raise ValueError("Actual selected backend differs from its requested proof")
    invocation = selected.get("invocation", {})
    if not isinstance(invocation, dict):
        raise ValueError("Malformed selected invocation")
    environment = invocation.get("environment_overrides", {})
    if not isinstance(environment, dict) or any(
            key not in ALLOWED_ENVIRONMENT or value != ALLOWED_ENVIRONMENT[key]
            for key, value in environment.items()):
        raise ValueError("Unsupported selected backend environment")
    if environment and not (target == "macos"
                            and normalized_architecture(architecture) == "x86_64"
                            and actual["driver"] == "vulkan"):
        raise ValueError("MoltenVK environment is limited to proven Intel Vulkan")
    return {"renderer": tier, "driver": actual["driver"],
            "actual_backend": actual.copy(), "environment": environment.copy()}


def validate_runtime(output: str, code: int, selected: dict,
                     data_dir: Path, scenario: str = "fire") -> dict:
    definition = scenario_definition(scenario)
    if code != 0:
        raise ValueError(f"Actual {scenario} gameplay process failed (exit {code})")
    if "ERROR:" in output:
        raise ValueError(f"Actual {scenario} gameplay logged an engine/script/runtime error")
    backend = backend_from_log(output)
    if backend is None:
        raise ValueError("Missing actual graphical backend marker")
    previous = selected["actual_backend"]
    for key in ("display", "renderer", "driver", "adapter", "api", "vendor", "adapter_type"):
        if backend.get(key) != previous.get(key):
            raise ValueError("Gameplay backend differs from proven graphics: " + key)
    if backend["display"].lower() == "headless":
        raise ValueError("Headless execution is not native graphical evidence")
    if (Path(backend["user_data_dir"]).resolve() != data_dir.resolve()
            or Path(previous["user_data_dir"]).resolve() != data_dir.resolve()):
        raise ValueError("Unexpected runtime user directory")
    lines = output.splitlines()
    if not any(line.startswith(definition["marker"]) for line in lines):
        raise ValueError(f"Missing successful actual {scenario} gameplay")
    for other in SCENARIOS:
        if other != scenario and any(line.startswith(f"SCENE112_{other.upper()}_OK")
                                     for line in lines):
            raise ValueError("Conflicting gameplay scenario success marker")
    stops = [line for line in lines if line.startswith("SCENE112_AUDIO_STOP")]
    if not stops:
        raise ValueError("Missing synchronized audio shutdown")
    for line in stops:
        match = re.fullmatch(r"SCENE112_AUDIO_STOP driver=Dummy mixes=(\d+) synchronized=true", line)
        if match is None or int(match[1]) < 2:
            raise ValueError("Audio shutdown did not observe two real mixes")
    return backend


def validate_archive_paths(archive: zipfile.ZipFile, staging: Path,
                           target: str) -> None:
    for item in archive.infolist():
        posix, windows = PurePosixPath(item.filename), PureWindowsPath(item.filename)
        if (posix.is_absolute() or windows.is_absolute() or windows.drive
                or ".." in posix.parts or ".." in windows.parts
                or not (staging / item.filename).resolve().is_relative_to(staging.resolve())):
            raise ValueError("Unsafe native archive path")
        if target == "windows" and stat.S_ISLNK(item.external_attr >> 16):
            raise ValueError("Unexpected Windows archive symlink")


def unpack_archive(archive_path: Path, staging: Path, target: str) -> Path:
    with zipfile.ZipFile(archive_path) as archive:
        validate_archive_paths(archive, staging, target)
        if target == "windows":
            archive.extractall(staging)
    if target == "macos":
        subprocess.run(["ditto", "-xk", str(archive_path.resolve()), str(staging)],
                       check=True, timeout=60)
        apps = list(staging.glob("*.app"))
        if len(apps) != 1:
            raise ValueError("Expected exactly one native application bundle")
        app = apps[0]
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)],
                       check=True, timeout=60)
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        name = info.get("CFBundleExecutable")
        if not isinstance(name, str) or not name or Path(name).name != name:
            raise ValueError("Invalid native bundle executable")
        executable = app / "Contents/MacOS" / name
    else:
        executable = staging / "Scene112.exe"
    if not executable.is_file() or not executable.resolve().is_relative_to(staging.resolve()):
        raise ValueError("Missing standalone executable in fresh archive")
    return executable.resolve()


def run_playthrough(executable: Path, evidence: Path, data_dir: Path,
                    selected: dict, scenario: str = "fire") -> dict:
    definition = scenario_definition(scenario)
    png_names = definition["png_names"]
    evidence.mkdir(parents=True, exist_ok=True)
    # Only this validation's known artifacts are removed. Images from an earlier
    # graphics profile or same/other-scenario run cannot satisfy the fresh replay.
    for filename in png_names:
        (data_dir / filename).unlink(missing_ok=True)
        (evidence / filename).unlink(missing_ok=True)
    engine_log = (evidence / "engine.txt").resolve()
    engine_log.unlink(missing_ok=True)
    command = [str(executable), "--verbose", "--log-file", str(engine_log),
               "--windowed", "--resolution", "1280x720", "--rendering-method",
               selected["renderer"], "--rendering-driver", selected["driver"],
               "--audio-driver", "Dummy", "--", f"--{scenario}-playthrough"]
    started = time.monotonic()
    code, output = invoke(command, executable.parent, evidence / "process.txt",
                          timeout=TIMEOUT, sample_own_process=platform.system() == "Darwin",
                          environment=selected["environment"])
    invocation_path = evidence / "process.invoke.json"
    if engine_log.is_file():
        output += "\n" + engine_log.read_text(encoding="utf-8", errors="replace")
    (evidence / "combined.txt").write_text(output, encoding="utf-8")
    result = {"scenario": scenario, "status": "failed", "returncode": code, "command": command,
              "wall_seconds": round(time.monotonic() - started, 3),
              "invocation": json_read(invocation_path.read_text()) if invocation_path.is_file() else {},
              "selected_backend": selected, "physical_target_gpu_acceptance": False}
    try:
        backend = validate_runtime(output, code, selected, data_dir, scenario)
        result["actual_backend"] = backend
        result.update(implementation_details(backend))
        screenshots = []
        for filename in png_names:
            path = data_dir / filename
            if path.is_symlink():
                raise ValueError("Screenshot is not a freshly written regular file")
            width, height = check_png(path)
            if (width, height) != (1280, 720):
                raise ValueError("Gameplay evidence must be exactly 1280x720")
            screenshots.append({"file": filename, "width": width, "height": height,
                                "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
        for picture in screenshots:
            shutil.copyfile(data_dir / picture["file"], evidence / picture["file"])
        result["screenshots"] = screenshots
        result["status"] = "passed"
    except (ValueError, OSError, TypeError, KeyError) as error:
        result["reason"] = str(error)
    json_write(evidence / "result.json", result)
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--provenance", required=True, type=Path)
    parser.add_argument("--graphics-provenance", required=True, type=Path)
    parser.add_argument("--source-head", required=True)
    parser.add_argument("--platform", required=True, choices=("macos", "windows"))
    parser.add_argument("--scenario", choices=tuple(SCENARIOS), default="fire")
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args(argv)
    definition = scenario_definition(args.scenario)
    report_name = f"{args.scenario}-graphics-provenance.json"
    args.output_dir.mkdir(parents=True, exist_ok=True)
    # A failed preflight must not leave an earlier successful report or screenshots
    # in this upload directory. Source user data is touched only after selection.
    for filename in (*definition["png_names"], report_name, "result.json", "engine.txt", "process.txt",
                     "process.invoke.json", "combined.txt"):
        (args.output_dir / filename).unlink(missing_ok=True)
    report = {"scenario": args.scenario, "source_head": args.source_head, "platform": args.platform,
              "runner_architecture": platform.machine(), "gate_passed": False,
              "scope": definition["scope"],
              "limits": "Hosted/software adapters are not physical desktop performance or human-play acceptance."}
    try:
        if platform.system() != {"macos": "Darwin", "windows": "Windows"}[args.platform]:
            raise ValueError("Native gameplay requires the requested operating system")
        digest = hashlib.sha256(args.archive.read_bytes()).hexdigest()
        report["archive_sha256"] = digest
        graphics_bytes = args.graphics_provenance.read_bytes()
        report["graphics_provenance_sha256"] = hashlib.sha256(graphics_bytes).hexdigest()
        selected = select_backend(json_read(args.provenance.read_text(encoding="utf-8")),
                                  json_read(graphics_bytes.decode("utf-8")), args.source_head,
                                  digest, args.platform, platform.machine())
        report["validated_quality_tier"] = selected["renderer"]
        with tempfile.TemporaryDirectory(prefix=f"scene112-native-{args.scenario}-") as directory:
            executable = unpack_archive(args.archive, Path(directory), args.platform)
            report["result"] = run_playthrough(executable, args.output_dir,
                                              user_directory(args.platform), selected, args.scenario)
        report["gate_passed"] = report["result"]["status"] == "passed"
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError,
            zipfile.BadZipFile) as error:
        report["reason"] = str(error)
    json_write(args.output_dir / report_name, report)
    print(f"SCENE112_NATIVE_{args.scenario.upper()}_" + ("OK" if report["gate_passed"] else "FAILED"))
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a", encoding="utf-8") as summary:
            summary.write(f"\nNative {args.scenario} gameplay {args.platform}/{platform.machine()}: "
                          f"{'passed' if report['gate_passed'] else 'FAILED'}; "
                          f"quality tier {report.get('validated_quality_tier', 'unproven')}. "
                          "Same archive/source proof; three fresh 1280×720 frames and clean synchronized shutdown required.\n")
    return 0 if report["gate_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
