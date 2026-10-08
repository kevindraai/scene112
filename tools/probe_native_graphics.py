#!/usr/bin/env python3
"""Compare exact standalone bundles on actual graphical backends, with strict evidence."""

from __future__ import annotations

import argparse
from datetime import datetime
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
    command: list[str],
    cwd: Path,
    log: Path,
    timeout: int = 240,
    *,
    separate_stderr: bool = False,
    sample_own_process: bool = False,
    environment: dict[str, str] | None = None,
) -> tuple[int, str]:
    started = time.monotonic()
    diagnostics = {
        "timeout_seconds": timeout,
        "environment_overrides": environment or {},
    }
    stderr = ""
    try:
        with subprocess.Popen(
            command,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE if separate_stderr else subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            env={**os.environ, **environment} if environment else None,
        ) as process:
            diagnostics["pid"] = process.pid
            # Diagnose this exact child early enough to preserve stack evidence.
            # Absolute deadlines include diagnostic time; the runtime budget is
            # unchanged and every subprocess is synchronously reaped.
            sampling = (
                sample_own_process
                and platform.system() == "Darwin"
                and Path(command[0]).name == "Scene112"
            )
            sample_times = [60, 180] if sampling else []
            sample_times = [point for point in sample_times if point + 12 < timeout]
            checkpoints = [*sample_times, timeout]
            for checkpoint in checkpoints:
                remaining = max(0.001, started + checkpoint - time.monotonic())
                try:
                    output, stderr = process.communicate(timeout=remaining)
                    break
                except subprocess.TimeoutExpired:
                    if checkpoint != timeout:
                        if process.poll() is None:
                            diagnostic = sample_child(process.pid, log.parent, checkpoint)
                            diagnostics.setdefault("live_samples", []).append(diagnostic)
                        continue
                    process.kill()
                    output, stderr = process.communicate()
                    output += (
                        "\nPROBE_TIMEOUT: graphical process exceeded bounded timeout\n"
                    )
                    diagnostics["timed_out"] = True
            code = 124 if diagnostics.get("timed_out") else process.returncode
    except OSError as error:
        output, code = "PROBE_LAUNCH_ERROR: " + str(error), 126
    diagnostics["returncode"] = code
    diagnostics["wall_seconds"] = round(time.monotonic() - started, 3)
    log.write_text(output, encoding="utf-8")
    if separate_stderr:
        log.with_name(log.stem + "-stderr" + log.suffix).write_text(
            stderr or "", encoding="utf-8"
        )
    json_write(log.with_suffix(".invoke.json"), diagnostics)
    return code, output


def sample_child(pid: int, evidence: Path, elapsed_checkpoint: int) -> dict:
    stem = f"live-process-{elapsed_checkpoint}s"
    command = [
        "sample", str(pid), "1", "1", "-file",
        str((evidence / (stem + "-sample.txt")).resolve()),
    ]
    result = {
        "pid": pid,
        "checkpoint_seconds": elapsed_checkpoint,
        "command": command,
        "scope": "own child stack and CPU/RSS; diagnostic time is inside runtime timeout",
    }
    commands = [
        ("process_snapshot", ["ps", "-p", str(pid), "-o", "pid=,ppid=,%cpu=,rss=,state=,etime=,comm="], 2),
        ("sample", command, 10),
    ]
    for name, invocation, budget in commands:
        record = {"command": invocation, "timeout_seconds": budget}
        try:
            sampled = subprocess.run(
                invocation,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=budget,
            )
            output = sampled.stdout
            record["returncode"] = sampled.returncode
        except subprocess.TimeoutExpired as error:
            # subprocess.run already kills and waits for the diagnostic child.
            output = error.stdout or ""
            if isinstance(output, bytes):
                output = output.decode("utf-8", errors="replace")
            record["capture_error"] = str(error)
        except OSError as error:
            output = ""
            record["capture_error"] = str(error)
        filename = stem + "-" + name + "-command.txt"
        (evidence / filename).write_text(output, encoding="utf-8")
        record["output_file"] = filename
        result[name] = record
    return result


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
        command,
        output_dir.resolve(),
        evidence / "system.txt",
        timeout=45,
        separate_stderr=True,
    )
    result = {
        "command": command,
        "returncode": code,
        "stderr_file": "host/system-stderr.txt",
        "scope": "host graphics/CPU capability inventory; not physical target acceptance",
    }
    try:
        result["inventory"] = json_read(output)
    except (ValueError, TypeError) as error:
        result["parse_error"] = str(error)
    json_write(evidence / "system.json", result)
    return {"file": "host/system.json", "returncode": code}


