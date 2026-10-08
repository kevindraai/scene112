#!/usr/bin/env python3
"""Compare exact standalone bundles on actual graphical backends, with strict evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import struct
import subprocess
import tempfile
import time
import zipfile

BACKEND_PREFIX = "SCENE112_GRAPHICS_BACKEND="
PNG_NAMES = tuple(
    f"visual-street-{name}.png" for name in ("day", "dusk", "rain", "high-rain")
)
DEPENDENCY_ERRORS = re.compile(
    r"(?:\.dll|dylib|dynamic librar|missing librar|invalid rendering driver|unsupported rendering driver|shader|SCRIPT ERROR:)",
    re.I,
)
# Only pre-app device/context/display initialization failures qualify as unavailable
# research hardware. Functional errors and missing runtime dependencies never do.
INIT_ERRORS = (
    re.compile(
        r"no (?:suitable )?(?:metal|vulkan|d3d12|direct3d ?12) (?:device|adapter)s?",
        re.I,
    ),
    re.compile(
        r"(?:failed|unable|could not) to (?:find|create|initialize|initialise).*(?:metal|vulkan|d3d12|direct3d|opengl).*(?:device|context|surface|renderer)",
        re.I,
    ),
    re.compile(
        r"could not initialize (?:metal|vulkan|opengl(?: es)?|renderingdevice)", re.I
    ),
    re.compile(r"unable to create displayserver.*all display drivers failed", re.I),
)


def json_write(path: Path, data: dict) -> None:
    path.write_text(
        json.dumps(data, indent=2, allow_nan=False) + "\n", encoding="utf-8"
    )


def reject_constant(value: str):
    raise ValueError("Nonfinite JSON constant: " + value)


def json_read(text: str):
    return json.loads(text, parse_constant=reject_constant)


def backend_from_log(output: str) -> dict | None:
    values = []
    for line in output.splitlines():
        if line.startswith(BACKEND_PREFIX):
            value = json_read(line[len(BACKEND_PREFIX) :])
            if not isinstance(value, dict):
                raise ValueError("Backend marker must be an object")
            values.append(value)
    if not values:
        return None
    if any(value != values[0] for value in values):
        raise ValueError("Conflicting actual-backend markers")
    value = values[0]
    for key in ("display", "renderer", "driver", "adapter", "api", "user_data_dir"):
        if not isinstance(value.get(key), str) or not value[key]:
            raise ValueError(f"Missing actual backend field: {key}")
    return value


def classify(
    output: str,
    code: int,
    backend: dict | None,
    renderer: str,
    driver: str,
    allow_angle_fallback: bool = False,
) -> str:
    if code == 124:
        return "timed_out"
    if code == 126:
        return "launch_failed"
    errors = [line for line in output.splitlines() if "ERROR:" in line]
    if backend is None:
        if (
            errors
            and "SCENE112_VISUAL_OK" not in output
            and not DEPENDENCY_ERRORS.search(output)
            and all(
                any(pattern.search(line) for pattern in INIT_ERRORS) for line in errors
            )
        ):
            return "environment_unavailable"
        return "failed_before_backend_report"
    if backend["display"] == "headless":
        return "invalid_headless_evidence"
    # CLI may automatically fall back. Actual API information is authoritative.
    driver_matches = backend["driver"] == driver
    if renderer == "gl_compatibility" and driver == "opengl3":
        driver_matches = backend["driver"] in ("opengl3", "opengl3_es")
    if backend["renderer"] != renderer or not driver_matches:
        if (
            allow_angle_fallback
            and renderer == "gl_compatibility"
            and driver == "opengl3"
            and backend["renderer"] == renderer
            and backend["driver"] == "opengl3_angle"
        ):
            if code != 0 or errors or "SCENE112_VISUAL_OK" not in output:
                return "failed_after_backend_initialization"
            # This is a detected fallback, never native OpenGL validation.
            # profile() must still validate every fresh gameplay report/PNG.
            return "clean_angle_fallback_detected"
        return "requested_backend_not_used"
    if code != 0 or errors or "SCENE112_VISUAL_OK" not in output:
        return "failed_after_backend_initialization"
    return "passed"


def require_gameplay_report(report: dict, backend: dict) -> None:
    if (
        report.get("display") == "headless"
        or report.get("renderer") != backend["renderer"]
        or report.get("driver") != backend["driver"]
    ):
        raise ValueError("Runtime report does not match the actual graphical backend")
    if type(report.get("checks")) is not int or report["checks"] < 1:
        raise ValueError("Visual assertions did not run")
    for key, minimum in (("walk_metres", 10), ("drive_metres", 20)):
        value = report.get(key)
        if (
            isinstance(value, bool)
            or not isinstance(value, (int, float))
            or not math.isfinite(value)
            or value <= minimum
        ):
            raise ValueError(f"Missing real gameplay distance: {key}")
    conditions = report.get("conditions", [])
    if [item.get("conditions") for item in conditions] != ["day", "dusk", "rain"]:
        raise ValueError("Three actual scene conditions were not validated")
    engine = report.get("engine", {})
    if (engine.get("major"), engine.get("minor"), engine.get("patch")) != (4, 7, 2):
        raise ValueError("Unexpected packaged Godot version")


def check_png(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if len(data) < 1024 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError("Missing actual rendered PNG: " + path.name)
    width, height = struct.unpack(">II", data[16:24])
    if width < 640 or height < 360:
        raise ValueError("Unexpected rendered screenshot dimensions")
    return width, height


def user_directory(target: str) -> Path:
    if target == "macos":
        return Path.home() / "Library/Application Support/Scene112"
    if target == "windows":
        return Path(os.environ["APPDATA"]) / "Scene112"
    return (
        Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "Scene112"
    )


def invoke(
    command: list[str], cwd: Path, log: Path, timeout: int = 240
) -> tuple[int, str]:
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
        )
        output, code = result.stdout, result.returncode
    except subprocess.TimeoutExpired as error:
        raw = error.output or b""
        output = (
            raw.decode("utf-8", errors="replace") if isinstance(raw, bytes) else raw
        )
        output += "\nPROBE_TIMEOUT: graphical process exceeded bounded timeout\n"
        code = 124
    except OSError as error:
        output, code = "PROBE_LAUNCH_ERROR: " + str(error), 126
    log.write_text(output, encoding="utf-8")
    return code, output


def capture_host(output_dir: Path, target: str) -> dict:
    evidence = output_dir / "host"
    evidence.mkdir(parents=True, exist_ok=True)
    if target == "macos":
        command = [
            "system_profiler",
            "SPDisplaysDataType",
            "SPHardwareDataType",
            "-json",
        ]
    else:
        command = [
            "powershell.exe",
            "-NoProfile",
            "-Command",
            "[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new($false);$d=@{video=Get-CimInstance Win32_VideoController | Select-Object Name,VideoProcessor,DriverVersion,AdapterRAM;computer=Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model,TotalPhysicalMemory;cpu=Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors};$d|ConvertTo-Json -Depth 5",
        ]
    code, output = invoke(
        command, output_dir.resolve(), evidence / "system.txt", timeout=45
    )
    result = {
        "command": command,
        "returncode": code,
        "scope": "host graphics/CPU capability inventory; not physical target acceptance",
    }
    try:
        result["inventory"] = json_read(output)
    except (ValueError, TypeError) as error:
        result["parse_error"] = str(error)
    json_write(evidence / "system.json", result)
    return {"file": "host/system.json", "returncode": code}


def capture_crashes(
    evidence: Path, started: float, wait_for_report: bool = False
) -> list[dict]:
    if platform.system() != "Darwin":
        return []
    directory = Path.home() / "Library/Logs/DiagnosticReports"
    candidates = []
    capture_errors = []
    deadline = time.monotonic() + (5.0 if wait_for_report else 0.0)
    while True:
        for suffix in ("ips", "crash"):
            for path in directory.glob("Scene112*." + suffix):
                try:
                    info = path.stat()
                    if info.st_mtime >= started - 1:
                        with path.open("rb") as stream:
                            header = stream.read(4096).decode("utf-8", errors="replace")
                        if suffix == "ips":
                            try:
                                own = (
                                    json_read(header.splitlines()[0]).get("app_name")
                                    == "Scene112"
                                )
                            except (ValueError, AttributeError, IndexError):
                                own = False
                        else:
                            own = bool(
                                re.search(r"^Process:\s+Scene112\s*\[", header, re.M)
                            )
                        if own:
                            candidates.append((info.st_mtime, path, info.st_size))
                except OSError as error:
                    capture_errors.append(
                        {"file": path.name, "capture_error": str(error)}
                    )
        if candidates or time.monotonic() >= deadline:
            break
        time.sleep(0.2)
    copied = capture_errors
    for modified, path, size in sorted(candidates, reverse=True)[:5]:
        item = {"file": path.name, "modified_epoch": modified, "bytes": size}
        if size > 4 * 1024 * 1024:
            item["copied"] = False
            item["reason"] = "bounded crash report size exceeded"
        else:
            destination = evidence / "own-crashes" / path.name
            destination.parent.mkdir(exist_ok=True)
            try:
                shutil.copyfile(path, destination)
                item["copied"] = True
                item["sha256"] = hashlib.sha256(destination.read_bytes()).hexdigest()
            except OSError as error:
                item["copied"] = False
                item["capture_error"] = str(error)
        copied.append(item)
    return copied


def profile(
    executable: Path,
    output_dir: Path,
    data_dir: Path,
    renderer: str,
    driver: str,
    allow_angle_fallback: bool = False,
) -> dict:
    name = renderer + "-" + driver
    evidence = output_dir / name
    evidence.mkdir(parents=True, exist_ok=True)
    # Known test files only. Prevent screenshots from an earlier profile/run from
    # being misattributed to this requested backend.
    for filename in (*PNG_NAMES, "visual-runtime.json"):
        (data_dir / filename).unlink(missing_ok=True)
    engine_log = (evidence / "engine.txt").resolve()
    engine_log.unlink(missing_ok=True)
    command = [
        str(executable),
        "--verbose",
        "--log-file",
        str(engine_log),
        "--windowed",
        "--resolution",
        "1280x720",
        "--rendering-method",
        renderer,
        "--rendering-driver",
        driver,
        "--audio-driver",
        "Dummy",
        "--",
        "--visual-playthrough",
    ]
    started = time.time()
    code, output = invoke(
        command, executable.parent, evidence / "process.txt",
        timeout=480 if renderer == "forward_plus" else 240,
    )
    if engine_log.is_file():
        output += "\n" + engine_log.read_text(encoding="utf-8", errors="replace")
    (evidence / "combined.txt").write_text(output, encoding="utf-8")
    result = {
        "requested_renderer": renderer,
        "requested_driver": driver,
        "returncode": code,
        "command": command,
        "scope": "exact standalone, actual graphical window and scripted gameplay; no human play/performance claim",
        "wall_seconds": round(time.time() - started, 3),
        "phase_log": [
            line
            for line in output.splitlines()
            if line.startswith(
                (
                    "SCENE112_GRAPHICS_STAGE=",
                    "SCENE112_GRAPHICS_BACKEND=",
                    "SCENE112_BRAKE_DIAGNOSTICS=",
                )
            )
        ],
        "crash_reports": capture_crashes(evidence, started, wait_for_report=code < 0),
    }
    try:
        backend = backend_from_log(output)
        result["actual_backend"] = backend
        if backend is not None:
            result.update(implementation_details(backend))
        result["status"] = classify(
            output, code, backend, renderer, driver, allow_angle_fallback
        )
        if result["status"] in ("passed", "clean_angle_fallback_detected"):
            if Path(backend["user_data_dir"]).resolve() != data_dir.resolve():
                raise ValueError("Unexpected runtime user directory")
            report = json_read(
                (data_dir / "visual-runtime.json").read_text(encoding="utf-8")
            )
            require_gameplay_report(report, backend)
            shutil.copyfile(
                data_dir / "visual-runtime.json", evidence / "visual-runtime.json"
            )
            screenshots = []
            for filename in PNG_NAMES:
                path = data_dir / filename
                width, height = check_png(path)
                shutil.copyfile(path, evidence / filename)
                screenshots.append(
                    {
                        "file": filename,
                        "width": width,
                        "height": height,
                        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                    }
                )
            result["screenshots"] = screenshots
            label = (backend["adapter"] + " " + str(backend.get("vendor", ""))).lower()
            result["software_adapter_detected"] = backend.get(
                "adapter_type"
            ) == 4 or any(
                token in label
                for token in (
                    "llvmpipe",
                    "lavapipe",
                    "software renderer",
                    "basic render driver",
                    "gdi generic",
                    "warp",
                )
            )
            result["adapter_classification"] = (
                "software (detected)"
                if result["software_adapter_detected"]
                else (
                    "virtual/paravirtual (detected); physical hardware not accepted"
                    if result["virtual_adapter_detected"]
                    else "unclassified; physical hardware not accepted"
                )
            )
            result["physical_target_gpu_acceptance"] = False
    except (ValueError, OSError, KeyError, TypeError, AttributeError) as error:
        result["status"] = "invalid_evidence"
        result["reason"] = str(error)
    json_write(evidence / "result.json", result)
    return result


def compatibility_passed(results: list[dict], target: str) -> bool:
    if results[1]["status"] == "passed":
        return True
    if target != "windows" or results[1]["status"] != "clean_angle_fallback_detected":
        return False
    # A clean automatic ANGLE run requires its own exact-driver replay.
    return len(results) == 3 and (
        results[2]["requested_renderer"] == "gl_compatibility"
        and results[2]["requested_driver"] == "opengl3_angle"
        and results[2]["status"] == "passed"
    )


def profile_drivers(target: str, architecture: str) -> tuple[str, str]:
    if target == "windows":
        return "d3d12", "opengl3"
    # The pinned official x86_64 template disables Metal; its registered RD
    # driver is Vulkan. Explicit ANGLE avoids the observed blank native-GL hang.
    if architecture.lower() in ("x86_64", "amd64"):
        return "vulkan", "opengl3_angle"
    if architecture.lower() in ("arm64", "aarch64"):
        return "metal", "opengl3"
    raise ValueError("Unsupported native macOS runner architecture")


def implementation_details(backend: dict) -> dict:
    signature = " ".join(
        str(backend.get(key, "")) for key in ("driver", "adapter", "api", "vendor")
    ).lower()
    angle = backend.get("driver") == "opengl3_angle" or bool(
        re.search(r"\bangle\b", signature)
    )
    virtual = any(
        token in signature
        for token in (
            "paravirtual",
            "virtual machine",
            "virtual adapter",
            "vmware",
            "parallels",
            "virtualbox",
        )
    )
    software = backend.get("adapter_type") == 4 or any(
        token in signature
        for token in (
            "llvmpipe",
            "lavapipe",
            "software renderer",
            "basic render driver",
            "gdi generic",
            "warp",
        )
    )
    native_gl = (
        backend.get("renderer") == "gl_compatibility"
        and backend.get("driver") == "opengl3"
        and not angle
        and "opengl es" not in signature
    )
    return {
        "angle_translation_detected": angle,
        "angle_backend": (
            "metal"
            if "metal" in signature
            else (
                "d3d11"
                if "d3d11" in signature or "direct3d11" in signature
                else "unidentified"
            )
        )
        if angle
        else None,
        "virtual_adapter_detected": virtual,
        "native_opengl_implementation": native_gl,
        "software_adapter_detected": software,
        "adapter_classification": "software (detected)"
        if software
        else (
            "virtual/paravirtual (detected); physical hardware not accepted"
            if virtual
            else "unclassified; physical hardware not accepted"
        ),
        "physical_target_gpu_acceptance": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--provenance", required=True, type=Path)
    parser.add_argument("--source-head", required=True)
    parser.add_argument("--platform", required=True, choices=("macos", "windows"))
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    provenance = json_read(args.provenance.read_text(encoding="utf-8"))
    digest = hashlib.sha256(args.archive.read_bytes()).hexdigest()
    if (
        provenance.get("source_head") != args.source_head
        or provenance.get("sha256") != digest
    ):
        raise ValueError("Exact source-head/archive provenance mismatch")
    host_information = capture_host(args.output_dir, args.platform)
    results = []
    with tempfile.TemporaryDirectory(prefix="scene112-native-graphics-") as directory:
        staging = Path(directory)
        if args.platform == "macos":
            subprocess.run(
                ["ditto", "-xk", str(args.archive.resolve()), str(staging)], check=True
            )
            apps = list(staging.glob("*.app"))
            if len(apps) != 1:
                raise ValueError("Expected exactly one native application bundle")
            app = apps[0]
            subprocess.run(
                ["codesign", "--verify", "--deep", "--strict", str(app)], check=True
            )
            info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
            executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
        else:
            with zipfile.ZipFile(args.archive) as archive:
                for item in archive.infolist():
                    if (
                        not (staging / item.filename)
                        .resolve()
                        .is_relative_to(staging.resolve())
                    ):
                        raise ValueError("Unsafe native archive path")
                archive.extractall(staging)
            executable = staging / "Scene112.exe"
        if not executable.is_file():
            raise ValueError("Missing standalone executable")
        primary, compatibility = profile_drivers(args.platform, platform.machine())
        results.append(
            profile(
                executable.resolve(),
                args.output_dir,
                user_directory(args.platform),
                "forward_plus",
                primary,
            )
        )
        results.append(
            profile(
                executable.resolve(),
                args.output_dir,
                user_directory(args.platform),
                "gl_compatibility",
                compatibility,
                allow_angle_fallback=args.platform == "windows",
            )
        )
        if (
            args.platform == "windows"
            and results[1]["status"] == "clean_angle_fallback_detected"
        ):
            results.append(
                profile(
                    executable.resolve(),
                    args.output_dir,
                    user_directory(args.platform),
                    "gl_compatibility",
                    "opengl3_angle",
                )
            )
    passed = compatibility_passed(results, args.platform) and results[0]["status"] in (
        "passed",
        "environment_unavailable",
    )
    report = {
        "source_head": args.source_head,
        "archive_sha256": digest,
        "platform": args.platform,
        "runner_architecture": platform.machine(),
        "host_information": host_information,
        "results": results,
        "required_compatibility_passed": compatibility_passed(results, args.platform),
        "native_opengl_validated": results[1]["status"] == "passed"
        and results[1].get("native_opengl_implementation", False),
        "automatic_angle_fallback_detected": results[1]["status"]
        == "clean_angle_fallback_detected",
        "explicit_angle_validated": any(
            result["requested_driver"] == "opengl3_angle"
            and result["status"] == "passed"
            for result in results
        ),
        "primary_forward_plus_validated": results[0]["status"] == "passed",
        "gate_passed": passed,
        "default_renderer_changed": False,
        "limits": "Research unavailability is explicit; source/asset/shader/late errors are fatal. Software/hosted adapters are not physical target acceptance.",
    }
    json_write(args.output_dir / "graphics-provenance.json", report)
    print(json.dumps(report, indent=2))
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(os.environ["GITHUB_STEP_SUMMARY"]).open(
            "a", encoding="utf-8"
        ) as summary:
            summary.write(
                f"\nNative graphics {args.platform}/{platform.machine()}\n\n| Requested tier | Result | Actual adapter |\n|---|---|---|\n"
            )
            for result in results:
                summary.write(
                    f"| {result['requested_renderer']}/{result['requested_driver']} | {result['status']} | {(result.get('actual_backend') or {}).get('adapter', 'No graphical initialization')} |\n"
                )
            summary.write(
                "\nProject default remains Compatibility. Hosted/software testing is not physical desktop acceptance.\n"
            )
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
