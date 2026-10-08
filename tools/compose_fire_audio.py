#!/usr/bin/env python3
"""Compose original M3 fire response audio; no recordings or cloud service."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import random

from compose_audio import MOTIF, RATE, TAU, empty, note, write


def texture(kind: str, seconds: float, seed: int):
    audio = empty(seconds, stereo=False)
    rng = random.Random(seed)
    low = middle = previous = 0.0
    clicks = [rng.randrange(int(seconds * RATE)) for _ in range(36)]
    pops = {index: rng.uniform(0.07, 0.13) for index in clicks}
    pop = 0.0
    for index in range(len(audio[0])):
        t = index / RATE
        white = rng.uniform(-1, 1)
        low = low * 0.985 + white * 0.015
        middle = middle * 0.83 + white * 0.17
        high = white - previous
        previous = white
        pop = pop * 0.965 + pops.get(index, 0.0)
        if kind == "fire_loop":
            swell = 0.75 + 0.2 * math.sin(TAU * t / 7)
            sound = swell * (low * 0.65 + middle * 0.2) + pop * high * 0.5
        elif kind == "water_loop":
            stream = 0.85 + 0.1 * math.sin(TAU * t * 3)
            sound = stream * (middle * 0.22 + high * 0.065 + low * 0.15)
        elif kind == "air_breathing":
            cycle = t % 3
            inhale = max(0.0, math.sin(math.pi * cycle / 1.1)) if cycle < 1.1 else 0.0
            exhale = max(0.0, math.sin(math.pi * (cycle - 1.5) / 1.1)) if 1.5 < cycle < 2.6 else 0.0
            sound = middle * (inhale * 0.23 + exhale * 0.16) + high * inhale * 0.012
        else:  # Original valve lever click and brief metallic resonance.
            pulse = math.exp(-t * 45) + (math.exp(-(t - 0.1) * 65) if t >= 0.1 else 0)
            sound = pulse * (middle * 0.24 + high * 0.04) + math.sin(TAU * 510 * t) * math.exp(-t * 35) * 0.065
        audio[0][index] = sound
    return audio


def fire_score(risk: bool):
    # A sparse 48-second cue contains more than 20 seconds of deliberate rest.
    # Both versions share the M2 sonic identity and stay below outcome cues.
    audio = empty(48)
    for at, root in [(1.0, 43), (17.0, 46), (33.0, 44)]:
        note(audio, at, 4.8, root, 0.045 if risk else 0.035, -0.2, soft=True)
        note(audio, at + 0.2, 4.4, root + 7, 0.025, 0.2, soft=True)
        if risk:
            for beat in range(4):
                note(audio, at + beat * 0.8, 0.45, root - 12, 0.035, 0.0)
    for index, pitch in enumerate(MOTIF[:3]):
        note(audio, 23 + index * 0.8, 1.5, pitch - 12, 0.035, 0.15 * math.sin(index))
    return audio


def outcome(kind: str):
    seconds, pitches = {
        "rescue": (2.4, (60, 67, 65)),
        "withdraw": (2.0, (60, 65, 63)),
        "handover": (3.0, (60, 67, 70, 65, 63)),
    }[kind]
    audio = empty(seconds)
    for index, pitch in enumerate(pitches):
        note(audio, 0.02 + index * 0.4, 0.8, pitch, 0.09, 0.12 * math.sin(index))
    return audio


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=Path("assets/audio"))
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    files = []
    for index, (kind, seconds, loop) in enumerate([
        ("fire_loop", 8, True), ("water_loop", 4, True),
        ("air_breathing", 6, True), ("nozzle_lever", 0.26, False),
    ]):
        files.append(write(args.output_dir / (kind + ".wav"), texture(kind, seconds, 3112 + index), loop))
    for risk in [False, True]:
        kind = "music_fire_risk" if risk else "music_fire_sparse"
        files.append(write(args.output_dir / (kind + ".wav"), fire_score(risk), False))
    for kind in ["rescue", "withdraw", "handover"]:
        files.append(write(args.output_dir / (kind + ".wav"), outcome(kind), False))
    for item in files:
        item["source"] = "tools/compose_fire_audio.py"
        item["creator"] = "SCENE 112 original procedural fire-response composition"
    manifest = {"schema": 1, "milestone": "M3", "source_seed": 3112,
                "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                "helper_sha256": hashlib.sha256(Path(__file__).with_name("compose_audio.py").read_bytes()).hexdigest(),
                "files": files}
    (args.output_dir / "fire_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Generated {len(files)} original M3 WAV assets with per-file SHA256/provenance")


if __name__ == "__main__":
    main()
