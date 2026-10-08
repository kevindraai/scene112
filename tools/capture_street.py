#!/usr/bin/env python3
"""Record the same real-time 22-second in-game street route before/after visuals."""

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile
import time


def run_text(command, cwd=None, env=None):
    return subprocess.check_output(command, cwd=cwd, env=env, text=True).strip()


def wait_file(path, process, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists() and path.stat().st_size:
            return
        if process.poll() is not None:
            raise RuntimeError(
                f"Process exited {process.returncode} before {path.name}; inspect logs"
            )
        time.sleep(0.05)
    raise RuntimeError(f"Timeout waiting for {path.name}")


def cleanup(process):
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    parser.add_argument(
        "--godot",
        type=Path,
        default=Path("/tmp/scene112-tools/Godot_v4.7.2-stable_linux.x86_64"),
    )
    parser.add_argument(
        "--ffmpeg",
        type=Path,
        default=Path("/tmp/scene112-tools/visual/root/usr/bin/ffmpeg"),
    )
    parser.add_argument(
        "--ffprobe",
        type=Path,
        default=Path("/tmp/scene112-tools/visual/root/usr/bin/ffprobe"),
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--tag", default="BEFORE blockout")
    parser.add_argument(
        "--driver",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "tests/quality_route.gd",
    )
    parser.add_argument(
        "--runtime-lib-dir",
        type=Path,
        default=Path("/tmp/scene112-tools/graphics/root/usr/lib/x86_64-linux-gnu"),
        help="Optional Linux XCursor/Xinerama runtime libraries",
    )
    parser.add_argument("--condition", choices=("day", "dusk", "rain"), default="day")
    parser.add_argument(
        "--source-revision",
        help="Revision for a plain git archive snapshot, checked against snapshot-provenance.json",
    )
    args = parser.parse_args()
    args.project = args.project.resolve()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    if any(args.output.iterdir()):
        raise RuntimeError(
            "Use a new empty output directory to preserve earlier evidence"
        )
    if args.source_revision:
        snapshot = json.loads((args.project / "snapshot-provenance.json").read_text())
        if snapshot["source_revision"] != args.source_revision:
            raise RuntimeError(
                "Snapshot revision does not match explicit source provenance"
            )
        revision, source_status = (
            args.source_revision,
            "plain read-only git archive snapshot",
        )
    else:
        revision = run_text(["git", "rev-parse", "HEAD"], args.project)
        source_status = run_text(["git", "status", "--porcelain"], args.project)
    source_files = [
        "project.godot",
        "scenes/main.tscn",
        "scripts/app.gd",
        "scripts/world.gd",
        "scripts/player.gd",
        "scripts/vehicle.gd",
    ]
    source_files += [
        str(path.relative_to(args.project))
        for path in sorted((args.project / "assets/models").rglob("*.glb"))
    ]
    source_files += [
        str(path.relative_to(args.project))
        for path in sorted((args.project / "assets/textures").rglob("*.png"))
    ]
    source_files += [
        name
        for name in (
            "scripts/street_atmosphere.gd",
            "scripts/authored_actor.gd",
            "shaders/wet_paving.gdshader",
        )
        if (args.project / name).is_file()
    ]
    source_hashes = {
        name: hashlib.sha256((args.project / name).read_bytes()).hexdigest()
        for name in source_files
    }
    ffenv = os.environ.copy()
    # Debian-extracted FFmpeg needs its bundled codec and pulse/BLAS libraries.
    root = args.ffmpeg.parent.parent.parent
    libraries = [
        root / "usr/lib/x86_64-linux-gnu",
        root / "usr/lib/x86_64-linux-gnu/pulseaudio",
        root / "usr/lib/x86_64-linux-gnu/blas",
        root / "usr/lib/x86_64-linux-gnu/lapack",
        root / "lib/x86_64-linux-gnu",
    ]
    ffenv["LD_LIBRARY_PATH"] = ":".join(map(str, libraries)) + (
        ":" + ffenv["LD_LIBRARY_PATH"] if ffenv.get("LD_LIBRARY_PATH") else ""
    )
    ffversion = run_text([str(args.ffmpeg), "-version"], env=ffenv).splitlines()[0]
    server = game = recorder = None
    created = time.time()
    with tempfile.TemporaryDirectory(prefix="scene112-quality-display-") as directory:
        display_file = Path(directory) / "display"
        with (
            display_file.open("w+") as display_out,
            (args.output / "xvfb.log").open("w") as xlog,
            (args.output / "runtime.log").open("w") as glog,
            (args.output / "ffmpeg.log").open("w") as flog,
            (args.output / "ffmpeg-progress.log").open("w") as progress,
        ):
            try:
                server = subprocess.Popen(
                    [
                        "Xvfb",
                        "-displayfd",
                        str(display_out.fileno()),
                        "-screen",
                        "0",
                        "1280x720x24",
                        "-nolisten",
                        "tcp",
                    ],
                    pass_fds=(display_out.fileno(),),
                    stdout=xlog,
                    stderr=xlog,
                )
                wait_file(display_file, server, 5)
                display = ":" + display_file.read_text().strip()
                env = os.environ.copy()
                env["LD_LIBRARY_PATH"] = str(args.runtime_lib_dir) + (
                    ":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else ""
                )
                env.update(
                    {
                        "DISPLAY": display,
                        "LIBGL_ALWAYS_SOFTWARE": "1",
                        "GODOT_SILENCE_ROOT_WARNING": "1",
                        "SCENE112_EVIDENCE_DIR": str(args.output),
                        "SCENE112_EVIDENCE_TAG": args.tag,
                        "SCENE112_EVIDENCE_CONDITION": args.condition,
                        "XDG_DATA_HOME": str(args.output / "xdg/data"),
                        "XDG_CONFIG_HOME": str(args.output / "xdg/config"),
                        "XDG_CACHE_HOME": str(args.output / "xdg/cache"),
                    }
                )
                command = [
                    str(args.godot),
                    "--path",
                    str(args.project),
                    "--audio-driver",
                    "Dummy",
                    "--resolution",
                    "1280x720",
                    "--position",
                    "0,0",
                    "--script",
                    str(args.driver.resolve()),
                ]
                game_started = time.monotonic()
                game = subprocess.Popen(command, env=env, stdout=glog, stderr=glog)
                wait_file(args.output / "ready.json", game, 90)
                ready_wall = time.monotonic() - game_started
                ffcmd = [
                    str(args.ffmpeg),
                    "-hide_banner",
                    "-nostats",
                    "-y",
                    "-f",
                    "x11grab",
                    "-framerate",
                    "30",
                    "-video_size",
                    "1280x720",
                    "-i",
                    display + ".0+0,0",
                    "-t",
                    "50",
                    "-an",
                    "-c:v",
                    "libx264",
                    "-threads",
                    "2",
                    "-preset",
                    "ultrafast",
                    "-crf",
                    "18",
                    "-pix_fmt",
                    "yuv420p",
                    "-movflags",
                    "+faststart",
                    "-progress",
                    "pipe:1",
                    str(args.output / "runtime.mp4"),
                ]
                record_started = time.monotonic()
                recorder = subprocess.Popen(
                    ffcmd,
                    env=ffenv,
                    stdin=subprocess.PIPE,
                    stdout=progress,
                    stderr=flog,
                )
                wait_file(args.output / "ffmpeg-progress.log", recorder, 5)
                # Confirm actual packets before releasing the real-time route.
                deadline = time.monotonic() + 5
                while "frame=" not in (args.output / "ffmpeg-progress.log").read_text():
                    if recorder.poll() is not None or time.monotonic() > deadline:
                        raise RuntimeError("FFmpeg did not capture screen frames")
                    time.sleep(0.05)
                prefix_seconds = time.monotonic() - record_started
                (args.output / "recording").write_text("started\n")
                game.wait(timeout=90)
                if game.returncode != 0:
                    raise RuntimeError(
                        f"Runtime failed: {game.returncode}; inspect runtime.log"
                    )
                recorder.stdin.write(b"q\n")
                recorder.stdin.flush()
                recorder.wait(timeout=10)
                if recorder.returncode != 0:
                    raise RuntimeError(f"Recording failed: {recorder.returncode}")
            finally:
                cleanup(recorder)
                cleanup(game)
                cleanup(server)
    runtime_log = (args.output / "runtime.log").read_text()
    if (
        "SCENE112_QUALITY_ROUTE_OK" not in runtime_log
        or "ERROR:" in runtime_log
        or "SCRIPT ERROR" in runtime_log
    ):
        raise RuntimeError("No clean runtime route success; inspect log")
    metrics = json.loads((args.output / "metrics.json").read_text())
    if metrics["wall_seconds"] < 22 or metrics["viewport"] != [1280, 720]:
        raise RuntimeError("Wrong runtime duration or viewport")
    probe = json.loads(
        run_text(
            [
                str(args.ffprobe),
                "-v",
                "error",
                "-select_streams",
                "v:0",
                "-show_entries",
                "stream=codec_name,width,height,avg_frame_rate,nb_frames:format=duration,size",
                "-of",
                "json",
                str(args.output / "runtime.mp4"),
            ],
            env=ffenv,
        )
    )
    with (args.output / "frames.csv").open("w", newline="") as out:
        writer = csv.DictWriter(out, fieldnames=list(metrics["samples"][0]))
        writer.writeheader()
        writer.writerows(metrics["samples"])
    hashes = {
        path.name: hashlib.sha256(path.read_bytes()).hexdigest()
        for path in args.output.iterdir()
        if path.is_file() and path.suffix in (".png", ".mp4", ".json", ".csv", ".log")
    }
    manifest = {
        "condition_requested": args.condition,
        "tag": args.tag,
        "created_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(created)),
        "source_revision": revision,
        "source_status_before": source_status,
        "source_revision_after": revision
        if args.source_revision
        else run_text(["git", "rev-parse", "HEAD"], args.project),
        "source_status_after": source_status
        if args.source_revision
        else run_text(["git", "status", "--porcelain"], args.project),
        "source_hashes": source_hashes,
        "driver_sha256": hashlib.sha256(args.driver.read_bytes()).hexdigest(),
        "capture_tool_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "host": platform.platform(),
        "cpu_count": os.cpu_count(),
        "godot_command": command,
        "ffmpeg_command": ffcmd,
        "ffmpeg_version": ffversion,
        "encoded_media": probe,
        "launch_to_capture_ready_seconds": ready_wall,
        "recording_prefix_seconds_approx": prefix_seconds,
        "runtime_renderer_log": [
            line
            for line in runtime_log.splitlines()
            if "OpenGL" in line or "Vulkan" in line or "Using Device" in line
        ],
        "artifacts_sha256": hashes,
        "limits": "Actual runtime X11 frames recorded in wall time. 30fps is encoded video cadence, not engine performance. Software renderer with simultaneous recorder, no audible output (Dummy), no target desktop/GPU claim. Initial on-foot and car fixtures disclosed in driver.",
    }
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(
        json.dumps(
            {
                "result": "SCENE112_CAPTURE_OK",
                "revision": revision,
                "output": str(args.output),
                "wall_seconds": metrics["wall_seconds"],
                "p95_frame_ms": metrics["frame_interval_p95_ms"],
                "car_metres": metrics["car_distance_metres"],
                "video_seconds": probe["format"]["duration"],
            }
        )
    )


if __name__ == "__main__":
    main()
