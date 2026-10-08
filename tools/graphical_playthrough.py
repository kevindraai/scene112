#!/usr/bin/env python3
"""Run an actual OpenGL playthrough on an isolated Linux virtual display."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("godot")
parser.add_argument("--project", default=".")
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix="scene112-display-") as directory:
    display_file = Path(directory) / "display"
    with display_file.open("w+") as output:
        server = subprocess.Popen(
            ["Xvfb", "-displayfd", str(output.fileno()), "-screen", "0", "1280x720x24", "-nolisten", "tcp"],
            pass_fds=(output.fileno(),), stdout=subprocess.DEVNULL,
        )
        try:
            for _ in range(100):
                if display_file.read_text().strip():
                    break
                if server.poll() is not None:
                    raise RuntimeError("Xvfb did not start")
                time.sleep(0.05)
            display = display_file.read_text().strip()
            if not display:
                raise RuntimeError("Xvfb display timeout")
            environment = os.environ.copy()
            environment["DISPLAY"] = ":" + display
            result = subprocess.run(
                [args.godot, "--path", args.project, "--audio-driver", "Dummy", "--", "--playthrough"],
                env=environment, timeout=90,
            )
            raise SystemExit(result.returncode)
        finally:
            server.terminate()
            server.wait(timeout=10)
