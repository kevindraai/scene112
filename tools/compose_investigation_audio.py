#!/usr/bin/env python3
"""Original object sounds for M4 investigation; no recordings or speech samples."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import random

from compose_audio import RATE, TAU, empty, write


def sound(kind: str, duration: float, seed: int):
    audio = empty(duration, stereo=False)
    rng = random.Random(seed)
    low = mid = previous = 0.0
    for index in range(len(audio[0])):
        t = index / RATE
        white = rng.uniform(-1, 1)
        low = low * 0.95 + white * 0.05
        mid = mid * 0.7 + white * 0.3
        high = white - previous
        previous = white
        if kind == "evidence_paper":
            envelope = math.sin(math.pi * t / duration) ** 2
            flutter = 0.5 + 0.5 * math.sin(TAU * 13 * t)
            value = envelope * flutter * (mid * 0.14 + high * 0.035)
        elif kind == "evidence_bag":
            envelope = math.sin(math.pi * t / duration) ** 2
            crinkle = max(0.0, math.sin(TAU * 19 * t)) ** 4
            value = envelope * (mid * 0.1 + high * crinkle * 0.09)
        elif kind == "evidence_camera":
            envelope = math.exp(-t * 70) + (math.exp(-(t - 0.08) * 55) if t > 0.08 else 0)
            value = envelope * (high * 0.045 + math.sin(TAU * 900 * t) * 0.06)
        elif kind == "office_chair":
            envelope = math.sin(math.pi * t / duration) ** 2
            creak = math.sin(TAU * (210 * t + 3 * math.sin(TAU * 2 * t)))
            value = envelope * (low * 0.075 + creak * 0.025)
        else:  # A sparse, quiet fictional clock, not a recorded product.
            phase = (t - 0.5) % 2
            envelope = math.exp(-phase * 90) if phase < 0.12 else 0.0
            value = envelope * (math.sin(TAU * 1500 * t) * 0.035 + high * 0.008)
        audio[0][index] = value
    return audio


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=Path("assets/audio"))
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    files = []
    for index, (kind, duration) in enumerate([
        ("evidence_paper", 0.65), ("evidence_bag", 0.55), ("evidence_camera", 0.28),
        ("office_chair", 0.8), ("office_clock_loop", 8),
    ]):
        item = write(args.output_dir / (kind + ".wav"), sound(kind, duration, 4112 + index), duration >= 8)
        item["source"] = "tools/compose_investigation_audio.py"
        item["creator"] = "SCENE 112 original procedural investigation object audio"
        files.append(item)
    manifest = {"schema": 1, "milestone": "M4", "source_seed": 4112,
                "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                "helper_sha256": hashlib.sha256(Path(__file__).with_name("compose_audio.py").read_bytes()).hexdigest(),
                "no_speech_recording_or_synthesis": True, "files": files}
    (args.output_dir / "investigation_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Generated {len(files)} original M4 object WAVs with per-file provenance")


if __name__ == "__main__":
    main()
