#!/usr/bin/env python3
"""Capture a two-case renderer-lifetime repro; a deep-copy failure is expected."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--godot", required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
project = Path(__file__).parent.resolve()
args.output.mkdir(parents=True, exist_ok=True)
environment = os.environ.copy()
environment.update(XDG_DATA_HOME=str(args.output / "data"), XDG_CONFIG_HOME=str(args.output / "config"),
                   XDG_CACHE_HOME=str(args.output / "cache"), GODOT_SILENCE_ROOT_WARNING="1")
results = []
with tempfile.TemporaryDirectory(prefix="scene112-sky-evidence-") as directory:
    display = Path(directory) / "display"
    with display.open("w+") as fd, (args.output / "xvfb.log").open("w") as xlog:
        server = subprocess.Popen(["Xvfb", "-displayfd", str(fd.fileno()), "-screen", "0", "320x180x24", "-nolisten", "tcp"],
                                  pass_fds=(fd.fileno(),), stdout=xlog, stderr=xlog)
        try:
            deadline = time.monotonic() + 5
            while not display.read_text().strip():
                if server.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError("Xvfb could not start")
                time.sleep(0.05)
            environment["DISPLAY"] = ":" + display.read_text().strip()
            for mode in ("deep", "shallow"):
                command = [args.godot, "--path", str(project), "--audio-driver", "Dummy", "--script", str(project / "sky_copy.gd"), "--", mode]
                result = subprocess.run(command, env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30)
                path = args.output / (mode + ".log")
                path.write_text(result.stdout)
                item = {"case": mode, "returncode": result.returncode, "command": command,
                        "rendered": "SCENE112_SKY_COPY_RENDERED" in result.stdout,
                        "errors": [line for line in result.stdout.splitlines() if "ERROR:" in line],
                        "log_sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                results.append(item)
                print(json.dumps(item), flush=True)
        finally:
            server.terminate()
            server.wait(timeout=5)
summary = {"scope": "Linux OpenGL software-renderer lifetime reproduction; not gameplay/performance acceptance",
           "source_sha256": hashlib.sha256((project / "sky_copy.gd").read_bytes()).hexdigest(),
           "results": results, "hypothesis_corroborated": results[0]["rendered"] and len(results[0]["errors"]) == 2 and results[1]["rendered"] and not results[1]["errors"]}
(args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
assert summary["hypothesis_corroborated"], "Expected reproduced deep-copy failure and clean shallow-copy comparison"