def capture_crashes(
    evidence: Path,
    started: float,
    wait_for_report: bool = False,
    expected_pid: int | None = None,
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
                item.update(
                    crash_origin(
                        destination.read_text(encoding="utf-8", errors="replace"),
                        expected_pid,
                    )
                )
            except OSError as error:
                item["copied"] = False
                item["capture_error"] = str(error)
        copied.append(item)
    return copied


def crash_origin(text: str, expected_pid: int | None) -> dict:
    """Publication time only determines capture eligibility, never process origin."""
    result = {"expected_pid": expected_pid, "origin": "unknown"}
    try:
        if text.startswith("{"):
            header, body = text.split("\n", 1)
            report = json_read(body)
            pid = report.get("pid")
            for field in ("procLaunch", "captureTime"):
                value = report.get(field)
                if isinstance(value, str):
                    result[field] = value
                    for format_string in (
                        "%Y-%m-%d %H:%M:%S.%f %z",
                        "%Y-%m-%d %H:%M:%S %z",
                    ):
                        try:
                            result[field + "_epoch"] = datetime.strptime(
                                value, format_string
                            ).timestamp()
                            break
                        except ValueError:
                            continue
        else:
            match = re.search(r"^Process:\s+Scene112\s*\[(\d+)\]", text, re.M)
            pid = int(match.group(1)) if match else None
        if isinstance(pid, int) and not isinstance(pid, bool) and pid > 0:
            result["reported_pid"] = pid
            if expected_pid is not None:
                result["origin"] = (
                    "current_process" if pid == expected_pid else "other_own_process"
                )
    except (ValueError, TypeError, AttributeError):
        pass
    return result


def profile(
    executable: Path,
    output_dir: Path,
    data_dir: Path,
    renderer: str,
    driver: str,
    allow_angle_fallback: bool = False,
    environment: dict[str, str] | None = None,
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
    invoke_options = (
        {"sample_own_process": True} if platform.system() == "Darwin" else {}
    )
    if environment:
        invoke_options["environment"] = environment
    code, output = invoke(
        command,
        executable.parent,
        evidence / "process.txt",
        timeout=480 if renderer == "forward_plus" else 240,
        **invoke_options,
    )
    invocation_file = evidence / "process.invoke.json"
    invocation = (
        json_read(invocation_file.read_text()) if invocation_file.is_file() else {}
    )
    if engine_log.is_file():
        output += "\n" + engine_log.read_text(encoding="utf-8", errors="replace")
    (evidence / "combined.txt").write_text(output, encoding="utf-8")
    result = {
        "requested_renderer": renderer,
        "requested_driver": driver,
        "returncode": code,
        "command": command,
        "invocation": invocation,
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
        "crash_reports": capture_crashes(
            evidence,
            started,
            wait_for_report=code < 0,
            expected_pid=invocation.get("pid"),
        ),
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
    # driver is Vulkan. ANGLE EGL initialization failed on the observed hosted
    # Intel adapter; explicitly test the initialized native GL implementation.
    if architecture.lower() in ("x86_64", "amd64"):
        return "vulkan", "opengl3"
    if architecture.lower() in ("arm64", "aarch64"):
        return "metal", "opengl3"
    raise ValueError("Unsupported native macOS runner architecture")


def intel_mobile_candidate(target: str, architecture: str, result: dict, output: str) -> bool:
    """A separate quality tier, never a reclassification of the failed run."""
    return (
        target == "macos"
        and architecture.lower() in ("x86_64", "amd64")
        and result.get("status") == "failed_before_backend_report"
        and result.get("returncode") == -6
        and result.get("actual_backend") is None
        and result.get("phase_log") == []
        and "MoltenVK version 1.4.1" in output
        and "Apple - Apple Paravirtual device" in output
        and "Render Pipeline Descriptor Validation\nNo valid pixelFormats set." in output
        and "ERROR:" not in output
        and "SCRIPT ERROR:" not in output
        and "SCENE112_GRAPHICS_BACKEND=" not in output
        and "SCENE112_GRAPHICS_STAGE=" not in output
    )


def quality_tier(results: list[dict]) -> str | None:
    if results[0]["status"] == "passed":
        return "forward_plus"
    if results[0].get("mobile_fallback_candidate_verified") is not True:
        return None
    for result in results[2:]:
        backend = result.get("actual_backend")
        if (
            result.get("requested_renderer") == "mobile"
            and result.get("requested_driver") == "vulkan"
            and result.get("status") == "passed"
            and isinstance(backend, dict)
            and backend.get("renderer") == "mobile"
            and backend.get("driver") == "vulkan"
        ):
            return "mobile"
    return None


def selected_intel_compatibility(
    target: str, architecture: str, explicit: bool, result: dict, runtime: dict
) -> bool:
    """Select the proven shipping renderer; retain failed research untouched."""
    if explicit is not True or target != "macos" or architecture.lower() not in ("x86_64", "amd64"):
        return False
    if (result.get("requested_renderer") != "gl_compatibility"
            or result.get("requested_driver") != "opengl3"
            or result.get("status") != "passed" or result.get("returncode") != 0):
        return False
    backend = result.get("actual_backend")
    if not isinstance(backend, dict) or (backend.get("display") != "macOS"
            or backend.get("renderer") != "gl_compatibility"
            or backend.get("driver") not in ("opengl3", "opengl3_es")
            or not isinstance(backend.get("adapter"), str) or not backend["adapter"]):
        return False
    try:
        require_gameplay_report(runtime, backend)
    except (KeyError, TypeError, ValueError, AttributeError):
        return False
    if type(runtime.get("checks")) is not int or runtime["checks"] < 200:
        return False
    pictures = result.get("screenshots")
    if not isinstance(pictures, list) or len(pictures) != len(PNG_NAMES):
        return False
    if any(not isinstance(picture, dict) for picture in pictures):
        return False
    if [picture.get("file") for picture in pictures] != list(PNG_NAMES):
        return False
    return all(type(p.get("width")) is int and p["width"] >= 640
               and type(p.get("height")) is int and p["height"] >= 360
               and isinstance(p.get("sha256"), str)
               and re.fullmatch("[0-9a-f]{64}", p["sha256"]) for p in pictures)


def intel_probe_environment(
    target: str, architecture: str, enabled: bool
) -> dict[str, str]:
    if not enabled:
        return {}
    if target != "macos" or architecture.lower() not in ("x86_64", "amd64"):
        raise ValueError("Argument-buffer diagnostic is limited to macOS Intel")
    # MoltenVK1.4.1 initMTLDevice otherwise calls the argument encoder that
    # aborted on the hosted Intel Apple Paravirtual Metal2 adapter. This is an
    # explicit per-process diagnostic; all actual backend/gameplay gates apply.
    # Bypass placement-heap size queries for coherent Shared staging buffers.
    # Real initialization/render/gameplay evidence remains mandatory.
    return {"MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS": "0", "MVK_CONFIG_USE_MTLHEAP": "0"}


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


def profile_pair(
    executable: Path,
    output_dir: Path,
    data_dir: Path,
    primary_driver: str,
    compatibility_driver: str,
    *,
    primary_environment: dict[str, str],
    allow_angle_fallback: bool,
    compatibility_first: bool,
) -> list[dict]:
    # The selected Intel tier runs on the fresh host before experimental driver
    # crashes. Preserve the established report order and all failure semantics.
    order = ["forward_plus", "gl_compatibility"]
    if compatibility_first:
        order.reverse()
    results = {}
    for renderer in order:
        if renderer == "forward_plus":
            result = profile(executable, output_dir, data_dir, renderer,
                             primary_driver, environment=primary_environment)
        else:
            result = profile(executable, output_dir, data_dir, renderer,
                             compatibility_driver, allow_angle_fallback=allow_angle_fallback)
        results[renderer] = result
    return [results["forward_plus"], results["gl_compatibility"]]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--provenance", required=True, type=Path)
    parser.add_argument("--source-head", required=True)
    parser.add_argument("--platform", required=True, choices=("macos", "windows"))
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument(
        "--intel-no-argument-buffers",
        action="store_true",
        help="Explicit Intel-only MoltenVK argument-buffer diagnostic",
    )
    parser.add_argument(
        "--intel-mobile-fallback",
        action="store_true",
        help="Require an additional Mobile/Vulkan quality proof for the known Intel host cluster-PSO failure",
    )
    parser.add_argument("--intel-compatibility-quality", action="store_true",
                        help="Explicitly choose fully verified default Compatibility as Intel quality tier")
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    primary_environment = intel_probe_environment(
        args.platform, platform.machine(), args.intel_no_argument_buffers
    )
    if args.intel_mobile_fallback and not primary_environment:
        raise ValueError("Intel Mobile research requires the explicit Intel-only configuration")
    if args.intel_compatibility_quality and not primary_environment:
        raise ValueError("Intel Compatibility quality is limited to the configured macOS Intel job")
    provenance = json_read(args.provenance.read_text(encoding="utf-8"))
    digest = hashlib.sha256(args.archive.read_bytes()).hexdigest()
    if (
        provenance.get("source_head") != args.source_head
        or provenance.get("sha256") != digest
    ):
        raise ValueError("Exact source-head/archive provenance mismatch")
    host_information = capture_host(args.output_dir, args.platform)
    if primary_environment:
        diagnostic = Path(__file__).with_name("probe_metal_allocation.swift")
        code, _ = invoke(
            ["xcrun", "swift", str(diagnostic.resolve())],
            args.output_dir.resolve(),
            args.output_dir / "host/metal-allocation.txt",
            timeout=45,
            separate_stderr=True,
        )
        host_information["metal_allocation_probe_returncode"] = code
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
        results.extend(
            profile_pair(
                executable.resolve(),
                args.output_dir,
                user_directory(args.platform),
                primary,
                compatibility,
                primary_environment=primary_environment,
                allow_angle_fallback=args.platform == "windows",
                compatibility_first=args.intel_compatibility_quality,
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
        if args.intel_mobile_fallback and intel_mobile_candidate(
            args.platform,
            platform.machine(),
            results[0],
            (args.output_dir / "forward_plus-vulkan/combined.txt").read_text(encoding="utf-8"),
        ):
            results[0]["mobile_fallback_candidate_verified"] = True
            results.append(
                profile(
                    executable.resolve(),
                    args.output_dir,
                    user_directory(args.platform),
                    "mobile",
                    "vulkan",
                    environment=primary_environment,
                )
            )
    accepted_quality = quality_tier(results)
    if args.intel_compatibility_quality:
        accepted_quality = None
        if results[1]["status"] == "passed":
            runtime = json_read((args.output_dir / "gl_compatibility-opengl3/visual-runtime.json").read_text(encoding="utf-8"))
            if selected_intel_compatibility(args.platform, platform.machine(), True, results[1], runtime):
                accepted_quality = "gl_compatibility"
    passed = compatibility_passed(results, args.platform) and (
        accepted_quality is not None or (
            not args.intel_compatibility_quality and results[0]["status"] == "environment_unavailable"
        )
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
        "validated_quality_tier": accepted_quality,
        "mobile_quality_fallback_validated": accepted_quality == "mobile",
        "requested_intel_quality_tier": "gl_compatibility" if args.intel_compatibility_quality else None,
        "gate_passed": passed,
        "default_renderer_changed": False,
        "limits": "Failed Forward+/Mobile research is retained. Only the explicitly selected, fully proven quality tier is accepted. Every selected-tier error remains fatal; software/hosted adapters are not physical target acceptance.",
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
